import fcntl
import importlib.util
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
        self.spot = self.root / "ParcBuild/engine-cx"
        self.spot.mkdir(parents=True)
        (self.spot / drive.RECEIPT).write_text("{}")
        self.mount = self.root / "Volumes/ParcEngine"
        self.mount.mkdir(parents=True)

    def disk(self, **overrides):
        info = {"FilesystemType": "apfs", "Internal": False, "DeviceIdentifier": "disk9s1",
                "VolumeUUID": "ABCD-1234", "MountPoint": str(self.mount), **overrides}
        return subprocess.CompletedProcess([], 0, plistlib.dumps(info).decode(), "")

    def prepare(self, **disk):
        with patch.object(drive, "run", return_value=self.disk(**disk)):
            return drive.prepare("ParcEngine", self.root, self.spot, use_fstab=False)

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
        self.assertTrue((self.spot / drive.RECEIPT).is_file())

    def test_an_engine_in_the_middle_of_a_build_is_left_alone(self):
        with (self.spot / ".parc-operation.lock").open("a") as guard:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(drive.DriveError, "let it finish"):
                self.prepare()
        self.assertFalse(any(self.root.glob("ParcBuild/engine-cx.local-*")))

    def test_a_drive_already_at_the_engine_folder_needs_nothing(self):
        self.assertEqual(self.prepare(MountPoint=str(self.spot))["state"], "already in place")

    def test_the_mount_setting_names_the_drive_and_the_engine_folder(self):
        self.assertEqual(drive.fstab_line("ABCD-1234", self.spot), f"UUID=ABCD-1234 {self.spot} apfs rw")

    def test_a_drive_with_only_system_files_counts_as_empty(self):
        (self.mount / ".fseventsd").mkdir()
        (self.mount / ".Spotlight-V100").mkdir()
        self.assertTrue(drive.empty(self.mount))


if __name__ == "__main__":
    unittest.main()
