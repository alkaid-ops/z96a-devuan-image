#!/bin/bash
# Run the z96a-v2 build inside the pinned container (phase 1: 固定构建根).
#
# Usage:
#   boards/z96a-v2/tools/build-in-container.sh <make-target...>
#   boards/z96a-v2/tools/build-in-container.sh preflight
#
# The repository is bind-mounted at /build so outputs land in output/ as usual.
# The container provides a fixed toolchain; it does not change build logic.
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

IMAGE=${Z96A_BUILD_IMAGE:-z96a-build:local}
BOARD=${BOARD:-z96a-v2}

if ! command -v docker >/dev/null 2>&1; then
    echo "docker not available; use the host toolchain or install docker" >&2
    exit 2
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "building $IMAGE from boards/$BOARD/tools/Dockerfile"
    docker build -f "boards/$BOARD/tools/Dockerfile" -t "$IMAGE" .
fi

targets=${*:-preflight}
echo "container: $IMAGE   board: $BOARD   targets: $targets"

# shellcheck disable=SC2086
# Host CA bundle: some build networks terminate TLS with a local CA.
CA_MOUNT=()
if [ -r /etc/ssl/certs/ca-certificates.crt ]; then
    CA_MOUNT=(-v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro)
fi

# Build metadata and the chroot cache must reach the container. The cache can
# live outside the repository (CI keeps it outside the checkout so git clean
# does not delete it), so bind it at the same absolute path.
EXTRA_ENV=()
for name in RELEASE_CHANNEL RELEASE_TAG CHROOT_CACHE CHROOT_CACHE_KEY Z96A_PREFLIGHT_HASH Z96A_DEBUG_PARTITION Z96A_ALIGN_IMAGE_SECTORS Z96A_VALIDATE_IMAGE Z96A_XZ_FAST Z96A_SSH_KEY Z96A_ROOT_PASSWORD Z96A_WIFI_SSID Z96A_WIFI_PASSKEY; do
    if [ -n "${!name:-}" ]; then
        EXTRA_ENV+=(-e "$name=${!name}")
    fi
done
CACHE_MOUNT=()
if [ -n "${CHROOT_CACHE_DIR:-}" ]; then
    mkdir -p "$CHROOT_CACHE_DIR"
    CACHE_MOUNT=(-v "$CHROOT_CACHE_DIR:$CHROOT_CACHE_DIR")
    EXTRA_ENV+=(-e "CHROOT_CACHE_DIR=$CHROOT_CACHE_DIR")
fi

docker run --rm --privileged \
    -v "$ROOT:/build" \
    -v /dev:/dev \
    "${CA_MOUNT[@]}" \
    "${CACHE_MOUNT[@]}" \
    -w /build \
    -e BOARD="$BOARD" \
    -e TERM="${TERM:-xterm}" \
    "${EXTRA_ENV[@]}" \
    "$IMAGE" \
    bash -lc "make $targets board=$BOARD"
