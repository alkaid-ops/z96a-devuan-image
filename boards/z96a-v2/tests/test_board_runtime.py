#!/usr/bin/env python3
"""Prove board.runtime equals the historical sed-mutation of board.txt.

The old `customize_image` edited board.txt with `sed -i`. The new path writes
board.runtime instead. This test replays the old sed chain in a temp dir for
several custom.txt permutations and compares the resulting variables with the
output of tools/gen-board-runtime.py.
"""

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BOARD = "z96a-v2"
BOARD_FILE = ROOT / "lib/boards" / BOARD
GEN = ROOT / "boards" / BOARD / "tools" / "gen-board-runtime.py"

VAR = re.compile(r'^([A-Z][A-Z0-9_]*)="(.*)"$')

# custom.txt permutations covering every branch of the old sed chain.
CASES = {
    "current": {
        "ENABLE_BOOT_EXT4": "false", "FSTYPE": "ext4", "ENABLE_BOOTCMD": "false",
        "ENABLE_EFI": "false", "ENABLE_PETITBOOT": "false", "ENABLE_BOOT_VFAT": "true",
    },
    "efi": {
        "ENABLE_BOOT_EXT4": "false", "FSTYPE": "ext4", "ENABLE_BOOTCMD": "false",
        "ENABLE_EFI": "true", "ENABLE_PETITBOOT": "false", "ENABLE_BOOT_VFAT": "false",
    },
    "bootcmd": {
        "ENABLE_BOOT_EXT4": "false", "FSTYPE": "ext4", "ENABLE_BOOTCMD": "true",
        "ENABLE_EFI": "false", "ENABLE_PETITBOOT": "false", "ENABLE_BOOT_VFAT": "false",
    },
    "bootext4+btrfs": {
        "ENABLE_BOOT_EXT4": "true", "FSTYPE": "btrfs", "ENABLE_BOOTCMD": "false",
        "ENABLE_EFI": "false", "ENABLE_PETITBOOT": "false", "ENABLE_BOOT_VFAT": "false",
    },
    "petitboot": {
        "ENABLE_BOOT_EXT4": "false", "FSTYPE": "ext4", "ENABLE_BOOTCMD": "false",
        "ENABLE_EFI": "false", "ENABLE_PETITBOOT": "true", "ENABLE_BOOT_VFAT": "false",
    },
    "everything": {
        "ENABLE_BOOT_EXT4": "true", "FSTYPE": "xfs", "ENABLE_BOOTCMD": "true",
        "ENABLE_EFI": "true", "ENABLE_PETITBOOT": "true", "ENABLE_BOOT_VFAT": "true",
    },
}

# Transcription of the sed chain in lib/function/staging::customize_image.
OLD_CHAIN = r'''
set -u
FSTYPE="$1"; ENABLE_BOOTCMD="$2"; ENABLE_BOOT_EXT4="$3"
ENABLE_BOOT_VFAT="$4"; ENABLE_EFI="$5"; ENABLE_PETITBOOT="$6"
f=board.txt
if [ "$FSTYPE" = btrfs ] || [ "$FSTYPE" = xfs ]; then
  if grep -q 'P_VALUE="p1"' "$f"; then sed -i 's/P_VALUE="p1"/P_VALUE="p2"/g' "$f"; fi
fi
if ! grep -q 'FAMILY="broadcom"' "$f"; then
  if [ "$ENABLE_BOOTCMD" = true ] && [ "$ENABLE_PETITBOOT" = false ]; then
    if grep -q 'EXTLINUX="true"' "$f"; then sed -i 's/EXTLINUX="true"/EXTLINUX="false"/g' "$f"; fi
    if grep -q 'BOOTCMD="false"' "$f"; then sed -i 's/BOOTCMD="false"/BOOTCMD="true"/g' "$f"; fi
  fi
fi
if [ "$ENABLE_BOOT_EXT4" = true ]; then
  if grep -q 'BOOT_EXT4="false"' "$f"; then sed -i 's/BOOT_EXT4="false"/BOOT_EXT4="true"/g' "$f"; fi
  if grep -q 'P_VALUE="p1"' "$f"; then sed -i 's/P_VALUE="p1"/P_VALUE="p2"/g' "$f"; fi
fi
if [ "$ENABLE_BOOT_VFAT" = true ]; then
  if grep -q 'BOOT_VFAT="false"' "$f"; then sed -i 's/BOOT_VFAT="false"/BOOT_VFAT="true"/g' "$f"; fi
  if grep -q 'P_VALUE="p1"' "$f"; then sed -i 's/P_VALUE="p1"/P_VALUE="p2"/g' "$f"; fi
fi
if ! grep -q 'FAMILY="broadcom"' "$f"; then
  if [ "$ENABLE_EFI" = true ]; then
    sed -i 's/EFI="false"/EFI="true"/g' "$f"
    if grep -q 'BOOT_VFAT="false"' "$f"; then sed -i 's/BOOT_VFAT="false"/BOOT_VFAT="true"/g' "$f"; fi
    if grep -q 'P_VALUE="p1"' "$f"; then sed -i 's/P_VALUE="p1"/P_VALUE="p2"/g' "$f"; fi
    if grep -q 'EXTLINUX="true"' "$f"; then sed -i 's/EXTLINUX="true"/EXTLINUX="false"/g' "$f"; fi
    if grep -q 'BOOTCMD="true"' "$f"; then sed -i 's/BOOTCMD="true"/BOOTCMD="false"/g' "$f"; fi
    if grep -q 'BOOTINI="true"' "$f"; then sed -i 's/BOOTINI="true"/BOOTCMD="false"/g' "$f"; fi
    if grep -q 'FAMILY="rockchip"' "$f" && grep -q 'GPT="false"' "$f"; then
      sed -i 's/GPT="false"/GPT="true"/g' "$f"
    fi
  fi
fi
if [ "$ENABLE_PETITBOOT" = true ] && grep -q 'FAMILY_EXT="odroid"' "$f"; then
  sed -i 's/P_VALUE="p1"/P_VALUE="p2"/g' "$f"
  sed -i 's/EXTLINUX="true"/EXTLINUX="false"/g' "$f"
  sed -i 's/PETITBOOT="false"/PETITBOOT="true"/g' "$f"
fi
'''


def parse_vars(path):
    values = {}
    for line in Path(path).read_text(errors="replace").splitlines():
        match = VAR.match(line)
        if match:
            values[match.group(1)] = match.group(2)
    return values


def overrides(path):
    values = {}
    for line in Path(path).read_text(errors="replace").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        match = VAR.match(line)
        if match:
            values[match.group(1)] = match.group(2)
    return values


class BoardRuntimeTests(unittest.TestCase):
    def test_runtime_equivalent_to_old_sed_chain(self):
        board_text = BOARD_FILE.read_text()
        for name, custom in CASES.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root / "custom.txt").write_text(
                    "".join(f'{k}="{v}"\n' for k, v in custom.items()))
                (root / "board.txt").write_text(board_text)
                subprocess.run(
                    ["bash", "-c", OLD_CHAIN, "_",
                     custom["FSTYPE"], custom["ENABLE_BOOTCMD"],
                     custom["ENABLE_BOOT_EXT4"], custom["ENABLE_BOOT_VFAT"],
                     custom["ENABLE_EFI"], custom["ENABLE_PETITBOOT"]],
                    cwd=root, check=True, capture_output=True)
                expected = parse_vars(root / "board.txt")

                result = subprocess.run(
                    ["python3", str(GEN), str(BOARD_FILE), str(root / "custom.txt")],
                    capture_output=True, text=True, check=True)
                runtime = overrides_text(result.stdout)

                applied = dict(parse_vars(BOARD_FILE))
                applied.update(runtime)
                self.assertEqual(applied, expected, f"case {name} diverged")


def overrides_text(text):
    values = {}
    for line in text.splitlines():
        match = VAR.match(line)
        if match:
            values[match.group(1)] = match.group(2)
    return values


if __name__ == "__main__":
    unittest.main(verbosity=2)
