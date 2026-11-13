import fcntl
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("engine_drive", ROOT / "scripts/engine_drive.py")
drive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(drive)


class DriveTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.repo = self.root / "checkout"
        (self.repo / "work").mkdir(parents=True)
        self.spot = self.root / "ParcBuild/engine-cx"
        self.spot.mkdir(parents=True)
        (self.spot / drive.RECEIPT).write_text(json.dumps({"workspace": str(self.spot)}))
        (self.repo / "work/engine").symlink_to(self.spot)
        self.mount = self.root / "Volumes/Parc"
        self.mount.mkdir(parents=True)
        self.lock = self.repo / "Engine/source-lock.json"
        self.registered = []

    def disk(self, **overrides):
        info = {"FilesystemType": "apfs", "Internal": False, "DeviceIdentifier": "disk9s1",
                "MountPoint": str(self.mount), **overrides}
        return subprocess.CompletedProcess([], 0, plistlib.dumps(info).decode(), "")

    def fake_copy(self, source, mount):
        (mount / drive.RECEIPT).write_text((source / drive.RECEIPT).read_text())

    def fake_register(self, source, mount, repo, lock):
        self.registered.append((source, mount))
        (mount / drive.RECEIPT).write_text(json.dumps({"workspace": str(mount)}))

    def prepare(self, **disk):
        with patch.object(drive, "run", return_value=self.disk(**disk)), \
                patch.object(drive, "copy_engine", side_effect=self.fake_copy), \
                patch.object(drive, "register", side_effect=self.fake_register):
            return drive.prepare("Parc", self.repo, None, self.lock)

    def test_a_drive_that_is_not_apfs_is_refused(self):
        with self.assertRaisesRegex(drive.DriveError, "erase it as APFS"):
            self.prepare(FilesystemType="exfat")

    def test_an_internal_disk_is_refused(self):
        with self.assertRaisesRegex(drive.DriveError, "internal disk"):
            self.prepare(Internal=True)

    def test_a_drive_holding_other_files_is_never_used(self):
        (self.mount / "photos").mkdir()
        with self.assertRaisesRegex(drive.DriveError, "holds other files"):
            self.prepare()
        self.assertEqual(Path((self.repo / "work/engine").resolve()), self.spot)

    def test_an_engine_in_the_middle_of_a_build_is_left_alone(self):
        with (self.spot / ".parc-operation.lock").open("a") as guard:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(drive.DriveError, "let it finish"):
                self.prepare()
        self.assertFalse((self.mount / drive.RECEIPT).exists())

    def test_an_empty_drive_gets_the_engine_registered_at_the_volume(self):
        result = self.prepare()
        self.assertEqual(result["state"], "copied")
        self.assertEqual(self.registered, [(self.spot, self.mount)])
        self.assertEqual(Path((self.repo / "work/engine").resolve()), self.mount)
        self.assertTrue((self.mount / ".metadata_never_index").exists())
        self.assertTrue((self.spot / drive.RECEIPT).is_file())

    def test_a_copied_engine_still_registered_elsewhere_is_registered_at_the_volume(self):
        self.fake_copy(self.spot, self.mount)
        self.assertEqual(self.prepare()["state"], "registered")
        self.assertEqual(self.registered, [(self.spot, self.mount)])

    def test_a_drive_already_registered_at_its_volume_needs_only_the_link(self):
        (self.mount / drive.RECEIPT).write_text(json.dumps({"workspace": str(self.mount)}))
        self.assertEqual(self.prepare()["state"], "already in place")
        self.assertEqual(self.registered, [])
        self.assertEqual(Path((self.repo / "work/engine").resolve()), self.mount)

    def test_a_real_engine_folder_in_the_checkout_is_not_replaced(self):
        (self.repo / "work/engine").unlink()
        (self.repo / "work/engine").mkdir()
        (self.mount / drive.RECEIPT).write_text(json.dumps({"workspace": str(self.mount)}))
        with self.assertRaisesRegex(drive.DriveError, "real folder"):
            self.prepare()

    def test_registering_needs_the_engine_the_drive_was_copied_from(self):
        with self.assertRaisesRegex(drive.DriveError, "no longer holds"):
            drive.register(self.root / "missing", self.mount, self.repo, self.lock)

    def test_a_drive_with_only_system_files_counts_as_empty(self):
        (self.mount / ".fseventsd").mkdir()
        (self.mount / ".Spotlight-V100").mkdir()
        self.assertTrue(drive.empty(self.mount))

    def test_status_reports_an_engine_registered_on_an_external_drive(self):
        (self.mount / drive.RECEIPT).write_text(json.dumps({"workspace": str(self.mount)}))
        info = subprocess.CompletedProcess([], 0, plistlib.dumps({"Internal": False, "VolumeName": "Parc"}).decode(), "")
        with patch.object(drive, "run", return_value=info):
            report = drive.status(self.repo, self.mount)
        self.assertEqual(report, {"engine": str(self.mount), "on_drive": True, "drive": "Parc",
                                  "engine_present": True, "registered": True, "idle": True})


if __name__ == "__main__":
    unittest.main()
