#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[3]
LAUNCHER = ROOT / "files/rootfs-overlay/z96a-v2/opt/z96a/session/xinitrc"
USERSCRIPT_DIR = ROOT / "boards/z96a-v2/userscripts"


def userscripts_text():
    parts = [(USERSCRIPT_DIR / "uscripts").read_text(encoding="utf-8")]
    for module in sorted(USERSCRIPT_DIR.rglob("*.sh")):
        parts.append(module.read_text(encoding="utf-8"))
    return "\n".join(parts)


class SessionLauncherTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "launched-session"
        self.home = self.root / "home"
        self.home.mkdir()
        self.write_command("xrdb")
        self.write_command("startlxqt")

    def tearDown(self):
        self.tmp.cleanup()

    def write_command(self, name):
        command = self.bin / name
        command.write_text(
            f"#!/bin/sh\nprintf '%s\\n' '{name}' > \"$SESSION_LOG\"\n",
            encoding="utf-8",
        )
        command.chmod(0o755)

    def launch(self, session=None):
        env = os.environ | {
            "HOME": str(self.home),
            "PATH": str(self.bin),
            "SESSION_LOG": str(self.log),
        }
        args = ["/bin/sh", str(LAUNCHER)]
        if session is not None:
            args.append(session)
        return subprocess.run(args, env=env, check=False, capture_output=True, text=True)

    def test_selects_lxqt(self):
        result = self.launch("LXQt")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(encoding="utf-8").strip(), "startlxqt")

    def test_empty_or_unknown_session_defaults_to_lxqt(self):
        for session in (None, "unexpected-session", "IceWM"):
            with self.subTest(session=session):
                result = self.launch(session)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.log.read_text(encoding="utf-8").strip(), "startlxqt")

    def test_slim_is_configured_for_lxqt_only(self):
        script = userscripts_text()
        self.assertIn("set_slim_option sessions 'LXQt'", script)
        self.assertNotIn("IceWM", script)
        self.assertIn(
            "set_slim_option login_cmd 'exec /bin/bash -login /home/user/.xinitrc %session'",
            script,
        )
        self.assertIn("/^[[:space:]]*sessiondir[[:space:]]+/ s|^|#|", script)
        self.assertIn("install -m 0755 /opt/z96a/session/xinitrc /home/user/.xinitrc", script)


if __name__ == "__main__":
    unittest.main()
