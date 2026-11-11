import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/package-app.sh"
LOOKUP = SCRIPT.read_text().split("<<'PYWORKSPACE'\n", 1)[1].split("\nPYWORKSPACE", 1)[0]

SELECTION = "overlay_manifest=" + SCRIPT.read_text().split("\noverlay_manifest=", 1)[1].split("\nstamp=", 1)[0]


class PackageWorkspaceTests(unittest.TestCase):
    def test_receipt_selects_direct_workspace_without_cef(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / "chromium/src/.git").mkdir(parents=True)
            receipt = root / ".parc-engine-source.json"
            receipt.write_text(json.dumps({"schema_version": 1, "workspace": str(root)}))
            self.assertEqual(subprocess.run([sys.executable, "-c", LOOKUP, str(root)]).returncode, 0)
            receipt.write_text(json.dumps({"schema_version": 1, "workspace": "/stale"}))
            self.assertEqual(subprocess.run([sys.executable, "-c", LOOKUP, str(root)]).returncode, 1)
            receipt.write_text("broken json")
            self.assertEqual(subprocess.run([sys.executable, "-c", LOOKUP, str(root)]).returncode, 1)


class PackageOverlayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "scripts").symlink_to(SCRIPT.parent)
        (self.root / "Engine/ParcHost").mkdir(parents=True)
        self.lock = self.root / "Engine/source-lock.json"
        (self.root / "Engine/ParcHost/overlay.json").write_text('{"version": 20}')

    def select(self):
        return subprocess.check_output(["bash", "-eu", "-c", SELECTION + '\nprintf "%s:%s" "$overlay_manifest" "$overlay"'], cwd=self.root, text=True)

    def test_package_stamp_uses_canonical_overlay(self):
        self.lock.write_text('{"schema_version": 2}')
        self.assertEqual(self.select(), "Engine/ParcHost/overlay.json:20")
