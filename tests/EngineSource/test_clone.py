"""Local clone adoption uses miniature Git workspaces, never a real engine."""
import fcntl
import importlib.util
from pathlib import Path
import shutil
import unittest

spec = importlib.util.spec_from_file_location('workspace_fixtures', Path(__file__).resolve().parents[1] / 'Packaging/test_engine_workspace.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
ws = fixture.ws


class CloneTests(unittest.TestCase):
    git = fixture.WorkspaceTests.git
    update_receipt = fixture.WorkspaceTests.update_receipt

    def setUp(self):
        fixture.WorkspaceTests.setUp(self)
        self.clone = self.root / 'cloned'

    def copy(self):
        shutil.copytree(self.source, self.clone, symlinks=True)

    def adopt(self):
        return ws.adopt_local_clone(self.source, self.clone, self.repo)

    def test_clone_fingerprint_provenance_and_objects(self):
        before = (self.source / self.engine.MARKER).read_bytes()
        self.copy()
        result = self.adopt()
        state, _ = ws._read(self.clone / self.engine.MARKER)
        self.assertEqual(state['workspace'], str(self.clone))
        self.assertEqual(state['phase'], 'synced')
        self.assertTrue(state['relocation']['requires_regeneration'])
        self.assertEqual(state['relocation']['kind'], 'local-clone')
        self.assertEqual(result['source_fingerprint'], self.state['source_fingerprint'])
        self.assertEqual((self.source / self.engine.MARKER).read_bytes(), before)
        original = self.output / 'cached.o'
        cloned = self.clone / original.relative_to(self.source)
        self.assertEqual(cloned.read_bytes(), original.read_bytes())
        self.assertEqual(cloned.stat().st_mtime_ns, original.stat().st_mtime_ns)

    def test_changed_clone_is_refused_without_adoption(self):
        self.copy()
        (self.clone / 'chromium/src/README').write_text('my work')
        with self.assertRaisesRegex(ws.Refusal, 'Source/dependency changes'):
            self.adopt()
        self.assertFalse((self.clone / ws.SNAPSHOT_FILE).exists())
        self.assertEqual((self.clone / 'chromium/src/README').read_text(), 'my work')

    def test_wrong_depth_refused(self):
        self.clone = self.root / 'nested/cloned'
        self.copy()
        with self.assertRaisesRegex(ws.Refusal, 'same depth'):
            self.adopt()

    def test_busy_source_or_clone_refused(self):
        self.copy()
        for root in [self.source, self.clone]:
            with (root / '.parc-operation.lock').open('r') as guard:
                fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaisesRegex(ws.Refusal, 'Another operation'):
                    self.adopt()
        self.assertFalse((self.clone / ws.SNAPSHOT_FILE).exists())

    def test_mismatched_or_incomplete_receipt_refused(self):
        self.state['phase'] = 'retarget-in-progress'
        self.update_receipt()
        self.copy()
        with self.assertRaisesRegex(ws.Refusal, 'complete source receipt'):
            self.adopt()

    def test_generated_links_normalized_only_in_clone(self):
        target = self.source / 'tmp/siso.log'
        target.write_text('log')
        link = self.output / 'siso.INFO'
        link.symlink_to(target)
        sdk = self.output / 'sdk/xcode_links'
        sdk.mkdir(parents=True)
        (sdk / 'MacOSX.platform').symlink_to('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform')
        self.copy()
        self.adopt()
        copied = self.clone / link.relative_to(self.source)
        self.assertEqual(copied.resolve(), self.clone / 'tmp/siso.log')
        self.assertTrue((sdk / 'MacOSX.platform').is_symlink())
        self.assertFalse((self.clone / sdk.relative_to(self.source) / 'MacOSX.platform').is_symlink())

    def test_previous_lock_allows_clone_before_retarget(self):
        previous = self.root / 'previous.json'
        previous.write_bytes((self.repo / 'Engine/source-lock.json').read_bytes())
        self.copy()
        (self.repo / 'Engine/source-lock.json').write_bytes(ws.canonical_json(self.lock) + b'\n')
        result = ws.adopt_local_clone(self.source, self.clone, self.repo, previous)
        self.assertEqual(result['phase'], 'synced')

    def test_previously_adopted_workspace_can_be_cloned_again(self):
        self.copy()
        self.adopt()
        self.source = self.clone
        self.clone = self.root / 'another'
        self.copy()
        self.assertEqual(self.adopt()['phase'], 'synced')

    def test_failed_graph_proof_can_be_repaired_and_retried(self):
        self.copy()
        graph = self.clone / 'chromium/src/out/Release_GN_arm64/toolchain.ninja'
        original = graph.read_bytes()
        graph.write_text('changed')
        with self.assertRaisesRegex(ws.Refusal, 'Toolchain/graph fingerprint'):
            self.adopt()
        self.assertFalse((self.clone / ws.SNAPSHOT_FILE).exists())
        graph.write_bytes(original)
        self.assertEqual(self.adopt()['phase'], 'synced')

    def test_inherited_snapshot_is_preserved_and_verified(self):
        snapshot = self.source / ws.SNAPSHOT_FILE
        snapshot.write_bytes(ws.canonical_json(ws.snapshot_metadata(self.source, self.repo)))
        self.copy()
        before = snapshot.read_bytes()
        self.adopt()
        self.assertEqual((self.clone / ws.SNAPSHOT_FILE).read_bytes(), before)
