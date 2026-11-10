#!/bin/bash
# Collect the image produced by a CI build and write release evidence.
#
# - finds the newest output/<board>/image/*.img.xz
# - verifies its .sha256 sidecar
# - parses [BUILD-TIME] TOTAL from the build log when present
# - writes output/ci/build-evidence.json
# - prints key=value lines (also appended to $GITHUB_OUTPUT when set)
#
# Usage:
#   boards/z96a-v2/tools/ci-collect-image.sh \
#     [--log build.log] [--validation PASS|FAIL] [--tag v1.2.3] [--channel stable]
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

BOARD=z96a-v2
LOG=""
VALIDATION="PENDING"
TAG=${RELEASE_TAG:-}
CHANNEL=${RELEASE_CHANNEL:-nightly}

while [ $# -gt 0 ]; do
    case "$1" in
        --log) LOG=${2:?}; shift 2 ;;
        --validation) VALIDATION=${2:?}; shift 2 ;;
        --tag) TAG=${2:?}; shift 2 ;;
        --channel) CHANNEL=${2:?}; shift 2 ;;
        --help|-h) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

IMAGE_XZ=$(ls -t output/"$BOARD"/image/*.img.xz 2>/dev/null | head -n 1 || true)
[ -n "$IMAGE_XZ" ] || { echo "no built image under output/$BOARD/image" >&2; exit 1; }
[ -f "$IMAGE_XZ.sha256" ] || { echo "missing checksum: $IMAGE_XZ.sha256" >&2; exit 1; }
(cd "$(dirname "$IMAGE_XZ")" && sha256sum -c "$(basename "$IMAGE_XZ").sha256")

NAME=$(basename "$IMAGE_XZ")
SHA=$(sha256sum "$IMAGE_XZ" | cut -d' ' -f1)
SIZE=$(stat -c '%s' "$IMAGE_XZ")
TOTAL=${BUILD_SECONDS:-}
if [ -z "$TOTAL" ] && [ -n "$LOG" ] && [ -f "$LOG" ]; then
    TOTAL=$(sed -n 's/^\[BUILD-TIME\] TOTAL: \([0-9]*\)s$/\1/p' "$LOG" | tail -n 1)
fi
TOTAL=${TOTAL:-}

# Open the source manifest produced by the build (inside the image it is also
# at /etc/z96a/manifest.json). output/<board>/manifest.json is the host copy.
MANIFEST="output/$BOARD/manifest.json"
[ -f "$MANIFEST" ] || MANIFEST=""

EVIDENCE="output/ci/build-evidence.json"
mkdir -p output/ci
python3 - "$EVIDENCE" "$NAME" "$IMAGE_XZ" "$SHA" "$SIZE" "$TOTAL" "$VALIDATION" "$TAG" "$CHANNEL" "$MANIFEST" <<'PY'
import json, os, subprocess, sys
path, name, image, sha, size, total, validation, tag, channel, manifest = sys.argv[1:]
data = {
    "image": name,
    "image_path": image,
    "sha256": sha,
    "compressed_bytes": int(size),
    "compressed_mib": round(int(size) / (1024 * 1024), 1),
    "build_seconds": int(total) if total else None,
    "validation": validation,
    "release_tag": tag or None,
    "channel": channel or None,
    "commit": subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True,
                             text=True).stdout.strip() or None,
}
if manifest and os.path.exists(manifest):
    try:
        m = json.load(open(manifest))
        data["kernel"] = m.get("kernel", {}).get("version")
        data["mesa"] = m.get("mesa", {}).get("version")
        data["installed_packages"] = m.get("packages", {}).get("installed_count")
        data["artifact_name"] = m.get("release_info", {}).get("artifact_name")
    except Exception as exc:  # keep evidence even if the manifest is odd
        data["manifest_error"] = str(exc)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
print("evidence written: %s" % path)
PY

OUTPUTS="name=$NAME"
OUTPUTS="$OUTPUTS
image=$IMAGE_XZ
sha256=$SHA
size=$SIZE
evidence=$EVIDENCE"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    # stdin heredoc syntax keeps the multiline file write portable.
    {
        printf 'name=%s\n' "$NAME"
        printf 'image=%s\n' "$IMAGE_XZ"
        printf 'sha256=%s\n' "$SHA"
        printf 'size=%s\n' "$SIZE"
        printf 'evidence=%s\n' "$EVIDENCE"
    } >> "$GITHUB_OUTPUT"
fi
printf '%s\n' "$OUTPUTS"
echo "COLLECT: PASS"
