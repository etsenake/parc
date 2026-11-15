from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import app_copy

DYLD = "com.apple.security.cs.allow-dyld-environment-variables"
LIBRARY = "com.apple.security.cs.disable-library-validation"
JIT = "com.apple.security.cs.allow-jit"
DETAILS = ("Executable=/x/Parc.app/Contents/MacOS/Parc\n"
           "Authority=Developer ID Application: Example (TEAM123456)\n"
           "Authority=Developer ID Certification Authority\n"
           "Authority=Apple Root CA\n")


def entitlements(values):
    return plistlib.dumps(values, fmt=plistlib.FMT_XML)


class FakeCodesign:
    def __init__(self, granted=b"", details=DETAILS):
        self.granted = granted
        self.details = details
        self.commands = []

    def __call__(self, argv, **kwargs):
        self.commands.append(list(argv))
        if argv[0] == "cp":
            Path(argv[-1]).mkdir()
            return subprocess.CompletedProcess(argv, 0)
        if argv[:2] == ["codesign", "-d"]:
            return subprocess.CompletedProcess(argv, 0, stdout=self.granted, stderr=b"")
        if argv[:2] == ["codesign", "-dvv"]:
            return subprocess.CompletedProcess(argv, 0, stdout="", stderr=self.details)
        if argv[:2] == ["codesign", "--force"]:
            return subprocess.CompletedProcess(argv, 0)
        raise AssertionError(f"unexpected command {argv}")


class RefusalTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="parc-app-copy-test-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.app = self.root / "build" / "Parc.app"
        self.app.mkdir(parents=True)

    def test_installed_means_under_applications(self):
        self.assertTrue(app_copy.installed("/Applications/Parc.app"))
        self.assertFalse(app_copy.installed("/Applications"))
        self.assertFalse(app_copy.installed("/Users/me/Applications/Parc.app"))

    def test_installed_app_is_refused_before_it_is_read(self):
        with patch.object(app_copy.os.path, "realpath") as realpath:
            with self.assertRaisesRegex(ValueError, "installed in /Applications"):
                app_copy.source_of("/Applications/Parc.app")
        realpath.assert_not_called()

    def test_link_into_applications_is_refused(self):
        with patch.object(app_copy.os.path, "realpath", return_value="/Applications/Parc.app"):
            with self.assertRaisesRegex(ValueError, "installed in /Applications"):
                app_copy.source_of(self.app)

    def test_missing_app_is_an_error(self):
        with self.assertRaises(FileNotFoundError):
            app_copy.source_of(self.root / "missing.app")

    def test_source_is_the_resolved_app(self):
        link = self.root / "link.app"
        link.symlink_to(self.app)
        self.assertEqual(app_copy.source_of(link), self.app)

    def test_copy_folder_may_not_hold_or_sit_inside_the_app(self):
        for directory in (self.root / "build", self.app, self.app / "Contents" / "copy"):
            with self.subTest(directory=directory):
                with self.assertRaisesRegex(ValueError, "overlap"):
                    app_copy.refuse_overlap(self.app, directory)
        app_copy.refuse_overlap(self.app, self.root / "copies" / "launch")


class EntitlementTests(unittest.TestCase):
    def test_no_entitlements_read_as_empty(self):
        self.assertEqual(app_copy.granted_entitlements(b""), {})
        self.assertEqual(app_copy.granted_entitlements(b"\n"), {})

    def test_missing_lists_wanted_keys_not_granted_in_order(self):
        granted = {JIT: True, LIBRARY: True}
        self.assertEqual(app_copy.missing_entitlements(granted, app_copy.INJECTION_ENTITLEMENTS), [DYLD])
        self.assertEqual(app_copy.missing_entitlements({}, app_copy.INJECTION_ENTITLEMENTS), [DYLD, LIBRARY])

    def test_a_granted_key_counts_whatever_its_value(self):
        self.assertEqual(app_copy.missing_entitlements({DYLD: False}, [DYLD]), [])

    def test_merge_keeps_the_original_entitlements_and_adds_the_missing_ones(self):
        granted = {JIT: True, "com.apple.application-identifier": "TEAM123456.org.parc", "keychain-access-groups": ["a"]}
        merged = plistlib.loads(app_copy.merged_entitlements(granted, [DYLD, LIBRARY]))
        self.assertEqual(merged, {**granted, DYLD: True, LIBRARY: True})

    def test_plan_is_empty_when_nothing_changes(self):
        granted = entitlements({JIT: True, DYLD: True, LIBRARY: True})
        self.assertIsNone(app_copy.signing_plan(granted, app_copy.INJECTION_ENTITLEMENTS))
        self.assertIsNone(app_copy.signing_plan(entitlements({JIT: True}), ()))

    def test_plan_adds_injection_entitlements(self):
        plan = app_copy.signing_plan(entitlements({JIT: True}), app_copy.INJECTION_ENTITLEMENTS)
        self.assertEqual(plistlib.loads(plan), {JIT: True, DYLD: True, LIBRARY: True})

    def test_plan_for_an_app_without_entitlements(self):
        plan = app_copy.signing_plan(b"", app_copy.INJECTION_ENTITLEMENTS)
        self.assertEqual(plistlib.loads(plan), {DYLD: True, LIBRARY: True})


class CommandTests(unittest.TestCase):
    def test_commands_match_ardia(self):
        source, copy, plist = Path("/b/Parc.app"), Path("/c/Parc.app"), Path("/c/entitlements.plist")
        self.assertEqual(app_copy.clone_command(source, copy), ["cp", "-cR", "/b/Parc.app", "/c/Parc.app"])
        self.assertEqual(app_copy.entitlements_command(source),
                         ["codesign", "-d", "--entitlements", "-", "--xml", "/b/Parc.app"])
        self.assertEqual(app_copy.sign_command(plist, copy),
                         ["codesign", "--force", "--sign", "-", "--timestamp=none", "--options", "runtime",
                          "--entitlements", "/c/entitlements.plist", "/c/Parc.app"])


class PrepareTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="parc-app-copy-test-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.app = self.root / "build" / "Parc.app"
        self.app.mkdir(parents=True)
        self.out = self.root / "runs" / "app"

    def prepare(self, fake, **options):
        with patch.object(app_copy.subprocess, "run", side_effect=fake):
            return app_copy.prepare_app(self.app, self.out, **options)

    def test_unchanged_copy_is_not_signed(self):
        fake = FakeCodesign(granted=entitlements({JIT: True, DYLD: True, LIBRARY: True}))
        copy = self.prepare(fake, entitlements=app_copy.INJECTION_ENTITLEMENTS)
        self.assertEqual(copy, self.out / "Parc.app")
        self.assertEqual(fake.commands, [app_copy.clone_command(self.app, copy), app_copy.entitlements_command(self.app)])
        self.assertFalse((self.out / "entitlements.plist").exists())

    def test_plain_copy_needs_no_signature(self):
        fake = FakeCodesign(granted=entitlements({JIT: True}))
        self.prepare(fake)
        self.assertEqual([command[:2] for command in fake.commands], [["cp", "-cR"], ["codesign", "-d"]])

    def test_missing_entitlements_resign_ad_hoc_without_the_keychain(self):
        fake = FakeCodesign(granted=entitlements({JIT: True}))
        copy = self.prepare(fake, entitlements=app_copy.INJECTION_ENTITLEMENTS)
        plist = self.out / "entitlements.plist"
        self.assertEqual(plistlib.loads(plist.read_bytes()), {JIT: True, DYLD: True, LIBRARY: True})
        self.assertEqual(fake.commands[2], app_copy.sign_command(plist, copy))
        self.assertEqual(len(fake.commands), 3)

    def test_ad_hoc_build_is_resigned_ad_hoc(self):
        fake = FakeCodesign(granted=b"", details="Signature=adhoc\n")
        copy = self.prepare(fake, entitlements=app_copy.INJECTION_ENTITLEMENTS)
        self.assertEqual(fake.commands[-1][:4], ["codesign", "--force", "--sign", "-"])
        self.assertEqual(fake.commands[-1][-1], str(copy))

    def test_previous_copy_is_replaced(self):
        self.out.mkdir(parents=True)
        (self.out / "entitlements.plist").write_text("old")
        (self.out / "Parc.app").mkdir()
        self.prepare(FakeCodesign(granted=entitlements({})))
        self.assertEqual(sorted(path.name for path in self.out.iterdir()), ["Parc.app"])

    def test_folder_with_other_files_is_kept(self):
        self.out.mkdir(parents=True)
        (self.out / "notes.txt").write_text("mine")
        fake = FakeCodesign()
        with patch.object(app_copy.subprocess, "run", side_effect=fake):
            with self.assertRaisesRegex(ValueError, "notes.txt"):
                app_copy.prepare_app(self.app, self.out)
        self.assertEqual(fake.commands, [])
        self.assertEqual((self.out / "notes.txt").read_text(), "mine")

    def test_installed_app_is_refused_whatever_the_case(self):
        for path in ("/applications/Parc.app", "/System/Volumes/Data/Applications/Parc.app"):
            with self.subTest(path=path):
                self.assertTrue(app_copy.installed(path))

    def test_installed_app_runs_nothing(self):
        fake = FakeCodesign()
        with patch.object(app_copy.subprocess, "run", side_effect=fake):
            with self.assertRaises(ValueError):
                app_copy.prepare_app("/Applications/Parc.app", self.out)
        self.assertEqual(fake.commands, [])
        self.assertFalse(self.out.exists())

    def test_overlapping_folder_runs_nothing_and_keeps_the_app(self):
        fake = FakeCodesign()
        with patch.object(app_copy.subprocess, "run", side_effect=fake):
            with self.assertRaises(ValueError):
                app_copy.prepare_app(self.app, self.root / "build")
        self.assertEqual(fake.commands, [])
        self.assertTrue(self.app.is_dir())


if __name__ == "__main__":
    unittest.main()
