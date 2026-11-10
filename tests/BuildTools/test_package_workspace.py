"""Exercise the package wrapper's actual receipt lookup without packaging."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/package-app.sh"
LOOKUP = SCRIPT.read_text().split("<<'PYWORKSPACE'\n", 1)[1].split("\nPYWORKSPACE", 1)[0]


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
