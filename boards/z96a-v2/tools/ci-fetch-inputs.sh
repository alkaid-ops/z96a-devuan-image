#!/bin/bash
# Download the component releases pinned by config/inputs.lock.
#
# Unlike the old monolithic inputs-vN release, each component (kernel,
# base+apps, U-Boot) is an independent prerelease. This script verifies the
# component manifest against the SHA256 stored in the lock, then verifies
# every asset against that manifest, and only then populates the cache.
#
# Cache layout (Z96A_INPUT_CACHE):
#   debs/       linux-image/linux-headers + u-boot .deb
#   packages/   bundled application .debs
#   tarball/    devuan-excalibur-minimal-rootfs-arm64.tar.xz
#   blobs/      u-boot.itb / idbloader raw blobs
#   manifests/  downloaded component checksum manifests
#   .lock-sha   digest of the lock file the cache was built from
#
# Env: Z96A_INPUT_CACHE (required), Z96A_INPUTS_LOCK (default config/inputs.lock),
#      GITHUB_REPOSITORY (defaults to alkaid-ops/z96a-devuan-image).
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

CACHE=${Z96A_INPUT_CACHE:?set Z96A_INPUT_CACHE}
LOCK=${Z96A_INPUTS_LOCK:-config/inputs.lock}
REPOSITORY=${GITHUB_REPOSITORY:-alkaid-ops/z96a-devuan-image}
BASE="https://github.com/${REPOSITORY}/releases/download"

[ -f "$LOCK" ] || { echo "missing lock file: $LOCK" >&2; exit 1; }

lock_get() {
    awk -v key="$1" '
        /^[[:space:]]*#/ { next }
        {
            n = index($0, "=")
            if (n == 0) next
            k = substr($0, 1, n - 1)
            v = substr($0, n + 1)
            gsub(/[[:space:]"]/, "", k); gsub(/[[:space:]"]/, "", v)
            if (k == key) { print v; exit }
        }
    ' "$LOCK"
}

for key in kernel_release kernel_sums base_apps_release base_apps_sums \
           uboot_release uboot_sums; do
    val=$(lock_get "$key")
    [ -n "$val" ] || { echo "lock is missing $key" >&2; exit 1; }
done

mkdir -p "$CACHE"/{debs,packages,tarball,blobs,manifests}

lock_sha=$(sha256sum "$LOCK" | cut -d' ' -f1)
marker="$CACHE/.lock-sha"

fetch_manifest() {
    name=$1 release=$2 expected=$3
    manifest="$CACHE/manifests/SHA256SUMS.$name"
    asset="SHA256SUMS.$name"
    encoded=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="._+-"))' "$asset")
    curl --fail --location --silent --show-error --retry 3 \
        "$BASE/$release/$encoded" --output "$manifest"
    printf '%s  %s\n' "$expected" "$manifest" | sha256sum -c --quiet - || {
        echo "manifest checksum mismatch: $asset from $release" >&2; exit 1; }
}

verify_cached() {
    local ok=1 rel dest
    for component in kernel base uboot; do
        manifest="$CACHE/manifests/SHA256SUMS.$component"
        [ -f "$manifest" ] || { ok=0; break; }
        while read -r expected rel extra; do
            [ -n "${expected:-}" ] || continue
            case "$expected" in \#*) continue ;; esac
            dest="$CACHE/$rel"
            printf '%s  %s\n' "$expected" "$dest" | sha256sum -c --quiet - 2>/dev/null || { ok=0; break; }
        done < "$manifest"
        [ "$ok" -eq 1 ] || break
    done
    return $((1 - ok))
}

if [ -f "$marker" ] && [ "$(cat "$marker")" = "$lock_sha" ] && verify_cached; then
    echo "cache hit: $LOCK ($lock_sha)"
    exit 0
fi

kernel_release=$(lock_get kernel_release)
kernel_sums=$(lock_get kernel_sums)
base_apps_release=$(lock_get base_apps_release)
base_apps_sums=$(lock_get base_apps_sums)
uboot_release=$(lock_get uboot_release)
uboot_sums=$(lock_get uboot_sums)

fetch_manifest kernel "$kernel_release" "$kernel_sums"
fetch_manifest base "$base_apps_release" "$base_apps_sums"
fetch_manifest uboot "$uboot_release" "$uboot_sums"

# Component manifest names differ from the asset prefix; map each to the
# release it came from.
download_list() {
    release=$1 manifest=$2
    while read -r expected rel extra; do
        [ -n "${expected:-}" ] || continue
        case "$expected" in \#*) continue ;; esac
        [ -z "${extra:-}" ] || { echo "invalid manifest row: $rel" >&2; exit 1; }
        case "$rel" in */../*|../*|*/..|/*) echo "unsafe path: $rel" >&2; exit 1 ;; esac
        dest="$CACHE/$rel"
        mkdir -p "$(dirname "$dest")"
        if [ -f "$dest" ] && printf '%s  %s\n' "$expected" "$dest" | sha256sum -c --quiet -; then
            echo "cache hit: $rel"
            continue
        fi
        asset=${rel##*/}
        encoded=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="._+-"))' "$asset")
        rm -f "$dest"
        curl --fail --location --silent --show-error --retry 3 \
            "$BASE/$release/$encoded" --output "$dest"
        printf '%s  %s\n' "$expected" "$dest" | sha256sum -c --quiet -
        echo "fetch: $rel"
    done < "$manifest"
}

download_list "$kernel_release" "$CACHE/manifests/SHA256SUMS.kernel"
download_list "$base_apps_release" "$CACHE/manifests/SHA256SUMS.base"
download_list "$uboot_release" "$CACHE/manifests/SHA256SUMS.uboot"

printf '%s\n' "$lock_sha" > "$marker"
echo "inputs: kernel=$kernel_release base=$base_apps_release uboot=$uboot_release"
