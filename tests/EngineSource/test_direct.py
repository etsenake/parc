"""Direct plans and recipes are checked without invoking engine tools."""
import copy
import json
import unittest
from pathlib import Path
from unittest.mock import patch
import test_engine_source as fixture
engine = fixture.engine


class DirectTests(unittest.TestCase):
    def setUp(self):
        fixture.EngineSourceTests.setUp(self)
        self.lock, self.sha = engine.load_lock(fixture.ROOT / 'Engine/source-lock-direct.json')

    def test_default_stays_stopgap(self):
        self.assertIn('cef', engine.load_lock()[0])
        self.assertNotIn('cef', self.lock)
        self.assertEqual(set(engine.locations(self.workspace, self.lock)), {'chromium', 'depot_tools'})

    def test_sync_and_build_have_no_cef_and_keep_chromium_hooks(self):
        plan = engine.command_plan(self.workspace, self.lock, 4)
        self.assertNotIn('cef', json.dumps(plan))
        self.assertEqual(plan['sync'][-1]['argv'][-1], 'runhooks')
        self.assertEqual(plan['build'][1]['argv'][-2:], ['gen', 'out/Release_GN_arm64'])
        self.assertEqual(plan['build'][-1]['argv'][-2:], [t[2:] for t in self.lock['build']['targets']])

    def test_explicit_recipe_preserves_media_and_storage_identity(self):
        args = engine.gn_arguments(engine.environment(self.workspace, self.lock, 1)['GN_DEFINES']).decode()
        for value in ['is_debug=false', 'enable_widevine=true', 'enable_cdm_host_verification=true',
                      'alternate_cdm_storage_id_key="968b476909da4373b08903c28e859454"',
                      'enable_background_mode=false', 'enable_downgrade_processing=false',
                      'enable_ffmpeg_video_decoders=false', 'symbol_level=1']:
            self.assertIn(value + '\n', args)
        for value in ['enable_precompiled_headers', 'forbid_non_component_debug_builds', 'enable_resource_allowlist_generation']:
            self.assertNotIn(value, args)

    def test_shipping_uses_same_direct_inputs_with_official_overrides(self):
        env = engine.shipping_environment(self.workspace, self.lock, 0)
        with patch.object(engine, 'run', side_effect=AssertionError('CEF generator called')):
            args = engine.shipping_arguments(self.workspace, env, self.lock).decode()
        for value in ['is_component_build=false', 'is_official_build=true', 'chrome_pgo_phase=0']:
            self.assertIn(value + '\n', args)
        plan = engine.shipping_command_plan(self.workspace, 4, self.lock)
        self.assertEqual(plan[-1]['argv'][-2:], [t[2:] for t in self.lock['build']['targets']])

    def test_lock_refuses_cef_and_expression_arguments(self):
        for mutate in [lambda l: l.update(cef={}), lambda l: l['build'].update(gn_defines='import("x")')]:
            lock = copy.deepcopy(self.lock)
            mutate(lock)
            path = self.base / 'bad.json'
            path.write_text(json.dumps(lock))
            with self.assertRaises(engine.Refusal):
                engine.load_lock(path)

    def test_direct_overlay_cannot_write_cef(self):
        with self.assertRaisesRegex(engine.Refusal, 'cannot target CEF'):
            engine.target_path(self.workspace, 'cef/BUILD.gn', self.lock)

    def test_dependency_inventory_has_no_cef(self):
        self.workspace.mkdir()
        (self.workspace / 'dependency-sync.json').write_text(json.dumps({'solutions': {'src/third_party/a': {'scm': 'git'}}}))
        self.assertEqual(engine.synced_repositories(self.workspace, self.lock), ['chromium/src', 'chromium/src/third_party/a'])

    def generated(self, operation='generate', applied=True):
        self.workspace.mkdir()
        (self.workspace / '.parc-operation.lock').touch()
        state = dict(schema_version=1, workspace=str(self.workspace), lock_sha256=self.sha,
                     phase='synced', symbol_level=0, repositories=['chromium/src'], source_fingerprint='source')
        engine.write_marker(self.workspace, state)
        with patch.object(engine, 'host_report', return_value=self.good_host), patch.object(engine, 'verify_workspace'), \
             patch.object(engine, 'recorded_overlay', return_value={'build_targets': []} if applied else None), \
             patch.object(engine, 'tree_fingerprint', return_value='source'), patch.object(engine, 'run') as run:
            engine.execute(self.workspace, self.lock, self.sha, operation, 0, 4)
        return engine.read_marker(self.workspace, self.sha), run

    def test_generate_writes_and_seals_explicit_args(self):
        state, run = self.generated()
        self.assertEqual(state['phase'], 'generated')
        self.assertEqual(state['engine_mode'], 'direct')
        args = self.workspace / 'chromium/src/out/Release_GN_arm64/args.gn'
        self.assertEqual(state['args_sha256'], engine.digest(args.read_bytes()))
        self.assertFalse(any('autoninja' in str(call) for call in run.call_args_list))
        (self.workspace / 'chromium/.gclient').write_text(engine.gclient_text(self.lock))
        with patch.object(engine, 'verify_repository'), patch.object(engine, 'tree_fingerprint', return_value='source'), patch.object(engine, 'recorded_overlay'):
            engine.verify_workspace(self.workspace, self.lock, state, self.env)
            args.write_text('is_debug=true')
            with self.assertRaisesRegex(engine.Refusal, 'arguments differ'):
                engine.verify_workspace(self.workspace, self.lock, state, self.env)

    def test_missing_overlay_refuses_before_generation_receipt(self):
        with self.assertRaisesRegex(engine.Refusal, 'requires the reviewed Parc overlay'):
            self.generated(applied=False)
        self.assertEqual(engine.read_marker(self.workspace, self.sha)['phase'], 'synced')

    def test_sync_executes_only_two_checkouts_and_keeps_hooks(self):
        with patch.object(engine, 'host_report', return_value=self.good_host), patch.object(engine, 'verify_repository'), \
             patch.object(engine, 'synced_repositories', return_value=['chromium/src']), \
             patch.object(engine, 'tree_fingerprint', return_value='source'), patch.object(engine, 'run') as run:
            engine.execute(self.workspace, self.lock, self.sha, 'sync', 0, 4)
        self.assertEqual(len(run.call_args_list), 10)
        self.assertEqual(run.call_args_list[-1].args[0][-1], 'runhooks')
        self.assertFalse((self.workspace / 'chromium/src/.git/info/exclude').exists())

    def test_prepare_direct_overlay_and_label_validation(self):
        root = self.base / 'overlay'
        root.mkdir()
        (root / 'source.h').write_text('owned')
        spec = dict(schema_version=1, id='direct', version=1, upstream={'chromium': self.lock['chromium']['commit']},
                    build_targets=['//parc/native:native_components'],
                    files=[dict(source='source.h', target='parc/native/source.h', sha256=engine.digest(b'owned'))])
        manifest = root / 'overlay.json'
        manifest.write_text(json.dumps(spec))
        with patch.object(engine, 'recorded_overlay', return_value=None):
            record, writes = engine.prepare_overlay(self.workspace, self.lock, {}, manifest)
            self.assertEqual(writes['parc/native/source.h'], b'owned')
            self.assertEqual(record['upstream'], spec['upstream'])
            spec['build_targets']=['//cef:cef_framework']
            manifest.write_text(json.dumps(spec))
            with self.assertRaisesRegex(engine.Refusal, 'Invalid overlay build targets'):
                engine.prepare_overlay(self.workspace, self.lock, {}, manifest)
