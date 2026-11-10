#!/usr/bin/python3
import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[3] / "files/rootfs-overlay/z96a-v2/opt/z96a/desktop/z96a-theme"
LOADER = importlib.machinery.SourceFileLoader("z96a_theme", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("z96a_theme", LOADER)
THEME = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(THEME)


class ThemeSwitcherTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.config = root / "config"
        self.profiles = root / "profiles"
        self.theme_root = root / "themes"
        self.lxqt_root = root / "lxqt-themes"
        self.icon_root = root / "icons"
        self.state = root / "state"
        self.wallpapers = root / "wallpapers"
        self.wallpapers.mkdir(parents=True)
        for name in ("windows7", "windows11", "macos"):
            profile = self.profiles / name
            profile.mkdir(parents=True)
            (profile / "profile.json").write_text(json.dumps({
                "label": name, "lxqt_theme": "Light", "icon_theme": "Papirus",
                "qt_style": "Fusion", "openbox_theme": "Z96A-Test",
                "panel": "panel.conf",
                "wallpaper": str(self.wallpapers / f"{name}.png"),
            }), encoding="utf-8")
            (profile / "panel.conf").write_text(f"panels={name}\n", encoding="utf-8")
            (self.wallpapers / f"{name}.png").write_bytes(b"png")
        (self.theme_root / "Z96A-Test/openbox-3").mkdir(parents=True)
        (self.theme_root / "Z96A-Test/openbox-3/themerc").write_text("test\n")
        (self.lxqt_root / "Light").mkdir(parents=True)
        (self.icon_root / "Papirus").mkdir(parents=True)
        THEME.CONFIG = self.config
        THEME.STATE = self.state
        THEME.PROFILE_DIR = self.profiles
        THEME.THEME_ROOTS = [self.theme_root]
        THEME.LXQT_THEME_ROOTS = [self.lxqt_root]
        THEME.ICON_ROOTS = [self.icon_root]
        THEME.LXQT_CONFIG = self.config / "lxqt/lxqt.conf"
        THEME.PANEL_CONFIG = self.config / "lxqt/panel.conf"
        THEME.OPENBOX_CONFIG = self.config / "openbox/lxqt-rc.xml"
        THEME.PCMANFM_QT_CONFIG = self.config / "pcmanfm-qt/z96a/settings.conf"

    def tearDown(self):
        self.tmp.cleanup()

    def test_switch_and_restore_existing_configuration(self):
        for relative in THEME.MANAGED:
            path = self.config / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if relative == "lxqt/lxqt.conf":
                content = "[General]\ntheme = old\n[Qt]\nstyle = old\n"
            elif relative.startswith("openbox/"):
                content = "<openbox_config/>\n"
            elif relative.startswith("pcmanfm-qt/"):
                content = "[Desktop]\nWallpaper = \nShadowColor = #000000\n"
            else:
                content = "original\n"
            path.write_text(content, encoding="utf-8")
        saved = THEME.apply_profile("windows11")
        self.assertIn("theme = Light", THEME.LXQT_CONFIG.read_text())
        self.assertEqual(THEME.PANEL_CONFIG.read_text(), "panels=windows11\n")
        self.assertIn("Z96A-Test", THEME.OPENBOX_CONFIG.read_text())
        THEME.restore_snapshot(saved)
        self.assertIn("old", THEME.LXQT_CONFIG.read_text())
        self.assertEqual(THEME.PANEL_CONFIG.read_text(), "original\n")
        self.assertEqual(THEME.OPENBOX_CONFIG.read_text(), "<openbox_config/>\n")

    def test_restore_removes_files_that_were_absent(self):
        saved = THEME.apply_profile("macos")
        THEME.restore_snapshot(saved)
        for relative in THEME.MANAGED:
            self.assertFalse((self.config / relative).exists())

    def test_reconfigure_failure_rolls_back(self):
        with mock.patch.dict("os.environ", {"DISPLAY": ":99"}), \
                mock.patch.object(THEME.shutil, "which", return_value="/usr/bin/openbox"), \
                mock.patch.object(THEME.subprocess, "run", side_effect=RuntimeError("reconfigure")):
            with self.assertRaises(THEME.ProfileError):
                THEME.apply_profile("windows7")
        for relative in THEME.MANAGED:
            self.assertFalse((self.config / relative).exists())

    def test_missing_resources_fail_before_backup(self):
        THEME.LXQT_THEME_ROOTS = []
        with self.assertRaises(THEME.ProfileError):
            THEME.apply_profile("windows7")


if __name__ == "__main__":
    unittest.main()
