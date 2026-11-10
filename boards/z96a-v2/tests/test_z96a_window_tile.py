#!/usr/bin/env python3
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[3]
SCRIPT = ROOT / "files/rootfs-overlay/z96a-v2/opt/z96a/window/z96a-window-tile"
USERSCRIPT_DIR = ROOT / "boards/z96a-v2/userscripts"


def userscripts_text():
    parts = [(USERSCRIPT_DIR / "uscripts").read_text(encoding="utf-8")]
    for module in sorted(USERSCRIPT_DIR.rglob("*.sh")):
        parts.append(module.read_text(encoding="utf-8"))
    return "\n".join(parts)
SHORTCUTS = ROOT / "files/rootfs-overlay/z96a-v2/opt/z96a/session/lxqt/globalkeyshortcuts.conf"

MONITORS_ONE = """\
Monitors: 1
 0: +*eDP-1 1920/344x1080/193+0+0  eDP-1
"""

MONITORS_TWO = """\
Monitors: 2
 0: +*HDMI-1 1280/300x1024/200+0+0  HDMI-1
 1: +*eDP-1 1280/300x1024/200+1280+0  eDP-1
"""


class WindowTileTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.state_dir = self.root / "state"
        self.geom_file = self.root / "geometry"
        self.ewmh_file = self.root / "ewmh"
        self.log = self.root / "commands.log"
        self.monitors_file = self.root / "monitors"
        self.set_geometry()
        self.set_ewmh()
        self.set_monitors(MONITORS_ONE)
        self.write_fakes()

    def tearDown(self):
        self.tmp.cleanup()

    def set_geometry(self, x=100, y=100, width=800, height=600):
        self.geom_file.write_text(
            f"X={x}\nY={y}\nWIDTH={width}\nHEIGHT={height}\n",
            encoding="utf-8",
        )

    def set_ewmh(self, states=""):
        self.ewmh_file.write_text(states, encoding="utf-8")

    def set_monitors(self, text):
        self.monitors_file.write_text(text, encoding="utf-8")

    def write_fakes(self):
        self.fake(
            "xdotool",
            """\
            #!/bin/sh
            case "$1" in
                getactivewindow) echo 4194307 ;;
                getwindowgeometry)
                    printf 'WINDOW=%s\\n' 4194307
                    cat "$FAKE_GEOM_FILE"
                    ;;
                windowminimize) printf 'xdotool windowminimize %s\\n' "$2" >> "$FAKE_LOG" ;;
                getdisplaygeometry) echo "1920 1080" ;;
            esac
            """,
        )
        self.fake(
            "xwininfo",
            """\
            #!/bin/sh
            [ "$2" = 4194307 ] || exit 1
            . "$FAKE_GEOM_FILE"
            printf '  Absolute upper-left X:  %s\\n' "$X"
            printf '  Absolute upper-left Y:  %s\\n' "$Y"
            printf '  Width: %s\\n' "$WIDTH"
            printf '  Height: %s\\n' "$HEIGHT"
            """,
        )
        self.fake(
            "xprop",
            """\
            #!/bin/sh
            case "$1" in
                -root) printf '_NET_WORKAREA(CARDINAL) = %s\\n' "${FAKE_WORKAREA:-0, 0, 1920, 1050}" ;;
                -id)
                    case "$3" in
                        _NET_WM_STATE)
                            printf '_NET_WM_STATE(ATOM) = '
                            cat "$FAKE_EWMH_FILE"
                            ;;
                        _NET_FRAME_EXTENTS)
                            printf '_NET_FRAME_EXTENTS(CARDINAL) = %s\\n' "${FAKE_FRAME_EXTENTS:-0, 0, 0, 0}"
                            ;;
                        WM_NORMAL_HINTS)
                            printf 'WM_NORMAL_HINTS(WM_SIZE_HINTS):\\n\\t\\twindow gravity: %s\\n' "${FAKE_GRAVITY:-Static}"
                            ;;
                        WM_CLASS)
                            printf 'WM_CLASS(STRING) = "fake", "Fake"\\n'
                            ;;
                    esac
                    ;;
            esac
            """,
        )
        self.fake(
            "xrandr",
            """\
            #!/bin/sh
            case "$1" in
                --listmonitors) cat "$FAKE_MONITORS_FILE" ;;
                --query) cat "$FAKE_MONITORS_FILE" ;;
            esac
            """,
        )
        self.fake(
            "wmctrl",
            """\
            #!/bin/sh
            printf 'wmctrl %s\\n' "$*" >> "$FAKE_LOG"
            case "$*" in
                *"-b remove,maximized_vert"*)
                    if [ -f "$FAKE_GEOM_FILE.saved" ]; then
                        mv -f "$FAKE_GEOM_FILE.saved" "$FAKE_GEOM_FILE"
                    fi
                    : > "$FAKE_EWMH_FILE"
                    ;;
                *"-b remove,maximized_horz"*)
                    : > "$FAKE_EWMH_FILE"
                    ;;
                *"-b add,maximized_vert,maximized_horz"*)
                    cp "$FAKE_GEOM_FILE" "$FAKE_GEOM_FILE.saved"
                    printf 'X=0\\nY=0\\nWIDTH=1920\\nHEIGHT=1050\\n' > "$FAKE_GEOM_FILE"
                    printf '_NET_WM_STATE_MAXIMIZED_VERT, _NET_WM_STATE_MAXIMIZED_HORZ' > "$FAKE_EWMH_FILE"
                    ;;
            esac
            case "$*" in
                *" -e "*)
                    geometry=${*#* -e }
                    geometry=${geometry%% *}
                    old_ifs=$IFS
                    IFS=,
                    set -- $geometry
                    IFS=$old_ifs
                    gravity=$1; x=$2; y=$3; width=$4; height=$5
                    ext_left=0; ext_top=0
                    if [ -n "${FAKE_FRAME_EXTENTS:-}" ]; then
                        old_ifs=$IFS
                        IFS=', '
                        set -- $FAKE_FRAME_EXTENTS
                        IFS=$old_ifs
                        ext_left=${1:-0}; ext_top=${3:-0}
                    fi
                    case "${FAKE_GRAVITY:-Static}" in
                        Static) client_x=$x; client_y=$y ;;
                        *) client_x=$((x + ext_left)); client_y=$((y + ext_top)) ;;
                    esac
                    printf 'X=%s\\nY=%s\\nWIDTH=%s\\nHEIGHT=%s\\n' \\
                        "$client_x" "$client_y" "$width" "$height" > "$FAKE_GEOM_FILE"
                    ;;
            esac
            """,
        )
        self.fake(
            "sleep",
            """\
            #!/bin/sh
            exit 0
            """,
        )

    def fake(self, name, body):
        path = self.bin / name
        path.write_text(textwrap.dedent(body), encoding="utf-8")
        path.chmod(0o755)

    def run_tile(self, action, state="normal", **env_overrides):
        env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "DISPLAY": ":99",
            "Z96A_WINDOW_TILE_STATE_DIR": str(self.state_dir),
            "FAKE_GEOM_FILE": str(self.geom_file),
            "FAKE_EWMH_FILE": str(self.ewmh_file),
            "FAKE_MONITORS_FILE": str(self.monitors_file),
            "FAKE_LOG": str(self.log),
            "FAKE_GRAVITY": "Static",
        }
        env.update({key: str(value) for key, value in env_overrides.items()})
        return subprocess.run(
            ["/bin/sh", str(SCRIPT), action],
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )

    def resolve(self, state, direction):
        env = os.environ | {"PATH": f"{self.bin}:{os.environ['PATH']}"}
        return subprocess.run(
            ["/bin/sh", str(SCRIPT), "--resolve", state, direction],
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )

    def wmctrl_lines(self):
        if not self.log.exists():
            return []
        return [
            line.rstrip("\n")[len("wmctrl "):]
            for line in self.log.read_text(encoding="utf-8").splitlines()
            if line.startswith("wmctrl ")
        ]

    def last_geometry(self):
        for line in reversed(self.wmctrl_lines()):
            if " -e " in line:
                return line.split(" -e ", 1)[1]
        self.fail(f"no wmctrl -e call in {self.wmctrl_lines()}")

    def tracked_state(self):
        files = [
            path for path in self.state_dir.glob("*")
            if not path.name.endswith(".sig")
        ]
        self.assertEqual(len(files), 1, files)
        self.assertTrue(
            (files[0].parent / f"{files[0].name}.sig").exists(),
            "state signature file is missing",
        )
        return files[0].read_text(encoding="utf-8").strip()

    def test_resolve_cycles_like_kwin(self):
        cases = {
            ("normal", "left"): "left",
            ("normal", "right"): "right",
            ("normal", "up"): "top",
            ("normal", "down"): "bottom",
            ("maximized", "left"): "left",
            ("maximized", "down"): "bottom",
            ("left", "up"): "top-left",
            ("left", "down"): "bottom-left",
            ("right", "up"): "top-right",
            ("right", "down"): "bottom-right",
            ("top", "left"): "top-left",
            ("bottom", "right"): "bottom-right",
            ("top", "up"): "maximized",
            ("top-left", "up"): "maximized",
            ("top-right", "up"): "maximized",
            ("bottom", "down"): "minimized",
            ("bottom-left", "down"): "minimized",
            ("bottom-right", "down"): "minimized",
            ("top-left", "right"): "top",
            ("top-left", "down"): "left",
            ("top-right", "left"): "top",
            ("top-right", "down"): "right",
            ("bottom-left", "right"): "bottom",
            ("bottom-left", "up"): "left",
            ("bottom-right", "left"): "bottom",
            ("bottom-right", "up"): "right",
            ("left", "left"): "left",
            ("right", "left"): "left",
        }
        for (state, direction), expected in cases.items():
            with self.subTest(state=state, direction=direction):
                result = self.resolve(state, direction)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_unknown_state_or_direction_is_rejected(self):
        self.assertEqual(self.resolve("normal", "escape").returncode, 2)
        self.assertEqual(self.resolve("sideways", "left").returncode, 2)
        self.assertEqual(self.run_tile("unknown-action").returncode, 2)

    def test_left_tiles_to_half_workarea_and_remembers_original_geometry(self):
        result = self.run_tile("left")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.last_geometry(), "0,0,0,960,1050")
        self.assertEqual(self.tracked_state(), "v2 left 100 100 800 600")

    def test_left_then_right_cycles_to_the_other_half(self):
        self.assertEqual(self.run_tile("left").returncode, 0)
        self.assertEqual(self.run_tile("right").returncode, 0)
        self.assertEqual(self.last_geometry(), "0,960,0,960,1050")

    def test_left_then_up_reaches_top_left_quarter(self):
        self.assertEqual(self.run_tile("left").returncode, 0)
        self.assertEqual(self.run_tile("up").returncode, 0)
        self.assertEqual(self.last_geometry(), "0,0,0,960,525")
        self.assertEqual(self.tracked_state(), "v2 top-left 100 100 800 600")

    def test_top_right_then_down_becomes_right_half(self):
        self.assertEqual(self.run_tile("up").returncode, 0)
        self.assertEqual(self.run_tile("right").returncode, 0)
        self.assertEqual(self.run_tile("down").returncode, 0)
        self.assertEqual(self.last_geometry(), "0,960,0,960,1050")

    def test_up_on_top_half_maximizes(self):
        self.assertEqual(self.run_tile("up").returncode, 0)
        self.assertEqual(self.run_tile("up").returncode, 0)
        self.assertIn("-b add,maximized_vert,maximized_horz", self.wmctrl_lines()[-1])
        self.assertEqual(self.tracked_state(), "v2 maximized 100 100 800 600")

    def test_up_on_top_quarter_maximizes(self):
        self.assertEqual(self.run_tile("left").returncode, 0)
        self.assertEqual(self.run_tile("up").returncode, 0)
        self.assertEqual(self.run_tile("up").returncode, 0)
        self.assertIn("-b add,maximized_vert,maximized_horz", self.wmctrl_lines()[-1])
        self.assertEqual(self.tracked_state(), "v2 maximized 100 100 800 600")

    def test_up_on_top_right_quarter_maximizes(self):
        self.assertEqual(self.run_tile("up").returncode, 0)
        self.assertEqual(self.run_tile("right").returncode, 0)
        self.assertEqual(self.run_tile("up").returncode, 0)
        self.assertIn("-b add,maximized_vert,maximized_horz", self.wmctrl_lines()[-1])

    def test_down_on_bottom_half_minimizes(self):
        self.assertEqual(self.run_tile("down").returncode, 0)
        self.assertEqual(self.run_tile("down").returncode, 0)
        self.assertIn(
            "xdotool windowminimize 4194307",
            self.log.read_text(encoding="utf-8"),
        )
        self.assertEqual(self.tracked_state(), "v2 bottom 100 100 800 600")

    def test_down_on_bottom_corner_minimizes(self):
        self.assertEqual(self.run_tile("down").returncode, 0)
        self.assertEqual(self.run_tile("right").returncode, 0)
        self.assertEqual(self.run_tile("down").returncode, 0)
        self.assertIn(
            "xdotool windowminimize 4194307",
            self.log.read_text(encoding="utf-8"),
        )
        self.assertEqual(self.tracked_state(), "v2 bottom-right 100 100 800 600")

    def test_restore_returns_to_original_geometry_and_forgets_state(self):
        self.assertEqual(self.run_tile("left").returncode, 0)
        self.assertEqual(self.run_tile("restore").returncode, 0)
        self.assertEqual(self.last_geometry(), "0,100,100,800,600")
        self.assertEqual(list(self.state_dir.glob("*")), [])

    def test_stale_signature_is_ignored(self):
        self.state_dir.mkdir(parents=True)
        (self.state_dir / "4194307").write_text("v2 left 10 10 500 400\n", encoding="utf-8")
        (self.state_dir / "4194307.sig").write_text("1\n", encoding="utf-8")
        result = self.run_tile("up")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.last_geometry(), "0,0,0,1920,525")
        self.assertEqual(self.tracked_state(), "v2 top 100 100 800 600")

    def test_state_for_dead_window_is_pruned(self):
        self.state_dir.mkdir(parents=True)
        (self.state_dir / "999999").write_text("v2 left 1 1 10 10\n", encoding="utf-8")
        (self.state_dir / "999999.sig").write_text("1\n", encoding="utf-8")
        self.assertEqual(self.run_tile("left").returncode, 0)
        self.assertFalse((self.state_dir / "999999").exists())
        self.assertFalse((self.state_dir / "999999.sig").exists())

    def test_maximize_toggle_keeps_original_geometry(self):
        self.assertEqual(self.run_tile("maximize").returncode, 0)
        self.assertIn("-b add,maximized_vert,maximized_horz", self.wmctrl_lines()[-1])
        self.assertEqual(self.tracked_state(), "v2 maximized 100 100 800 600")
        self.assertEqual(self.run_tile("maximize").returncode, 0)
        self.assertEqual(self.last_geometry(), "0,100,100,800,600")
        self.assertEqual(list(self.state_dir.glob("*")), [])

    def test_directional_tile_clears_maximized_window(self):
        self.set_ewmh("_NET_WM_STATE_MAXIMIZED_VERT, _NET_WM_STATE_MAXIMIZED_HORZ")
        result = self.run_tile("left")
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.wmctrl_lines()
        self.assertIn("-i -r 4194307 -b remove,maximized_vert", lines)
        self.assertIn("-i -r 4194307 -b remove,maximized_horz", lines)
        self.assertEqual(self.last_geometry(), "0,0,0,960,1050")

    def test_fullscreen_is_cleared_before_tiling(self):
        self.set_ewmh("_NET_WM_STATE_FULLSCREEN")
        result = self.run_tile("right")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-i -r 4194307 -b remove,fullscreen", self.wmctrl_lines())
        self.assertEqual(self.last_geometry(), "0,960,0,960,1050")

    def test_minimize_uses_xdotool(self):
        self.assertEqual(self.run_tile("minimize").returncode, 0)
        self.assertIn(
            "xdotool windowminimize 4194307",
            self.log.read_text(encoding="utf-8"),
        )

    def test_left_at_left_edge_moves_to_adjacent_monitor_with_flipped_tile(self):
        self.set_monitors(MONITORS_TWO)
        self.set_geometry(x=1400, y=100, width=400, height=300)
        result = self.run_tile("left", FAKE_WORKAREA="0, 0, 2560, 1024")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.last_geometry(), "0,1280,0,640,1024")
        self.assertEqual(self.run_tile("left", FAKE_WORKAREA="0, 0, 2560, 1024").returncode, 0)
        self.assertEqual(self.last_geometry(), "0,640,0,640,1024")

    def test_panel_workarea_is_subtracted_from_tile_height(self):
        result = self.run_tile("left", FAKE_WORKAREA="0, 0, 1920, 1000")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.last_geometry(), "0,0,0,960,1000")

    def test_frame_extents_are_compensated(self):
        self.set_geometry(x=202, y=187, width=700, height=499)
        result = self.run_tile("left", FAKE_FRAME_EXTENTS="2, 2, 37, 2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.last_geometry(), "0,2,37,956,1011")
        self.assertEqual(self.tracked_state(), "v2 left 200 150 704 538")
        self.assertEqual(self.run_tile("restore", FAKE_FRAME_EXTENTS="2, 2, 37, 2").returncode, 0)
        self.assertEqual(self.last_geometry(), "0,202,187,700,499")

    def test_northwest_gravity_uses_frame_coordinates(self):
        self.set_geometry(x=302, y=237, width=600, height=400)
        result = self.run_tile(
            "left",
            FAKE_FRAME_EXTENTS="2, 2, 37, 2",
            FAKE_GRAVITY="NorthWest",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.last_geometry(), "0,0,0,956,1011")
        self.assertEqual(self.tracked_state(), "v2 left 300 200 604 439")
        self.assertEqual(self.run_tile(
            "restore",
            FAKE_FRAME_EXTENTS="2, 2, 37, 2",
            FAKE_GRAVITY="NorthWest",
        ).returncode, 0)
        self.assertEqual(self.last_geometry(), "0,300,200,600,400")

    def test_installer_and_shortcuts_are_wired(self):
        uscripts = userscripts_text()
        self.assertIn(
            "install -m 0755 /opt/z96a/window/z96a-window-tile /usr/local/bin/z96a-window-tile",
            uscripts,
        )
        shortcuts = SHORTCUTS.read_text(encoding="utf-8")
        for key, action in (
            ("Meta%2BLeft", "left"),
            ("Meta%2BRight", "right"),
            ("Meta%2BUp", "up"),
            ("Meta%2BDown", "down"),
            ("Meta%2BPrior", "maximize"),
            ("Meta%2BNext", "minimize"),
            ("Meta%2BBackSpace", "restore"),
        ):
            self.assertIn(f"[{key}.", shortcuts)
            self.assertIn(f"Exec=/usr/local/bin/z96a-window-tile, {action}", shortcuts)


if __name__ == "__main__":
    unittest.main()
