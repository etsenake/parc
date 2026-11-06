"""Reject mismatched or unnotarized archives before changing the public tap."""
import hashlib
import copy
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
        self.report = {"app_version": {"version": "1.0.1", "build": 2},
                       "purpose": "distribution", "configuration": "release", "layout": "standalone-app",
                       "distribution_eligible": True, "notarized": True, "signing_team": publisher.PRODUCTION_TEAM,
                       "notarization": {"status": "Accepted", "stapled": True,
                                        "gatekeeper_verified": True, "team": publisher.PRODUCTION_TEAM},
                       "signed_images": {"Parc.app/Contents/MacOS/Parc": hashlib.sha256(self.image).hexdigest()}}
        self.info = {"CFBundleShortVersionString": "1.0.1", "CFBundleVersion": "2",
                     "CFBundleIdentifier": "org.parc.Browser"}
        self.release = {"tag_name": "v1.0.1", "target_commitish": "a" * 40,
                        "draft": False, "prerelease": False, "assets": []}

    def pack(self):
        with zipfile.ZipFile(self.archive, "w") as bundle:
            bundle.writestr("development/package-report.json", json.dumps(self.report))
            bundle.writestr("development/Parc.app/Contents/Info.plist", plistlib.dumps(self.info))
            bundle.writestr("development/Parc.app/Contents/MacOS/Parc", self.image)
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.release["assets"] = [{"name": "Parc-1.0.1-arm64.zip", "digest": "sha256:" + digest}]
        return digest

    def test_verified_release_produces_pinned_cask(self):
        digest = self.pack()
        self.assertEqual(publisher.verify_release(self.release, self.archive)[:3],
                         ({"version": "1.0.1", "build": 2}, digest, "a" * 40))
        text = publisher.cask("1.0.1", digest)
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

    def test_draft_or_mutable_source_rejected(self):
        for key, value in (("draft", True), ("target_commitish", "main")):
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
        self.release["assets"].append({"name": "Parc-1.0.1-arm64.dmg", "digest": "sha256:" + digest})
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
            publisher.verify_tag("v1.0.1", commit)
            with self.assertRaisesRegex(ValueError, "different source commit"):
                publisher.verify_tag("v1.0.1", "b" * 40)
        annotation = json.dumps({"object": {"type": "tag", "sha": "c" * 40}})
        with patch.object(publisher, "github", side_effect=[annotation, direct]) as request:
            publisher.verify_tag("v1.0.1", commit)
            self.assertEqual(request.call_count, 2)
        with patch.object(publisher, "github", return_value=annotation):
            with self.assertRaisesRegex(ValueError, "nesting"):
                publisher.verify_tag("v1.0.1", commit)

    def acceptance(self):
        return {"schema_version": 1, "status": "passed", "acceptance_kind": "automatic", "release_tag": "v1.0.1",
                "source_commit": "a" * 40, "app_version": {"version": "1.0.1", "build": 2},
                "package_report_sha256": "f" * 64, "signing_team": publisher.PRODUCTION_TEAM,
                "prelaunch_strict_verified": True, "installed_code_hashes_verified": True,
                "designated_requirement": publisher.PRODUCTION_DESIGNATED_REQUIREMENT,
                "launch_observation": {"passed": True, "observed_seconds": 90, "main_pid": 123,
                                       "new_crash_reports": [], "failure": None}}

    def test_acceptance_rejects_failure_short_check_new_crash_or_dead_pid(self):
        for field, value in (("passed", False), ("observed_seconds", 59.99), ("observed_seconds", float("nan")),
                             ("new_crash_reports", ["fixture.ips"]), ("main_pid", 0), ("failure", "exited")):
            with self.subTest(field=field, value=value):
                receipt = self.acceptance()
                receipt["launch_observation"][field] = value
                with self.assertRaisesRegex(ValueError, "passed startup"):
                    publisher.verify_acceptance(receipt, "v1.0.1", "a" * 40, self.report["app_version"], "f" * 64)

    def test_acceptance_binds_commit_version_report_and_signing(self):
        receipt = self.acceptance()
        publisher.verify_acceptance(receipt, "v1.0.1", "a" * 40, self.report["app_version"], "f" * 64)
        for field, value in (("source_commit", "b" * 40), ("package_report_sha256", "e" * 64),
                             ("app_version", {"version": "1.0.1", "build": 1}), ("signing_team", "OTHER12345"),
                             ("prelaunch_strict_verified", False), ("installed_code_hashes_verified", False),
                             ("designated_requirement", "other")):
            with self.subTest(field=field):
                changed = copy.deepcopy(receipt)
                changed[field] = value
                with self.assertRaisesRegex(ValueError, "exact release commit"):
                    publisher.verify_acceptance(changed, "v1.0.1", "a" * 40, self.report["app_version"], "f" * 64)

    def test_failed_automatic_receipt_never_promotes(self):
        receipt = self.acceptance()
        receipt["launch_observation"]["passed"] = False
        with patch.object(publisher, "github") as request:
            with self.assertRaises(ValueError):
                publisher.promote_release(self.release, receipt, self.report["app_version"], "f" * 64)
            request.assert_not_called()

    def test_explicit_dated_user_acceptance_preserves_interrupted_observation(self):
        receipt = self.acceptance()
        receipt.update(status="user-confirmed", acceptance_kind="user-confirmed", release_tag="v1.0.0",
            app_version={"version": "1.0.0", "build": 1}, artifact_code_hashes_verified=True,
            artifact_strict_verified=True, automatic_startup_acceptance_claimed=False,
            user_confirmation={"confirmed_by": "Josh", "confirmed_at": "2026-11-05T21:35:00-06:00",
                               "scope": "normal-startup", "statement": "Normal startup worked; I deliberately triggered a separate behavior test."})
        receipt["launch_observation"].update(passed=False, observed_seconds=20.05,
            new_crash_reports=["user-triggered.ips"], failure="Uncontrolled observation interrupted")
        original = copy.deepcopy(receipt["launch_observation"])
        publisher.verify_acceptance(receipt, "v1.0.0", "a" * 40, receipt["app_version"], "f" * 64)
        self.assertEqual(receipt["launch_observation"], original)
        for field, value in (("confirmed_at", "2026-11-05"), ("statement", ""), ("scope", "other")):
            changed = copy.deepcopy(receipt)
            changed["user_confirmation"][field] = value
            with self.assertRaises(ValueError):
                publisher.verify_acceptance(changed, "v1.0.0", "a" * 40, receipt["app_version"], "f" * 64)
        receipt["automatic_startup_acceptance_claimed"] = True
        with self.assertRaises(ValueError):
            publisher.verify_acceptance(receipt, "v1.0.0", "a" * 40, receipt["app_version"], "f" * 64)

    def test_versioned_prerelease_can_be_verified_before_acceptance_promotion(self):
        self.release["prerelease"] = True
        self.pack()
        self.assertEqual(publisher.verify_release(self.release, self.archive)[0], self.report["app_version"])

    def test_passed_receipt_promotes_without_changing_assets(self):
        self.pack()
        self.release.update(name="Parc 1.0.1 candidate (engine overlay 327)", prerelease=True)
        self.release["assets"][0]["id"] = 123
        promoted = copy.deepcopy(self.release)
        promoted["prerelease"] = False
        def request(*args):
            if "git/ref/tags" in args[1]:
                return json.dumps({"object": {"type": "commit", "sha": "a" * 40}})
            if args[:2] == ("api", "repos/etsenake/parc"):
                return "true"
            if args[:2] == ("release", "edit"):
                self.assertIn("--prerelease=false", args)
                self.assertIn("--latest", args)
                return ""
            return json.dumps(promoted)
        with patch.object(publisher, "github", side_effect=request):
            publisher.promote_release(self.release, self.acceptance(), self.report["app_version"], "f" * 64)


if __name__ == "__main__":
    unittest.main()
