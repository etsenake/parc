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
            (root / '.gitignore').write_text('/out/\n')
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
        self.old['chromium']['tag'] = '156.0.8078.48'
        self.previous = self.base / 'previous.json'
        self.previous.write_text(json.dumps(self.old))
        _, self.old_sha = engine.load_lock(self.previous)
        self.new_sha = engine.digest(json.dumps(self.new).encode())
        (self.workspace / 'chromium/.gclient').write_text(engine.gclient_text(self.old))
        (self.workspace / '.parc-operation.lock').touch()
        self.repos = ['chromium/src']
        self.state = dict(schema_version=1, workspace=str(self.workspace), lock_sha256=self.old_sha,
                          phase='built', symbol_level=0, repositories=self.repos,
                          source_fingerprint=engine.tree_fingerprint(self.workspace, self.env, self.repos))
        output = self.roots['chromium'] / 'out' / self.old['build']['configuration']
        output.mkdir(parents=True)
        args = engine.engine_arguments(self.old, engine.environment(self.workspace, self.old, 0)['GN_DEFINES'])
        (output / 'args.gn').write_bytes(args)
        self.state.update(engine_mode='direct', build_targets=self.old['build']['targets'], args_sha256=engine.digest(args))
        engine.write_marker(self.workspace, self.state)
        self.calls = []
        self.command_locations = []
        self.prove_branch = False

    def git(self, root, *args):
        return subprocess.check_output(engine.GIT + list(args), cwd=root, stderr=subprocess.DEVNULL)

    def call(self, fail=False, free_bytes=None):
        real = engine.run
        def command(argv, cwd, env, capture=False):
            self.calls.append(argv)
            self.command_locations.append((argv, cwd))
            if 'fetch' in argv:
                return b''
            if argv[0] != engine.GIT[0]:
                if fail:
                    raise OSError('fixture hook failed')
                return b''
            return real(argv, cwd, env, capture)
        def host(workspace, lock, operation):
            required = lock['storage'][operation + '_minimum_free_bytes']
            free = 200_000_000_000 if free_bytes is None else free_bytes
            return dict(minimum_free_bytes=required,
                        blockers=[] if free >= required else ['Insufficient space'])
        with patch.object(engine, 'host_report', side_effect=host), patch.object(engine, 'run', side_effect=command), patch.object(engine, 'synced_repositories', return_value=self.repos):
            return engine.retarget(self.workspace, self.new, self.new_sha, self.previous)

    def test_moves_all_pins_and_preserves_objects_and_user_files(self):
        output = self.roots['chromium'] / 'out/object.o'
        output.parent.mkdir(exist_ok=True)
        output.write_bytes(b'cached')
        user = self.roots['chromium'] / 'notes.txt'
        user.write_text('mine')
        self.state['source_fingerprint'] = engine.tree_fingerprint(self.workspace, self.env, self.repos)
        engine.write_marker(self.workspace, self.state)
        self.assertEqual(self.call()["reserve"], "sync")
        for name, root in self.roots.items():
            self.assertEqual(self.git(root, 'rev-parse', 'HEAD').strip().decode(), self.new[name]['commit'])
        self.assertEqual(output.read_bytes(), b'cached')
        self.assertFalse(user.exists())
        state = engine.read_marker(self.workspace, self.new_sha)
        self.assertEqual(state['phase'], 'synced')
        engine.verify_workspace(self.workspace, self.new, state, self.env)

    def test_hand_edits_are_overwritten_and_the_upgrade_carries_on(self):
        (self.roots['chromium'] / 'pinned').write_text('user edit')
        (self.roots['chromium'] / 'source.cc').write_text('stray change\n')
        self.call()
        self.assertEqual((self.roots['chromium'] / 'pinned').read_text(), 'new\n')
        self.assertEqual((self.roots['chromium'] / 'source.cc').read_text(), 'upstream\n')
        self.assertEqual(engine.read_marker(self.workspace, self.new_sha)['phase'], 'synced')

    def test_an_upgrade_clears_dropped_dependencies_and_forces_the_new_version(self):
        self.call()
        sync = next(argv for argv in self.calls if argv[0].endswith('gclient') and 'sync' in argv)
        self.assertIn('--reset', sync)
        self.assertIn('--delete_unversioned_trees', sync)
        checkouts = [argv for argv in self.calls if 'checkout' in argv and '--detach' in argv]
        self.assertTrue(checkouts and all('--force' in argv for argv in checkouts))
        hooks = next(argv for argv in self.calls if argv[0].endswith('gclient') and 'runhooks' in argv)
        self.assertNotIn('--reset', hooks)

    def reset(self):
        real = engine.run
        def command(argv, cwd, env, capture=False):
            self.calls.append(argv)
            return real(argv, cwd, env, capture) if argv[0] == engine.GIT[0] else b''
        with patch.object(engine, 'run', side_effect=command):
            return engine.reset_source(self.workspace, self.old, self.old_sha)

    def test_a_clean_engine_is_left_exactly_as_it_is_before_a_build(self):
        source = self.roots['chromium'] / 'source.cc'
        before = source.stat().st_mtime_ns
        self.assertFalse(self.reset()['reset'])
        self.assertFalse(any('clean' in argv or 'runhooks' in argv for argv in self.calls))
        self.assertEqual(source.stat().st_mtime_ns, before)
        self.assertEqual(engine.read_marker(self.workspace, self.old_sha)['phase'], 'built')

    def test_hand_edits_are_overwritten_before_an_ordinary_build(self):
        (self.roots['chromium'] / 'source.cc').write_text('hand edit\n')
        (self.roots['chromium'] / 'pinned').write_text('another hand edit\n')
        (self.roots['chromium'] / 'added_by_hand.cc').write_text('stray\n')
        objects = self.roots['chromium'] / 'out/object.o'
        objects.parent.mkdir(exist_ok=True)
        objects.write_bytes(b'cached')
        self.assertTrue(self.reset()['reset'])
        self.assertFalse((self.roots['chromium'] / 'added_by_hand.cc').exists())
        self.assertEqual(objects.read_bytes(), b'cached')
        self.assertTrue(any(argv[0].endswith('gclient') and 'runhooks' in argv for argv in self.calls))
        self.assertEqual((self.roots['chromium'] / 'source.cc').read_text(), 'upstream\n')
        self.assertEqual((self.roots['chromium'] / 'pinned').read_text(), 'old\n')
        state = engine.read_marker(self.workspace, self.old_sha)
        self.assertEqual(state['phase'], 'synced')
        engine.verify_workspace(self.workspace, self.old, state, self.env)

    def test_an_interrupted_upgrade_resumes_to_the_same_version(self):
        output = self.roots['chromium'] / 'out/object.o'
        output.parent.mkdir(exist_ok=True)
        output.write_bytes(b'cached')
        self.state['source_fingerprint'] = engine.tree_fingerprint(self.workspace, self.env, self.repos)
        engine.write_marker(self.workspace, self.state)
        with self.assertRaises(OSError):
            self.call(True)
        self.assertEqual(engine.read_marker(self.workspace, self.old_sha)['phase'], 'retarget-in-progress')
        self.call()
        state = engine.read_marker(self.workspace, self.new_sha)
        self.assertEqual(state['phase'], 'synced')
        self.assertNotIn('retarget_lock_sha256', state)
        self.assertEqual(output.read_bytes(), b'cached')
        for name, root in self.roots.items():
            self.assertEqual(self.git(root, 'rev-parse', 'HEAD').strip().decode(), self.new[name]['commit'])

    def test_an_interrupted_upgrade_cannot_switch_to_another_version(self):
        with self.assertRaises(OSError):
            self.call(True)
        self.new['chromium']['tag'] = '156.0.8078.999'
        self.new_sha = engine.digest(json.dumps(self.new).encode())
        with self.assertRaisesRegex(engine.Refusal, 'good source phase'):
            self.call()

    def test_build_settings_changed_with_the_version_ride_along_in_place(self):
        self.new['build']['gn_defines'] += ' changed=true'
        self.new['storage']['basis'] = 'updated'
        self.new_sha = engine.digest(json.dumps(self.new).encode())
        self.call()
        state = engine.read_marker(self.workspace, self.new_sha)
        self.assertEqual(state['phase'], 'synced')
        self.assertNotIn('args_sha256', state)

    def test_another_target_platform_is_refused(self):
        self.new['target'] = 'mac-x64'
        self.new_sha = engine.digest(json.dumps(self.new).encode())
        with self.assertRaisesRegex(engine.Refusal, 'target platform'):
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
        output = self.roots['chromium'] / 'out' / engine.SHIPPING_CONFIGURATION
        output.mkdir()
        (output / 'shipping.o').write_bytes(b'cached shipping object')
        shipping = dict(schema_version=1, workspace=str(self.workspace), lock_sha256=self.old_sha,
                        configuration=engine.SHIPPING_CONFIGURATION, gn_defines=engine.SHIPPING_DEFINES,
                        symbol_level=0, phase='built', overlay=None)
        engine.write_marker(self.workspace, shipping, engine.SHIPPING_MARKER)
        self.call()
        current = engine.read_shipping_marker(self.workspace, self.new_sha, self.state)
        self.assertEqual(current['phase'], 'reconfigured')
        self.assertEqual((output / 'shipping.o').read_bytes(), b'cached shipping object')
        with self.assertRaises(engine.Refusal):
            engine.verify_shipping_build(self.workspace, self.new_sha, self.state)


    def test_cross_milestone_or_branch_keeps_80gb_and_never_fetches(self):
        for tag in ['157.0.8103.51', '156.0.8079.1', '156.1.8078.1']:
            self.new['chromium']['tag'] = tag
            with self.subTest(tag=tag), self.assertRaisesRegex(engine.Refusal, 'Insufficient space'):
                self.call(free_bytes=47_000_000_000)
            self.assertFalse(any('fetch' in c or 'restore' in c for c in self.calls))
            self.assertEqual(engine.read_marker(self.workspace, self.old_sha)['phase'], 'built')

    def test_unknown_tags_require_80gb(self):
        for tag in [None, '', 'malformed']:
            self.new['chromium']['tag'] = tag
            with self.subTest(tag=tag), self.assertRaisesRegex(engine.Refusal, 'Insufficient space'):
                self.call(free_bytes=47_000_000_000)
            self.assertFalse(any('restore' in c for c in self.calls))


    def test_below_40gb_refused_before_any_git_command(self):
        self.prove_branch = True
        with self.assertRaisesRegex(engine.Refusal, 'Insufficient space'):
            self.call(free_bytes=39_000_000_000)
        self.assertEqual(self.calls, [])


    def test_changed_source_prevents_retarget_fetches(self):
        self.prove_branch = True
        (self.roots['chromium'] / 'source.cc').write_text('user changes')
        with self.assertRaises(engine.Refusal):
            self.call(free_bytes=47_000_000_000)
        self.assertFalse(any('fetch' in c for c in self.calls))
