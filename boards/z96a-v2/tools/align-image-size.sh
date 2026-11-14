#!/usr/bin/env bash
# Trim non-sector-aligned trailing padding from a raw disk image.
#
# GPT/MBR describe a disk in logical sectors. Image sizing via decimal MB can
# leave zero padding after the final complete sector; keep the disk's declared
# sector count unchanged and discard only those bytes before block-device use.
set -euo pipefail

image=${1:?usage: align-image-size.sh IMAGE [SECTOR_SIZE]}
sector_size=${2:-512}
[ -f "$image" ] || { echo "image not found: $image" >&2; exit 2; }
[[ "$sector_size" =~ ^[1-9][0-9]*$ ]] || { echo "invalid sector size: $sector_size" >&2; exit 2; }

size=$(stat -c '%s' -- "$image")
remainder=$((size % sector_size))
if [ "$remainder" -eq 0 ]; then
    echo "image already sector aligned: $size bytes (sector size $sector_size)"
    exit 0
fi

aligned=$((size - remainder))
[ "$aligned" -ge "$sector_size" ] || { echo "image is smaller than one sector" >&2; exit 1; }
truncate -s "$aligned" -- "$image"
echo "trimmed $remainder trailing byte(s): $size -> $aligned bytes (sector size $sector_size)"
