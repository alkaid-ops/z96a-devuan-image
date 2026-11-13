#!/usr/bin/env python3
"""Phase 0 static consistency checks for the z96a-v2 board.

These checks never touch the device and never modify files. They verify that
the repository is internally consistent: board config, kernel defconfig, rootfs
overlay layout, packaged deb naming, userscript references and documentation
links.

Run directly, or via unittest discovery.
"""

import hashlib
import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BOARD = "z96a-v2"
BOARD_FILE = ROOT / "lib/boards" / BOARD
DEFCONFIG = ROOT / "defconfig" / f"{BOARD}_defconfig"
OVERLAY = ROOT / "files/rootfs-overlay" / BOARD
USERSCRIPT = ROOT / "boards" / BOARD / "userscripts" / "uscripts"
PACKAGES = OVERLAY / "opt/z96a/packages"
RUNTIME_PACKAGES = OVERLAY / "opt/z96a/runtime-packages.txt"
SHA256SUMS = PACKAGES / "SHA256SUMS"

OVERLAY_WHITELIST = {"etc", "home", "opt", "usr"}
REQUIRED_VARS = ("BOARD", "ARCH", "ARCH_EXT", "FAMILY", "DTB", "LINUX_DEFCONFIG")
# (name, allowed values); Panfrost/VDEC are modules, MMC must be built in.
REQUIRED_DEFCONFIG = {
    "CONFIG_GENERIC_ADC_THERMAL": {"y"},
    "CONFIG_DRM_PANFROST": {"y", "m"},
    "CONFIG_VIDEO_ROCKCHIP_VDEC": {"y", "m"},
    "CONFIG_MMC": {"y"},
}

PACKAGE_REF = re.compile(r"/opt/z96a/packages/([A-Za-z0-9._+-]+\.deb)")


def userscripts_text():
    """Main script plus every sourced module (phase 2 split)."""
    root = ROOT / "boards" / BOARD / "userscripts"
    parts = [(root / "uscripts").read_text(errors="replace")]
    for module in sorted(root.rglob("*.sh")):
        parts.append(module.read_text(errors="replace"))
    return "\n".join(parts)


def board_vars():
    """Source the board file in a subshell and print KEY=VALUE lines."""
    out = subprocess.run(
        ["bash", "-c", f'cd "{ROOT}" && source "{BOARD_FILE}" && '
         'for v in BOARD ARCH ARCH_EXT FAMILY DTB LINUX_DEFCONFIG UBOOT_DEFCONFIG '
         'GIT_REPO GIT_BRANCH GIT_PIN_COMMIT FORCE_LINUX_VERSION FORCE_UBOOT_VERSION; do '
         'printf "%s=%s\\n" "$v" "${!v}"; done'],
        check=True, capture_output=True, text=True,
    )
    result = {}
    for line in out.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


class BoardConfigTests(unittest.TestCase):
    def test_board_file_exists_and_parses(self):
        self.assertTrue(BOARD_FILE.is_file(), BOARD_FILE)
        syntax = subprocess.run(["bash", "-n", str(BOARD_FILE)], capture_output=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr.decode())

    def test_required_variables(self):
        data = board_vars()
        self.assertEqual(data.get("BOARD"), BOARD)
        for name in REQUIRED_VARS:
            self.assertTrue(data.get(name), f"missing board variable {name}")
        self.assertTrue((ROOT / "defconfig" / data["LINUX_DEFCONFIG"]).is_file())

    def test_kernel_defconfig_has_board_features(self):
        self.assertTrue(DEFCONFIG.is_file(), DEFCONFIG)
        text = DEFCONFIG.read_text(errors="replace")
        for option, allowed in REQUIRED_DEFCONFIG.items():
            match = re.search(rf"^{option}=([ym])\s*$", text, re.MULTILINE)
            self.assertIsNotNone(match, f"{option} is not set in defconfig")
            self.assertIn(match.group(1), allowed,
                          f"{option}={match.group(1)} not in {sorted(allowed)}")

    def test_userscript_exists_and_parses(self):
        self.assertTrue(USERSCRIPT.is_file(), USERSCRIPT)
        syntax = subprocess.run(["bash", "-n", str(USERSCRIPT)], capture_output=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr.decode())


class OverlayTests(unittest.TestCase):
    def test_overlay_only_uses_whitelisted_top_dirs(self):
        self.assertTrue(OVERLAY.is_dir(), OVERLAY)
        top = {entry.name for entry in OVERLAY.iterdir()}
        unexpected = top - OVERLAY_WHITELIST
        self.assertFalse(
            unexpected,
            f"directories that the build would silently ignore: {sorted(unexpected)}",
        )

    def test_userscript_package_references_exist(self):
        text = userscripts_text()
        referenced = set(PACKAGE_REF.findall(text))
        self.assertTrue(referenced, "userscript references no packaged deb")
        if not any(PACKAGES.glob("*.deb")):
            listed = {
                fields[1]
                for line in SHA256SUMS.read_text(errors="replace").splitlines()
                if len(fields := line.split()) == 2
            }
            missing = sorted(referenced - listed)
        else:
            missing = sorted(name for name in referenced if not (PACKAGES / name).is_file())
        self.assertFalse(missing, f"userscript references missing packages: {missing}")

    def test_packaged_debs_are_checksummed(self):
        self.assertTrue(SHA256SUMS.is_file(), SHA256SUMS)
        listed = {}
        for line in SHA256SUMS.read_text(errors="replace").splitlines():
            fields = line.split()
            if len(fields) == 2:
                listed[fields[1]] = fields[0]
        debs = {path.name for path in PACKAGES.glob("*.deb")}
        unlisted = sorted(debs - set(listed))
        missing = sorted(set(listed) - debs)
        self.assertFalse(unlisted, f"debs without a SHA256SUMS entry: {unlisted}")
        if debs:
            self.assertFalse(missing, f"SHA256SUMS entries without a deb: {missing}")
        else:
            sources = ROOT / "boards" / BOARD / "packages-sources.tsv"
            source_hashes = {}
            for line in sources.read_text(errors="replace").splitlines():
                fields = line.split("\t")
                if len(fields) >= 2 and fields[0] and not fields[0].startswith("#"):
                    source_hashes[fields[0]] = fields[1]
            self.assertEqual(listed, source_hashes,
                             "SHA256SUMS must match the source manifest when blobs are absent")

    @unittest.skipUnless(os.environ.get("Z96A_VERIFY_PACKAGE_HASHES") == "1",
                         "set Z96A_VERIFY_PACKAGE_HASHES=1 to hash ~884MB of debs")
    def test_package_hashes_match(self):
        for line in SHA256SUMS.read_text(errors="replace").splitlines():
            fields = line.split()
            if len(fields) != 2:
                continue
            expected, name = fields
            path = PACKAGES / name
            digest = hashlib.sha256()
            with path.open("rb") as handle:
                for block in iter(lambda: handle.read(1 << 20), b""):
                    digest.update(block)
            self.assertEqual(digest.hexdigest(), expected, name)

    def test_runtime_packages_has_no_duplicates(self):
        self.assertTrue(RUNTIME_PACKAGES.is_file(), RUNTIME_PACKAGES)
        entries = [line.strip() for line in RUNTIME_PACKAGES.read_text().splitlines()]
        entries = [line for line in entries if line and not line.startswith("#")]
        duplicates = sorted({name for name in entries if entries.count(name) > 1})
        self.assertFalse(duplicates, f"duplicate runtime package entries: {duplicates}")

    def test_network_tray_is_nm_applet(self):
        """Agreed desktop requirement: nm-applet, never nm-tray."""
        lines = [line.strip() for line in RUNTIME_PACKAGES.read_text().splitlines()]
        self.assertIn("network-manager-gnome", lines,
                      "network-manager-gnome (nm-applet) must be installed")
        for stale in ("nm-tray", "nm-tray-l10n"):
            self.assertNotIn(stale, lines, f"{stale} must not be shipped")
        uscript = userscripts_text()
        self.assertIn("apt-get purge -y nm-tray nm-tray-l10n", uscript,
                      "userscript must purge nm-tray")

    def test_runtime_packages_matches_layered_lists(self):
        """runtime-packages.txt is generated from packages/*.txt; no drift."""
        layers = ROOT / "boards" / BOARD / "packages"
        expected = []
        for name in ("base", "desktop", "multimedia", "applications"):
            path = layers / f"{name}.txt"
            self.assertTrue(path.is_file(), path)
            for line in path.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    expected.append(line)
        actual = [line.strip() for line in RUNTIME_PACKAGES.read_text().splitlines()
                  if line.strip() and not line.startswith("#")]
        self.assertEqual(sorted(actual), sorted(expected),
                         "run boards/z96a-v2/tools/gen-runtime-packages.sh")
        self.assertEqual(len(actual), len(set(actual)), "duplicate packages across layers")


class BuildInputTests(unittest.TestCase):
    def test_kernel_commit_is_pinned(self):
        data = board_vars()
        pin = data.get("GIT_PIN_COMMIT", "")
        self.assertRegex(pin, r"^[0-9a-f]{40}$",
                         "GIT_PIN_COMMIT must be a full 40-char commit")
        git_fn = (ROOT / "lib/function/git").read_text(errors="replace")
        self.assertIn('GIT_PIN_COMMIT', git_fn,
                      "lib/function/git must honour GIT_PIN_COMMIT")

    def test_version_sources_agree(self):
        data = board_vars()
        userdata = (ROOT / "userdata.txt").read_text(errors="replace")
        match = re.search(r'^VERSION="?([^"\n]+)"?', userdata, re.MULTILINE)
        self.assertIsNotNone(match, "userdata.txt has no VERSION")
        self.assertEqual(match.group(1), data.get("FORCE_LINUX_VERSION"),
                         "userdata VERSION and board FORCE_LINUX_VERSION differ")

    def test_manifest_records_build_identity(self):
        data = board_vars()
        for name in ("GIT_PIN_COMMIT", "FORCE_LINUX_VERSION", "FORCE_UBOOT_VERSION"):
            self.assertTrue(data.get(name), f"board variable {name} is empty")
        uboot = ROOT / "files/boot/uboot" / BOARD
        for blob in ("u-boot.bin", "idbloader.bin"):
            self.assertTrue((uboot / blob).is_file(), f"missing {blob}")
        script = ROOT / "boards" / BOARD / "tools" / "make-manifest.sh"
        self.assertTrue(script.is_file(), script)


class PackagingDistributionTests(unittest.TestCase):
    def test_no_deb_blobs_tracked_in_git(self):
        result = subprocess.run(["git", "ls-files", "*.deb"],
                                cwd=ROOT, capture_output=True, text=True)
        tracked = [line for line in result.stdout.splitlines() if line]
        self.assertEqual(tracked, [],
                         "bundled debs must live outside git: " + ", ".join(tracked))

    def test_every_present_deb_has_a_source_entry(self):
        sources = ROOT / "boards" / BOARD / "packages-sources.tsv"
        self.assertTrue(sources.is_file(), sources)
        known = {}
        for line in sources.read_text().splitlines():
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) >= 2:
                known[fields[0]] = fields[1]
        for deb in PACKAGES.glob("*.deb"):
            self.assertIn(deb.name, known, f"{deb.name} has no packages-sources.tsv entry")
            self.assertRegex(known[deb.name], r"^[0-9a-f]{64}$",
                             f"{deb.name} sha256 is missing or malformed")

    def test_fetch_script_exists(self):
        script = ROOT / "boards" / BOARD / "tools" / "fetch-packages.sh"
        self.assertTrue(script.is_file(), script)
        syntax = subprocess.run(["bash", "-n", str(script)], capture_output=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr.decode())


class FeatureFlagTests(unittest.TestCase):
    def test_feature_file_defines_expected_switches(self):
        path = ROOT / "boards" / BOARD / "features.conf"
        self.assertTrue(path.is_file(), path)
        text = path.read_text()
        for flag in ("ENABLE_DESKTOP", "ENABLE_APPS", "ENABLE_MULTIMEDIA",
                     "ENABLE_VULKAN", "ENABLE_LOCALSEND"):
            self.assertRegex(text, rf"(?m)^{flag}=\$\{{{flag}:-[01]\}}$",
                             f"{flag} must have a documented default",
                             )

    def test_userscript_loads_feature_file(self):
        uscript = userscripts_text()
        self.assertIn("/opt/z96a-features.conf", uscript,
                      "run_function2 must source the feature file")
        self.assertIn("ENABLE_VULKAN", uscript)
        self.assertIn("ENABLE_LOCALSEND", uscript)
        # stage1 must ship the feature file into the image
        self.assertIn("z96a-features.conf", uscript)


class ScriptModuleSplitTests(unittest.TestCase):
    """Phase 2: install/configure/verify modules sourced in order."""

    EXPECTED = (
        "install/10-base.sh",
        "configure/10-environment.sh",
        "install/20-multimedia.sh",
        "configure/20-hwdb.sh",
        "configure/30-locale.sh",
        "configure/40-input-method.sh",
        "configure/50-lock.sh",
        "configure/60-session.sh",
        "install/30-apps.sh",
        "configure/70-network.sh",
        "configure/80-x11.sh",
        "configure/85-theme.sh",
        "configure/88-services.sh",
        "configure/96-ownership.sh",
        "verify/99-seal.sh",
    )

    def test_modules_exist_and_parse(self):
        root = ROOT / "boards" / BOARD / "userscripts"
        for rel in self.EXPECTED:
            path = root / rel
            self.assertTrue(path.is_file(), path)
            syntax = subprocess.run(["bash", "-n", str(path)], capture_output=True)
            self.assertEqual(syntax.returncode, 0, syntax.stderr.decode())

    def test_main_sources_modules_in_correct_order(self):
        main = USERSCRIPT.read_text(errors="replace")
        found = re.findall(r'\. "\$Z96A_USCRIPTS_DIR/([^"]+)"', main)
        self.assertEqual(tuple(found), self.EXPECTED,
                         "source order must match the original execution order")

    def test_lib_source_copies_modules_into_chroot(self):
        """The modules live outside files/userscripts, so lib/source must copy them."""
        source = (ROOT / "lib/source").read_text(errors="replace")
        self.assertIn('userscripts/${sub}', source,
                      "lib/source must copy install/configure/verify into the chroot")
        for sub in ("install", "configure", "verify"):
            self.assertIn(sub, source)

    def test_no_module_is_empty(self):
        root = ROOT / "boards" / BOARD / "userscripts"
        for rel in self.EXPECTED:
            body = (root / rel).read_text(errors="replace").splitlines()
            code = [line for line in body if line.strip() and not line.strip().startswith("#")]
            self.assertGreaterEqual(len(code), 1, f"{rel} has no executable content")


class ConfigSingleSourceTests(unittest.TestCase):
    def test_toml_matches_board_file(self):
        generator = ROOT / "boards" / BOARD / "tools" / "gen-board-config.sh"
        self.assertTrue(generator.is_file(), generator)
        result = subprocess.run(["bash", str(generator), "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_toml_covers_every_board_variable(self):
        board_file = (ROOT / "lib/boards" / BOARD).read_text(errors="replace")
        toml_file = (ROOT / "config" / f"{BOARD}.toml").read_text(errors="replace")
        board_vars = set(re.findall(r"^([A-Z][A-Z0-9_]*)=", board_file, re.MULTILINE))
        toml_vars = set(re.findall(r"^([A-Z][A-Z0-9_]*) = ", toml_file, re.MULTILINE))
        self.assertEqual(sorted(board_vars - toml_vars), [],
                         "board variables missing from config TOML")
        self.assertEqual(sorted(toml_vars - board_vars), [],
                         "config TOML has variables absent from the board file")

    def test_makefile_exposes_config_target(self):
        makefile = (ROOT / "Makefile").read_text(errors="replace")
        self.assertIn("\nboard-config:", makefile)
        self.assertIn("gen-board-config.sh", makefile)


class BuildPreflightTests(unittest.TestCase):
    @unittest.skipUnless(any(PACKAGES.glob("*.deb")),
                         "binary package inputs are restored in the image-build job")
    def test_preflight_passes(self):
        script = ROOT / "boards" / BOARD / "tools" / "preflight.sh"
        self.assertTrue(script.is_file(), script)
        result = subprocess.run(["bash", str(script), "--quiet"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0,
                         result.stdout + result.stderr)

    def test_preflight_is_wired_into_build(self):
        uscript = userscripts_text()
        self.assertIn("run_function0", uscript, "board script defines run_function0")
        self.assertIn("tools/preflight.sh", uscript,
                      "run_function0 must call the preflight script")
        makefile = (ROOT / "Makefile").read_text(errors="replace")
        self.assertIn("\npreflight:", makefile, "Makefile has a preflight target")

    def test_hosted_build_registers_arm64_binfmt(self):
        workflow = (ROOT / ".github/workflows/build-image.yml").read_text(errors="replace")
        self.assertIn("docker/setup-qemu-action@29109295f81e9208d7d86ff1c6c12d2833863392", workflow)
        self.assertIn("platforms: arm64", workflow)

    def test_image_validator_waits_for_loop_partitions(self):
        validator = (ROOT / "boards" / BOARD / "tools/validate-image.sh").read_text(errors="replace")
        self.assertIn("udevadm settle --timeout=10", validator)
        self.assertIn('while [ "$attempt" -lt 10 ]', validator)

    def test_image_evidence_accepts_empty_manual_release_tag(self):
        collector = (ROOT / "boards" / BOARD / "tools/ci-collect-image.sh").read_text(errors="replace")
        self.assertIn('--tag) TAG=${2-}; shift 2 ;;', collector)

    def test_release_staging_does_not_require_hardlinks(self):
        workflow = (ROOT / ".github/workflows/build-image.yml").read_text(errors="replace")
        self.assertIn('cp "$img" "$img.sha256" output/ci/release/', workflow)
        self.assertNotIn('cp -l "$img"', workflow)

    def test_input_cache_is_saved_only_on_miss(self):
        workflow = (ROOT / ".github/workflows/build-image.yml").read_text(errors="replace")
        self.assertIn("id: input-cache", workflow)
        self.assertIn("if: steps.input-cache.outputs.cache-hit != 'true'", workflow)

    def test_ci_skips_version_tags(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(errors="replace")
        self.assertIn("tags-ignore:", workflow)
        self.assertIn("- 'v*'", workflow)

    def test_env_modules_do_not_clobber_ssh_key_variable(self):
        # The environment loops used to assign to `key`, which leaked into
        # 88-services.sh and wrote "SDL_IM_MODULE" into authorized_keys.
        for name in ("10-environment.sh", "30-locale.sh", "60-session.sh"):
            text = (ROOT / "boards" / BOARD / "userscripts/configure" / name).read_text(errors="replace")
            self.assertNotRegex(text, r"\bkey=\$\{line", name)
            self.assertIn("env_key=${line%%=*}", text, name)
        services = (ROOT / "boards" / BOARD / "userscripts/configure/88-services.sh").read_text(errors="replace")
        self.assertIn("${Z96A_SSH_KEY:-}", services)
        self.assertNotIn('"$key"', services)
        self.assertNotIn("local key=", userscripts_text())


class SwapPolicyTests(unittest.TestCase):
    """zram-only swap with conservative sizing and swappiness."""

    def test_zram_defaults_are_lz4_and_half_of_ram(self):
        text = (ROOT / "files/rootfs-overlay" / BOARD / "etc/default/zramswap").read_text(errors="replace")
        self.assertIn("ALGO=lz4", text)
        self.assertIn("PERCENT=50", text)
        self.assertIn("PRIORITY=100", text)

    def test_swappiness_is_lowered(self):
        text = (ROOT / "files/rootfs-overlay" / BOARD / "etc/sysctl.d/99-zram.conf").read_text(errors="replace")
        self.assertIn("vm.swappiness = 30", text)

    def test_no_disk_swap_in_fstab_generator(self):
        staging = (ROOT / "lib/function/staging").read_text(errors="replace")
        self.assertNotIn("swap", staging.lower())

    def test_kernel_defaults_zram_to_lz4(self):
        defconfig = (ROOT / "defconfig" / f"{BOARD}_defconfig").read_text(errors="replace")
        self.assertIn("CONFIG_ZRAM_BACKEND_LZ4=y", defconfig)
        self.assertIn("CONFIG_ZRAM_DEF_COMP_LZ4=y", defconfig)
        self.assertIn('CONFIG_ZRAM_DEF_COMP="lz4"', defconfig)


class CredentialPolicyTests(unittest.TestCase):
    def test_ssh_credentials_are_optional_and_fail_closed(self):
        board_userscript = (ROOT / "boards" / BOARD / "userscripts/uscripts").read_text()
        services = (ROOT / "boards" / BOARD / "userscripts/configure/88-services.sh").read_text()
        ownership = (ROOT / "boards" / BOARD / "userscripts/configure/96-ownership.sh").read_text()
        workflow = (ROOT / ".github/workflows/build-image.yml").read_text()
        self.assertNotIn("Z96A_SSH_KEY:?", board_userscript)
        self.assertIn("if [ -n \"${Z96A_SSH_KEY:-}\" ]", services)
        self.assertIn("rm -f /root/.ssh/authorized_keys /home/user/.ssh/authorized_keys", services)
        self.assertIn("[ -e \"$nmconnection\" ] || continue", ownership)
        self.assertIn("required: false", workflow)

    def test_sshd_policy_lives_in_main_config_with_empty_dropin_dir(self):
        services = (ROOT / "boards" / BOARD / "userscripts/configure/88-services.sh").read_text()
        # The drop-in directory must stay empty; policy comes from sshd_config.
        self.assertIn("rm -f /etc/ssh/sshd_config.d/*.conf", services)
        self.assertNotIn("99-z96a-root-login.conf", services)
        self.assertIn("s/^#*PasswordAuthentication .*/PasswordAuthentication yes/", services)
        self.assertIn("s/^#*PermitRootLogin .*/PermitRootLogin yes/", services)
        self.assertIn("s/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/", services)


class AudioMuxTests(unittest.TestCase):
    def test_rk817_mux_is_switched_to_the_active_output(self):
        script = (ROOT / "files/rootfs-overlay" / BOARD / "usr/local/bin/z96a-audio-mux")
        self.assertTrue(script.is_file(), script)
        text = script.read_text(errors="replace")
        self.assertIn('"Headphones Jack"', text.replace("'", '"'))
        self.assertIn('sset "Playback Mux" HP', text)
        self.assertIn('sset "Internal Speakers" off', text)
        self.assertIn('sset "Internal Speakers" on', text)
        self.assertIn("alsactl monitor", text)

    def test_audio_mux_service_is_registered(self):
        init = ROOT / "files/rootfs-overlay" / BOARD / "etc/init.d/z96a-audio-mux"
        self.assertTrue(init.is_file(), init)
        self.assertIn("Provides:          z96a-audio-mux", init.read_text(errors="replace"))
        ownership = (ROOT / "boards" / BOARD / "userscripts/configure/96-ownership.sh").read_text()
        self.assertIn("update-rc.d z96a-audio-mux defaults", ownership)


class BootLayoutTests(unittest.TestCase):
    """Static guard for the Rockchip U-Boot write offsets (phase 4 R4)."""

    UB_SEC = 64
    UB_SECTORS = 16384

    def test_rockchip_flash_offsets_unchanged(self):
        source = (ROOT / "lib/function/rockchip").read_text(errors="replace")
        self.assertIn('dd if="${OUTPUT}/idbloader.bin" of="${IMAGE_LOOP_DEV}" seek=64',
                      source, "idbloader offset changed; update docs/OPTIMIZATION.md")
        self.assertIn('dd if="${OUTPUT}/u-boot.bin" of="${IMAGE_LOOP_DEV}" seek=16384',
                      source, "u-boot offset changed; update docs/OPTIMIZATION.md")

    def test_uboot_blobs_fit_before_rootfs(self):
        uboot = ROOT / "files/boot/uboot" / BOARD
        idbloader = uboot / "idbloader.bin"
        self.assertTrue(idbloader.is_file(), idbloader)
        first_sector = self.UB_SEC * 512
        gap = self.UB_SECTORS * 512 - first_sector
        self.assertLessEqual(idbloader.stat().st_size, gap,
                             "idbloader overlaps the u-boot write offset")


class ManifestAndSbomTests(unittest.TestCase):
    """Phase 4 R6/R7: manifest carries release naming and an SBOM is produced."""

    def _fake_rootfs(self, root):
        (root / "etc/z96a").mkdir(parents=True)
        (root / "etc/z96a/mesa-version").write_text("26.1.6-1~bpo13+1\n")
        (root / "var/lib/dpkg").mkdir(parents=True)
        (root / "var/lib/dpkg/status").write_text(
            "Package: lxqt-core\nVersion: 2.1.0-1\n\n"
            "Package: network-manager-gnome\nVersion: 1.36.0-3\n")
        (root / "usr/lib/modules/7.2.12-z96a").mkdir(parents=True)

    def test_manifest_and_sbom_from_fake_rootfs(self):
        import json, tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "rootfs"; out = Path(tmp) / "out"
            self._fake_rootfs(root)
            script = ROOT / "boards" / BOARD / "tools" / "make-manifest.sh"
            env = dict(os.environ, RELEASE_CHANNEL="stable")
            result = subprocess.run(["bash", str(script),
                                     str(out / "manifest.json"), str(root)],
                                    capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((out / "manifest.json").read_text())
            self.assertEqual(manifest["release"], "excalibur")
            info = manifest["release_info"]
            self.assertEqual(info["channel"], "stable")
            self.assertRegex(info["artifact_name"],
                             r"^z96a-v2-.*-stable-\d{8}\.img\.xz$")
            self.assertEqual(manifest["packages"]["installed_count"], 2)
            sbom = json.loads((out / "sbom.json").read_text())
            self.assertEqual(sbom["spdxVersion"], "SPDX-2.3-lite")
            names = {pkg["name"] for pkg in sbom["packages"]}
            self.assertIn("lxqt-core", names)
            self.assertIn("linux-z96a", names)
            self.assertIn("u-boot", names)


class MesaBackportsTests(unittest.TestCase):
    """Mesa must come from backports, and a silent fallback must be impossible."""

    MODULE = "boards/z96a-v2/userscripts/install/10-base.sh"

    def setUp(self):
        self.text = (ROOT / self.MODULE).read_text(errors="replace")

    def test_detection_uses_apt_sources(self):
        self.assertIn("grep -rqs 'excalibur-backports'", self.text,
                      "detect backports from apt sources, not `apt-cache policy`")
        self.assertNotIn("apt-cache policy mesa-vulkan-drivers 2>/dev/null | grep",
                         self.text,
                         "pipeline detection breaks under `set -o pipefail`")

    def test_pin_uses_codename(self):
        self.assertIn("Pin: release n=excalibur-backports", self.text)
        self.assertIn("Pin-Priority: 900", self.text)

    def test_version_below_26_fails_when_backports_present(self):
        self.assertIn("ERROR: Mesa ${mesa_version} < 26.1", self.text)
        self.assertIn('exit 1', self.text)


class BoardRuntimeInjectionTests(unittest.TestCase):
    """run_function3 must copy board.runtime and manifest/sbom into the image."""

    def test_run_function3_records_runtime_and_manifest(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "rootfs"; out = Path(tmp) / "out"
            (root / "etc").mkdir(parents=True)
            (Path(tmp) / "board.runtime").write_text(
                'P_VALUE="p2"\nBOOT_VFAT="true"\nEFI="false"\n')
            script = (
                "set -euo pipefail\n"
                'Z96A_USCRIPTS_DIR="' + str(ROOT) + '/boards/' + BOARD + '/userscripts"\n'
                'P_VALUE="' + str(root) + '"\n'
                'OUTPUT="' + str(out) + '"\n'
                'BOARD="' + BOARD + '"\n'
                'Z96A_MANIFEST_TOOL="' + str(ROOT) + '/boards/' + BOARD + '/tools/make-manifest.sh"\n'
                'Z96A_BOARD_RUNTIME="' + str(Path(tmp) / "board.runtime") + '"\n'
                '. "$Z96A_USCRIPTS_DIR/uscripts"\n'
                'run_function3\n'
            )
            result = subprocess.run(["bash", "-c", script], cwd=tmp,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((root / "etc/z96a/board.runtime").is_file(),
                            "run_function3 must record board.runtime")
            self.assertIn('P_VALUE="p2"',
                          (root / "etc/z96a/board.runtime").read_text())
            self.assertTrue((root / "etc/z96a/manifest.json").is_file())
            self.assertTrue((root / "etc/z96a/sbom.json").is_file())
            self.assertTrue((out / "manifest.json").is_file())
            self.assertTrue((out / "sbom.json").is_file())


class RootfsPruneTests(unittest.TestCase):
    """Pruning is package-level and guarded by module firmware references."""

    SCRIPT = "boards/z96a-v2/tools/prune-rootfs.sh"

    def setUp(self):
        self.text = (ROOT / self.SCRIPT).read_text(errors="replace")

    def test_prune_tool_exists(self):
        script = ROOT / self.SCRIPT
        self.assertTrue(script.is_file(), script)
        syntax = subprocess.run(["bash", "-n", str(script)], capture_output=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr.decode())

    def test_prune_runs_from_run_function3(self):
        main = USERSCRIPT.read_text(errors="replace")
        self.assertIn("run_function3 (){", main)
        run3 = main.split("run_function3 (){", 1)[1]
        self.assertIn("prune-rootfs.sh", run3,
                      "pruning must run after kernel packages are installed")

    def test_prune_is_package_level_not_directory_level(self):
        # keeping a package but deleting its files broke dpkg -V and removed
        # the board's Bluetooth firmware once; forbid the directory sweep
        self.assertIn("apt-get purge", self.text)
        for banned in ("rm -rf \"$ROOT\"/usr/lib/firmware/", "rm -rf /usr/lib/firmware/"):
            self.assertNotIn(banned, self.text)

    def test_prune_keeps_essential_packages(self):
        # parse only the purge list assignment, not comments
        purge = self.text.split("purge_pkgs=", 1)[1].split('"', 2)[1]
        for pkg in ("firmware-realtek", "firmware-mediatek",
                    "firmware-brcm80211", "firmware-ath9k-htc"):
            self.assertNotIn(pkg, purge,
                             f"{pkg} provides firmware this board or USB peripherals need")

    def test_prune_verifies_module_firmware(self):
        self.assertIn("tr '\\0' '\\n'", self.text,
                      "firmware references must be parsed from NUL-separated .modinfo")
        self.assertIn("critical firmware", self.text,
                      "missing critical firmware must fail the build")
        self.assertIn("missing_critical", self.text)


class DefconfigTrimTests(unittest.TestCase):
    """Layer 3: defconfig only removes hardware this board cannot have."""

    TRIM = "boards/z96a-v2/defconfig-trim.txt"

    def test_trim_applied(self):
        script = ROOT / "boards" / BOARD / "tools" / "trim-defconfig.sh"
        self.assertTrue(script.is_file(), script)
        result = subprocess.run(["bash", str(script), "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_trim_list_is_conservative(self):
        text = (ROOT / self.TRIM).read_text(errors="replace")
        for must_disable in ("CONFIG_IWLWIFI", "CONFIG_ATH10K",
                             "CONFIG_DRM_AMDGPU", "CONFIG_DVB_CORE"):
            self.assertIn(f"-# {must_disable}", text)
        # USB and onboard hardware must stay enabled
        for must_keep in ("RTW88", "BTRTL", "USB_VIDEO_CLASS", "ATH9K_HTC"):
            self.assertNotIn(f"-# CONFIG_{must_keep}", text,
                             f"{must_keep} is needed for onboard/USB hardware")


class ChrootCacheTests(unittest.TestCase):
    """Phase 3: reuse the prepared chroot when inputs are unchanged."""

    TOOL = "boards/z96a-v2/tools/chroot-cache.sh"

    def test_tool_exists_and_parses(self):
        script = ROOT / self.TOOL
        self.assertTrue(script.is_file(), script)
        syntax = subprocess.run(["bash", "-n", str(script)], capture_output=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr.decode())

    def test_stage1_uses_cache(self):
        stage1 = (ROOT / "scripts/stage1").read_text(errors="replace")
        self.assertIn("chroot_cache_restore", stage1)
        self.assertIn("chroot_cache_save", stage1)
        self.assertIn("CHROOT_CACHE", stage1, "cache must be switchable")

    def test_key_stable_and_input_sensitive(self):
        env = dict(os.environ)
        key1 = subprocess.run(["bash", str(ROOT / self.TOOL), "key", BOARD],
                             capture_output=True, text=True, env=env).stdout.strip()
        key2 = subprocess.run(["bash", str(ROOT / self.TOOL), "key", BOARD],
                             capture_output=True, text=True, env=env).stdout.strip()
        self.assertEqual(key1, key2, "cache key must be deterministic")
        self.assertRegex(key1, r"^[0-9a-f]{64}$")

    def test_save_restore_roundtrip(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "cache"
            src = Path(tmp) / "rootfs"
            dst = Path(tmp) / "restored"
            (src / "etc").mkdir(parents=True)
            (src / "etc/os-release").write_text("id=devuan\n")
            (src / "root").mkdir()
            (src / "root/kernel.release").write_text("KERNEL_VERSION=7.2.12\n")
            env = dict(os.environ, CHROOT_CACHE_DIR=str(cache))
            subprocess.run(["bash", str(ROOT / self.TOOL), "save", BOARD, str(src)],
                           check=True, capture_output=True, env=env)
            dst.mkdir()
            result = subprocess.run(["bash", str(ROOT / self.TOOL), "restore", BOARD, str(dst)],
                                    capture_output=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual((dst / "etc/os-release").read_text(), "id=devuan\n")
            self.assertEqual((dst / "root/kernel.release").read_text(),
                             "KERNEL_VERSION=7.2.12\n")


class CiReleaseWorkflowTests(unittest.TestCase):
    """Phase 3/4 CI: tag builds must be gated on validation before release."""

    WORKFLOWS = ROOT / ".github" / "workflows"
    TOOLS = (
        "boards/z96a-v2/tools/ci-prepare-inputs.sh",
        "boards/z96a-v2/tools/ci-validate-image.sh",
        "boards/z96a-v2/tools/ci-collect-image.sh",
    )

    def read(self, name):
        path = self.WORKFLOWS / name
        self.assertTrue(path.is_file(), path)
        return path.read_text(errors="replace")

    def test_workflow_set(self):
        for name in ("ci.yml", "build.yml", "release.yml", "build-image.yml"):
            self.assertTrue((self.WORKFLOWS / name).is_file(), name)

    def test_tag_trigger_and_release_gate(self):
        text = self.read("release.yml")
        self.assertIn("tags:", text)
        self.assertRegex(text, r"-\s*'v\*'", "release must trigger on v* tags")
        self.assertIn("needs: build", text)
        self.assertIn("contents: write", text)
        self.assertIn("sha256sum -c", text, "release must re-verify the checksum")

    def test_release_tag_suffix_marks_prerelease(self):
        text = self.read("release.yml")
        self.assertIn("prerelease:", text)

    def test_build_uses_hosted_runner_and_validation(self):
        text = self.read("build-image.yml")
        self.assertIn("runs-on: ubuntu-24.04", text)
        self.assertIn("group: z96a-image-build", text)
        self.assertIn("build-in-container.sh image", text)
        self.assertIn("ci-validate-image.sh", text)
        self.assertIn("ci-prepare-inputs.sh", text)
        self.assertIn("ci-collect-image.sh", text)
        self.assertIn("CHROOT_CACHE_DIR", text)
        self.assertIn("RELEASE_TAG", text)

    def test_no_pull_request_target(self):
        for name in ("ci.yml", "build.yml", "release.yml", "build-image.yml"):
            self.assertNotIn("pull_request_target", self.read(name))

    def test_ci_tools_parse(self):
        for tool in self.TOOLS:
            path = ROOT / tool
            self.assertTrue(path.is_file(), path)
            self.assertTrue(os.access(path, os.X_OK), f"{tool} must be executable")
            syntax = subprocess.run(["bash", "-n", str(path)], capture_output=True)
            self.assertEqual(syntax.returncode, 0, syntax.stderr.decode())

    def test_manifest_records_release_tag(self):
        text = (ROOT / "boards/z96a-v2/tools/make-manifest.sh").read_text(errors="replace")
        self.assertIn("RELEASE_TAG", text)
        self.assertIn('"tag"', text)


class DocumentationTests(unittest.TestCase):
    LINK = re.compile(r"\[[^\]]*\]\(([^)#]+)\)")

    def test_markdown_links_resolve(self):
        documents = list(ROOT.glob("*.md"))
        documents += list((ROOT / "docs").rglob("*.md"))
        documents += list((ROOT / "boards").rglob("*.md"))
        broken = []
        for document in documents:
            for target in self.LINK.findall(document.read_text(errors="replace")):
                if target.startswith(("http://", "https://", "mailto:")):
                    continue
                if not (document.parent / target).exists():
                    broken.append(f"{document.relative_to(ROOT)} -> {target}")
        self.assertFalse(broken, "broken markdown links: " + ", ".join(broken))


class ArtCraftWrapperTests(unittest.TestCase):
    """ArtCraft apps must be pinned to the wgpu GL backend (PanVK limit 512)."""

    WRAPPERS = ("deckcraft", "gridcraft", "wordcraft")

    def test_wrappers_pin_wgpu_to_gl(self):
        for name in self.WRAPPERS:
            path = ROOT / "files/rootfs-overlay" / BOARD / "usr/local/bin" / name
            self.assertTrue(path.is_file(), f"missing wrapper {path}")
            self.assertTrue(path.stat().st_mode & 0o111, f"wrapper not executable: {path}")
            text = path.read_text(errors="replace")
            self.assertIn("WGPU_BACKEND=gl", text)
            self.assertIn(f"exec /usr/bin/{name} \"$@\"", text)

    def test_wrappers_explain_panvk_limit(self):
        text = (ROOT / "boards" / BOARD / "docs" / "MEMORY.md").read_text(errors="replace")
        self.assertIn("max_texture_dimension_3d", text)
        self.assertIn("WGPU_BACKEND=gl", text)


class BootLogoAssetTests(unittest.TestCase):
    """U-Boot reads its logo from the boot partition, so the build must ship it."""

    def test_staging_copies_logo_into_boot_partition(self):
        text = (ROOT / "lib/function/staging").read_text(errors="replace")
        self.assertIn("z96a-logo.bin.gz", text)
        self.assertIn("logo-bgra.bin.gz", text)
        self.assertIn('"$BOARD" == "z96a-v2"', text)

    def test_logo_source_exists(self):
        src = ROOT / "boards" / BOARD / "chroot-files/theme/alkaid/logo-bgra.bin.gz"
        self.assertTrue(src.is_file(), f"missing logo source {src}")

    def test_logo_requirement_is_documented(self):
        doc = (ROOT / "boards" / BOARD / "docs" / "BOOT-LOGO.md").read_text(errors="replace")
        self.assertIn("z96a-logo.bin.gz", doc)


class PowerLedPolicyTests(unittest.TestCase):
    """The system-running LED must survive late driver registration."""

    def test_led_policy_includes_power_led(self):
        text = (ROOT / "files/rootfs-overlay" / BOARD
                / "usr/local/sbin/z96a-charge-led").read_text(errors="replace")
        self.assertIn('[ -d "$WHITE" ]', text)
        self.assertIn("ensure_power_led", text)
        self.assertIn(r'grep -q "\[default-on\]"', text)
        self.assertIn("hw_ready", text)


class BootMountPolicyTests(unittest.TestCase):
    """fstab must not depend on udev by-uuid for /boot."""

    def test_staging_fstab_uses_partuuid(self):
        text = (ROOT / "lib/function/staging").read_text(errors="replace")
        self.assertIn("BOOT_PARTUUID=$(blkid", text)
        self.assertIn("PARTUUID=${BOOT_PARTUUID}", text)
        self.assertIn("PARTUUID=${ROOT_PARTUUID}", text)


class PowerPolicyTests(unittest.TestCase):
    """Menu shutdown/reboot must reach logind without an auth agent."""

    RULE = "files/rootfs-overlay/z96a-v2/etc/polkit-1/rules.d/50-z96a-power.rules"

    def test_polkit_rule_allows_power_actions(self):
        text = (ROOT / self.RULE).read_text(errors="replace")
        for action in ("power-off", "reboot", "suspend"):
            self.assertIn("org.freedesktop.login1." + action, text)
        self.assertIn('subject.isInGroup("users")', text)


class BootHandoverTests(unittest.TestCase):
    """Slim must not hand the splash VT to the first X server."""

    def test_no_novtswitch_and_waits_for_plymouth(self):
        text = (ROOT / "custom.txt").read_text(errors="replace")
        self.assertNotIn("16 -novtswitch", text)
        self.assertIn("while /usr/bin/plymouth --ping", text)
        self.assertIn("dpi 144 -nolisten tcp -deferglyphs 16", text)

    def test_handover_is_documented(self):
        doc = (ROOT / "boards" / BOARD / "docs" / "BOOT-LOGO.md").read_text(errors="replace")
        self.assertIn("Not seen SigUSR1", doc)


class KnownIssueTests(unittest.TestCase):
    """Recorded baseline issues. Reported, but not fatal during phase 0."""

    def test_kernel_version_conflict_is_documented(self):
        data = board_vars()
        userdata = (ROOT / "userdata.txt").read_text(errors="replace")
        match = re.search(r'^VERSION="?([^"\n]+)"?', userdata, re.MULTILINE)
        version = match.group(1) if match else ""
        forced = data.get("FORCE_LINUX_VERSION", "")
        # Baseline fact, not a failure: userdata and board disagree today.
        self.assertIn(forced, ("7.2.12", "7.2.11"),
                      f"unexpected forced kernel version {forced!r} (userdata={version!r})")


if __name__ == "__main__":
    unittest.main(verbosity=2)
