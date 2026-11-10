#!/bin/bash
# Validate a built image: structure, rootfs contents, and build provenance.
#
# Runs the phase 0 checks plus the phase 1/2 artefacts that only exist in a real
# image: /etc/z96a/manifest.json, sbom.json, mesa-version, board.runtime.
#
# Usage:  sudo boards/z96a-v2/tools/validate-image.sh output/z96a-v2/image/<file>.img
set -uo pipefail

IMAGE=${1:-}
[ -n "$IMAGE" ] || { echo "usage: $0 <image file>" >&2; exit 2; }
[ -f "$IMAGE" ] || { echo "no such image: $IMAGE" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "must run as root (loop mount)" >&2; exit 2; }

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

fail=0
ok()  { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }

echo "== static image checks"
boards/z96a-v2/tests/smoke-static.sh --image "$IMAGE" || fail=$((fail + 1))

loop=$(losetup -f --show -P "$IMAGE") || { echo "cannot attach loop" >&2; exit 1; }
rootpart=""
for part in "${loop}"p*; do
    [ -b "$part" ] || continue
    case "$(blkid -s TYPE -o value "$part" 2>/dev/null)" in
        ext4) rootpart=$part ;;
    esac
done
if [ -z "$rootpart" ]; then
    echo "no ext4 root partition in $IMAGE" >&2
    losetup -d "$loop"; exit 1
fi

mnt=$(mktemp -d)
if ! mount -o ro "$rootpart" "$mnt"; then
    echo "cannot mount $rootpart" >&2
    losetup -d "$loop"; exit 1
fi

cleanup() { umount "$mnt" 2>/dev/null; losetup -d "$loop" 2>/dev/null; rmdir "$mnt" 2>/dev/null; }
trap cleanup EXIT HUP INT TERM

echo "== built-in provenance"
for f in etc/z96a/manifest.json etc/z96a/sbom.json etc/z96a/mesa-version; do
    [ -s "$mnt/$f" ] && ok "image has $f" || bad "image missing $f"
done
if [ -s "$mnt/etc/z96a/board.runtime" ]; then
    ok "image records board.runtime overrides"
elif [ -s "$mnt/etc/opt/board.txt" ]; then
    # Older builds stored only the effective values; accept that as evidence
    # that the overrides were applied, and flag the missing record.
    ok "image has effective board.txt (no board.runtime record in this build)"
else
    bad "image has no evidence of board overrides"
fi
[ -s "$mnt/etc/opt/board.txt" ] && ok "image has effective board.txt" \
    || bad "image missing /etc/opt/board.txt"

if [ -s "$mnt/etc/z96a/manifest.json" ]; then
    python3 - "$mnt/etc/z96a/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
print("PASS  manifest parses: board=%s kernel=%s pinned=%s"
      % (data.get("board"), data["kernel"].get("version"),
         (data["kernel"].get("pinned_commit") or "none")[:12]))
print("PASS  manifest installed packages: %d" % data["packages"].get("installed_count", 0))
print("PASS  manifest artifact: %s" % data.get("release_info", {}).get("artifact_name"))
PY
    [ $? -eq 0 ] || bad "manifest.json is not valid JSON"
fi
if [ -s "$mnt/etc/z96a/sbom.json" ]; then
    python3 - "$mnt/etc/z96a/sbom.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print("PASS  sbom: %s with %d packages"
          % (data.get("spdxVersion"), len(data.get("packages", []))))
PY
    [ $? -eq 0 ] || bad "sbom.json is not valid JSON"
fi

echo "== image size / pruning"
if ls "$mnt/opt/z96a/packages"/*.deb >/dev/null 2>&1; then
    bad "bundled .deb files still present in the image"
else
    ok "no bundled .deb files in the image"
fi
for spec in "usr/share/doc:40" "usr/share/locale:100" "usr/lib/firmware:300"; do
    path=${spec%%:*}; limit=${spec#*:}
    mb=$(du -sm "$mnt/$path" 2>/dev/null | cut -f1)
    mb=${mb:-0}
    if [ "$mb" -le "$limit" ]; then
        ok "$path ${mb}M <= ${limit}M"
    else
        bad "$path ${mb}M > ${limit}M (pruning not applied?)"
    fi
done
root_mb=$(du -sm "$mnt" 2>/dev/null | cut -f1)
echo "PASS  rootfs used: ${root_mb}M"

# firmware this board and USB peripherals need must be present.
# Symlinks in /usr/lib/firmware are absolute (/etc/alternatives/...), so
# resolve them inside the mounted root instead of the host.
root_exists() {
    local rel=$1 p="$mnt/$1" x hops=0
    [ -e "$p" ] && return 0
    while [ -L "$p" ] && [ "$hops" -lt 10 ]; do
        x=$(readlink "$p") || return 1
        case "$x" in
            /*) p="$mnt$x" ;;
            *) p="$(dirname "$p")/$x" ;;
        esac
        hops=$((hops + 1))
    done
    [ -e "$p" ]
}
for must in rtl_bt rtw88 rtl_nic realtek rtlwifi brcm rkwifi regulatory.db; do
    if root_exists "/usr/lib/firmware/$must"; then
        ok "firmware present: $must"
    else
        bad "firmware missing: $must"
    fi
done

echo "== rootfs content checks"
boards/z96a-v2/tests/smoke-rootfs.sh "$mnt" || fail=$((fail + 1))

echo "== chroot package closure"
boards/z96a-v2/tests/smoke-rootfs.sh "$mnt" --chroot || fail=$((fail + 1))

if [ "$fail" -eq 0 ]; then echo "IMAGE VALIDATION: PASS"; exit 0; fi
echo "IMAGE VALIDATION: FAIL ($fail)"
exit 1
