# Fixed build root for z96a-v2 (docs/OPTIMIZATION.md phase 1: 固定构建根).
#
# Pinned by image digest-on-build and an explicit package list so two builds on
# different hosts share the same toolchain. Usage:
#
#   docker build -f boards/z96a-v2/tools/Dockerfile -t z96a-build:local .
#   boards/z96a-v2/tools/build-in-container.sh
#
# The image intentionally does not run the build; build-in-container.sh mounts
# the repository and runs `make` inside, so host differences only affect the
# kernel cache, not the toolchain.
FROM debian:trixie-slim

# Mirror used for the toolchain packages; override for a different network.
ARG APT_MIRROR=http://deb.debian.org/debian

LABEL org.opencontainers.image.title="z96a-v2 build root"
LABEL org.opencontainers.image.description="Pinned toolchain for the z96a-v2 Devuan image build"

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# Base build dependencies (mirrors lib/source PKGS/PKGS_FULL essentials).
RUN if [ -n "$APT_MIRROR" ]; then \
        sed -i "s|http://deb.debian.org/debian|$APT_MIRROR|g" /etc/apt/sources.list.d/debian.sources 2>/dev/null || true; \
    fi; \
    apt-get update && apt-get install -y --no-install-recommends \
        bc \
        binutils-aarch64-linux-gnu \
        gcc-aarch64-linux-gnu \
        libc6-dev-arm64-cross \
        bison \
        build-essential \
        cpio \
        curl \
        device-tree-compiler \
        dialog \
        dosfstools \
        e2fsprogs \
        fdisk \
        file \
        flex \
        git \
        gzip \
        kpartx \
        kmod \
        lsb-release \
        dpkg-dev \
        fakeroot \
        debhelper \
        libelf-dev \
        libncurses-dev \
        libssl-dev \
        mmdebstrap \
        mtools \
        parted \
        patch \
        pkg-config \
        python3 \
        python3-setuptools \
        qemu-user-static \
        rsync \
        sudo \
        u-boot-tools \
        uuid-runtime \
        wget \
        xz-utils \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# Record the exact toolchain versions for manifest.json comparisons.
RUN { \
        echo "container debian:trixie-slim"; \
        gcc --version | head -1; \
        make --version | head -1; \
        python3 --version; \
        git --version; \
    } > /etc/z96a-buildroot.txt

WORKDIR /build

# Everything below is provided by the bind mount at run time.
CMD ["/bin/bash"]
