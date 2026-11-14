import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'scripts'))
import release


class DirectReleaseTests(unittest.TestCase):
    def test_engine_jobs_scale_with_cores_and_memory(self):
        gib = 2**30
        self.assertEqual(release.engine_jobs(8, 24 * gib), 7)
        self.assertEqual(release.engine_jobs(18, 36 * gib), 17)
        self.assertEqual(release.engine_jobs(10, 16 * gib), 8)
        self.assertEqual(release.engine_jobs(8, 8 * gib), 4)
        self.assertEqual(release.engine_jobs(2, 1 * gib), 1)
        self.assertEqual(release.engine_jobs(8, 0), 7)

    def test_selected_lock_routes_reuse_and_build_to_matching_overlay(self):
        for reuse, stale in ((False, False), (True, False), (True, True)):
            with self.subTest(reuse=reuse, stale=stale), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                source = root / 'source'
                (source / 'scripts').mkdir(parents=True)
                (source / 'scripts/engine-source.py').write_bytes((REPO / 'scripts/engine-source.py').read_bytes())
                (source / 'Engine/ParcHost').mkdir(parents=True)
                selected = REPO / 'Engine/source-lock.json'
                lock = source / 'Engine/source-lock.json'
                lock.write_bytes(selected.read_bytes())
                overlay = source / 'Engine/ParcHost/overlay.json'
                overlay.write_text('{"version": 7}')
                workspace = root / 'workspace'
                workspace.mkdir()
                (workspace / '.parc-engine-source.json').write_text(json.dumps({
                    'lock_sha256': release.sha(lock), 'phase': 'built',
                    'overlay': {'identity': 'old' if stale else release.sha(overlay)}}))
                runner = release.Release(root)
                runner.state = {'source': str(source), 'run': str(root / 'run')}
                runner.checkpoint = lambda **values: runner.state.update(values)
                runner.git = lambda *args, **kwargs: ''
                runner.superseded_shipping_build = lambda: None
                commands = []
                def command(args, **kwargs):
                    commands.append((list(map(str, args)), kwargs['name']))
                    if kwargs['name'] == 'engine-reuse' and not reuse:
                        raise release.Failure('incomplete seal')
                    if kwargs['name'] in ('engine-reuse', 'engine-seal'):
                        manifest = Path(args[args.index('--manifest') + 1])
                        manifest.parent.mkdir(parents=True, exist_ok=True)
                        manifest.write_text('{}')
                runner.command = command
                with patch.dict(release.os.environ, PARC_ENGINE_WORKSPACE=str(workspace)):
                    runner.engine()
                names = [name for _, name in commands]
                self.assertIn('engine-reuse', names)
                self.assertEqual('engine-build' in names, not reuse)
                checked = next(args for args, name in commands if name == 'overlay-check')
                self.assertEqual(checked[-2:], ['--manifest', str(overlay)])
                self.assertEqual('overlay-apply' in names, stale)
                if stale:
                    applied = next(args for args, name in commands if name == 'overlay-apply')
                    self.assertEqual(applied[-2:], ['--manifest', str(overlay)])


if __name__ == '__main__':
    unittest.main()
