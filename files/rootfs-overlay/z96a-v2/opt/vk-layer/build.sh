#!/bin/sh
# Rebuild libconformance.so for aarch64 from conformance_layer.c.
#
# This layer makes wgpu accept PanVK on Mali-G52 (Bifrost v7): Mesa reports
# conformanceVersion 0.0.0.0 for PAN_ARCH < 10, and wgpu then hides the adapter
# as "not Vulkan compliant". The layer lifts it to 1.3.0.0.
#
# Requirements: aarch64 cross toolchain + Vulkan headers.
#   sudo apt install gcc-aarch64-linux-gnu libvulkan-dev:arm64
set -eu

cd "$(dirname "$0")"

CC=${CC:-aarch64-linux-gnu-gcc}
SYSROOT=${SYSROOT:-}

if [ -n "$SYSROOT" ]; then
    CC_ARGS="--sysroot=$SYSROOT -I$SYSROOT/usr/include"
else
    CC_ARGS=""
fi

# shellcheck disable=SC2086
$CC $CC_ARGS -shared -fPIC -O2 -o libconformance.so conformance_layer.c

echo "built: $(pwd)/libconformance.so"
file libconformance.so 2>/dev/null || true
