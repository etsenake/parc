"""Reject mismatched or unnotarized archives before changing the public tap."""
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_homebrew", REPO / "scripts/publish-homebrew.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class HomebrewReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / "Parc.zip"
        self.image = b"signed fixture image"
        self.report = {"app_version": {"version": "1.0.0", "build": 1},
                       "purpose": "distribution", "configuration": "release", "layout": "standalone-app",
                       "distribution_eligible": True, "notarized": True, "signing_team": publisher.PRODUCTION_TEAM,
                       "notarization": {"status": "Accepted", "stapled": True,
                                        "gatekeeper_verified": True, "team": publisher.PRODUCTION_TEAM},
                       "signed_images": {"Parc.app/Contents/MacOS/Parc": hashlib.sha256(self.image).hexdigest()}}
        self.info = {"CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1",
                     "CFBundleIdentifier": "org.parc.Browser"}
        self.release = {"tag_name": "v1.0.0", "target_commitish": "a" * 40,
                        "draft": False, "prerelease": False, "assets": []}

    def pack(self):
        with zipfile.ZipFile(self.archive, "w") as bundle:
            bundle.writestr("development/package-report.json", json.dumps(self.report))
            bundle.writestr("development/Parc.app/Contents/Info.plist", plistlib.dumps(self.info))
            bundle.writestr("development/Parc.app/Contents/MacOS/Parc", self.image)
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.release["assets"] = [{"name": "Parc-1.0.0-arm64.zip", "digest": "sha256:" + digest}]
        return digest

    def test_verified_release_produces_pinned_cask(self):
        digest = self.pack()
        self.assertEqual(publisher.verify_release(self.release, self.archive)[:3],
                         ({"version": "1.0.0", "build": 1}, digest, "a" * 40))
        text = publisher.cask("1.0.0", digest)
        self.assertIn('sha256 "' + digest + '"', text)
        self.assertIn('using: ParcPrivateReleaseDownloadStrategy', text)
        self.assertIn('app "Parc.app"', text)
        self.assertIn('Parc-#{version}-arm64.dmg', text)
        self.assertNotIn('zap ', text)

    def test_missing_notarization_or_mismatched_identity_rejected(self):
        for key, value in (("notarized", False), ("purpose", "development"), ("signing_team", "OTHERTEAM")):
            with self.subTest(key=key):
                old = self.report[key]
                self.report[key] = value
                self.pack()
                with self.assertRaisesRegex(ValueError, "notarized standalone"):
                    publisher.verify_release(self.release, self.archive)
                self.report[key] = old

    def test_bundle_version_mismatch_rejected(self):
        self.info["CFBundleShortVersionString"] = "0.1.0"
        self.pack()
        with self.assertRaisesRegex(ValueError, "versions"):
            publisher.verify_release(self.release, self.archive)

    def test_tampered_archive_and_signed_image_rejected(self):
        self.pack()
        self.archive.write_bytes(self.archive.read_bytes() + b"tampered")
        with self.assertRaisesRegex(ValueError, "GitHub's digest"):
            publisher.verify_release(self.release, self.archive)
        self.image = b"changed image with unchanged signed report"
        self.pack()
        with self.assertRaisesRegex(ValueError, "signed image differs"):
            publisher.verify_release(self.release, self.archive)

    def test_preview_or_mutable_source_rejected(self):
        for key, value in (("prerelease", True), ("draft", True), ("target_commitish", "main")):
            with self.subTest(key=key):
                old = self.release[key]
                self.release[key] = value
                self.pack()
                with self.assertRaisesRegex(ValueError, "exact source commit"):
                    publisher.verify_release(self.release, self.archive)
                self.release[key] = old

    def test_dmg_digest_must_match_before_apple_verification(self):
        self.pack()
        image = Path(self.temp.name) / "Parc.dmg"
        image.write_bytes(b"fixture dmg")
        digest = hashlib.sha256(image.read_bytes()).hexdigest()
        self.release["assets"].append({"name": "Parc-1.0.0-arm64.dmg", "digest": "sha256:" + digest})
        with patch.object(publisher.dmg_tool, "verify_dmg") as verify:
            self.assertEqual(publisher.verify_dmg_asset(self.release, image, self.report, Path(self.temp.name)), digest)
            verify.assert_called_once()
        image.write_bytes(b"changed dmg")
        with patch.object(publisher.dmg_tool, "verify_dmg") as verify:
            with self.assertRaisesRegex(ValueError, "DMG differs"):
                publisher.verify_dmg_asset(self.release, image, self.report, Path(self.temp.name))
            verify.assert_not_called()

    def test_wrong_production_team_rejected_even_if_notary_team_matches(self):
        self.report["signing_team"] = self.report["notarization"]["team"] = "OTHER12345"
        self.pack()
        with self.assertRaisesRegex(ValueError, "notarized standalone"):
            publisher.verify_release(self.release, self.archive)

    def test_lightweight_and_annotated_tags_must_resolve_to_release_commit(self):
        commit = "a" * 40
        direct = json.dumps({"object": {"type": "commit", "sha": commit}})
        with patch.object(publisher, "github", return_value=direct):
            publisher.verify_tag("v1.0.0", commit)
            with self.assertRaisesRegex(ValueError, "different source commit"):
                publisher.verify_tag("v1.0.0", "b" * 40)
        annotation = json.dumps({"object": {"type": "tag", "sha": "c" * 40}})
        with patch.object(publisher, "github", side_effect=[annotation, direct]) as request:
            publisher.verify_tag("v1.0.0", commit)
            self.assertEqual(request.call_count, 2)
        with patch.object(publisher, "github", return_value=annotation):
            with self.assertRaisesRegex(ValueError, "nesting"):
                publisher.verify_tag("v1.0.0", commit)


if __name__ == "__main__":
    unittest.main()
