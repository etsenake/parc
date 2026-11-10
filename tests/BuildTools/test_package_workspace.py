"""Exercise the package wrapper's actual receipt lookup without packaging."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/package-app.sh"
LOOKUP = SCRIPT.read_text().split("<<'PYWORKSPACE'\n", 1)[1].split("\nPYWORKSPACE", 1)[0]

SELECTION = "overlay_manifest=" + SCRIPT.read_text().split("\noverlay_manifest=", 1)[1].split("\nstamp=", 1)[0]
CANDIDATE_LOOP = "    for candidate in $candidates; do" + SCRIPT.read_text().split("    for candidate in $candidates; do", 1)[1].split('    if [ -z "$release_tag" ]', 1)[0]


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
        (self.root / "Engine/ParcHost/overlay.json").write_text('{"version": 10}')
        (self.root / "Engine/ParcHost/overlay-direct.json").write_text('{"version": 20}')

    def select(self):
        return subprocess.check_output(["bash", "-eu", "-c", SELECTION + '\nprintf "%s:%s" "$overlay_manifest" "$overlay"'], cwd=self.root, text=True)

    def test_package_stamp_follows_canonical_lock(self):
        self.lock.write_text('{"schema_version": 1, "cef": {}}')
        self.assertEqual(self.select(), "Engine/ParcHost/overlay.json:10")
        self.lock.write_text('{"schema_version": 2}')
        self.assertEqual(self.select(), "Engine/ParcHost/overlay-direct.json:20")
        (self.root / "Engine/ParcHost/overlay.json").unlink()
        self.assertEqual(self.select(), "Engine/ParcHost/overlay-direct.json:20")

    def test_release_selection_skips_missing_tags_and_wrong_engine_mode(self):
        def git(*args):
            subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", *args], cwd=self.root, check=True, capture_output=True)
        git("init", "-q")
        self.lock.write_text('{"schema_version": 1, "cef": {}}')
        # Both manifests have the same number; the lock still distinguishes engines.
        (self.root / "Engine/ParcHost/overlay.json").write_text('{"version": 20}')
        git("add", "Engine")
        git("commit", "-qm", "legacy fixture")
        git("tag", "vlegacy")
        self.lock.write_text('{"schema_version": 2}')
        git("add", "Engine")
        git("commit", "-qm", "direct fixture")
        git("tag", "vdirect")
        command = SELECTION + '\ncandidates="missing vlegacy vdirect"; local_test=""; release_tag=""\n' + CANDIDATE_LOOP + '\nprintf "%s" "$release_tag"'
        selected = subprocess.check_output(["bash", "-euo", "pipefail", "-c", command], cwd=self.root, text=True)
        self.assertEqual(selected, "vdirect")
