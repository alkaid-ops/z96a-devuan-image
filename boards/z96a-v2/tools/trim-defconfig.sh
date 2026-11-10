#!/bin/bash
# Apply boards/<board>/defconfig-trim.txt to defconfig/<board>_defconfig.
#
# Disabling a symbol is done by writing "# CONFIG_X is not set", which is what
# `make defconfig` produces. Parent symbols are disabled first (the list is
# ordered), and dependencies are resolved by the kernel's `olddefconfig` during
# the normal kernel build.
#
# Usage:
#   boards/z96a-v2/tools/trim-defconfig.sh           # apply (idempotent)
#   boards/z96a-v2/tools/trim-defconfig.sh --check   # exit 1 if not applied
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
BOARD=${BOARD:-z96a-v2}
DEFCONFIG="$ROOT/defconfig/${BOARD}_defconfig"
TRIM="$ROOT/boards/$BOARD/defconfig-trim.txt"
MODE=${1:-apply}

[ -f "$DEFCONFIG" ] || { echo "missing $DEFCONFIG" >&2; exit 1; }
[ -f "$TRIM" ] || { echo "missing $TRIM" >&2; exit 1; }

missing=0
while IFS= read -r line; do
	case "$line" in ''|'#'*) continue ;; esac
	# only "-# CONFIG_X" entries disable symbols
	case "$line" in
		'-# '*)
			sym=${line#-# }
			if ! grep -qx "# ${sym} is not set" "$DEFCONFIG"; then
				missing=$((missing + 1))
				if [ "$MODE" = apply ]; then
					# replace an existing "CONFIG_X=y/m" line, or append
					if grep -qE "^${sym}=" "$DEFCONFIG"; then
						sed -i "s|^${sym}=.*|# ${sym} is not set|" "$DEFCONFIG"
					else
						printf '# %s is not set\n' "$sym" >> "$DEFCONFIG"
					fi
				fi
			fi
			;;
	esac
done < "$TRIM"

if [ "$MODE" = check ]; then
	if [ "$missing" -eq 0 ]; then
		echo "DEFCONFIG TRIM: PASS"
		exit 0
	fi
	echo "DEFCONFIG TRIM: FAIL ($missing symbols still enabled)" >&2
	exit 1
fi
echo "defconfig trimmed ($missing symbols updated): $DEFCONFIG"
