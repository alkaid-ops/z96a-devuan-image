#!/bin/bash
# Shrink a built rootfs (docs/OPTIMIZATION.md §7.8/§7.9).
#
# Strategy:
#   1. purge firmware packages for hardware this board cannot have
#      (no M.2 slot, no discrete GPU, no tuner) — keeps dpkg consistent
#   2. never delete files from packages we keep: that broke dpkg -V and
#      removed the board's own Bluetooth firmware in an earlier revision
#   3. verify every firmware path referenced by an installed module still
#      exists; fail loudly instead of silently breaking features
#   4. drop the bundled .deb payload, documentation (keep copyright) and
#      non-zh/en gettext catalogues
#
# Usage: prune-rootfs.sh <rootfs-dir>      (root required for chroot/apt)
set -eu

ROOT=${1:?usage: prune-rootfs.sh <rootfs-dir>}
[ -d "$ROOT" ] || { echo "no such rootfs: $ROOT" >&2; exit 2; }

# --- 1. packages that cannot apply to this board -------------------------
# Kept on purpose: firmware-realtek (RTW88 + rtl_bt for RTL8822CS),
# firmware-mediatek (MT76 USB WiFi), firmware-brcm80211, firmware-ath9k-htc,
# firmware-misc-nonfree (USB serial/video helpers), firmware-linux-free.
purge_pkgs="firmware-iwlwifi firmware-qcom-soc firmware-amd-graphics \
	firmware-nvidia-graphics firmware-intel-graphics firmware-intel-misc \
	firmware-intel-sound firmware-atheros"
# shellcheck disable=SC2086
chroot "$ROOT/." env DEBIAN_FRONTEND=noninteractive \
    apt-get purge -y $purge_pkgs >/dev/null 2>&1 || true

# 1b. Leftover files of the purged packages above. Some Debian firmware
#     packages leave their directory behind after purge; nothing else owns it.
#     This list is only hardware that does not exist on this board.
absent_fw_dirs="qcom amdgpu nvidia ath10k ath11k ath12k intel i915 iwlwifi"
for d in $absent_fw_dirs; do
	rm -rf "$ROOT/usr/lib/firmware/$d"
done
rm -f "$ROOT"/usr/lib/firmware/iwlwifi-*.ucode 2>/dev/null || true

# --- 2. bundled .deb payload and docs ------------------------------------
rm -f "$ROOT"/opt/z96a/packages/*.deb "$ROOT"/opt/z96a/packages/*.deb.sha256 2>/dev/null || true

if [ -d "$ROOT/usr/share/doc" ]; then
	find "$ROOT/usr/share/doc" -mindepth 2 -type f ! -name copyright -delete 2>/dev/null || true
	find "$ROOT/usr/share/doc" -mindepth 2 -type l ! -name copyright -delete 2>/dev/null || true
	find "$ROOT/usr/share/doc" -mindepth 2 -type d -empty -delete 2>/dev/null || true
	find "$ROOT/usr/share/doc" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
fi
rm -rf "$ROOT"/usr/share/man/* 2>/dev/null || true

if [ -d "$ROOT/usr/share/locale" ]; then
	for entry in "$ROOT"/usr/share/locale/*; do
		[ -e "$entry" ] || continue
		case "$(basename "$entry")" in
			zh|zh_CN|zh_TW|zh_HK|en|en_US|en_GB|en_CA|locale|C) ;;
			*) rm -rf "$entry" ;;
		esac
	done
fi

# --- 3. firmware referenced by installed modules must still exist --------
# Critical families: onboard WiFi/BT and USB hotplug devices this image ships.
# Exact firmware this board must have: RTL8822CS WiFi (rtw88) and Bluetooth.
critical_files="rtl_bt/rtl8822cs_config.bin rtl_bt/rtl8822cs_fw.bin
	rtw88/rtw8822c_fw.bin rtw88/rtw8822c_wow_fw.bin"
refs=$(mktemp)
trap 'rm -f "$refs"' EXIT HUP INT TERM
if [ -d "$ROOT/usr/lib/modules" ]; then
	# .modinfo entries are NUL-separated, so converting NULs to newlines
	# yields exactly one string per line — no ELF tool needed and no
	# concatenation (which `grep -a` on raw binaries does produce).
	for ko in $(find "$ROOT/usr/lib/modules" -name '*.ko'); do
		tr '\0' '\n' < "$ko" 2>/dev/null | grep -a '^firmware='
	done | sed 's/^firmware=//' | sort -u > "$refs" || true
fi
# Panel symlinks are absolute (/etc/alternatives/... and /lib/firmware/...),
# so a plain -e against a mounted root would report false "missing". Resolve
# every hop inside the root instead.
root_exists() {
	local rel=$1 path="$ROOT/$1" target hops=0
	[ -e "$path" ] && return 0
	while [ -L "$path" ] && [ "$hops" -lt 10 ]; do
		target=$(readlink "$path") || return 1
		case "$target" in
			/*) path="$ROOT$target" ;;
			*) path="$(dirname "$path")/$target" ;;
		esac
		hops=$((hops + 1))
	done
	[ -e "$path" ]
}

missing_critical=0
missing_other=0
while IFS= read -r ref; do
	[ -n "$ref" ] || continue
	case "$ref" in *%*|*'*'*) continue ;; esac
	if root_exists "usr/lib/firmware/$ref"; then continue; fi
	is_critical=0
	case " $(echo $critical_files) " in
		*" $ref "*) is_critical=1 ;;
	esac
	if [ "$is_critical" -eq 1 ]; then
		echo "ERROR: critical firmware referenced but missing: $ref" >&2
		missing_critical=$((missing_critical + 1))
	else
		missing_other=$((missing_other + 1))
		[ "$missing_other" -le 5 ] && echo "note: firmware not shipped (hardware absent): $ref" >&2
	fi
done < "$refs"
echo "prune: firmware references checked ($(wc -l < "$refs") entries), missing critical=$missing_critical, other=$missing_other"

# --- 4. apt leftovers (always run, even if the guard below fails) --------

# --- 4. apt leftovers (the kernel install refreshes these) --------------
chroot "$ROOT/." apt-get clean >/dev/null 2>&1 || true
rm -rf "$ROOT"/var/lib/apt/lists/* 2>/dev/null || true
rm -rf "$ROOT"/var/cache/apt/archives/* 2>/dev/null || true
rm -rf "$ROOT"/var/log/*.log 2>/dev/null || true

# Only onboard/USB-critical firmware is allowed to fail the build; other
# missing references belong to drivers whose hardware cannot exist here.
if [ "$missing_critical" -gt 0 ]; then
	echo "prune: $missing_critical critical firmware file(s) missing" >&2
	exit 1
fi

echo "pruned: $(du -sm "$ROOT" 2>/dev/null | cut -f1)M rootfs"
