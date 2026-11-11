import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("parc_acceptance", Path(__file__).resolve().parents[2] /
                                            "scripts/record-release-acceptance.py")
recorder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recorder)


class ReleaseAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / "package"
        self.package.mkdir()
        self.app = self.root / "installed/Parc.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        images = {}
        for index in range(12):
            relative = "Parc.app/Contents/MacOS/" + ("Parc" if index == 0 else f"fixture-{index}")
            image = self.app.parent / relative
            image.write_bytes(f"fixture code {index}".encode())
            images[relative] = hashlib.sha256(image.read_bytes()).hexdigest()
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "org.parc.Browser",
            "CFBundleShortVersionString": "1.0.1", "CFBundleVersion": "2"}))
        self.report = {"purpose": "distribution", "configuration": "release", "layout": "standalone-app",
            "distribution_eligible": True, "notarized": True, "signing_team": recorder.publisher.PRODUCTION_TEAM,
            "notarization": {"team": recorder.publisher.PRODUCTION_TEAM, "status": "Accepted",
                             "stapled": True, "gatekeeper_verified": True},
            "app_version": {"version": "1.0.1", "build": 2}, "signed_images": images}
        (self.package / "package-report.json").write_text(json.dumps(self.report))
        self.output = self.root / "acceptance.json"
        self.clock = 0
        self.opened = False
        self.exit_at = None
        self.post_crash = False
        self.crash_during_post_verify = False
        self.team = recorder.publisher.PRODUCTION_TEAM
        self.dr = recorder.EXPECTED_DR
        self.calls = []

    def run_tool(self, args, **kwargs):
        args = list(map(str, args))
        self.calls.append(args)
        stdout, stderr = "", ""
        if args[0] == "open":
            self.opened = True
        if args[:2] == ["codesign", "-dv"]:
            stderr = f"TeamIdentifier={self.team}\nAuthority=Developer ID Application: Fixture\nTimestamp=Today\n"
        if args[:2] == ["codesign", "-dr"]:
            stdout = self.dr
        if args[:3] == ["codesign", "--verify", "--deep"] and "--strict" not in args:
            self.post_crash = self.crash_during_post_verify
        return subprocess.CompletedProcess(args, 0, stdout, stderr)

    def processes(self, app):
        if not self.opened or (self.exit_at is not None and self.clock >= self.exit_at):
            return []
        return [{"pid": 123, "state": "S", "executable": str(app / "Contents/MacOS/Parc")}]

    def sleep(self, seconds):
        self.clock += seconds

    def execute(self):
        with patch.object(recorder.publisher, "verify_tag"), \
                patch.object(recorder.subprocess, "run", side_effect=self.run_tool), \
                patch.object(recorder, "processes", side_effect=self.processes), \
                patch.object(recorder, "crash_reports", side_effect=lambda: {"fixture-helper.ips": 1} if self.post_crash else {}), \
                patch.object(recorder.time, "monotonic", side_effect=lambda: self.clock), \
                patch.object(recorder.time, "sleep", side_effect=self.sleep):
            return recorder.record(self.package, self.app, "v1.0.1", "a" * 40, self.output, 60)

    def test_passed_receipt_binds_exact_code_and_report(self):
        receipt = self.execute()
        self.assertEqual(receipt["status"], "passed")
        self.assertEqual(receipt["code_image_count"], 12)
        self.assertTrue(receipt["prelaunch_strict_verified"])
        self.assertEqual(receipt["launch_observation"]["observed_seconds"], 60)
        recorder.publisher.verify_acceptance(receipt, "v1.0.1", "a" * 40, self.report["app_version"],
                                             hashlib.sha256((self.package / "package-report.json").read_bytes()).hexdigest())
        strict_index = next(i for i, call in enumerate(self.calls) if "--strict" in call)
        open_index = next(i for i, call in enumerate(self.calls) if call[0] == "open")
        self.assertLess(strict_index, open_index)

    def test_pid_exit_records_failure_and_cannot_promote(self):
        self.exit_at = 20
        receipt = self.execute()
        self.assertEqual(receipt["status"], "failed")
        self.assertIn("exited", receipt["launch_observation"]["failure"])
        with self.assertRaisesRegex(ValueError, "passed startup"):
            recorder.publisher.verify_acceptance(receipt, "v1.0.1", "a" * 40, self.report["app_version"], "f" * 64)

    def test_helper_report_during_post_verify_is_rejected(self):
        self.crash_during_post_verify = True
        receipt = self.execute()
        self.assertEqual(receipt["status"], "failed")
        self.assertEqual(receipt["launch_observation"]["new_crash_reports"], ["fixture-helper.ips"])
        self.assertIn("post-launch", receipt["launch_observation"]["failure"])

    def test_changed_code_or_wrong_team_never_opens_app(self):
        (self.app / "Contents/MacOS/fixture-11").write_bytes(b"changed")
        receipt = self.execute()
        self.assertEqual(receipt["status"], "failed")
        self.assertFalse(self.opened)
        self.assertIn("code differs", receipt["launch_observation"]["failure"])

    def test_changed_production_requirement_never_opens_app(self):
        self.dr = 'designated => identifier "other"'
        receipt = self.execute()
        self.assertEqual(receipt["status"], "failed")
        self.assertFalse(self.opened)
        self.assertIn("requirement changed", receipt["launch_observation"]["failure"])

    def test_wrong_team_never_opens_app(self):
        self.team = "OTHER12345"
        receipt = self.execute()
        self.assertEqual(receipt["status"], "failed")
        self.assertFalse(self.opened)
        self.assertIn("production Developer ID", receipt["launch_observation"]["failure"])

    def test_stale_installed_version_never_opens_app(self):
        path = self.app / "Contents/Info.plist"
        info = plistlib.loads(path.read_bytes())
        info["CFBundleShortVersionString"] = "0.1.0"
        path.write_bytes(plistlib.dumps(info))
        receipt = self.execute()
        self.assertEqual(receipt["status"], "failed")
        self.assertFalse(self.opened)
        self.assertIn("version/identity differs", receipt["launch_observation"]["failure"])

    def test_user_confirmation_checks_only_artifact_and_keeps_raw_failure(self):
        shutil.copytree(self.app, self.package / "Parc.app")
        observation = self.root / "interrupted.json"
        observation.write_text(json.dumps({"passed": False, "observed_seconds": 20.05,
            "main_pid": 123, "new_crash_reports": ["user-triggered.ips"], "failure": "Interrupted"}))
        original = observation.read_bytes()
        with patch.object(recorder.publisher, "verify_tag"), \
                patch.object(recorder.subprocess, "run", side_effect=self.run_tool), \
                patch.object(recorder, "processes", side_effect=AssertionError("Must not inspect current app processes")):
            receipt = recorder.record_user_confirmation(self.package, "v1.0.1", "a" * 40, self.output,
                "Josh confirms normal startup; a deliberate behavior test interrupted the observer.",
                "2026-11-05T21:35:00-06:00", observation)
        self.assertEqual(receipt["acceptance_kind"], "user-confirmed")
        self.assertFalse(receipt["automatic_startup_acceptance_claimed"])
        self.assertFalse(receipt["launch_observation"]["passed"])
        self.assertEqual(observation.read_bytes(), original)
        self.assertFalse(any(call[0] == "open" for call in self.calls))
        self.assertTrue(receipt["artifact_code_hashes_verified"])


if __name__ == "__main__":
    unittest.main()
