#!/bin/sh
# Regenerate the image package list from the layered lists in this directory.
#
# Layering keeps system base, desktop, multimedia and bundled applications
# separate so each can be reviewed and updated independently.
#
#   boards/z96a-v2/packages/{base,desktop,multimedia,applications}.txt
#        -> files/rootfs-overlay/z96a-v2/opt/z96a/runtime-packages.txt
#
# Run after editing any layer. `tests/test_repo_consistency.py` fails when the
# generated file and the layers disagree.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
SRC="$ROOT/boards/z96a-v2/packages"
OUT="$ROOT/files/rootfs-overlay/z96a-v2/opt/z96a/runtime-packages.txt"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM

: > "$tmp"
for layer in base desktop multimedia applications; do
    file="$SRC/$layer.txt"
    [ -f "$file" ] || { echo "missing layer: $file" >&2; exit 1; }
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        printf '%s\n' "$line" >> "$tmp"
    done < "$file"
done

# Reject duplicates across layers: a package must be owned by exactly one.
dupes=$(sort "$tmp" | uniq -d)
if [ -n "$dupes" ]; then
    echo "duplicate packages across layers:" >&2
    printf '%s\n' "$dupes" >&2
    exit 1
fi

install -m 0644 "$tmp" "$OUT"
printf 'generated %s (%s packages)\n' "$OUT" "$(wc -l < "$OUT")"
