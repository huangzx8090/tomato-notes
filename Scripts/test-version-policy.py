#!/usr/bin/env python3
"""在临时目录验证版本门禁，避免用实际发版文件做失败测试。"""

from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


class VersionPolicyTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="tomato-version-policy-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        (self.root / "Scripts").mkdir()
        self.script = self.root / "Scripts/check-versions.py"
        shutil.copyfile(Path(__file__).with_name("check-versions.py"), self.script)
        self.version = self.root / "VERSION"
        self.version.write_text("1.6.1\n")
        self.macos = self.root / "apps/macos/Packaging/Info.plist"
        self.macos.parent.mkdir(parents=True)
        self.macos.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.6.1"}))
        self.windows = self.root / "apps/windows/TomatoNotes/TomatoNotes.csproj"
        self.windows.parent.mkdir(parents=True)
        self.fields = {"VersionPrefix": "1.6.1", "AssemblyVersion": "1.6.1.0", "FileVersion": "1.6.1.0"}
        self.write_windows()

    def write_windows(self):
        fields = "".join(f"<{key}>{value}</{key}>" for key, value in self.fields.items())
        self.windows.write_text(f"<Project><PropertyGroup>{fields}</PropertyGroup></Project>")

    def check(self):
        return subprocess.run([sys.executable, str(self.script)], cwd=self.root.parent,
                              text=True, capture_output=True, check=False)

    def test_matching_versions_succeed_from_another_directory_without_modification(self):
        paths = (self.version, self.macos, self.windows)
        before = [path.read_bytes() for path in paths]
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "1.6.1")
        self.assertEqual([path.read_bytes() for path in paths], before)

    def test_macos_mismatch_fails(self):
        self.macos.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.6.0"}))
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("macOS", result.stderr)

    def test_each_windows_version_field_must_match(self):
        for field in self.fields:
            with self.subTest(field=field):
                original = self.fields[field]
                self.fields[field] = "0.0.0"
                self.write_windows()
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(field, result.stderr)
                self.fields[field] = original

    def test_invalid_product_version_fails(self):
        for value in ("v1.6.1", "1.6", "", "1.6.1-beta"):
            with self.subTest(value=value):
                self.version.write_text(value)
                self.assertNotEqual(self.check().returncode, 0)

    def test_missing_platform_config_fails(self):
        self.windows.unlink()
        self.assertNotEqual(self.check().returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
