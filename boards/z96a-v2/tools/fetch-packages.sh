#!/bin/bash
# Fetch bundled .deb files that are not kept in git.
#
# Blobs live outside the repository (artifact cache, release assets or vendor
# URLs). This script restores them into the overlay and verifies SHA256 against
# boards/<board>/packages-sources.tsv + the package SHA256SUMS.
#
# Usage:
#   boards/z96a-v2/tools/fetch-packages.sh [--from DIR]
#
#   --from DIR   copy missing debs from a local artifact cache directory
#   Z96A_FETCH_URL_BASE  prefix for entries whose url column is empty
set -u
export LC_ALL=C

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

BOARD=z96a-v2
PKG_DIR="files/rootfs-overlay/$BOARD/opt/z96a/packages"
SOURCES="boards/$BOARD/packages-sources.tsv"
FROM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --from) FROM=${2:?}; shift 2 ;;
        --help|-h) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -f "$SOURCES" ] || { echo "missing $SOURCES" >&2; exit 1; }
mkdir -p "$PKG_DIR"

fail=0
while IFS=$'\t' read -r name sha url license; do
    case "$name" in ''|'#'*) continue ;; esac
    target="$PKG_DIR/$name"
    if [ -f "$target" ]; then
        if printf '%s  %s\n' "$sha" "$target" | sha256sum -c --quiet - 2>/dev/null; then
            printf 'ok      %s\n' "$name"
            continue
        fi
        echo "BAD     $name (checksum mismatch, removing)"
        rm -f "$target"
    fi

    if [ -z "$url" ] || [ "$url" = "build artifact" ]; then
        if [ -n "$FROM" ] && [ -f "$FROM/$name" ]; then
            cp -f "$FROM/$name" "$target"
        else
            printf 'MISSING %s (no url; provide via --from or artifact cache)\n' "$name"
            fail=$((fail + 1))
            continue
        fi
    elif [ -n "${Z96A_FETCH_URL_BASE:-}" ] && [ "$url" = "relative" ]; then
        curl -fsSL -o "$target" "${Z96A_FETCH_URL_BASE%/}/$name" || { echo "FETCH FAIL $name"; fail=$((fail+1)); continue; }
    else
        curl -fsSL -o "$target" "$url" || { echo "FETCH FAIL $name"; fail=$((fail + 1)); continue; }
    fi

    if printf '%s  %s\n' "$sha" "$target" | sha256sum -c --quiet -; then
        printf 'fetched %s\n' "$name"
    else
        echo "BAD     $name (checksum mismatch)"
        rm -f "$target"
        fail=$((fail + 1))
    fi
done < "$SOURCES"

# Keep the packages SHA256SUMS in sync with what is on disk.
if [ -d "$PKG_DIR" ]; then
    tmp_sums=$(mktemp "$PKG_DIR/SHA256SUMS.XXXXXX")
    if ( cd "$PKG_DIR" && sha256sum -- *.deb ) > "$tmp_sums"; then
        if ! cmp -s "$tmp_sums" "$PKG_DIR/SHA256SUMS"; then
            mv -f "$tmp_sums" "$PKG_DIR/SHA256SUMS"
        else
            rm -f "$tmp_sums"
        fi
    else
        rm -f "$tmp_sums"
        echo "failed to generate package checksums" >&2
        exit 1
    fi
    printf 'updated %s/SHA256SUMS\n' "$PKG_DIR"
fi

if [ "$fail" -eq 0 ]; then echo "FETCH: PASS"; exit 0; fi
echo "FETCH: FAIL ($fail)"
exit 1
