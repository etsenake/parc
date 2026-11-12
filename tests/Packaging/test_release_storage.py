import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import release


class ReleaseStorageTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.source = self.base / 'source'
        (self.source / 'scripts').mkdir(parents=True)
        shutil.copy(ROOT / 'scripts/engine_storage.py', self.source / 'scripts/engine_storage.py')
        self.settings = self.base / 'engine-storage.json'
        self.settings.write_text(json.dumps({'schema_version': 1, 'share': 'nfs://nas.test/engine'}))
        environment = patch.dict(os.environ, {'PARC_ENGINE_STORAGE': str(self.settings)})
        environment.start()
        self.addCleanup(environment.stop)
        self.runner = release.Release(self.base / 'repo')
        run = self.base / 'run'; run.mkdir()
        self.runner.state = {'source': str(self.source), 'run': str(run), 'workspace': str(self.base / 'engine'),
                             'completed': []}
        self.runner.emit = Mock()

    def launched(self, outcome):
        child = Mock(pid=4242)

        def wait(timeout=None):
            if outcome is not None:
                Path(self.runner.state['storage_upload']['result']).write_text(json.dumps(outcome))
            return 0

        child.wait.side_effect = wait
        return child

    def test_upload_runs_in_the_background_and_reports_at_the_end(self):
        with patch.object(release.subprocess, 'Popen', return_value=self.launched({'published': True})) as popen:
            self.runner.start_storage_upload()
            args = [str(a) for a in popen.call_args.args[0]]
            self.assertEqual(args[2:4], ['publish', '--repo'])
            self.assertIn('--result', args)
            self.assertTrue(popen.call_args.kwargs['start_new_session'])
            self.runner.storage()
        self.assertEqual(self.runner.state['storage_result'], 'updated')

    def test_failed_upload_never_stops_the_release_and_names_the_retry(self):
        self.runner.state['storage_mode'] = 'image'
        with patch.object(release.subprocess, 'Popen', return_value=self.launched({'published': None, 'error': 'NAS offline'})), \
                patch.object(self.runner, 'storage_cleanup', return_value=False) as cleanup:
            self.runner.start_storage_upload()
            self.runner.storage()
        self.assertIn('not updated (NAS offline)', self.runner.state['storage_result'])
        self.assertIn('engine_storage.py publish', self.runner.state['storage_result'])
        cleanup.assert_called_once_with('detach')

    def test_an_eject_that_never_finishes_is_stopped_and_the_release_moves_on(self):
        child = Mock(pid=4343)
        child.wait.side_effect = release.subprocess.TimeoutExpired('detach', 1)
        with patch.object(release.subprocess, 'Popen', return_value=child), \
                patch.object(release.os, 'killpg') as killpg:
            self.assertFalse(self.runner.storage_cleanup('detach'))
        self.assertEqual([call.args for call in killpg.call_args_list],
                         [(4343, release.signal.SIGTERM), (4343, release.signal.SIGKILL)])

    def test_upload_that_dies_without_a_result_is_reported(self):
        with patch.object(release.subprocess, 'Popen', return_value=self.launched(None)):
            self.runner.start_storage_upload()
            self.runner.storage()
        self.assertIn('stopped without reporting a result', self.runner.state['storage_result'])

    def test_resumed_release_waits_for_an_upload_it_did_not_start(self):
        result = Path(self.runner.state['run']) / 'engine-storage-publish.json'
        result.write_text(json.dumps({'published': False, 'reason': 'already current'}))
        self.runner.state['storage_upload'] = {'pid': 4242, 'result': str(result)}
        uploader = Mock(stdout=f'python3 scripts/engine_storage.py publish --result {result}\n')
        gone = Mock(stdout='')
        with patch.object(release.subprocess, 'run', side_effect=[uploader, gone]), \
                patch.object(release.time, 'sleep') as sleep:
            self.runner.storage()
        sleep.assert_called_once()
        self.assertEqual(self.runner.state['storage_result'], 'already holds this engine')

    def test_resumed_release_ignores_a_reused_process_id(self):
        result = Path(self.runner.state['run']) / 'engine-storage-publish.json'
        self.runner.state['storage_upload'] = {'pid': 4242, 'result': str(result)}
        with patch.object(release.subprocess, 'run', return_value=Mock(stdout='/usr/sbin/someone-else\n')), \
                patch.object(release.time, 'sleep', side_effect=AssertionError('waited')):
            self.runner.storage()
        self.assertIn('stopped without reporting a result', self.runner.state['storage_result'])

    def test_upload_that_cannot_start_is_reported_without_stopping_the_release(self):
        with patch.object(release.subprocess, 'Popen', side_effect=OSError('no such interpreter')):
            self.runner.start_storage_upload()
            self.runner.storage()
        self.assertIn('not updated (no such interpreter)', self.runner.state['storage_result'])

    def test_a_stuck_eject_helper_is_killed_even_after_its_leader_exits(self):
        child = Mock(pid=4444)
        child.wait.side_effect = [release.subprocess.TimeoutExpired('detach', 1), 0, 0]
        with patch.object(release.subprocess, 'Popen', return_value=child), \
                patch.object(release.os, 'killpg') as killpg:
            self.assertFalse(self.runner.storage_cleanup('detach'))
        self.assertEqual([call.args for call in killpg.call_args_list],
                         [(4444, release.signal.SIGTERM), (4444, release.signal.SIGKILL)])

    def test_upload_past_the_deadline_is_left_running_and_reported(self):
        child = Mock(pid=4242)
        child.wait.side_effect = release.subprocess.TimeoutExpired('publish', 1)
        self.runner.state['storage_mode'] = 'image'
        with patch.object(release.subprocess, 'Popen', return_value=child), \
                patch.object(self.runner, 'storage_cleanup', side_effect=AssertionError('ejected')):
            self.runner.start_storage_upload()
            self.runner.storage()
        self.assertIn('still uploading in the background', self.runner.state['storage_result'])

    def test_unreadable_settings_turn_storage_off_instead_of_failing(self):
        self.settings.write_text('{not json')
        self.assertFalse(self.runner.storage_enabled())

    def test_without_settings_nothing_is_uploaded(self):
        self.settings.unlink()
        with patch.object(release.subprocess, 'Popen') as popen:
            self.runner.start_storage_upload()
            self.runner.storage()
        popen.assert_not_called()
        self.assertNotIn('storage_result', self.runner.state)


if __name__ == '__main__':
    unittest.main()
