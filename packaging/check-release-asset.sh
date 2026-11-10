#!/usr/bin/env bash
set -euo pipefail

usage () {
	cat <<'EOF'
Usage: packaging/check-release-asset.sh IMAGE.img.xz

Checks that an image is smaller than GitHub's 2 GiB per-asset limit, passes xz integrity validation, and matches its .sha256 file. Does not upload it.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi
if [[ "$#" -ne 1 ]]; then
	usage >&2
	exit 2
fi

image="$1"
max_bytes=2147483648

if [[ ! -f "$image" ]]; then
	echo "Image not found: $image" >&2
	exit 1
fi
if [[ "$image" != *.img.xz ]]; then
	echo "Expected a .img.xz image: $image" >&2
	exit 1
fi

size_bytes=$(stat -c '%s' -- "$image")
if (( size_bytes >= max_bytes )); then
	printf 'Image is too large for a GitHub Release asset (%s bytes; must be under %s bytes / 2 GiB).\n' "$size_bytes" "$max_bytes" >&2
	exit 1
fi

checksum_file="${image}.sha256"
if [[ ! -f "$checksum_file" ]]; then
	echo "Checksum file not found: $checksum_file" >&2
	exit 1
fi

echo "Checking XZ integrity..."
xz -t -- "$image"
echo "Checking SHA-256..."
(cd -- "$(dirname -- "$image")" && sha256sum --check -- "$(basename -- "$checksum_file")")
printf 'Release asset preflight passed: %s (%s bytes; under 2 GiB).\n' "$image" "$size_bytes"
