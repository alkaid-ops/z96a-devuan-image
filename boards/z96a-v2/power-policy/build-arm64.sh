#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OUT=${1:-"$ROOT/dist"}
mkdir -p "$OUT"
if ! docker image inspect z96a-power-build >/dev/null 2>&1; then
    echo "z96a-power-build arm64 container image is required" >&2
    exit 1
fi
docker run --rm --platform linux/arm64 -v "$ROOT:/src" -w /src z96a-power-build \
    sh -lc 'gcc -std=gnu11 -O2 -Wall -Wextra -Wno-unused-parameter \
    -o z96a-power-policy z96a-power-policy.c \
    $(pkg-config --cflags --libs glib-2.0 gio-2.0 x11 xscrnsaver xext)'
mkdir -p "$ROOT/package/usr/local/sbin"
cp "$ROOT/z96a-power-policy" "$ROOT/package/usr/local/sbin/z96a-power-policy"
chmod 0755 "$ROOT/package/usr/local/sbin/z96a-power-policy"
dpkg-deb --build --root-owner-group "$ROOT/package" "$OUT/z96a-power-policy_1.0.2_arm64.deb"
sha256sum "$OUT/z96a-power-policy_1.0.2_arm64.deb" > "$OUT/z96a-power-policy_1.0.2_arm64.deb.sha256"
