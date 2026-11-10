"""Direct transition preserves real fixture Git trees and cached objects."""
import copy
import json
import unittest
from unittest.mock import patch
import test_retarget as fixture
engine = fixture.engine


class DirectRetargetTests(unittest.TestCase):
    git = fixture.RetargetTests.git

    def setUp(self):
        fixture.RetargetTests.setUp(self)
        self.new, _ = engine.load_lock(engine.REPO / 'Engine/source-lock-direct.json')
        for name in ('chromium', 'depot_tools', 'storage'):
            self.new[name] = copy.deepcopy(self.old[name])
        self.new_sha = engine.digest(json.dumps(self.new).encode())
        self.exclude = self.roots['chromium'] / '.git/info/exclude'
        self.exclude.parent.mkdir(exist_ok=True)
        self.exclude.write_text('# keep me\n/cef/\n/local-notes/\n')
        self.output = self.roots['chromium'] / 'out/object.o'
        self.output.parent.mkdir()
        self.output.write_bytes(b'cached')

    def call(self, fail=False):
        real = engine.run
        def command(argv, cwd, env, capture=False):
            self.calls.append(argv)
            if 'fetch' in argv:
                return b''
            if argv[0] != engine.GIT[0]:
                if fail:
                    raise OSError('fixture hook failed')
                return b''
            return real(argv, cwd, env, capture)
        with patch.object(engine, 'host_report', return_value=self.good_host), patch.object(engine, 'run', side_effect=command), \
             patch.object(engine, 'synced_repositories', return_value=['chromium/src']):
            return engine.retarget(self.workspace, self.new, self.new_sha, self.previous)

    def test_transition_retires_cef_preserves_objects_and_user_files(self):
        user = self.roots['cef'] / 'notes.txt'
        user.write_text('keep')
        (self.roots['chromium'] / 'source.cc').write_text('CEF patch\n')
        self.state['source_fingerprint'] = engine.tree_fingerprint(self.workspace, self.env, self.repos)
        engine.write_marker(self.workspace, self.state)
        report = self.call()
        self.assertEqual(report['reserve'], 'build')
        self.assertFalse(self.roots['cef'].exists())
        self.assertEqual((self.workspace / 'cef-retired/notes.txt').read_text(), 'keep')
        self.assertEqual((self.roots['chromium'] / 'source.cc').read_text(), 'upstream\n')
        self.assertEqual(self.exclude.read_text(), '# keep me\n/local-notes/\n')
        self.assertEqual(self.output.read_bytes(), b'cached')
        self.assertFalse(any('patcher.py' in str(c) for c in self.calls))
        self.assertEqual([c for c in self.calls if c[0] != engine.GIT[0]][-1][-1], 'runhooks')
        state = engine.read_marker(self.workspace, self.new_sha)
        self.assertEqual(state['engine_mode'], 'direct')
        self.assertEqual(state['repositories'], ['chromium/src'])
        engine.verify_workspace(self.workspace, self.new, state, self.env)

    def test_pin_upgrade_cannot_hide_in_transition(self):
        self.new['chromium']['commit'] = '0'*40
        with self.assertRaisesRegex(engine.Refusal, 'identical Chromium'):
            self.call()
        self.assertEqual(self.calls, [])

    def test_requires_generated_source(self):
        self.state['phase'] = 'synced'
        engine.write_marker(self.workspace, self.state)
        with self.assertRaisesRegex(engine.Refusal, 'good source phase'):
            self.call()
        self.assertTrue(self.roots['cef'].exists())

    def test_reserved_destination_prevents_mutation(self):
        (self.workspace / 'cef-retired').mkdir()
        with self.assertRaisesRegex(engine.Refusal, 'destination already exists'):
            self.call()
        self.assertFalse(any('restore' in c for c in self.calls))

    def test_shipping_invalidated_with_objects_retained(self):
        folder = self.roots['chromium'] / 'out' / engine.SHIPPING_CONFIGURATION
        folder.mkdir()
        args = folder / 'args.gn'
        args.write_bytes(b'legacy args')
        (folder / 'shipping.o').write_bytes(b'shipping object')
        receipt = dict(schema_version=1, workspace=str(self.workspace), lock_sha256=self.old_sha,
                       configuration=engine.SHIPPING_CONFIGURATION, gn_defines=engine.SHIPPING_DEFINES,
                       symbol_level=0, phase='built', args_sha256=engine.digest(args.read_bytes()))
        engine.write_marker(self.workspace, receipt, engine.SHIPPING_MARKER)
        self.call()
        state = engine.read_marker(self.workspace, self.new_sha)
        shipping = engine.read_shipping_marker(self.workspace, self.new_sha, state)
        self.assertEqual(shipping['phase'], 'reconfigured')
        self.assertEqual(shipping['engine_mode'], 'direct')
        self.assertEqual(shipping['args_sha256'], engine.digest(args.read_bytes()))
        self.assertEqual((folder / 'shipping.o').read_bytes(), b'shipping object')
        with self.assertRaises(engine.Refusal):
            engine.verify_shipping_build(self.workspace, self.new_sha, state)

    def test_interrupted_transition_cannot_be_sealed_or_retried(self):
        with self.assertRaises(OSError):
            self.call(fail=True)
        self.assertEqual(engine.read_marker(self.workspace, self.old_sha)['phase'], 'retarget-in-progress')
        self.assertEqual(self.output.read_bytes(), b'cached')
        self.assertTrue((self.workspace / 'cef-retired/.git').is_dir())
        with self.assertRaisesRegex(engine.Refusal, 'good source phase'):
            self.call()

    def test_direct_pin_retarget_uses_sync_floor_without_cef(self):
        self.call()
        self.previous.write_text(json.dumps(self.new))
        self.new['chromium']['tag'] = '156.0.8078.97'
        self.new_sha = engine.digest(json.dumps(self.new).encode())
        self.calls.clear()
        self.assertEqual(self.call()['reserve'], 'sync')
        self.assertFalse(any('patcher.py' in str(c) for c in self.calls))

    def test_return_to_cef_is_refused_before_changes(self):
        self.previous.write_text(json.dumps(self.new))
        with self.assertRaisesRegex(engine.Refusal, 'cannot retarget back to CEF'):
            engine.retarget(self.workspace, self.old, self.old_sha, self.previous)
        self.assertEqual(self.calls, [])

    def test_generated_unbuilt_transition_verifies_overlay_and_keeps_objects(self):
        self.state['phase'] = 'generated'
        engine.write_marker(self.workspace, self.state)
        with self.assertRaisesRegex(engine.Refusal, 'requires the verified source overlay'):
            self.call()
        self.assertTrue(self.roots['cef'].is_dir())
        self.assertFalse(any('restore' in c for c in self.calls))
        target = self.roots['chromium'] / 'source.cc'
        target.write_text('reviewed overlay\n')
        record = dict(identity='a'*64, targets={'source.cc': dict(original='upstream\n', mode=0o644,
                      output_sha256=engine.digest(target.read_bytes()))})
        raw = engine.overlay_record_bytes(record)
        folder = self.workspace / '.parc-overlays'
        folder.mkdir()
        (folder / ('a'*64 + '.json')).write_bytes(raw)
        self.state.update(phase='generated', overlay=dict(identity='a'*64, record_sha256=engine.digest(raw)),
                          source_fingerprint=engine.tree_fingerprint(self.workspace, self.env, self.repos))
        engine.write_marker(self.workspace, self.state)
        self.call()
        self.assertEqual(target.read_text(), 'upstream\n')
        self.assertEqual(self.output.read_bytes(), b'cached')
        self.assertEqual(engine.read_marker(self.workspace, self.new_sha)['phase'], 'synced')
