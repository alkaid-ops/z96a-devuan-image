#!/usr/bin/env bash
# Resolve an explicit component combination into an ephemeral, checksum-pinned
# lock file. With no component tags, copy the repository's reviewed lock.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

LOCK_OUT=${1:?usage: ci-resolve-inputs.sh LOCK_OUT COMPONENTS_JSON}
JSON_OUT=${2:?usage: ci-resolve-inputs.sh LOCK_OUT COMPONENTS_JSON}
REPOSITORY=${GITHUB_REPOSITORY:-alkaid-ops/z96a-devuan-image}
tags=("${KERNEL_RELEASE:-}" "${BASE_APPS_RELEASE:-}" "${UBOOT_RELEASE:-}")
present=0
for tag in "${tags[@]}"; do [ -z "$tag" ] || present=$((present + 1)); done

mkdir -p "$(dirname "$LOCK_OUT")" "$(dirname "$JSON_OUT")"
if [ "$present" -eq 0 ]; then
    cp config/inputs.lock "$LOCK_OUT"
    python3 - "$LOCK_OUT" "$JSON_OUT" <<'PY'
import json, re, sys
lock, output = sys.argv[1:]
values = {}
for line in open(lock, encoding="utf-8"):
    match = re.match(r'^\s*(\w+)\s*=\s*"([^"]+)"', line)
    if match:
        values[match.group(1)] = match.group(2)
components = {
    "kernel": {"release": values["kernel_release"], "sums_sha256": values["kernel_sums"]},
    "base_apps": {"release": values["base_apps_release"], "sums_sha256": values["base_apps_sums"]},
    "uboot": {"release": values["uboot_release"], "sums_sha256": values["uboot_sums"]},
    "selection": "config/inputs.lock",
}
with open(output, "w", encoding="utf-8") as f:
    json.dump(components, f, indent=2, sort_keys=True)
    f.write("\n")
PY
else
    [ "$present" -eq 3 ] || { echo "supply all three component tags, or leave all empty" >&2; exit 2; }
    [[ ${tags[0]} =~ ^kernel-[A-Za-z0-9.+_-]+$ ]] || { echo "invalid kernel tag" >&2; exit 2; }
    [[ ${tags[1]} =~ ^base-apps-[A-Za-z0-9.+_-]+$ ]] || { echo "invalid base-apps tag" >&2; exit 2; }
    [[ ${tags[2]} =~ ^uboot-[A-Za-z0-9.+_-]+$ ]] || { echo "invalid U-Boot tag" >&2; exit 2; }
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    names=(kernel base uboot)
    releases=("${tags[@]}")
    keys=(kernel_release base_apps_release uboot_release)
    sum_keys=(kernel_sums base_apps_sums uboot_sums)
    declare -a sums=()
    for i in 0 1 2; do
        tag=${releases[$i]}
        state=$(gh release view "$tag" --repo "$REPOSITORY" --json isDraft,isPrerelease -q '[.isDraft,.isPrerelease] | @tsv')
        IFS=$'\t' read -r is_draft is_prerelease <<< "$state"
        [ "$is_draft" = false ] || { echo "component release is a draft: $tag" >&2; exit 1; }
        [ "$is_prerelease" = true ] || { echo "component release must be a prerelease: $tag" >&2; exit 1; }
        mkdir -p "$tmp/$tag"
        gh release download "$tag" --repo "$REPOSITORY" --dir "$tmp/$tag" \
            --pattern "SHA256SUMS.${names[$i]}"
        manifest="$tmp/$tag/SHA256SUMS.${names[$i]}"
        [ -s "$manifest" ] || { echo "missing component checksum manifest: $tag" >&2; exit 1; }
        sums[$i]=$(sha256sum "$manifest" | cut -d' ' -f1)
    done
    {
        echo "${keys[0]} = \"${releases[0]}\""
        echo "${sum_keys[0]} = \"${sums[0]}\""
        echo "${keys[1]} = \"${releases[1]}\""
        echo "${sum_keys[1]} = \"${sums[1]}\""
        echo "${keys[2]} = \"${releases[2]}\""
        echo "${sum_keys[2]} = \"${sums[2]}\""
    } > "$LOCK_OUT"
    python3 - "$JSON_OUT" "${releases[@]}" "${sums[@]}" <<'PY'
import json, sys
path, kernel, base, uboot, kernel_sha, base_sha, uboot_sha = sys.argv[1:]
data = {
    "kernel": {"release": kernel, "sums_sha256": kernel_sha},
    "base_apps": {"release": base, "sums_sha256": base_sha},
    "uboot": {"release": uboot, "sums_sha256": uboot_sha},
    "selection": "explicit workflow inputs",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
fi

echo "resolved component lock: $(sha256sum "$LOCK_OUT" | cut -d' ' -f1)"
cat "$JSON_OUT"
