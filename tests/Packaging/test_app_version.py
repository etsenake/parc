import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_packager_version", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


class AppVersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.write({"version": "1.0.0", "build": 1})

    def write(self, value):
        (self.repo / "app-version.json").write_text(json.dumps(value))

    def test_bundle_metadata_shares_release_and_build(self):
        version = pkg.app_version.read(self.repo)
        for name in ("Parc", "Parc Helper", "ParcDockTile"):
            info = pkg.info_plist(name, "fixture." + name, version)
            self.assertEqual(info["CFBundleShortVersionString"], "1.0.0")
            self.assertEqual(info["CFBundleVersion"], "1")

    def test_bump_requires_increasing_numeric_version(self):
        for version in ("0.9.9", "1.0.0", "1.0", "v1.1.0", "1.01.0", "1.1.0-beta"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                pkg.app_version.advance(version, self.repo)
        self.assertEqual(pkg.app_version.advance("1.10.0", self.repo), {"version": "1.10.0", "build": 2})
        with self.assertRaises(ValueError):
            pkg.app_version.advance("1.2.0", self.repo)

    def test_invalid_or_missing_version_refused(self):
        for value in ({}, [], {"version": "1.0.0", "build": True},
                      {"version": "1.0.0", "build": 0}, {"version": "1.0.0", "build": 10000},
                      {"version": "1.0", "build": 1}, {"version": "01.0.0", "build": 1}):
            with self.subTest(value=value):
                self.write(value)
                with self.assertRaises(ValueError):
                    pkg.app_version.read(self.repo)
        (self.repo / "app-version.json").unlink()
        with self.assertRaises(ValueError):
            pkg.app_version.read(self.repo)


if __name__ == "__main__":
    unittest.main()
