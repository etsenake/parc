import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import release


class EngineUpgradeTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.runner = release.Release(self.base / 'repo')
        run = self.base / 'run'
        run.mkdir()
        self.runner.state = {'commit': 'abc123', 'run': str(run)}
        self.runner.emit = Mock()
        self.runner.checkpoint = Mock()
        self.workspace = self.base / 'ParcBuild/engine-cx'
        self.workspace.mkdir(parents=True)
        self.before = {'chromium': {'url': 'https://chromium.googlesource.com/chromium/src.git',
                                    'commit': 'a' * 40, 'tag': '156.0.8078.48'},
                       'depot_tools': {'url': 'https://chromium.googlesource.com/chromium/tools/depot_tools.git',
                                       'commit': 'b' * 40},
                       'build': {'gn_defines': 'is_official_build=true', 'configuration': 'Parc_GN_arm64'},
                       'storage': {'sync_minimum_free_bytes': 80, 'build_minimum_free_bytes': 40}}
        self.previous_text = json.dumps(self.before)
        marker = {'lock_sha256': hashlib.sha256((self.previous_text + '\n').encode()).hexdigest()}
        (self.workspace / '.parc-engine-source.json').write_text(json.dumps(marker))

    def upgrade(self, after):
        lock = self.base / 'source-lock.json'
        lock.write_text(json.dumps(after) + '\n')
        self.runner.git = lambda *args, **kwargs: 'rev1' if args[0] == 'rev-list' else self.previous_text
        self.runner.command = Mock(return_value='')
        workspace = self.runner.move_engine_to_lock(Path('/repo/scripts/engine-source.py'), self.workspace, lock)
        return workspace, [[str(arg) for arg in call.args[0]] for call in self.runner.command.call_args_list]

    def test_a_chromium_upgrade_moves_the_existing_engine_instead_of_downloading_a_new_one(self):
        after = copy.deepcopy(self.before)
        after['chromium'].update(commit='c' * 40, tag='156.0.8078.103')
        workspace, commands = self.upgrade(after)
        self.assertEqual(workspace, self.workspace)
        self.assertEqual(len(commands), 1)
        self.assertEqual(commands[0][2:4], ['retarget', '--workspace'])
        self.assertEqual(commands[0][4], str(self.workspace))
        self.assertFalse(any('sync' in command for command in commands))

    def test_an_interrupted_upgrade_is_handed_back_to_the_same_in_place_move(self):
        after = copy.deepcopy(self.before)
        after['chromium'].update(commit='c' * 40, tag='156.0.8078.103')
        self.upgrade(after)
        workspace, commands = self.upgrade(after)
        self.assertEqual((workspace, commands[0][2]), (self.workspace, 'retarget'))

    def test_a_version_and_build_setting_change_together_still_moves_in_place(self):
        after = copy.deepcopy(self.before)
        after['chromium'].update(commit='c' * 40, tag='156.0.8078.103')
        after['build']['gn_defines'] += ' enable_nacl=false'
        after['storage']['sync_minimum_free_bytes'] = 90
        workspace, commands = self.upgrade(after)
        self.assertEqual((workspace, commands[0][2]), (self.workspace, 'retarget'))

    def test_a_build_setting_change_reconfigures_in_place(self):
        after = copy.deepcopy(self.before)
        after['build']['gn_defines'] += ' enable_nacl=false'
        workspace, commands = self.upgrade(after)
        self.assertEqual((workspace, commands[0][2]), (self.workspace, 'reconfigure'))

    def test_only_a_change_the_move_cannot_handle_starts_a_new_checkout(self):
        after = copy.deepcopy(self.before)
        after['chromium'].update(url='https://example.org/chromium.git', commit='c' * 40)
        workspace, commands = self.upgrade(after)
        self.assertNotEqual(workspace, self.workspace)
        self.assertEqual(commands[0][2], 'sync')

    def test_an_engine_already_on_this_version_is_left_alone(self):
        lock = self.base / 'source-lock.json'
        lock.write_text(self.previous_text + '\n')
        self.runner.command = Mock()
        self.assertEqual(self.runner.move_engine_to_lock(Path('/x'), self.workspace, lock), self.workspace)
        self.runner.command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
