#!/bin/bash
# Generate (or verify) the board variables from config/<board>.toml.
#
# Phase 2 migration step M1: config/z96a-v2.toml is the editable source of
# truth; lib/boards/<board> and board.txt are generated from it. While M1 is in
# place the two must stay byte-identical, enforced by --check.
#
# Usage:
#   boards/z96a-v2/tools/gen-board-config.sh [--check] [--write]
#
#   --check   fail if lib/boards/<board> differs from the generated result
#   --write   replace lib/boards/<board> with the generated result
#   (default) print the generated file to stdout
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

BOARD=z96a-v2
CONFIG="config/$BOARD.toml"
TARGET="lib/boards/$BOARD"

MODE="print"
while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --write) MODE="write"; shift ;;
        --help|-h) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -f "$CONFIG" ] || { echo "missing $CONFIG" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

generated=$(mktemp)
trap 'rm -f "$generated"' EXIT HUP INT TERM

python3 - "$CONFIG" > "$generated" <<'PY'
import json, sys, tomllib

with open(sys.argv[1], "rb") as handle:
    data = tomllib.load(handle)

variables = data.get("vars", {})
if not variables:
    raise SystemExit("config has no [vars] section")

print("#!/bin/bash")
print("# GENERATED from %s by boards/<board>/tools/gen-board-config.sh" % sys.argv[1])
print("# Do not edit by hand; edit the TOML and run --write.")
print()

for key, value in variables.items():
    if isinstance(value, bool):
        value = "true" if value else "false"
    elif isinstance(value, int):
        value = str(value)
    else:
        value = str(value)
    # keep shell default-expansion syntax ($ARCH etc.) verbatim
    print(f'{key}="{value}"')
PY

header_ok() {
    # Compare only the variable lines: the generated file carries a header.
    grep -vE '^(#!/bin/bash|#|$)' "$1" || true
}

case "$MODE" in
    print)
        cat "$generated"
        ;;
    write)
        install -m 0644 "$generated" "$TARGET"
        printf 'wrote %s\n' "$TARGET"
        ;;
    check)
        if diff -q <(header_ok "$generated") <(header_ok "$TARGET") >/dev/null 2>&1; then
            echo "CONFIG SOURCE: PASS ($CONFIG == $TARGET)"
            exit 0
        fi
        echo "CONFIG SOURCE: FAIL ($CONFIG and $TARGET disagree)" >&2
        diff -u <(header_ok "$TARGET") <(header_ok "$generated") | sed -n '1,40p' >&2
        exit 1
        ;;
esac
