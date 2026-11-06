"""Disposable-profile guard tests; no application, Chromium or Keychain access."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("native_host_launcher", Path(__file__).with_name("launch.py"))
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.profile = self.root / "profile"

    def test_new_owned_profile_and_explicit_reuse(self):
        self.assertEqual(launcher.profile_directory(self.profile, False), self.profile)
        self.assertEqual(self.profile.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.profile / launcher.MARKER).read_text(), launcher.MARKER_TEXT)
        self.assertEqual(launcher.profile_directory(self.profile, True), self.profile)

    def test_existing_directory_is_preserved_without_reuse(self):
        self.profile.mkdir()
        original = self.profile / "user-data"
        original.write_bytes(b"keep exactly")
        with self.assertRaises(FileExistsError):
            launcher.profile_directory(self.profile, False)
        self.assertEqual(original.read_bytes(), b"keep exactly")
        self.assertEqual(list(self.profile.iterdir()), [original])

    def test_foreign_existing_directory_is_not_adopted(self):
        self.profile.mkdir(mode=0o700)
        with self.assertRaises(FileNotFoundError):
            launcher.profile_directory(self.profile, True)
        self.assertEqual(list(self.profile.iterdir()), [])

    def test_wrong_marker_and_broad_permissions_are_rejected(self):
        launcher.profile_directory(self.profile, False)
        marker = self.profile / launcher.MARKER
        marker.write_text("foreign profile")
        with self.assertRaises(ValueError):
            launcher.profile_directory(self.profile, True)
        self.assertEqual(marker.read_text(), "foreign profile")
        marker.write_text(launcher.MARKER_TEXT)
        self.profile.chmod(0o755)
        with self.assertRaises(ValueError):
            launcher.profile_directory(self.profile, True)

    def test_symlink_profile_and_marker_are_rejected(self):
        launcher.profile_directory(self.profile, False)
        alias = self.root / "alias"
        alias.symlink_to(self.profile, target_is_directory=True)
        with self.assertRaises(ValueError):
            launcher.profile_directory(alias, True)
        marker = self.profile / launcher.MARKER
        marker.unlink()
        actual = self.root / "marker"
        actual.write_text(launcher.MARKER_TEXT)
        marker.symlink_to(actual)
        with self.assertRaises(ValueError):
            launcher.profile_directory(self.profile, True)

    def test_relative_and_dotdot_paths_are_rejected(self):
        for value in [Path("relative"), self.root / "x" / ".." / "profile"]:
            with self.subTest(path=value), self.assertRaises(ValueError):
                launcher.profile_directory(value, False)


if __name__ == "__main__":
    unittest.main()
