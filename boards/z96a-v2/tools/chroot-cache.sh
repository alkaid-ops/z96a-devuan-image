#!/bin/bash
# Cache the chroot package-install result (phase 3 build-speed optimisation).
#
# `make image` re-runs the whole chroot setup (apt install of the desktop stack
# plus the board userscript) even when nothing changed. This cache stores the
# prepared rootfs tree keyed on the build inputs and restores it next time.
#
# Usage (called from scripts/stage1):
#   chroot-cache.sh key [<board>]              print the cache key
#   chroot-cache.sh save <board> <rootfs-dir>  store the tree
#   chroot-cache.sh restore <board> <rootfs-dir>
#
# Env: CHROOT_CACHE=0 disables the cache; CHROOT_CACHE_DIR overrides location.
set -eu
# Locale affects `sort` collation (uppercase vs lowercase paths), which would
# make the key differ between the host and the build container.
export LC_ALL=C

MODE=${1:?usage: chroot-cache.sh key|save|restore <board> [<rootfs>] [<slot>]}
BOARD=${2:-z96a-v2}
ROOTFS=${3:-}
SLOT=${4:-}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
CACHE_DIR=${CHROOT_CACHE_DIR:-"$ROOT/output/cache"}

cd "$ROOT"

inputs_key() {
	{
		sha256sum "lib/boards/$BOARD" "config/$BOARD.toml" \
			"boards/$BOARD/features.conf" "boards/$BOARD/defconfig-trim.txt" \
			"custom.txt" "userdata.txt" "scripts/stage2" "lib/function/staging" 2>/dev/null || true
		# files installed into the rootfs by stage1/stage2 but not covered by
		# the overlay hash above (ALSA state, init extras).
		for extra in "files/asound/$BOARD.state" "files/asound/$BOARD.conf" files/inits/*.init; do
			[ -f "$extra" ] && sha256sum "$extra"
		done
		sha256sum "defconfig/$(sed -n 's/^LINUX_DEFCONFIG="\([^"]*\)".*/\1/p' "lib/boards/$BOARD" | head -1)" 2>/dev/null || true
		package_sums="files/rootfs-overlay/$BOARD/opt/z96a/packages/SHA256SUMS"
		if [ -f "$package_sums" ]; then
			# Hash canonical contents, not the source file's locale-dependent order.
			LC_ALL=C sort "$package_sums" | sha256sum
		fi
		# userscript modules and rootfs overlay (excluding the .deb blobs, which
		# are covered by SHA256SUMS above and are far too large to hash each run)
		find "boards/$BOARD/userscripts" -type f -print0 2>/dev/null | sort -z |
			xargs -0 -r sha256sum || true
		find "files/rootfs-overlay/$BOARD" -type f \
			! -path "*/opt/z96a/packages/*.deb" \
			! -path "*/opt/z96a/packages/*.sha256" \
			-print0 2>/dev/null | sort -z | xargs -0 -r sha256sum || true
		# kernel packages produced by `make kernel`
		for deb in output/"$BOARD"/linux-image-*.deb; do
			[ -f "$deb" ] && sha256sum "$deb"
		done
	} | sha256sum | cut -d' ' -f1
}

# A key computed once at build start is authoritative: inputs can change while
# the build runs (package lists, temporary files), so recomputing later would
# store the tree under a different key than the one restore will use.
CACHE_KEY=${CHROOT_CACHE_KEY:-}

compute_key(){
	if [ -n "$CACHE_KEY" ]; then printf '%s\n' "$CACHE_KEY"; else inputs_key; fi
}

case "$MODE" in
	key)
		compute_key
		;;
	save)
		[ -n "$ROOTFS" ] && [ -d "$ROOTFS" ] || { echo "no rootfs: $ROOTFS" >&2; exit 2; }
		key=$(compute_key)
		dest="$CACHE_DIR/chroot-$BOARD-$key"
		[ -n "$SLOT" ] && dest="$dest/$SLOT"
		mkdir -p "$CACHE_DIR"
		rm -rf "$dest.tmp"
		mkdir -p "$dest.tmp"
		# Never cache runtime mounts or volatile content: restoring /dev over
		# the build's bind mount would clobber the host /dev.
		rsync -a --delete \
			--exclude '/dev/***' --exclude '/proc/***' --exclude '/sys/***' \
			--exclude '/tmp/***' --exclude '/var/cache/***' --exclude '/var/log/***' \
			"$ROOTFS/" "$dest.tmp/"
		# drop cache-host noise that the next build recreates anyway
		rm -rf "$dest.tmp/var/cache/debconf"/* 2>/dev/null || true
		mv "$dest.tmp" "$dest"
		echo "$dest"
		;;
	restore)
		[ -n "$ROOTFS" ] && [ -d "$ROOTFS" ] || { echo "no rootfs: $ROOTFS" >&2; exit 2; }
		key=$(compute_key)
		src="$CACHE_DIR/chroot-$BOARD-$key"
		[ -n "$SLOT" ] && src="$src/$SLOT"
		[ -d "$src" ] || exit 1
		if [ "$SLOT" = "p1" ]; then
			# p1 is the vfat boot partition: preserving owner/mode on vfat
			# makes rsync exit with "failed to set permissions", which used
			# to leave p2 restored but reported a cache miss.
			rsync -rlt --no-owner --no-group --no-perms \
				--exclude '/dev/***' --exclude '/proc/***' --exclude '/sys/***' \
				--exclude '/tmp/***' \
				"$src/" "$ROOTFS/"
		else
			rsync -a \
				--exclude '/dev/***' --exclude '/proc/***' --exclude '/sys/***' \
				--exclude '/tmp/***' \
				"$src/" "$ROOTFS/"
		fi
		echo "$src"
		;;
	*)
		echo "unknown mode: $MODE" >&2
		exit 2
		;;
esac
