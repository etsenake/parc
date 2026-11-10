"""Retarget exercises real temporary Git trees and inert upstream commands."""
import copy
import json
import subprocess
import unittest
import fcntl
from unittest.mock import patch
import test_engine_source as fixture
engine = fixture.engine


class RetargetTests(unittest.TestCase):
    def setUp(self):
        fixture.EngineSourceTests.setUp(self)
        self.old = copy.deepcopy(self.lock)
        self.new = copy.deepcopy(self.lock)
        self.workspace.mkdir()
        self.roots = engine.locations(self.workspace)
        for name, root in self.roots.items():
            root.mkdir(parents=True, exist_ok=True)
            self.git(root, 'init')
            self.git(root, 'config', 'user.email', 'fixture@example.org')
            self.git(root, 'config', 'user.name', 'Fixture')
            self.git(root, 'remote', 'add', 'origin', self.lock[name]['url'])
            (root / '.gitignore').write_text('/cef/\n/out/\n')
            (root / 'pinned').write_text('old\n')
            (root / 'source.cc').write_text('upstream\n')
            self.git(root, 'add', '.')
            self.git(root, 'commit', '-qm', 'old')
            self.old[name]['commit'] = self.git(root, 'rev-parse', 'HEAD').strip().decode()
            (root / 'pinned').write_text('new\n')
            self.git(root, 'commit', '-qam', 'new')
            self.new[name]['commit'] = self.git(root, 'rev-parse', 'HEAD').strip().decode()
            self.git(root, 'checkout', '--detach', self.old[name]['commit'])
            for lock, data in [(self.old, b'old\n'), (self.new, b'new\n')]:
                lock[name]['files'] = {'pinned': engine.digest(data)}
        self.previous = self.base / 'previous.json'
        self.previous.write_text(json.dumps(self.old))
        _, self.old_sha = engine.load_lock(self.previous)
        self.new_sha = engine.digest(json.dumps(self.new).encode())
        (self.workspace / 'chromium/.gclient').write_text(engine.gclient_text(self.old))
        (self.workspace / '.parc-operation.lock').touch()
        self.repos = ['chromium/src', 'chromium/src/cef']
        self.state = dict(schema_version=1, workspace=str(self.workspace), lock_sha256=self.old_sha,
                          phase='built', symbol_level=0, repositories=self.repos,
                          source_fingerprint=engine.tree_fingerprint(self.workspace, self.env, self.repos))
        engine.write_marker(self.workspace, self.state)
        self.calls = []

    def git(self, root, *args):
        return subprocess.check_output(engine.GIT + list(args), cwd=root, stderr=subprocess.DEVNULL)

    def call(self, fail=False):
        real = engine.run
        def command(argv, cwd, env, capture=False):
            self.calls.append(argv)
            if 'fetch' in argv:
                return b''  # Both revisions already exist in the fixture.
            if argv[0] != engine.GIT[0]:
                if fail:
                    raise OSError('fixture hook failed')
                return b''
            return real(argv, cwd, env, capture)
        with patch.object(engine, 'host_report', return_value=self.good_host), patch.object(engine, 'run', side_effect=command), patch.object(engine, 'synced_repositories', return_value=self.repos):
            return engine.retarget(self.workspace, self.new, self.new_sha, self.previous)

    def test_moves_all_pins_and_preserves_objects_and_user_files(self):
        output = self.roots['chromium'] / 'out/object.o'
        output.parent.mkdir()
        output.write_bytes(b'cached')
        user = self.roots['chromium'] / 'notes.txt'
        user.write_text('mine')
        self.state['source_fingerprint'] = engine.tree_fingerprint(self.workspace, self.env, self.repos)
        engine.write_marker(self.workspace, self.state)
        self.call()
        for name, root in self.roots.items():
            self.assertEqual(self.git(root, 'rev-parse', 'HEAD').strip().decode(), self.new[name]['commit'])
        self.assertEqual(output.read_bytes(), b'cached')
        self.assertEqual(user.read_text(), 'mine')
        state = engine.read_marker(self.workspace, self.new_sha)
        self.assertEqual(state['phase'], 'synced')
        engine.verify_workspace(self.workspace, self.new, state, self.env)

    def test_changed_source_refused_before_mutation(self):
        (self.roots['chromium'] / 'pinned').write_text('user edit')
        with self.assertRaises(engine.Refusal):
            self.call()
        self.assertFalse(any('restore' in c for c in self.calls))
        self.assertEqual((self.roots['chromium'] / 'pinned').read_text(), 'user edit')

    def test_failure_leaves_incomplete_receipt(self):
        with self.assertRaises(OSError):
            self.call(True)
        self.assertEqual(engine.read_marker(self.workspace, self.old_sha)['phase'], 'retarget-in-progress')
        with self.assertRaises(engine.Refusal):
            self.call()

    def test_build_change_refused(self):
        self.new['build']['gn_defines'] += ' changed=true'
        with self.assertRaisesRegex(engine.Refusal, 'unchanged build'):
            self.call()

    def test_overlay_originals_restored_and_owned_additions_retired(self):
        target = self.roots['chromium'] / 'source.cc'
        target.write_text('overlay\n')
        addition = self.roots['chromium'] / 'parc.cc'
        addition.write_text('owned\n')
        record = dict(identity='a'*64, targets={
            'source.cc': dict(original='upstream\n', mode=0o644, output_sha256=engine.digest(target.read_bytes())),
            'parc.cc': dict(original=None, mode=0o644, output_sha256=engine.digest(addition.read_bytes()))})
        raw = engine.overlay_record_bytes(record)
        folder = self.workspace / '.parc-overlays'
        folder.mkdir()
        (folder / ('a'*64 + '.json')).write_bytes(raw)
        self.state['overlay'] = dict(identity='a'*64, record_sha256=engine.digest(raw))
        self.state['source_fingerprint'] = engine.tree_fingerprint(self.workspace, self.env, self.repos)
        engine.write_marker(self.workspace, self.state)
        self.call()
        self.assertFalse(addition.exists())
        self.assertEqual(target.read_text(), 'upstream\n')
        self.assertNotIn('overlay', engine.read_marker(self.workspace, self.new_sha))

    def test_busy_workspace_refused(self):
        with (self.workspace / '.parc-operation.lock').open('r') as guard:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(engine.Refusal, 'Another operation'):
                self.call()
        self.assertEqual(self.calls, [])

    def test_shipping_is_invalidated_without_deleting_objects(self):
        shipping = dict(schema_version=1, workspace=str(self.workspace), lock_sha256=self.old_sha,
                        configuration=engine.SHIPPING_CONFIGURATION, gn_defines=engine.SHIPPING_DEFINES,
                        symbol_level=0, phase='built', overlay=None)
        engine.write_marker(self.workspace, shipping, engine.SHIPPING_MARKER)
        self.call()
        current = engine.read_shipping_marker(self.workspace, self.new_sha, self.state)
        self.assertEqual(current['phase'], 'reconfigured')
