import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
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
        self.output = self.package.parent / "Parc-1.0.0-arm64.dmg"
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

    def run_tool(self, args, **kwargs):
        args = list(map(str, args))
        self.calls.append(args)
        out, err = "", ""
        code = int(self.fail is not None and args[:len(self.fail)] == self.fail)
        if args[0] in ("tiffutil", "xattr"):
            return subprocess.CompletedProcess(args, 1, "", "") if code else REAL_RUN(args, **kwargs)
        if args[0] == "ditto":
            shutil.copytree(args[1], args[2])
        elif args[:2] == ["hdiutil", "create"]:
            self.assertEqual(args[args.index("-format") + 1], "UDRW")
            stage = Path(args[args.index("-srcfolder") + 1])
            self.assertTrue((stage / "Applications").is_symlink())
            shutil.rmtree(self.volume, ignore_errors=True)
            shutil.copytree(stage, self.volume, symlinks=True)
            Path(args[-1]).write_bytes(b"writable fixture image")
        elif args[:2] == ["hdiutil", "attach"] and not code:
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
        elif args[:2] == ["hdiutil", "convert"] and not code:
            self.assertEqual(args[args.index("-format") + 1], "UDZO")
            if self.tamper:
                self.tamper(self.volume)
            Path(args[args.index("-o") + 1]).write_bytes(b"fixture disk image")
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
        with (patch.object(dmg.subprocess, "run", side_effect=self.run_tool), patch.object(dmg.time, "sleep"),
              patch.object(dmg.os.path, "ismount", side_effect=lambda path: Path(path) in self.mounted),
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

    def test_install_window_is_laid_out_before_compression_and_signing(self):
        self.execute()
        steps = [["tiffutil", "-cathidpicheck"], ["hdiutil", "create"], ["hdiutil", "attach"],
                 ["xattr", "-wx", "com.apple.FinderInfo"], ["hdiutil", "detach"], ["hdiutil", "convert"],
                 ["codesign", "--sign"], ["xcrun", "notarytool", "submit"]]
        self.assertEqual([self.position(step) for step in steps], sorted(self.position(step) for step in steps))
        attach = self.calls[self.position(["hdiutil", "attach"])]
        self.assertIn("-nobrowse", attach)
        self.assertNotIn("-readonly", attach)
        entries = layout.read_store((self.volume / ".DS_Store").read_bytes())
        self.assertEqual(entries[("Parc.app", "Iloc")][1][:8], (160).to_bytes(4, "big") + (204).to_bytes(4, "big"))
        self.assertEqual(entries[("Applications", "Iloc")][1][:8], (480).to_bytes(4, "big") + (204).to_bytes(4, "big"))
        background = self.volume / layout.BACKGROUND
        self.assertEqual(layout.tiff_sizes(background.read_bytes()), [(640, 400), (1280, 800)])
        self.assertTrue(background.parent.stat().st_flags & stat.UF_HIDDEN)
        self.assertEqual((self.volume / ".VolumeIcon.icns").read_bytes(), b"fixture icon")
        self.assertEqual(self.leftovers(), [])

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

    def test_missing_or_wrong_install_window_is_refused_before_submission(self):
        def moved(volume):
            entries = [entry if entry[0] != "Applications" else (*entry[:3], layout.icon_location(480, 320))
                       for entry in layout.layout_entries(layout.background_alias(volume))]
            (volume / ".DS_Store").write_bytes(layout.store(entries))

        def stale(volume):
            image = (volume / layout.BACKGROUND).stat()
            alias = layout.alias_record(layout.VOLUME, layout.mac_time(volume.stat().st_birthtime), ".background",
                                        (volume / ".background").stat().st_ino, "background.tiff", image.st_ino + 1,
                                        layout.mac_time(image.st_birthtime))
            (volume / ".DS_Store").write_bytes(layout.store(layout.layout_entries(alias)))

        def single(volume):
            one = Path(self.temp.name) / "one.tiff"
            REAL_RUN(["tiffutil", "-cat", str(layout.ART / layout.ARTWORK[0]), "-out", str(one)], check=True,
                     capture_output=True)
            with (volume / layout.BACKGROUND).open("r+b") as stream:
                stream.truncate(0)
                stream.write(one.read_bytes())

        tampers = {"no layout file": lambda volume: (volume / ".DS_Store").unlink(),
                   "moved icon": moved,
                   "stale background reference": stale,
                   "single-size background": single,
                   "visible background folder": lambda volume: os.chflags(volume / ".background", 0),
                   "no custom icon flag": lambda volume: REAL_RUN(["xattr", "-d", "com.apple.FinderInfo", str(volume)],
                                                                  check=True),
                   "different volume icon": lambda volume: (volume / ".VolumeIcon.icns").write_bytes(b"other")}
        for name, tamper in tampers.items():
            with self.subTest(name):
                self.reset()
                self.tamper = tamper
                with self.assertRaisesRegex(dmg.Refusal, "install window"):
                    self.execute()
                self.assertEqual(self.count(["xcrun", "notarytool", "submit"]), 0)

    def test_failed_layout_unmounts_and_leaves_no_image(self):
        self.fail = ["xattr", "-wx"]
        with self.assertRaisesRegex(dmg.Refusal, "xattr failed"):
            self.execute()
        self.assertGreater(self.count(["hdiutil", "detach"]), 0)
        self.assertGreater(self.position(["hdiutil", "detach"]), self.position(["xattr", "-wx"]))
        self.assertTrue(self.volume.is_dir())
        self.assertFalse(self.output.exists())
        self.assertEqual(self.leftovers(), [])
        self.fail = None
        self.assertEqual(self.execute()["phase"], "complete")

    def test_failed_compression_leaves_no_partial_image(self):
        self.fail = ["hdiutil", "convert"]
        with self.assertRaisesRegex(dmg.Refusal, "hdiutil failed"):
            self.execute()
        self.assertFalse(self.output.exists())
        self.assertEqual(self.leftovers(), [])
        self.fail = None
        self.assertEqual(self.execute()["phase"], "complete")

    def test_layout_checked_on_the_writable_volume_never_reaches_the_output(self):
        with patch.object(layout, "hide"), self.assertRaisesRegex(dmg.Refusal, "background folder is visible"):
            self.execute()
        self.assertEqual(self.count(["hdiutil", "convert"]), 0)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.leftovers(), [])
        self.assertEqual(self.execute()["phase"], "complete")

    def test_failed_attach_leaves_no_staging_behind(self):
        self.fail = ["hdiutil", "attach"]
        with self.assertRaisesRegex(dmg.Refusal, "hdiutil failed"):
            self.execute()
        self.assertEqual(self.leftovers(), [])
        self.assertFalse(self.output.exists())

    def test_stuck_volume_keeps_the_first_error_and_its_files(self):
        self.fail = ["xattr", "-wx"]
        self.stuck = True
        with self.assertRaisesRegex(dmg.Refusal, "xattr failed"):
            self.execute()
        self.assertEqual(self.count(["hdiutil", "detach", "-force"]), 1)
        [work] = self.leftovers()
        self.assertTrue((self.output.parent / work / "volume/Parc.app/Contents/MacOS/Parc").is_file())
        self.assertFalse(self.output.exists())

    def test_unmount_that_reports_busy_after_succeeding_is_not_retried(self):
        self.phantom = True
        self.execute()
        self.assertEqual(self.count(["hdiutil", "detach", "-force"]), 0)
        self.assertEqual(self.position(["hdiutil", "convert"]) - self.position(["hdiutil", "detach"]), 1)

    def test_resumed_image_from_before_the_install_window_skips_only_the_layout(self):
        self.execute()
        receipt_path = self.package.parent / "dmg-notarization/submission.json"
        receipt = json.loads(receipt_path.read_text())
        del receipt["install_window"]
        receipt_path.write_text(json.dumps(receipt))
        (self.volume / ".DS_Store").unlink()
        self.calls = []
        self.assertEqual(self.execute()["phase"], "complete")
        self.assertEqual(self.count(["xattr", "-px"]), 0)

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
        self.assertEqual(self.count(["hdiutil", "create"]), 1)
        self.assertEqual(self.count(["hdiutil", "convert"]), 1)
        self.assertEqual(sum(call[:2] == ["hdiutil", "attach"] and "-readonly" not in call for call in self.calls), 1)

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
        self.tamper = lambda volume: (volume / ".DS_Store").unlink()
        with self.assertRaisesRegex(dmg.Refusal, "install window"):
            self.execute()
        self.calls = []
        with patch.object(dmg.subprocess, "run", side_effect=self.run_tool):
            dmg.verify_dmg(self.output, self.report, self.package.parent / "dmg-notarization", notarized=False,
                           layout_expected=False)
        self.assertEqual(self.count(["xattr", "-px"]), 0)


if __name__ == "__main__":
    unittest.main()
