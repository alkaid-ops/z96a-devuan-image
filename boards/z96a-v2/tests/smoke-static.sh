#!/bin/bash
# Phase 0 static smoke test.
#
# Repo mode (default): no image needed, never touches the device.
# Image mode: pass an image file; requires root for loop mounting and fsck.
#
# Usage:
#   boards/z96a-v2/tests/smoke-static.sh
#   sudo boards/z96a-v2/tests/smoke-static.sh --image output/z96a-v2/*.img
set -uo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
BOARD=z96a-v2
IMAGE=""
fail=0

while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE=${2:?}; shift 2 ;;
        --help|-h) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

ok()   { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }
skip() { printf 'SKIP  %s\n' "$*"; }

cd "$ROOT" || exit 1

echo "== repository checks"
if python3 -m unittest discover -s "boards/$BOARD/tests" -p 'test_*.py' >/tmp/z96a-static-tests.log 2>&1; then
    ok "repository unit tests"
else
    bad "repository unit tests (see /tmp/z96a-static-tests.log)"
fi

for path in "lib/boards/$BOARD" "defconfig/${BOARD}_defconfig" \
            "files/rootfs-overlay/$BOARD" "boards/$BOARD/userscripts/uscripts"; do
    if [ -e "$path" ]; then ok "exists: $path"; else bad "missing: $path"; fi
done

if bash -n files/userscripts/uscripts 2>/dev/null &&
   bash -n "boards/$BOARD/userscripts/uscripts" 2>/dev/null; then
    ok "shell syntax: uscripts"
else
    bad "shell syntax: uscripts"
fi

if git -c safe.directory="$ROOT" diff --check >/tmp/z96a-diffcheck.log 2>&1; then
    ok "git diff --check"
else
    bad "git diff --check (see /tmp/z96a-diffcheck.log)"
fi

if [ -z "$IMAGE" ]; then
    echo "== image checks skipped (no --image)"
    [ "$fail" -eq 0 ] && { echo "STATIC SMOKE: PASS"; exit 0; }
    echo "STATIC SMOKE: FAIL ($fail)"; exit 1
fi

echo "== image checks: $IMAGE"
if [ "$(id -u)" -ne 0 ]; then
    skip "image checks need root (loop mount + fsck)"
else
    if file "$IMAGE" | grep -qiE 'disk image|DOS/MBR boot sector'; then ok "image file type"; else bad "not a disk image"; fi
    if command -v sfdisk >/dev/null && sfdisk -d "$IMAGE" >/dev/null 2>&1; then
        ok "partition table readable"
    else
        bad "partition table not readable"
    fi

    loop=$(losetup -f --show -P "$IMAGE" 2>/dev/null) && mounted=0 || mounted=1
    if [ "$mounted" -eq 0 ]; then
        boot=""
        for part in "${loop}"p*; do
            [ -b "$part" ] || continue
            type=$(blkid -s TYPE -o value "$part" 2>/dev/null || true)
            case "$type" in
                vfat) boot=$part ;;
                ext4)
                    if fsck -n "$part" >/dev/null 2>&1; then
                        ok "ext4 clean: $(basename "$part")"
                    else
                        bad "ext4 issues: $(basename "$part")"
                    fi
                    ;;
            esac
        done
        if [ -n "$boot" ]; then
            tmp=$(mktemp -d)
            if mount -o ro "$boot" "$tmp" 2>/dev/null; then
                [ -f "$tmp/extlinux/extlinux.conf" ] && ok "extlinux.conf present" || bad "extlinux.conf missing"
                if find "$tmp" -name '*.dtb' -print -quit 2>/dev/null | grep -q .; then
                    ok "DTB present in boot partition"
                else
                    bad "DTB missing in boot partition"
                fi
                umount "$tmp"
            else
                bad "cannot mount boot partition"
            fi
            rmdir "$tmp" 2>/dev/null || true
        else
            bad "no vfat boot partition found"
        fi
        losetup -d "$loop" 2>/dev/null || true
    else
        bad "cannot attach loop device"
    fi
fi

[ "$fail" -eq 0 ] && { echo "STATIC SMOKE: PASS"; exit 0; }
echo "STATIC SMOKE: FAIL ($fail)"; exit 1
