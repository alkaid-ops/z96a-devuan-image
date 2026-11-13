"""Behavioral checks for the CI image finalization and input cache."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ImageFinalizationTests(unittest.TestCase):
    def run_finish(self, validation_status):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            validator = root / "boards/test/tools/validate-image.sh"
            validator.parent.mkdir(parents=True)
            validator.write_text(
                '#!/bin/sh\n[ -f "$1" ] || exit 90\n'
                f'exit {validation_status}\n'
            )
            validator.chmod(0o755)
            (root / "raw.img").write_bytes(b"test image contents")
            staging = (ROOT / "lib/function/staging").read_text()
            finish = staging[staging.index("finish_image (){"):]
            script = """set -eu
BOARD=test OUTPUT=output/test IMAGE_FILE_NAME=raw.img
MINIMAL_ROOTFS=false DEVICE_SOC=test DISTRO=test DISTRO_VERSION=1
INSTALLED_KERNEL=1 ARCH_EXT=arm64 FSTYPE=ext4 IMAGE_DATE=20260101
COMPRESS_IMG=1 IMG_COMPRESSION=xz CORES=1 Z96A_VALIDATE_IMAGE=1 Z96A_XZ_FAST=1
""" + finish + "\nfinish_image\n"
            result = subprocess.run(["bash", "-c", script], cwd=root,
                                    capture_output=True, text=True)
            images = list((root / "output/test/image").glob("*.img"))
            archives = list((root / "output/test/image").glob("*.img.xz"))
            if validation_status:
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(len(images), 1)
                self.assertFalse(archives, "must not compress a rejected image")
            else:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(images)
                self.assertEqual(len(archives), 1)
                self.assertEqual(subprocess.check_output(["xz", "-dc", str(archives[0])]),
                                 b"test image contents")
                self.assertTrue(Path(str(archives[0]) + ".sha256").is_file())

    def test_validates_before_compressing(self):
        self.run_finish(0)

    def test_validation_failure_stops_compression(self):
        self.run_finish(1)


class InputCacheVerificationTests(unittest.TestCase):
    def test_modified_manifest_is_not_trusted_on_cache_hit(self):
        with tempfile.TemporaryDirectory() as directory:
            tmp = Path(directory)
            cache = tmp / "cache"
            (cache / "manifests").mkdir(parents=True)
            (cache / "debs").mkdir()
            (cache / "debs/asset.deb").write_bytes(b"payload")
            asset_hash = hashlib.sha256(b"payload").hexdigest()
            manifest = f"{asset_hash}  debs/asset.deb\n".encode()
            sums = hashlib.sha256(manifest).hexdigest()
            for name in ("kernel", "base", "uboot"):
                (cache / f"manifests/SHA256SUMS.{name}").write_bytes(manifest)
            lock = tmp / "inputs.lock"
            lock.write_text("\n".join(
                f'{name}_{suffix} = "{value}"'
                for name in ("kernel", "base_apps", "uboot")
                for suffix, value in (("release", "test"), ("sums", sums))
            ) + "\n")
            (cache / ".lock-sha").write_text(hashlib.sha256(lock.read_bytes()).hexdigest() + "\n")
            fakebin = tmp / "bin"
            fakebin.mkdir()
            curl = fakebin / "curl"
            curl.write_text("#!/bin/sh\nexit 42\n")
            curl.chmod(0o755)
            env = dict(os.environ, Z96A_INPUT_CACHE=str(cache), Z96A_INPUTS_LOCK=str(lock),
                       PATH=f"{fakebin}:{os.environ['PATH']}")
            command = [str(ROOT / "boards/z96a-v2/tools/ci-fetch-inputs.sh")]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("cache hit:", result.stdout)
            (cache / "manifests/SHA256SUMS.kernel").write_bytes(b"")
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("cache hit:", result.stdout)


if __name__ == "__main__":
    unittest.main()
