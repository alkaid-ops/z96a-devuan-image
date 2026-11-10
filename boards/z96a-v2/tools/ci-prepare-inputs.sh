#!/bin/bash
# Seed a clean checkout with the prebuilt inputs that `make image` consumes.
#
# A tag build starts from a fresh checkout: output/tarball and the kernel/U-Boot
# .debs are gitignored build products. CI keeps them in a persistent input cache
# and copies them back here, then verifies the bundled application .debs.
#
# Cache layout (Z96A_INPUT_CACHE):
#   packages/   bundled application .deb files (+ SHA256SUMS)
#   tarball/    devuan-<release>-minimal-rootfs-arm64.tar.xz
#   debs/       linux-image-*.deb, linux-headers-*.deb, u-boot-*.deb
#
# Usage:
#   boards/z96a-v2/tools/ci-prepare-inputs.sh [--cache DIR]
#
# Env: Z96A_INPUT_CACHE overrides the cache directory.
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

BOARD=z96a-v2
CACHE=${Z96A_INPUT_CACHE:-}
while [ $# -gt 0 ]; do
    case "$1" in
        --cache) CACHE=${2:?}; shift 2 ;;
        --help|-h) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -n "$CACHE" ] || { echo "Z96A_INPUT_CACHE is not set" >&2; exit 2; }
[ -d "$CACHE" ] || { echo "input cache not found: $CACHE" >&2; exit 2; }
CACHE=$(cd -- "$CACHE" && pwd)

PKG_DIR="files/rootfs-overlay/$BOARD/opt/z96a/packages"
OUTPUT="output/$BOARD"
TARBALL_OUT="output/tarball"
mkdir -p "$PKG_DIR" "$OUTPUT" "$TARBALL_OUT"

fail=0

# 1) Bundled application debs. Internal "build artifact" packages are not
# downloadable, so they must come from the cache; vendor URLs are fetched and
# checksum-verified by fetch-packages.sh.
if [ -d "$CACHE/packages" ]; then
    cp -f "$CACHE/packages"/*.deb "$PKG_DIR"/ 2>/dev/null || true
    echo "input cache: copied bundled debs from $CACHE/packages"
fi
"$ROOT/boards/$BOARD/tools/fetch-packages.sh" --from "$CACHE/packages" || fail=$((fail + 1))

# 2) Rootfs tarball, named exactly as scripts/rootfs expects.
DISTRO=$(sed -n 's/^DISTRO="\([^"]*\)".*/\1/p' userdata.txt | head -n 1)
DISTRO_VERSION=$(sed -n 's/^DISTRO_VERSION="\([^"]*\)".*/\1/p' userdata.txt | head -n 1)
ARCH_EXT=$(sed -n 's/^ARCH_EXT="\([^"]*\)".*/\1/p' "lib/boards/$BOARD" | head -n 1)
MINIMAL=$(sed -n 's/^MINIMAL_ROOTFS="\([^"]*\)".*/\1/p' custom.txt | head -n 1)
if [ "$MINIMAL" = "true" ]; then
    TARBALL="${DISTRO}-${DISTRO_VERSION}-minimal-rootfs-${ARCH_EXT}.tar.xz"
else
    TARBALL="${DISTRO}-${DISTRO_VERSION}-rootfs-${ARCH_EXT}.tar.xz"
fi
if [ -f "$CACHE/tarball/$TARBALL" ]; then
    if cp -f "$CACHE/tarball/$TARBALL" "$TARBALL_OUT/$TARBALL"; then
        echo "input cache: rootfs tarball $TARBALL"
    else
        echo "MISSING cannot write $TARBALL_OUT/$TARBALL (check permissions)" >&2
        fail=$((fail + 1))
    fi
elif [ -f "$TARBALL_OUT/$TARBALL" ]; then
    echo "input cache: rootfs tarball already present"
else
    echo "MISSING $CACHE/tarball/$TARBALL (run: make rootfs board=$BOARD)" >&2
    fail=$((fail + 1))
fi

# 3) Kernel and U-Boot packages. `make image` refuses to start without them.
KV=$(sed -n 's/^FORCE_LINUX_VERSION="\([^"]*\)".*/\1/p' "lib/boards/$BOARD" | head -n 1)
UV=$(sed -n 's/^FORCE_UBOOT_VERSION="\([^"]*\)".*/\1/p' "lib/boards/$BOARD" | head -n 1)
UV=${UV#v}
if [ -d "$CACHE/debs" ]; then
    find "$CACHE/debs" -maxdepth 1 -type f -name "linux-image-*_${KV}-*.deb" \
        -exec cp -f {} "$OUTPUT/" \;
    find "$CACHE/debs" -maxdepth 1 -type f -name "linux-headers-*_${KV}-*.deb" \
        -exec cp -f {} "$OUTPUT/" \;
    find "$CACHE/debs" -maxdepth 1 -type f -name "u-boot-*_${UV}-*.deb" \
        -exec cp -f {} "$OUTPUT/" \;
fi
if ! ls "$OUTPUT"/linux-image-*_"${KV}"-*.deb >/dev/null 2>&1; then
    echo "MISSING $CACHE/debs/linux-image-*_${KV}-*.deb (run: make kernel board=$BOARD)" >&2
    fail=$((fail + 1))
fi
if ! ls "$OUTPUT"/u-boot-*_"${UV}"-*.deb >/dev/null 2>&1; then
    echo "MISSING $CACHE/debs/u-boot-*_${UV}-*.deb (run: make uboot board=$BOARD)" >&2
    fail=$((fail + 1))
fi

# The image partition writer flashes these blobs into the raw disk before the
# target rootfs is mounted. They are also packaged inside the U-Boot deb for
# installation in the image, so restore the host-side copies on clean runners.
if [ "$fail" -eq 0 ]; then
    uboot_deb=$(find "$OUTPUT" -maxdepth 1 -type f -name "u-boot-*_${UV}-*.deb" -print -quit)
    uboot_tmp=$(mktemp -d)
    if dpkg-deb --extract "$uboot_deb" "$uboot_tmp"; then
        uboot_blob_dir=$(find "$uboot_tmp/usr/lib" -mindepth 1 -maxdepth 1 -type d -print -quit)
        for blob in idbloader.bin u-boot.bin; do
            if [ -s "$uboot_blob_dir/$blob" ]; then
                cp -f "$uboot_blob_dir/$blob" "$OUTPUT/$blob"
                echo "input cache: restored U-Boot $blob"
            else
                echo "MISSING $blob in $uboot_deb" >&2
                fail=$((fail + 1))
            fi
        done
    else
        echo "cannot extract U-Boot package: $uboot_deb" >&2
        fail=$((fail + 1))
    fi
    rm -rf "$uboot_tmp"
fi

if [ "$fail" -eq 0 ]; then
    echo "INPUTS: PASS ($CACHE)"
    exit 0
fi
echo "INPUTS: FAIL ($fail)" >&2
exit 1
