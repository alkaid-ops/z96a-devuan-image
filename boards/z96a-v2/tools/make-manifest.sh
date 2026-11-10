#!/bin/sh
# Generate manifest.json for a z96a-v2 image: the "identity card" of a build.
#
# Records what went in (kernel repo/branch/pinned commit, defconfig hash,
# U-Boot blobs, patch series hash, toolchain versions, package list) so any
# image can be traced back to its inputs.
#
# Usage:
#   boards/z96a-v2/tools/make-manifest.sh <output-file> [rootfs-dir]
#
# Without rootfs-dir it records repository state only (host mode).
# With rootfs-dir (a mounted image root, or run from run_function3 where
# ${P_VALUE} is mounted) it also records the installed package list and
# the kernel version found in the image.
set -eu

OUT=${1:?usage: make-manifest.sh <output-file> [rootfs-dir] [image-file]}
ROOTFS=${2:-}
IMAGE_FILE=${3:-}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
BOARD=z96a-v2

cd "$ROOT"

# --- inputs -------------------------------------------------------------
board_file="lib/boards/$BOARD"
defconfig="defconfig/${BOARD}_defconfig"
uboot_dir="files/boot/uboot/$BOARD"
patchdir="patches/git/$BOARD"

board_var() {
    [ -r "$board_file" ] || return 1
    sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$board_file" | head -n 1
}

sha256() { [ -f "$1" ] && sha256sum "$1" | cut -d' ' -f1 || printf 'missing'; }

tool_version() {
    command -v "$1" >/dev/null 2>&1 || { printf 'missing'; return; }
    "$1" --version 2>/dev/null | head -n 1 || printf 'unknown'
}

patch_series_hash() {
    [ -d "$patchdir" ] || { printf 'none'; return; }
    # shellcheck disable=SC2046
    ( cd "$patchdir" && cat $(find . -name '*.patch' | sort) 2>/dev/null | sha256sum | cut -d' ' -f1 )
}

mesa_version="unknown"
[ -n "$ROOTFS" ] && [ -r "$ROOTFS/etc/z96a/mesa-version" ] && \
    mesa_version=$(head -n 1 "$ROOTFS/etc/z96a/mesa-version")

kernel_version="$(board_var FORCE_LINUX_VERSION)"
[ -n "$kernel_version" ] || kernel_version="$(board_var GIT_BRANCH)"
kernel_img_version=""
if [ -n "$ROOTFS" ] && [ -r "$ROOTFS/usr/lib/modules" ]; then
    kernel_img_version=$(ls -1 "$ROOTFS/usr/lib/modules" 2>/dev/null | head -n 1)
fi

uboot_sha=$(sha256 "$uboot_dir/u-boot.bin")
idbloader_sha=$(sha256 "$uboot_dir/idbloader.bin")
defconfig_sha=$(sha256 "$defconfig")

pkg_count=$(find files/rootfs-overlay/"$BOARD"/opt/z96a/packages -name '*.deb' 2>/dev/null | wc -l)
packages_sha=$(sha256 files/rootfs-overlay/"$BOARD"/opt/z96a/packages/SHA256SUMS)
runtime_packages_sha=$(sha256 files/rootfs-overlay/"$BOARD"/opt/z96a/runtime-packages.txt)

installed_list=""
if [ -n "$ROOTFS" ] && [ -r "$ROOTFS/var/lib/dpkg/status" ]; then
    installed_list=$(awk '/^Package: /{p=$2} /^Version: /{if (p) {print p "=" $2; p=""}}' \
        "$ROOTFS/var/lib/dpkg/status" | sort)
fi

patch_sha=$(patch_series_hash)
GIT_PIN_COMMIT=${GIT_PIN_COMMIT:-$(board_var GIT_PIN_COMMIT)}
if [ -n "$IMAGE_FILE" ] && [ -f "$IMAGE_FILE" ]; then
    IMAGE_SHA256=$(sha256sum "$IMAGE_FILE" | cut -d' ' -f1)
else
    IMAGE_SHA256=""
fi
if [ -z "${ARTIFACT_NAME:-}" ]; then
    channel=${RELEASE_CHANNEL:-nightly}
    ARTIFACT_NAME="${BOARD}-${kernel_version}-${channel}-$(date +%Y%m%d).img.xz"
fi
export OUT ROOTFS BOARD kernel_version kernel_img_version GIT_PIN_COMMIT mesa_version IMAGE_SHA256 ARTIFACT_NAME \
    uboot_sha idbloader_sha defconfig_sha pkg_count packages_sha \
    runtime_packages_sha installed_list patch_sha

python3 - <<'PY'
import json, os, subprocess, sys, hashlib, pathlib

root = pathlib.Path.cwd()

def txt(name, default=""):
    return os.environ.get(name) or default

def git(*args):
    try:
        return subprocess.run(["git", *args], capture_output=True, text=True,
                              check=True).stdout.strip()
    except Exception:
        return ""

installed = [line for line in txt("installed_list").splitlines() if line]
manifest = {
    "schema": 1,
    "generated_at": subprocess.run(["date", "-Is"], capture_output=True,
                                   text=True).stdout.strip(),
    "build_host": subprocess.run(["hostname"], capture_output=True,
                                  text=True).stdout.strip(),
    "image_sha256": os.environ.get("IMAGE_SHA256") or None,
    "board": txt("BOARD", "z96a-v2"),
    "architecture": "arm64",
    "distribution": "devuan",
    "release": "excalibur",
    "release_info": {
        "channel": os.environ.get("RELEASE_CHANNEL") or "nightly",
        "tag": os.environ.get("RELEASE_TAG") or None,
        "artifact_name": os.environ.get("ARTIFACT_NAME") or None,
        "sbom": "sbom.json",
    },
    "kernel": {
        "version": txt("kernel_version"),
        "version_in_image": txt("kernel_img_version"),
        "repository": "https://github.com/yjun123/linux",
        "branch": "add_sunniwell_z96a",
        "pinned_commit": txt("GIT_PIN_COMMIT") or None,
        "defconfig_sha256": txt("defconfig_sha"),
        "patch_series_sha256": txt("patch_sha"),
    },
    "u_boot": {
        "version": "v2026.01",
        "precompiled": True,
        "u_boot_sha256": txt("uboot_sha"),
        "idbloader_sha256": txt("idbloader_sha"),
    },
    "mesa": {
        "version": txt("mesa_version", "unknown"),
        "source": "excalibur-backports",
        "pinned": bool(os.environ.get("MESA_BACKPORTS_PIN")),
    },
    "packages": {
        "bundled_deb_count": int(txt("pkg_count", "0") or 0),
        "bundled_sha256sums_sha256": txt("packages_sha"),
        "runtime_list_sha256": txt("runtime_packages_sha"),
        "installed_count": len(installed),
        "installed": installed,
    },
    "source_tree": {
        "commit": git("rev-parse", "HEAD"),
        "dirty": bool(git("status", "--porcelain")),
    },
}

# toolchain versions from the host running the build
def cmd_first_line(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True,
                              check=True).stdout.splitlines()[0]
    except Exception:
        return "missing"

manifest["toolchain"] = {
    "gcc": cmd_first_line(["aarch64-linux-gnu-gcc", "--version"]),
    "make": cmd_first_line(["make", "--version"]),
    "python3": cmd_first_line(["python3", "--version"]),
    "git": cmd_first_line(["git", "--version"]),
}

out = pathlib.Path(os.environ["OUT"])
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"manifest written: {out} ({len(installed)} installed packages)")

# SBOM (SPDX-lite JSON): one package entry per installed dpkg package, plus the
# kernel/U-Boot blobs. CVE scanning is a separate step that needs a feed.
sbom = {
    "spdxVersion": "SPDX-2.3-lite",
    "name": f"{manifest['board']}-{manifest['distribution']}-{manifest['release']}",
    "creationInfo": {
        "created": manifest["generated_at"],
        "creator": "z96a make-manifest.sh",
    },
    "packages": [
        {
            "name": name.split("=", 1)[0],
            "versionInfo": name.split("=", 1)[1] if "=" in name else "",
            "supplier": "Devuan",
            "downloadLocation": "NOASSERTION",
            "licenseConcluded": "NOASSERTION",
        }
        for name in installed
    ]
    + [
        {"name": "linux-z96a", "versionInfo": manifest["kernel"]["version"],
         "supplier": "yjun123/linux", "downloadLocation": "NOASSERTION",
         "licenseConcluded": "GPL-2.0-only"},
        {"name": "u-boot", "versionInfo": manifest["u_boot"]["version"],
         "supplier": "upstream", "downloadLocation": "NOASSERTION",
         "licenseConcluded": "GPL-2.0-or-later"},
    ],
}
sbom_path = out.parent / "sbom.json"
sbom_path.write_text(json.dumps(sbom, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"sbom written: {sbom_path} ({len(sbom['packages'])} packages)")
PY
