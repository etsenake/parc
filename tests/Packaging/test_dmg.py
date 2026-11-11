import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("parc_dmg", Path(__file__).resolve().parents[2] / "scripts/package-dmg.py")
dmg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg)
TEAM = "TEAM123456"
SUBMISSION = "b6743aa6-df42-48cb-bd8e-cbbebee591fd"


class DmgTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.package = Path(self.temp.name) / "run/development"
        self.app = self.package / "Parc.app"
        self.image = self.app / "Contents/MacOS/Parc"
        self.image.parent.mkdir(parents=True)
        self.image.write_bytes(b"notarized fixture image")
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "org.parc.Browser",
            "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1"}))
        self.report = {"configuration": "release", "purpose": "distribution", "layout": "standalone-app",
                       "distribution_eligible": True, "signing_team": TEAM, "notarized": True,
                       "notarization": {"status": "Accepted", "stapled": True,
                                        "gatekeeper_verified": True, "team": TEAM},
                       "app_version": {"version": "1.0.0", "build": 1},
                       "signed_images": {"Parc.app/Contents/MacOS/Parc": hashlib.sha256(self.image.read_bytes()).hexdigest()}}
        self.report_path = self.package / "package-report.json"
        self.report_path.write_text(json.dumps(self.report))
        self.output = self.package.parent / "Parc-1.0.0-arm64.dmg"
        self.calls = []
        self.status = "Accepted"
        self.fail = None
        self.no_id = False
        self.wrong_hash = False
        self.actual_team = TEAM
        self.cdhash = "a" * 40
        self.upload_hash = None
        self.omit_shortcut = False

    def run_tool(self, args, **kwargs):
        args = list(map(str, args))
        self.calls.append(args)
        out, err = "", ""
        code = int(self.fail is not None and args[:len(self.fail)] == self.fail)
        if args[0] == "ditto":
            shutil.copytree(args[1], args[2])
        elif args[:2] == ["hdiutil", "create"]:
            self.assertTrue((Path(args[args.index("-srcfolder") + 1]) / "Applications").is_symlink())
            Path(args[-1]).write_bytes(b"fixture disk image")
        elif args[:2] == ["hdiutil", "attach"]:
            mount = Path(args[args.index("-mountpoint") + 1])
            shutil.copytree(self.app, mount / "Parc.app")
            if not self.omit_shortcut:
                (mount / "Applications").symlink_to("/Applications")
        elif args[:2] == ["codesign", "-dv"]:
            err = f"Authority=Developer ID Application: Fixture\nTeamIdentifier={self.actual_team}\nTimestamp=Today\nCDHash={self.cdhash}\n"
        elif args[:3] == ["xcrun", "notarytool", "submit"]:
            self.upload_hash = hashlib.sha256(Path(args[3]).read_bytes()).hexdigest()
            out = json.dumps({} if self.no_id else {"id": SUBMISSION})
        elif args[:3] == ["xcrun", "notarytool", "info"]:
            out = json.dumps({"id": SUBMISSION, "status": self.status})
        elif args[:3] == ["xcrun", "notarytool", "log"]:
            Path(args[-1]).write_text(json.dumps({"status": self.status, "jobId": SUBMISSION,
                "sha256": "wrong" if self.wrong_hash else self.upload_hash, "issues": None}))
        elif args[:3] == ["xcrun", "stapler", "staple"] and not code:
            if not self.output.read_bytes().endswith(b"ticket"):
                self.output.write_bytes(self.output.read_bytes() + b"ticket")
        return subprocess.CompletedProcess(args, code, out, err)

    def execute(self):
        with patch.object(dmg.subprocess, "run", side_effect=self.run_tool), contextlib.redirect_stdout(io.StringIO()):
            return dmg.package_dmg(self.package, self.output, "fixture-identity", "fixture-profile", TEAM, 0)

    def test_complete_image_retains_app_and_container_acceptance(self):
        receipt = self.execute()
        self.assertEqual(receipt["phase"], "complete")
        self.assertTrue(receipt["stapled"] and receipt["gatekeeper_verified"])
        self.assertNotEqual(receipt["archive_sha256"], receipt["stapled_sha256"])
        self.assertEqual(json.loads(self.report_path.read_text()), self.report)
        self.assertTrue(any(call[:6] == ["spctl", "--assess", "--type", "open", "--context", "context:primary-signature"]
                            for call in self.calls))

    def test_unnotarized_app_or_changed_image_never_creates_dmg(self):
        self.report["notarized"] = False
        self.report_path.write_text(json.dumps(self.report))
        with self.assertRaisesRegex(dmg.Refusal, "verified notarized"):
            self.execute()
        self.assertFalse(self.output.exists())
        self.report["notarized"] = True
        self.report_path.write_text(json.dumps(self.report))
        self.image.write_bytes(b"changed")
        with self.assertRaisesRegex(dmg.Refusal, "signed image differs"):
            self.execute()
        self.assertFalse(self.output.exists())

    def test_missing_shortcut_is_rejected_before_submission(self):
        self.omit_shortcut = True
        with self.assertRaisesRegex(dmg.Refusal, "Applications shortcut"):
            self.execute()
        self.assertFalse(any(call[:3] == ["xcrun", "notarytool", "submit"] for call in self.calls))

    def test_approval_must_match_exact_input(self):
        self.wrong_hash = True
        with self.assertRaisesRegex(dmg.Refusal, "exact DMG"):
            self.execute()

    def test_rejected_image_is_never_stapled(self):
        self.status = "Invalid"
        with self.assertRaisesRegex(dmg.Refusal, "exact DMG"):
            self.execute()
        self.assertFalse(any(call[:3] == ["xcrun", "stapler", "staple"] for call in self.calls))

    def test_resume_reuses_submission_even_after_stapling_changes_hash(self):
        self.fail = ["spctl", "--assess", "--type", "open"]
        with self.assertRaises(dmg.Refusal):
            self.execute()
        self.fail = None
        self.assertEqual(self.execute()["phase"], "complete")
        self.execute()
        self.assertEqual(sum(call[:3] == ["xcrun", "notarytool", "submit"] for call in self.calls), 1)

    def test_ambiguous_upload_cannot_submit_twice(self):
        self.no_id = True
        with self.assertRaisesRegex(dmg.Refusal, "confirmed success"):
            self.execute()
        with self.assertRaisesRegex(dmg.Refusal, "earlier DMG upload"):
            self.execute()
        self.assertEqual(sum(call[:3] == ["xcrun", "notarytool", "submit"] for call in self.calls), 1)

    def test_changed_app_report_or_completed_image_cannot_resume(self):
        self.execute()
        self.output.write_bytes(b"changed disk image")
        with self.assertRaisesRegex(dmg.Refusal, "differs from its receipt"):
            self.execute()
        self.report["extra"] = "changed"
        self.report_path.write_text(json.dumps(self.report))
        with self.assertRaisesRegex(dmg.Refusal, "app changed"):
            self.execute()


if __name__ == "__main__":
    unittest.main()
