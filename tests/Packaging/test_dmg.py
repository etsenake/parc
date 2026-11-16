import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("parc_dmg", Path(__file__).resolve().parents[2] / "scripts/package-dmg.py")
dmg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg)
layout = dmg.layout
REAL_RUN = subprocess.run
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
        (self.app / "Contents/Resources").mkdir()
        (self.app / "Contents/Resources/Parc.icns").write_bytes(b"fixture icon")
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
        self.output = self.package.parent / "Parc-arm64.dmg"
        self.volume = Path(self.temp.name) / "volume"
        self.calls = []
        self.status = "Accepted"
        self.fail = None
        self.no_id = False
        self.wrong_hash = False
        self.actual_team = TEAM
        self.cdhash = "a" * 40
        self.upload_hash = None
        self.tamper = None
        self.busy = 0
        self.phantom = False
        self.stuck = False
        self.mounted = set()
        self.build_error = None
        self.layout_error = None
        self.attached = []

    def run_tool(self, args, **kwargs):
        args = list(map(str, args))
        self.calls.append(args)
        out, err = "", ""
        code = int(self.fail is not None and args[:len(self.fail)] == self.fail)
        if args[0] == "xattr":
            return subprocess.CompletedProcess(args, 1, "", "") if code else REAL_RUN(args, **kwargs)
        if args[:3] == ["hdiutil", "info", "-plist"]:
            return subprocess.CompletedProcess(args, 0, plistlib.dumps({"images": self.attached}), b"")
        if args[:2] == ["hdiutil", "attach"] and not code:
            mount = Path(args[args.index("-mountpoint") + 1])
            mount.rmdir()
            os.rename(self.volume, mount)
            self.mounted.add(mount)
        elif args[:2] == ["hdiutil", "detach"]:
            if self.stuck or (self.busy and "-force" not in args):
                self.busy = max(self.busy - 1, 0)
                return subprocess.CompletedProcess(args, 16, "", "resource busy")
            mount = Path(args[-1])
            os.rename(mount, self.volume)
            mount.mkdir()
            self.mounted.discard(mount)
            if self.phantom:
                self.phantom = False
                return subprocess.CompletedProcess(args, 16, "", "reported busy after unmounting")
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

    def dmgbuild(self, app, image, log):
        self.calls.append(["dmgbuild", str(app), str(image), str(log)])
        if self.build_error:
            mount = Path(self.temp.name) / "Parc"
            mount.mkdir()
            self.mounted.add(mount)
            writable = str(image.with_name(".tempParc-arm64.dmg")).replace("/private/var/", "/var/", 1)
            self.attached = [{"image-path": str(Path(self.temp.name) / "other.dmg"),
                              "system-entities": [{"mount-point": "/Volumes/Other"}]}, {},
                             {"image-path": writable, "system-entities": [{"dev-entry": "/dev/disk9"}]},
                             {"image-path": writable,
                              "system-entities": [{"dev-entry": "/dev/disk9"}, {"mount-point": str(mount)}]}]
            raise self.build_error
        shutil.rmtree(self.volume, ignore_errors=True)
        self.volume.mkdir()
        shutil.copytree(app, self.volume / "Parc.app")
        (self.volume / "Applications").symlink_to("/Applications")
        if self.tamper:
            self.tamper(self.volume)
        image.write_bytes(b"fixture disk image")

    def check_layout(self, volume, finder_info, icon):
        self.calls.append(["layout", str(volume), icon.decode()])
        if self.layout_error:
            raise layout.LayoutError(self.layout_error)

    def execute(self):
        with (patch.object(dmg.subprocess, "run", side_effect=self.run_tool), patch.object(dmg.time, "sleep"),
              patch.object(dmg.os.path, "ismount", side_effect=lambda path: Path(path) in self.mounted),
              patch.object(layout, "build", side_effect=self.dmgbuild),
              patch.object(layout, "verify", side_effect=self.check_layout),
              contextlib.redirect_stdout(io.StringIO())):
            return dmg.package_dmg(self.package, self.output, "fixture-identity", "fixture-profile", TEAM, 0)

    def count(self, prefix):
        return sum(call[:len(prefix)] == prefix for call in self.calls)

    def position(self, prefix):
        return next(index for index, call in enumerate(self.calls) if call[:len(prefix)] == prefix)

    def reset(self):
        self.output.unlink(missing_ok=True)
        shutil.rmtree(self.package.parent / "dmg-notarization", ignore_errors=True)
        shutil.rmtree(self.volume, ignore_errors=True)
        self.calls = []

    def leftovers(self):
        return [path.name for path in self.output.parent.iterdir() if path.name.startswith(".parc-dmg-")]

    def test_complete_image_retains_app_and_container_acceptance(self):
        receipt = self.execute()
        self.assertEqual(receipt["phase"], "complete")
        self.assertTrue(receipt["stapled"] and receipt["gatekeeper_verified"])
        self.assertNotEqual(receipt["archive_sha256"], receipt["stapled_sha256"])
        self.assertEqual(json.loads(self.report_path.read_text()), self.report)
        self.assertTrue(any(call[:6] == ["spctl", "--assess", "--type", "open", "--context", "context:primary-signature"]
                            for call in self.calls))

    def test_install_window_is_built_by_dmgbuild_and_checked_before_submission(self):
        self.execute()
        steps = [["dmgbuild"], ["codesign", "--sign"], ["hdiutil", "attach"], ["layout"],
                 ["xcrun", "notarytool", "submit"]]
        self.assertEqual([self.position(step) for step in steps], sorted(self.position(step) for step in steps))
        build = self.calls[self.position(["dmgbuild"])]
        self.assertEqual(Path(build[1]), self.app.resolve())
        image = Path(build[2])
        self.assertEqual(image.name, "Parc-arm64.dmg")
        self.assertTrue(image.parent.name.startswith(".parc-dmg-"))
        self.assertEqual(image.parent.parent, self.output.parent.resolve())
        self.assertEqual(Path(build[3]), self.package.parent.resolve() / "dmg-notarization/dmgbuild.log")
        attach = self.calls[self.position(["hdiutil", "attach"])]
        self.assertIn("-nobrowse", attach)
        self.assertIn("-readonly", attach)
        self.assertEqual(self.calls[self.position(["layout"])][2], "fixture icon")
        self.assertEqual(self.leftovers(), [])

    def test_image_keeps_one_stable_name_beside_the_package(self):
        self.assertEqual(dmg.ASSET, "Parc-arm64.dmg")
        for wrong in (self.package.parent / "Parc-1.0.0-arm64.dmg", self.package / "Parc-arm64.dmg"):
            with self.subTest(output=wrong), self.assertRaisesRegex(dmg.Refusal, "Parc-arm64.dmg beside"):
                dmg.package_dmg(self.package, wrong, "fixture-identity", "fixture-profile", TEAM, 0)
            self.assertFalse(wrong.exists())
        self.assertEqual(self.calls, [])

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
        self.tamper = lambda volume: (volume / "Applications").unlink()
        with self.assertRaisesRegex(dmg.Refusal, "Applications shortcut"):
            self.execute()
        self.assertEqual(self.count(["xcrun", "notarytool", "submit"]), 0)

    def test_wrong_install_window_is_refused_before_submission(self):
        self.layout_error = "the Finder layout differs from what dmgbuild writes for this window: . vstl"
        with self.assertRaisesRegex(dmg.Refusal, "install window is missing or wrong: .* vstl"):
            self.execute()
        self.assertEqual(self.count(["xcrun", "notarytool", "submit"]), 0)
        self.assertEqual(self.count(["hdiutil", "detach"]), 1)

    def test_failed_dmgbuild_leaves_no_image_or_staging(self):
        self.build_error = RuntimeError("Unable to attach disk image")
        with self.assertRaisesRegex(dmg.Refusal, "dmgbuild could not build the install window: Unable to attach"):
            self.execute()
        self.assertFalse(self.output.exists())
        self.assertEqual(self.leftovers(), [])
        self.assertEqual(self.count(["codesign", "--sign"]), 0)
        self.build_error = None
        self.assertEqual(self.execute()["phase"], "complete")

    def test_failed_or_interrupted_dmgbuild_unmounts_only_its_own_image(self):
        for error in (RuntimeError("Unable to sync"), KeyboardInterrupt()):
            with self.subTest(error=type(error).__name__):
                self.reset()
                self.build_error = error
                with self.assertRaises((dmg.Refusal, KeyboardInterrupt)):
                    self.execute()
                detaches = [call for call in self.calls if call[:2] == ["hdiutil", "detach"]]
                self.assertEqual(detaches, [["hdiutil", "detach", str(Path(self.temp.name) / "Parc")]])
                self.assertEqual(self.mounted, set())
                self.assertFalse(self.output.exists())
                self.assertEqual(self.leftovers(), [])
                shutil.rmtree(Path(self.temp.name) / "Parc")
                self.attached = []

    def test_stop_signal_interrupts_packaging_so_its_cleanup_runs(self):
        prior = signal.getsignal(signal.SIGTERM)
        self.addCleanup(signal.signal, signal.SIGTERM, prior)
        arguments = ["package-dmg.py", str(self.package), "--output", str(self.output), "--sign-identity", "id",
                     "--profile", "profile", "--team", TEAM]
        with (patch.object(sys, "argv", arguments),
              patch.object(dmg, "package_dmg", side_effect=lambda *args: os.kill(os.getpid(), signal.SIGTERM)),
              self.assertRaisesRegex(KeyboardInterrupt, "signal 15")):
            dmg.main()

    def test_unmount_that_reports_busy_after_succeeding_is_not_retried(self):
        self.phantom = True
        self.assertEqual(self.execute()["phase"], "complete")
        self.assertEqual(self.count(["hdiutil", "detach", "-force"]), 0)
        first = self.position(["hdiutil", "detach"])
        self.assertNotEqual(self.calls[first + 1][:2], ["hdiutil", "detach"])

    def test_resumed_image_from_before_the_install_window_skips_only_the_layout(self):
        self.execute()
        receipt_path = self.package.parent / "dmg-notarization/submission.json"
        receipt = json.loads(receipt_path.read_text())
        del receipt["install_window"]
        receipt_path.write_text(json.dumps(receipt))
        self.layout_error = "the Finder layout is missing or unreadable"
        self.calls = []
        self.assertEqual(self.execute()["phase"], "complete")
        self.assertEqual(self.count(["xattr", "-px"]), 0)
        self.assertEqual(self.count(["layout"]), 0)

    def test_busy_volume_retries_then_forces_its_unmount(self):
        self.busy = 2
        self.execute()
        self.assertEqual(self.count(["hdiutil", "detach", "-force"]), 0)
        self.reset()
        self.busy = 5
        self.execute()
        layout_detaches = [call for call in self.calls if call[:2] == ["hdiutil", "detach"]][:6]
        self.assertEqual([call[2] == "-force" for call in layout_detaches], [False] * 5 + [True])

    def test_approval_must_match_exact_input(self):
        self.wrong_hash = True
        with self.assertRaisesRegex(dmg.Refusal, "exact DMG"):
            self.execute()

    def test_rejected_image_is_never_stapled(self):
        self.status = "Invalid"
        with self.assertRaisesRegex(dmg.Refusal, "exact DMG"):
            self.execute()
        self.assertEqual(self.count(["xcrun", "stapler", "staple"]), 0)

    def test_resume_reuses_submission_even_after_stapling_changes_hash(self):
        self.fail = ["spctl", "--assess", "--type", "open"]
        with self.assertRaises(dmg.Refusal):
            self.execute()
        self.fail = None
        self.assertEqual(self.execute()["phase"], "complete")
        self.execute()
        self.assertEqual(self.count(["xcrun", "notarytool", "submit"]), 1)
        self.assertEqual(self.count(["dmgbuild"]), 1)

    def test_ambiguous_upload_cannot_submit_twice(self):
        self.no_id = True
        with self.assertRaisesRegex(dmg.Refusal, "confirmed success"):
            self.execute()
        with self.assertRaisesRegex(dmg.Refusal, "earlier DMG upload"):
            self.execute()
        self.assertEqual(self.count(["xcrun", "notarytool", "submit"]), 1)

    def test_changed_app_report_or_completed_image_cannot_resume(self):
        self.execute()
        self.output.write_bytes(b"changed disk image")
        with self.assertRaisesRegex(dmg.Refusal, "differs from its receipt"):
            self.execute()
        self.report["extra"] = "changed"
        self.report_path.write_text(json.dumps(self.report))
        with self.assertRaisesRegex(dmg.Refusal, "app changed"):
            self.execute()

    def test_published_images_from_before_the_install_window_skip_only_the_layout(self):
        self.layout_error = "the Finder layout is missing or unreadable"
        with self.assertRaisesRegex(dmg.Refusal, "install window"):
            self.execute()
        self.calls = []
        with (patch.object(dmg.subprocess, "run", side_effect=self.run_tool),
              patch.object(layout, "verify", side_effect=self.check_layout)):
            dmg.verify_dmg(self.output, self.report, self.package.parent / "dmg-notarization", notarized=False,
                           layout_expected=False)
        self.assertEqual(self.count(["xattr", "-px"]), 0)
        self.assertEqual(self.count(["layout"]), 0)


if __name__ == "__main__":
    unittest.main()
