import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_sparkle_package", REPO / "scripts/sparkle.py")
sparkle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparkle)


class SparklePackageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="parc-sparkle-")
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name).resolve() / "repo"
        self.scratch = self.repo / ".build"
        self.pin(sparkle.VERSION, sparkle.REVISION)
        manifest = self.scratch / "checkouts/Sparkle/Package.swift"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(f'let checksum = "{sparkle.CHECKSUM}"\n')
        self.directory = self.scratch / "artifacts/sparkle/Sparkle"
        self.frameworks = self.directory / "Sparkle.xcframework/macos-arm64_x86_64"
        self.info(sparkle.VERSION)
        for tool in ("sign_update", "generate_keys"):
            (self.directory / "bin" / tool).parent.mkdir(parents=True, exist_ok=True)
            (self.directory / "bin" / tool).write_text("fixture")

    def pin(self, version, revision):
        self.repo.mkdir(parents=True, exist_ok=True)
        (self.repo / "Package.resolved").write_text(json.dumps({"pins": [{
            "identity": "sparkle", "kind": "remoteSourceControl", "location": sparkle.PACKAGE,
            "state": {"revision": revision, "version": version}}], "version": 3}))

    def info(self, version):
        resources = self.frameworks / "Sparkle.framework/Resources"
        resources.mkdir(parents=True, exist_ok=True)
        (resources / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": version}))

    def test_resolved_package_yields_the_framework_slice_and_signing_tools(self):
        release = sparkle.artifact(self.repo, self.scratch)
        self.assertEqual(release.frameworks, self.frameworks)
        self.assertEqual(release.tools, self.directory / "bin")

    def test_a_different_pin_is_refused(self):
        self.pin(sparkle.VERSION, "0" * 40)
        with self.assertRaisesRegex(ValueError, "Package.resolved must pin"):
            sparkle.artifact(self.repo, self.scratch)

    def test_a_package_that_declares_another_checksum_is_refused(self):
        (self.scratch / "checkouts/Sparkle/Package.swift").write_text('let checksum = "' + "0" * 64 + '"\n')
        with self.assertRaisesRegex(ValueError, "pinned binary checksum"):
            sparkle.artifact(self.repo, self.scratch)

    def test_a_framework_of_another_version_is_refused(self):
        self.info("2.0.0")
        with self.assertRaisesRegex(ValueError, "not version"):
            sparkle.artifact(self.repo, self.scratch)

    def test_missing_signing_tools_are_refused(self):
        (self.directory / "bin/sign_update").unlink()
        with self.assertRaisesRegex(ValueError, "signing tools"):
            sparkle.artifact(self.repo, self.scratch)

    def test_committed_pin_matches_the_release_constants(self):
        pins = json.loads((REPO / "Package.resolved").read_text())["pins"]
        self.assertIn({"identity": "sparkle", "kind": "remoteSourceControl", "location": sparkle.PACKAGE,
                       "state": {"revision": sparkle.REVISION, "version": sparkle.VERSION}}, pins)


if __name__ == "__main__":
    unittest.main()
