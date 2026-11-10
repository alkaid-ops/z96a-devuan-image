#!/bin/bash
# Validate a compressed image on a runner without requiring host sudo.
#
# Decompresses the .img.xz into output/ci and runs validate-image.sh inside the
# privileged build container (loop mount + chroot package closure need root).
#
# Usage:
#   boards/z96a-v2/tools/ci-validate-image.sh <image.img.xz>
#
# Env: Z96A_BUILD_IMAGE overrides the container image (default z96a-build:local).
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

IMAGE=${1:?usage: ci-validate-image.sh <image.img.xz>}
[ -f "$IMAGE" ] || { echo "no such image: $IMAGE" >&2; exit 2; }

CONTAINER=${Z96A_BUILD_IMAGE:-z96a-build:local}
WORK="$ROOT/output/ci"
mkdir -p "$WORK"

case "$IMAGE" in
    *.xz) IMG="$WORK/$(basename "${IMAGE%.xz}")" ;;
    *.img) IMG="$IMAGE" ;;
    *) echo "unsupported image type: $IMAGE" >&2; exit 2 ;;
esac

CREATED=0
if [ ! -f "$IMG" ]; then
    echo "decompressing $(basename "$IMAGE") -> $IMG"
    xz -dc "$IMAGE" > "$IMG"
    CREATED=1
fi

cleanup() { if [ "$CREATED" -eq 1 ]; then rm -f "$IMG"; fi; }
trap cleanup EXIT HUP INT TERM

docker run --rm --privileged \
    -v "$ROOT:/build" \
    -v "$WORK:/images" \
    -v /dev:/dev \
    -w /build \
    -e TERM="${TERM:-xterm}" \
    "$CONTAINER" \
    bash -lc "boards/z96a-v2/tools/validate-image.sh /images/$(basename "$IMG")"
