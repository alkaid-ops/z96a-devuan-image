#!/bin/bash
# Download the immutable CI input set from this repository's inputs-vN release.
# The SHA256 manifest is downloaded first; every input is verified before use.
#
# Usage: boards/z96a-v2/tools/ci-fetch-inputs.sh
# Env: Z96A_INPUT_CACHE (required), Z96A_INPUTS_RELEASE (default inputs-v2),
#      GITHUB_REPOSITORY (defaults to alkaid-ops/z96a-devuan-image).
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

CACHE=${Z96A_INPUT_CACHE:?set Z96A_INPUT_CACHE}
RELEASE=${Z96A_INPUTS_RELEASE:-inputs-v2}
REPOSITORY=${GITHUB_REPOSITORY:-alkaid-ops/z96a-devuan-image}
BASE="https://github.com/${REPOSITORY}/releases/download/${RELEASE}"
MANIFEST="$CACHE/SHA256SUMS.inputs"

mkdir -p "$CACHE/packages" "$CACHE/tarball" "$CACHE/debs"
manifest_tmp=$(mktemp "$CACHE/SHA256SUMS.inputs.XXXXXX")
trap 'rm -f "$manifest_tmp"' EXIT
curl --fail --location --silent --show-error --retry 3 \
    "$BASE/SHA256SUMS.inputs" --output "$manifest_tmp"
grep -Eq '^[0-9a-f]{64}[[:space:]]+[^[:space:]]+$' "$manifest_tmp" || {
    echo "invalid or empty input checksum manifest" >&2
    exit 1
}
mv -f "$manifest_tmp" "$MANIFEST"

count=0
while read -r expected rel extra; do
    [ -n "${expected:-}" ] || continue
    case "$expected" in \#*) continue ;; esac
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid SHA256: $expected" >&2; exit 1; }
    [ -z "${extra:-}" ] || { echo "invalid checksum manifest row: $rel" >&2; exit 1; }
    case "$rel" in */../*|../*|*/..|/*) echo "unsafe input path: $rel" >&2; exit 1 ;; esac
    case "$rel" in
        packages/*.deb) dest="$CACHE/$rel" ;;
        tarball/*.tar.xz) dest="$CACHE/$rel" ;;
        debs/*.deb) dest="$CACHE/$rel" ;;
        *) echo "unexpected input path in manifest: $rel" >&2; exit 1 ;;
    esac
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ] && printf '%s  %s\n' "$expected" "$dest" | sha256sum -c --quiet -; then
        echo "cache hit: $rel"
    else
        rm -f "$dest"
        asset=${rel##*/}
        encoded=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="._+-"))' "$asset")
        echo "fetch: $rel"
        curl --fail --location --silent --show-error --retry 3 \
            "$BASE/$encoded" --output "$dest"
        printf '%s  %s\n' "$expected" "$dest" | sha256sum -c --quiet -
    fi
    count=$((count + 1))
done < "$MANIFEST"

[ "$count" -gt 0 ] || { echo "empty input manifest: $MANIFEST" >&2; exit 1; }

# Re-check all inputs as a set so an interrupted/partial cache cannot pass.
while read -r expected rel extra; do
    [ -n "${expected:-}" ] || continue
    case "$expected" in \#*) continue ;; esac
    [ -z "${extra:-}" ] || exit 1
    case "$rel" in packages/*.deb|tarball/*.tar.xz|debs/*.deb) ;; *) exit 1 ;; esac
    printf '%s  %s\n' "$expected" "$CACHE/$rel"
done < "$MANIFEST" | sha256sum --check --quiet -

echo "INPUT FETCH: PASS ($count assets, release $RELEASE)"
