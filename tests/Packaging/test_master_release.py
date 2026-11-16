import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
import release
import release_assets
import release_inputs
import release_install
import release_lease


class RepositoryFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'repo'; self.root.mkdir()
        self.remote = Path(self.tmp.name) / 'remote.git'
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Fixture'); self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'core.hooksPath', '/dev/null')
        (self.root / '.gitignore').write_text('build/\n')
        (self.root / 'app-version.json').write_text('{"version":"1.0.0","build":1}\n')
        (self.root / 'release-notes.json').write_text('{"releases": []}\n')
        (self.root / 'Resources').mkdir(); (self.root / 'Resources/icon').write_bytes(b'icon')
        self.git('add', '.'); self.git('commit', '-m', 'Initial fixture'); self.git('tag', 'v1.0.0')
        subprocess.run(['git', 'init', '--bare', str(self.remote)], capture_output=True, check=True)
        self.git('remote', 'add', 'origin', str(self.remote)); self.git('push', '-u', 'origin', 'main', 'v1.0.0')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.DEVNULL, text=True).strip()

    def runner(self):
        runner = release.Release(self.root, 'minor'); runner.start()
        self.addCleanup(lambda: [item.close() for item in runner.locks])
        return runner

    def stopped_patch_release(self):
        self.commit('fix: Keep tabs')
        runner = release.Release(self.root); runner.start(); runner.prepare()
        runner.checkpoint(status='stopped', stage='engine', completed=['source'], command_pid=None,
                          error='compiler error',
                          engine_seal_path=str(Path(runner.state['run']) / 'engine-artifacts.json'))
        for item in runner.locks: item.close()

    def refresh(self, commit=None):
        refreshed = release.Release(self.root, refresh_source=True, source_commit=commit); refreshed.start()
        self.addCleanup(lambda: [item.close() for item in refreshed.locks])
        return refreshed

    def commit(self, message):
        self.git('commit', '--allow-empty', '-m', message); self.git('push', 'origin', 'main')

    def automatic(self):
        runner = release.Release(self.root); runner.start()
        self.addCleanup(lambda: [item.close() for item in runner.locks])
        return runner

    def notes(self):
        return json.loads((self.root / 'release-notes.json').read_text())['releases']

    def race(self, runner, killed=None, rewritten=False):
        peer = Path(self.tmp.name) / 'peer'
        subprocess.run(['git', 'clone', '-q', str(self.remote), str(peer)], check=True)
        original = runner.git; pushes = []
        def racing(*args, **kwargs):
            if args[0] == 'push':
                pushes.append(args)
                if len(pushes) == 1:
                    if rewritten:
                        subprocess.run(['git', 'reset', '-q', '--hard', 'HEAD~1'], cwd=peer, check=True)
                    (peer / 'release-notes.json').write_text('{"releases":[]}\n')
                    (peer / 'Resources/icon').write_bytes(b'late icon')
                    for command in (['-c', 'user.name=Peer', '-c', 'user.email=peer@example.invalid', 'commit',
                                     '-qam', 'feat: Land late'], ['push', '-qf', 'origin', 'main']):
                        subprocess.run(['git', *command], cwd=peer, check=True, capture_output=True)
                elif killed == 'push':
                    raise OSError('power lost before the merged version commit was pushed')
            return original(*args, **kwargs)
        saved = runner.checkpoint
        def checkpoint(**values):
            saved(**values)
            if pushes and 'notes' in values and killed == 'merge':
                raise OSError('power lost while merging, after saving the raised version')
        with patch.object(runner, 'git', side_effect=racing), patch.object(runner, 'checkpoint', side_effect=checkpoint):
            runner.prepare()

    def resume_after_a_kill_in_the_late_merge(self, killed):
        self.commit('fix: Keep tabs')
        runner = self.automatic()
        with self.assertRaises(OSError):
            self.race(runner, killed)
        for item in runner.locks: item.close()
        self.assertEqual((self.git('status', '--porcelain'), self.git('log', '-1', '--format=%s')),
                         ('', 'chore(release): 1.0.1'))
        self.assertTrue(subprocess.run(['git', 'rev-parse', '-q', '--verify', 'MERGE_HEAD'], cwd=self.root).returncode)
        resumed = self.automatic(); resumed.prepare()
        [entry] = json.loads(self.git('show', 'origin/main:release-notes.json'))['releases']
        self.assertEqual((entry['version'], [item['summary'] for item in entry['changes']]),
                         ('1.1.0', ['Keep tabs', 'Land late']))
        self.assertEqual(len(self.git('log', '-1', '--format=%p', 'origin/main').split()), 2)
        self.assertEqual(self.git('log', '-1', '--format=%s', 'origin/main'), 'chore(release): 1.1.0')
        self.assertEqual(self.git('log', '--format=%s', 'v1.0.0..origin/main').count('chore(release): 1.1.0'), 1)
        self.assertEqual(self.git('show', 'origin/main:Resources/icon'), 'late icon')
        self.assertEqual(json.loads(self.git('show', 'origin/main:app-version.json')), {'version': '1.1.0', 'build': 2})
        self.assertEqual((resumed.state['release_type'], resumed.state['tag']), ('minor', 'v1.1.0'))
        self.assertTrue(resumed.published(resumed.state['commit']))
        self.assertEqual(self.git('rev-parse', 'origin/main'), resumed.state['commit'])



class Repository(RepositoryFixture):
    def test_resume_ignores_obsolete_checkpoint_fields(self):
        runner = self.runner()
        legacy = {"storage_" + suffix: value for suffix, value in
                  (("mode", "image"), ("reason", "old choice"),
                   ("upload", {"pid": 999999, "result": "/missing/result.json"}),
                   ("result", "old result"))}
        runner.checkpoint(status="stopped", stage="storage", completed=["source", "storage"], **legacy)
        for handle in runner.locks:
            handle.close()
        resumed = self.runner()
        self.assertEqual(resumed.state["id"], runner.state["id"])
        self.assertEqual(resumed.state["completed"], ["source", "storage"])
        self.assertTrue(set(legacy).isdisjoint(resumed.state))
        self.assertTrue(set(legacy).isdisjoint(json.loads(resumed.current.read_text())))

    def test_semantic_bumps(self):
        for kind, expected in [('major','2.0.0'),('minor','1.1.0'),('patch','1.0.1')]:
            self.assertEqual(release.next_version('1.0.0', kind), expected)

    def test_refresh_failed_source_preserves_version_and_original_archive(self):
        runner = self.runner()
        runner.prepare()
        old_commit, old_source = runner.state['commit'], runner.state['source']
        runner.checkpoint(status='stopped', stage='engine', completed=['source'],
                          command_pid=None, error='compiler error',
                          engine_seal_path=str(Path(runner.state['run']) / 'engine-artifacts.json'))
        for item in runner.locks: item.close()
        (self.root / 'Resources/icon').write_bytes(b'fixed source')
        self.git('add', '.'); self.git('commit', '-m', 'Fix source'); self.git('push', 'origin', 'main')
        checked_commit = self.git('rev-parse', 'HEAD')
        (self.root / 'Resources/icon').write_bytes(b'later contributor change')
        self.git('add', '.'); self.git('commit', '-m', 'Later source'); self.git('push', 'origin', 'main')
        refreshed = release.Release(self.root, 'minor', refresh_source=True, source_commit=checked_commit)
        refreshed.start()
        self.addCleanup(lambda: [item.close() for item in refreshed.locks])
        refreshed.refresh_inputs()
        self.assertEqual(refreshed.state['version'], {'version': '1.1.0', 'build': 2})
        self.assertEqual(refreshed.state['commit'], checked_commit)
        self.assertNotEqual(refreshed.state['commit'], self.git('rev-parse', 'HEAD'))
        release_inputs.verify(self.root, old_source, old_commit)
        release_inputs.verify(self.root, refreshed.state['source'], refreshed.state['commit'])
        self.assertEqual(refreshed.state['source_history'][0]['error'], 'compiler error')
        self.git('tag', 'v1.1.0'); self.git('push', 'origin', 'v1.1.0')
        with self.assertRaisesRegex(release.Failure, 'immutable'):
            refreshed.refresh_inputs()

    def test_refresh_lists_the_fixes_it_freezes_and_keeps_later_commits_out(self):
        self.stopped_patch_release()
        self.commit('fix(engine): build with the new SDK'); checked = self.git('rev-parse', 'HEAD')
        self.commit('feat: Later work'); later = self.git('rev-parse', 'HEAD')
        refreshed = self.refresh(checked)
        with patch.object(release_inputs, 'create', side_effect=OSError('power lost after publishing the notes')):
            with self.assertRaises(OSError): refreshed.refresh_inputs()
        for item in refreshed.locks: item.close()
        refreshed = release.Release(self.root); refreshed.preflight = Mock(); refreshed.env['GH_TOKEN'] = 'fixture-token'
        with patch.dict(release.os.environ), patch.object(release_lease, 'acquire', return_value='lease'):
            with patch.object(refreshed, 'engine', side_effect=release.Failure('compiler error again')):
                self.assertEqual(refreshed.run(), 1)
        self.assertIsNone(refreshed.state['refresh_commit'])
        notes = refreshed.state['commit']
        self.assertEqual(self.git('rev-parse', notes + '^'), checked)
        self.assertEqual(self.git('log', '-1', '--format=%s %P', 'origin/main'),
                         'Merge chore(release): 1.0.1 notes ' + later + ' ' + notes)
        self.assertEqual(sorted(self.git('log', '--format=%s', checked + '..origin/main').splitlines()),
                         ['Merge chore(release): 1.0.1 notes', 'chore(release): 1.0.1 notes', 'feat: Later work'])
        self.assertTrue(subprocess.run(['git', 'merge-base', '--is-ancestor', later, notes], cwd=self.root).returncode)
        shipped = (Path(refreshed.state['source']) / 'release-notes.json').read_text().strip()
        self.assertEqual(shipped, self.git('show', 'origin/main:release-notes.json'))
        [entry] = json.loads(shipped)['releases']
        self.assertEqual(([item['summary'] for item in entry['changes']], refreshed.state['notes']),
                         (['Keep tabs', 'build with the new SDK'], entry))
        self.assertIn('- **engine:** Build with the new SDK', release.release_notes.markdown(entry))
        release_inputs.verify(self.root, refreshed.state['source'], notes)
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.git('rev-parse', 'origin/main'))

    def test_refresh_without_a_pin_publishes_its_notes_as_a_fast_forward(self):
        self.stopped_patch_release()
        self.commit('fix(engine): build with the new SDK'); fixed = self.git('rev-parse', 'HEAD')
        (self.root / 'stray').write_text('')
        refreshed = self.refresh(); refreshed.refresh_inputs()
        self.assertTrue((self.root / 'stray').exists())
        self.assertEqual(self.git('rev-parse', 'origin/main'), refreshed.state['commit'])
        self.assertEqual(self.git('log', '-1', '--format=%s %P', 'origin/main'), 'chore(release): 1.0.1 notes ' + fixed)

    def test_refresh_interrupted_in_a_git_command_reruns_once_it_is_gone(self):
        self.stopped_patch_release(); self.commit('fix(engine): build with the new SDK')
        interrupted = release.Release(self.root, refresh_source=True)
        interrupted.preflight = Mock(); interrupted.env['GH_TOKEN'] = 'fixture-token'
        original = interrupted.checkpoint
        def checkpoint(**values):
            original(**values)
            if values.get('command', [])[:2] == ['git', 'fetch']:
                raise KeyboardInterrupt('Release interrupted by signal 15')
        with patch.dict(release.os.environ), patch.object(release_lease, 'acquire', return_value='lease'), \
                patch.object(interrupted, 'checkpoint', side_effect=checkpoint):
            self.assertEqual(interrupted.run(), 1)
        stopped = json.loads(interrupted.current.read_text())
        self.assertEqual((stopped['status'], stopped['command'][:2]), ('stopped', ['git', 'fetch']))
        with self.assertRaises(ProcessLookupError): release.os.killpg(stopped['command_pid'], 0)
        refreshed = self.refresh(); refreshed.refresh_inputs()
        self.assertEqual(refreshed.state['interrupted_command']['pid'], stopped['command_pid'])
        self.assertEqual(self.git('log', '-1', '--format=%s', 'origin/main'), 'chore(release): 1.0.1 notes')

    def test_refresh_refuses_a_feat_its_patch_release_cannot_ship(self):
        self.stopped_patch_release(); self.commit('feat: Later work')
        with self.assertRaisesRegex(release.Failure, 'would ship a minor change in 1.0.1'):
            self.refresh().refresh_inputs()
        self.assertEqual(self.git('log', '-1', '--format=%s', 'origin/main'), 'feat: Later work')

    def test_other_type_supersedes_stopped_unpublished_release(self):
        patch_run = release.Release(self.root, 'patch'); patch_run.start()
        patch_run.prepare()
        patch_run.checkpoint(status='stopped', stage='engine', completed=['source'], command_pid=None,
                             lease='patch-lease', error='Release interrupted by signal 15')
        for item in patch_run.locks: item.close()
        patch_dir = Path(patch_run.state['run'])
        with patch.object(release_lease, 'release') as released:
            minor = self.runner()
        released.assert_called_once_with('patch-lease')
        old = json.loads((patch_dir / 'state.json').read_text())
        self.assertEqual((old['status'], old['superseded_by'], old['lease']), ('abandoned', 'minor', None))
        self.assertTrue(Path(old['source']).exists())
        self.assertNotEqual(minor.state['run'], str(patch_dir))
        minor.prepare()
        self.assertEqual(minor.state['version'], {'version': '1.1.0', 'build': 3})
        self.assertEqual(minor.state['since'], 'v1.0.0')
        self.assertEqual([item['version'] for item in self.notes()], ['1.1.0'])

    def test_superseding_release_finds_the_cancelled_shipping_build(self):
        patch_run = release.Release(self.root, 'patch'); patch_run.start()
        patch_run.prepare()
        patch_run.checkpoint(status='stopped', stage='engine', completed=['source'], command_pid=999999,
                             command=['python3', 'engine-source.py', 'shipping-build'])
        for item in patch_run.locks: item.close()
        with patch.object(release_lease, 'release'):
            minor = self.runner()
        self.assertEqual(minor.superseded_shipping_build()['id'], patch_run.state['id'])
        retired = Path(patch_run.state['run']) / 'state.json'
        release.save(retired, dict(json.loads(retired.read_text()), cancelled_build_recovered=minor.state['id']))
        self.assertIsNone(minor.superseded_shipping_build())

    def test_other_type_refuses_published_or_live_release(self):
        patch_run = release.Release(self.root, 'patch'); patch_run.start()
        patch_run.prepare()
        patch_run.checkpoint(status='stopped', stage='engine', completed=['source'], command_pid=None)
        for item in patch_run.locks: item.close()
        self.git('tag', 'v1.0.1'); self.git('push', 'origin', 'v1.0.1')
        with self.assertRaisesRegex(release.Failure, 'already published'):
            self.runner()
        self.git('push', 'origin', ':refs/tags/v1.0.1')
        live = release.Release(self.root, 'patch'); live.start()
        self.addCleanup(lambda: [item.close() for item in live.locks])
        with self.assertRaisesRegex(release.Failure, 'already active'):
            release.Release(self.root, 'minor').start()

    def test_refresh_before_engine_seal_recorded_and_after_a_crash(self):
        runner = self.runner()
        runner.prepare()
        runner.checkpoint(stage='engine', completed=['source'], command_pid=None)
        for item in runner.locks: item.close()
        self.assertEqual(json.loads(runner.current.read_text())['status'], 'running')
        (self.root / 'Resources/icon').write_bytes(b'fixed source')
        self.git('add', '.'); self.git('commit', '-m', 'Fix source'); self.git('push', 'origin', 'main')
        refreshed = release.Release(self.root, 'minor', refresh_source=True)
        refreshed.start()
        self.addCleanup(lambda: [item.close() for item in refreshed.locks])
        refreshed.refresh_inputs()
        self.assertEqual(refreshed.state['commit'], self.git('rev-parse', 'HEAD'))
        self.assertEqual(refreshed.state['version'], {'version': '1.1.0', 'build': 2})

    def test_refresh_rejects_active_stage(self):
        runner = self.runner()
        for item in runner.locks: item.close()
        refreshed = release.Release(self.root, 'minor', refresh_source=True)
        self.addCleanup(lambda: [item.close() for item in refreshed.locks])
        with self.assertRaisesRegex(release.Failure, 'stopped engine'):
            refreshed.start()

    def test_combined_log_appends_across_runners_and_includes_captured_errors(self):
        first = release.Release(self.root, 'minor')
        first.secrets.append('fixture-secret')
        first.emit('first run')
        captured = first.command([sys.executable, '-c',
                                  'import sys; print("fixture-secret"); print("stderr detail", file=sys.stderr)'],
                                 capture=True)
        self.assertIn('[REDACTED]', captured)
        second = release.Release(self.root, 'minor')
        second.emit('second run')
        with self.assertRaisesRegex(release.Failure, 'nightly-release.log'):
            second.command([sys.executable, '-c', 'print("failure detail"); raise SystemExit(3)'])
        contents = (self.root / 'build/master-release-development/nightly-release.log').read_text()
        for expected in ('first run', 'stderr detail', '[REDACTED]', 'second run', 'failure detail'):
            self.assertIn(expected, contents)
        self.assertNotIn('fixture-secret', contents)

    def test_snapshot_remains_frozen_when_main_changes_and_rejects_extra_resources(self):
        commit = self.git('rev-parse', 'HEAD'); source = self.root / 'build/source'
        release_inputs.create(self.root, source, commit)
        (self.root / 'Resources/icon').write_bytes(b'newmain')
        self.git('add', '.'); self.git('commit', '-m', 'Newer main')
        release_inputs.verify(self.root, source, commit)
        (source / 'Resources/untracked').write_bytes(b'must not ship')
        with self.assertRaisesRegex(ValueError, 'Untracked'):
            release_inputs.verify(self.root, source, commit)

    def test_snapshot_rejects_changed_tracked_input(self):
        commit = self.git('rev-parse', 'HEAD'); source = self.root / 'build/source'
        release_inputs.create(self.root, source, commit)
        (source / 'Resources/icon').write_bytes(b'tamper')
        with self.assertRaisesRegex(ValueError, 'changed'):
            release_inputs.create(self.root, source, commit)

    def test_version_commit_push_and_snapshot_resume_without_second_bump(self):
        runner = self.runner(); original = runner.git
        def interrupted(*args, **kwargs):
            if args[0] == 'push':
                raise release.Failure('network unavailable')
            return original(*args, **kwargs)
        with patch.object(runner, 'git', side_effect=interrupted):
            with self.assertRaises(release.Failure): runner.prepare()
        saved_commit = runner.state['commit']
        runner.prepare(); runner.prepare()
        self.assertEqual(runner.state['commit'], saved_commit)
        self.assertEqual(json.loads((self.root / 'app-version.json').read_text()), {'version':'1.1.0','build':2})
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.git('ls-remote', 'origin', 'refs/heads/main').split()[0])
        self.assertTrue(runner.state['source_frozen'])

    def test_interruption_after_commit_recovers_own_commit(self):
        runner = self.runner(); original = runner.checkpoint
        def interrupted(**values):
            if 'commit' in values: raise OSError('power lost after commit')
            return original(**values)
        with patch.object(runner, 'checkpoint', side_effect=interrupted):
            with self.assertRaises(OSError): runner.prepare()
        for item in runner.locks: item.close()
        commit = self.git('rev-parse', 'HEAD'); runner = self.runner(); runner.prepare()
        self.assertEqual(runner.state['commit'], commit)
        self.assertEqual(runner.state['version']['version'], '1.1.0')

    def test_dirty_main_is_preserved(self):
        runner = self.runner(); target = self.root / 'Resources/icon'; target.write_bytes(b'other owner')
        with self.assertRaisesRegex(release.Failure, 'clean main'): runner.prepare()
        self.assertEqual(target.read_bytes(), b'other owner')
        self.assertNotIn('version', runner.state)

    def test_untracked_files_never_block_and_stay_untouched(self):
        stray = self.root / 'stray'; stray.write_bytes(b'')
        notes = self.root / 'Resources/notes.txt'; notes.write_text('mine')
        runner = self.runner(); runner.prepare()
        self.assertEqual(self.git('log', '-1', '--format=%s', 'origin/main'), 'chore(release): 1.1.0')
        self.assertNotIn('stray', self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').splitlines())
        self.assertEqual((stray.read_bytes(), notes.read_text()), (b'', 'mine'))
        self.assertEqual(self.git('status', '--porcelain'), '?? Resources/notes.txt\n?? stray')
        self.assertFalse((Path(runner.state['source']) / 'stray').exists())
        self.assertFalse((Path(runner.state['source']) / 'Resources/notes.txt').exists())

    def test_child_commands_run_python3_with_the_release_interpreter(self):
        shim = self.root / 'build/release-tools/bin/python3'
        shim.parent.mkdir(parents=True); shim.write_text('#!/bin/sh\nexec /usr/bin/python3 "$@"\n')
        runner = self.runner()
        self.assertEqual(runner.env['PATH'].split(os.pathsep)[0], str(runner.root / 'build/release-tools/bin'))
        found = runner.command(['python3', '-c', 'import sys; print(sys.executable)'], capture=True)
        self.assertEqual(found, sys.executable)

    def test_nonblocking_lock_prevents_overlapping_run(self):
        first = self.runner(); second = release.Release(self.root, 'minor')
        with self.assertRaisesRegex(release.Failure, 'already active'): second.start()
        for item in second.locks: item.close()
        self.assertEqual(first.state['release_type'], 'minor')

    def test_nothing_to_release_takes_no_lease_and_commits_nothing(self):
        self.commit('docs: Explain releases'); self.commit('Unconventional history')
        head = self.git('rev-parse', 'HEAD')
        for _ in range(2):
            runner = release.Release(self.root); runner.preflight = Mock(); runner.env['GH_TOKEN'] = 'fixture-token'
            with patch.object(release_lease, 'acquire') as acquired:
                self.assertEqual(runner.run(), 0)
            acquired.assert_not_called()
            self.assertEqual(runner.state['status'], 'nothing-to-release')
        self.assertEqual(self.git('rev-parse', 'HEAD'), head)
        self.assertNotIn('version', runner.state)
        self.assertIn('Nothing to release since v1.0.0', runner.log.read_text())

    def test_conventional_commits_choose_the_bump_and_notes(self):
        self.commit('fix(tabs): Keep pinned tabs'); self.commit('chore: Tidy')
        self.commit('feat(sidebar): Show Update Complete')
        runner = self.automatic(); runner.prepare(); runner.prepare()
        self.assertEqual((runner.state['release_type'], runner.state['since']), ('minor', 'v1.0.0'))
        self.assertEqual(json.loads((self.root / 'app-version.json').read_text()), {'version': '1.1.0', 'build': 2})
        self.assertEqual(self.git('log', '-1', '--format=%s'), 'chore(release): 1.1.0')
        self.assertEqual(sorted(self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').split()),
                         ['CHANGELOG.md', 'app-version.json', 'release-notes.json'])
        [entry] = self.notes()
        self.assertEqual([item['summary'] for item in entry['changes']], ['Keep pinned tabs', 'Show Update Complete'])
        self.assertEqual(entry['date'], release.datetime.datetime.now(release.datetime.timezone.utc).date().isoformat())
        self.assertTrue((self.root / 'CHANGELOG.md').read_text().startswith('# Changelog\n\n## 1.1.0 ('))
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.git('ls-remote', 'origin', 'refs/heads/main').split()[0])

    def test_kill_before_version_commit_resumes_without_appending_twice(self):
        self.commit('perf: Paint sooner')
        runner = self.automatic(); original = runner.git
        def killed(*args, **kwargs):
            if args[0] == 'update-ref': raise OSError('power lost before commit')
            return original(*args, **kwargs)
        with patch.object(runner, 'git', side_effect=killed):
            with self.assertRaises(OSError): runner.prepare()
        (self.root / 'CHANGELOG.md').write_text('someone else\n')
        with self.assertRaisesRegex(release.Failure, 'Unexpected local edits'): runner.prepare()
        self.assertEqual((self.root / 'CHANGELOG.md').read_text(), 'someone else\n')
        (self.root / 'CHANGELOG.md').write_text(runner.version_files(runner.state['base_commit'])['CHANGELOG.md'])
        runner.prepare()
        self.assertEqual([item['version'] for item in self.notes()], ['1.0.1'])
        self.assertEqual(self.git('log', '-1', '--format=%s'), 'chore(release): 1.0.1')

    def test_automatic_run_resumes_a_stopped_explicit_run(self):
        explicit = release.Release(self.root, 'major'); explicit.start(); explicit.prepare()
        explicit.checkpoint(status='stopped', stage='engine', completed=['source'], command_pid=None)
        for item in explicit.locks: item.close()
        with patch.object(release_lease, 'release') as released:
            resumed = self.automatic()
        released.assert_not_called()
        self.assertEqual((resumed.state['id'], resumed.kind), (explicit.state['id'], 'major'))
        self.assertEqual(resumed.state['version']['version'], '2.0.0')

    def test_commits_landing_before_the_push_ship_with_their_notes_and_bump(self):
        self.resume_after_a_kill_in_the_late_merge('push')

    def test_a_kill_while_merging_late_commits_resumes_without_git_cleanup(self):
        self.resume_after_a_kill_in_the_late_merge('merge')

    def test_unpushed_local_commits_are_never_released(self):
        (self.root / 'Resources/icon').write_bytes(b'local icon'); self.git('commit', '-qam', 'fix: Unpushed')
        with self.assertRaisesRegex(release.Failure, 'unpushed commits'):
            self.automatic().prepare()
        self.assertEqual(self.git('log', '-1', '--format=%s'), 'fix: Unpushed')

    def test_late_merge_refuses_to_drop_what_a_rewritten_main_lost(self):
        (self.root / 'Resources/icon').write_bytes(b'kept icon'); self.git('commit', '-qam', 'fix: Keep icon')
        self.git('push', 'origin', 'main')
        with self.assertRaisesRegex(release.Failure, 'changes main lacks'):
            self.race(self.automatic(), rewritten=True)
        self.assertEqual(json.loads(self.git('show', 'origin/main:app-version.json'))['version'], '1.0.0')

    def test_type_override_keeps_its_version_when_a_feat_lands_late(self):
        self.commit('fix: Keep tabs')
        runner = release.Release(self.root, 'patch'); runner.start()
        self.addCleanup(lambda: [item.close() for item in runner.locks])
        self.race(runner)
        self.assertEqual([item['version'] for item in self.notes()], ['1.0.1'])
        self.assertEqual((runner.state['release_type'], runner.state['tag']), ('patch', 'v1.0.1'))
        self.assertTrue(runner.published(runner.state['commit']))

    def test_resuming_with_type_keeps_its_version_when_a_feat_lands_late(self):
        self.commit('fix: Keep tabs')
        automatic = self.automatic(); original = automatic.git
        def killed(*args, **kwargs):
            if args[0] == 'push': raise OSError('power lost before the first push')
            return original(*args, **kwargs)
        with patch.object(automatic, 'git', side_effect=killed):
            with self.assertRaises(OSError): automatic.prepare()
        for item in automatic.locks: item.close()
        runner = release.Release(self.root, 'patch'); runner.start()
        self.addCleanup(lambda: [item.close() for item in runner.locks])
        self.race(runner)
        self.assertEqual((runner.state['id'], runner.state['tag']), (automatic.state['id'], 'v1.0.1'))
        self.assertEqual([item['version'] for item in self.notes()], ['1.0.1'])


class SharedCheckout(RepositoryFixture):
    RELEASE_FILES = ['CHANGELOG.md', 'app-version.json', 'release-notes.json']

    def setUp(self):
        super().setUp()
        self.write({'README.md': 'readme\n', 'docs/guide.md': 'guide\n', 'site/index.html': 'site\n',
                    '.github/workflows/site.yml': 'on: push\n', 'tests/Site/test_site.py': 'pass\n',
                    'Engine/README.md': 'engine notes\n', 'Engine/patch.diff': 'patch\n',
                    'Sources/App.swift': 'let app = 1\n', 'scripts/tool.py': 'print(1)\n',
                    '.githooks/pre-push': 'exit 0\n'})
        self.git('add', '.'); self.git('commit', '-m', 'docs: Seed shared files'); self.git('push', 'origin', 'main')

    def write(self, files, root=None):
        for name, text in files.items():
            path = (root or self.root) / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text)

    def read(self, name):
        path = self.root / name
        return path.read_text() if path.exists() else None

    def push_from_peer(self, files, message):
        peer = Path(self.tmp.name) / 'peer'
        subprocess.run(['git', 'clone', '-q', str(self.remote), str(peer)], check=True)
        self.write(files, peer)
        for command in (['add', '-A'], ['-c', 'user.name=Peer', '-c', 'user.email=peer@example.invalid', 'commit',
                                        '-qm', message], ['push', '-q', 'origin', 'main']):
            subprocess.run(['git', *command], cwd=peer, check=True, capture_output=True)

    def released(self, runner):
        self.assertEqual(sorted(self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').split()),
                         self.RELEASE_FILES)
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.git('rev-parse', 'origin/main'))
        self.assertEqual(self.git('rev-parse', 'HEAD'), runner.state['commit'])
        self.assertTrue(runner.state['source_frozen'])

    def restore(self, name, original, staged):
        if original is None:
            if staged: self.git('rm', '-q', '--cached', '--', name)
            (self.root / name).unlink()
        else:
            self.write({name: original})
            if staged: self.git('add', '--', name)

    def refused(self, pattern, make=None):
        head, remote = self.git('rev-parse', 'HEAD'), self.git('ls-remote', 'origin', 'refs/heads/main')
        runner = make() if make else release.Release(self.root, 'minor')
        try:
            runner.start()
            with self.assertRaisesRegex(release.Failure, pattern):
                runner.refresh_inputs() if make else runner.prepare()
        finally:
            for item in runner.locks: item.close()
        self.assertEqual((self.git('rev-parse', 'HEAD'), self.git('ls-remote', 'origin', 'refs/heads/main')),
                         (head, remote))
        return runner

    def test_docs_site_ci_tests_and_markdown_edits_never_block(self):
        self.push_from_peer({'Resources/icon': 'peer icon'}, 'fix: Brighten the icon')
        edits = {'README.md': 'readme draft\n', 'docs/guide.md': 'guide draft\n', 'docs/new.md': 'new page\n',
                 'site/index.html': 'site draft\n', 'site/media/hero.png': 'png', '.github/workflows/site.yml': 'on: pr\n',
                 'tests/Site/test_site.py': 'assert True\n', 'Engine/README.md': 'engine draft\n'}
        self.write(edits)
        self.git('add', 'docs/guide.md', 'docs/new.md', '.github/workflows/site.yml')
        (self.root / 'tests/Site/test_site.py').unlink(); del edits['tests/Site/test_site.py']
        staged, unstaged = self.git('diff', '--cached', '--name-only'), self.git('diff', '--name-only')
        runner = self.runner(); runner.prepare()
        self.released(runner)
        self.assertEqual(self.git('show', 'HEAD:Resources/icon'), 'peer icon')
        self.assertEqual({name: self.read(name) for name in edits}, edits)
        self.assertIsNone(self.read('tests/Site/test_site.py'))
        self.assertEqual((self.git('diff', '--cached', '--name-only'), self.git('diff', '--name-only')), (staged, unstaged))
        source = Path(runner.state['source'])
        self.assertEqual(((source / 'README.md').read_text(), (source / 'docs/new.md').exists()), ('readme\n', False))

    def test_local_edits_to_release_source_engine_script_or_hook_files_refuse(self):
        self.write({'README.md': 'allowed draft\n'})
        tracked = self.RELEASE_FILES + ['Sources/App.swift', 'Engine/patch.diff', 'scripts/tool.py',
                                        '.githooks/pre-push', 'Resources/icon']
        for name, staged in [(name, staged) for name in tracked for staged in (False, True)] + [('Sources/New.swift', True)]:
            with self.subTest(name=name, staged=staged):
                original = self.read(name)
                self.write({name: 'peer draft\n'})
                if staged: self.git('add', '--', name)
                failure = self.refused('^Start on clean main.*: ' + re.escape(name) + '$')
                self.assertNotIn('version', failure.state)
                self.assertEqual(self.read(name), 'peer draft\n')
                self.restore(name, original, staged)
        self.git('rm', '-q', '--cached', 'scripts/tool.py'); self.write({'scripts/tool.py': 'peer draft\n'})
        self.refused('^Start on clean main.*: scripts/tool\\.py$')
        self.write({'scripts/tool.py': 'print(1)\n'}); self.git('add', 'scripts/tool.py')
        self.assertEqual(self.git('status', '--porcelain', '--untracked-files=no'), 'M README.md')
        runner = self.runner(); runner.prepare()
        self.released(runner)

    def test_peer_work_staged_mid_release_never_joins_the_version_commit(self):
        runner = self.runner(); original = runner.checkpoint
        def peer_stages(**values):
            original(**values)
            if 'version' in values:
                self.write({'README.md': 'peer staged\n', 'docs/peer.md': 'peer page\n', 'site/index.html': 'peer\n'})
                self.git('add', 'README.md', 'docs/peer.md')
        with patch.object(runner, 'checkpoint', side_effect=peer_stages):
            runner.prepare()
        self.released(runner)
        self.assertEqual(self.git('show', 'origin/main:README.md'), 'readme')
        self.assertNotIn('docs/peer.md', self.git('ls-tree', '-r', '--name-only', 'origin/main').splitlines())
        self.assertEqual(self.git('diff', '--cached', '--name-only').splitlines(), ['README.md', 'docs/peer.md'])
        self.assertEqual(self.git('diff', '--name-only').splitlines(), ['site/index.html'])
        self.assertEqual((self.read('README.md'), self.read('docs/peer.md')), ('peer staged\n', 'peer page\n'))

    def test_a_source_edit_appearing_mid_release_stops_before_the_version_commit(self):
        runner = self.runner(); original = runner.checkpoint
        def peer_stages(**values):
            original(**values)
            if 'version' in values:
                self.write({'Sources/App.swift': 'peer source\n'}); self.git('add', 'Sources/App.swift')
        head = self.git('rev-parse', 'HEAD')
        with patch.object(runner, 'checkpoint', side_effect=peer_stages):
            with self.assertRaisesRegex(release.Failure, 'Unexpected local edits'): runner.prepare()
        self.assertEqual((self.git('rev-parse', 'HEAD'), self.git('rev-parse', 'origin/main')), (head, head))
        self.assertEqual(self.git('status', '--porcelain', '--untracked-files=no'), 'M  Sources/App.swift')
        self.assertNotIn('commit', runner.state)

    def test_fast_forward_onto_a_locally_edited_allowed_path_stops_without_touching_it(self):
        (self.root / '.git/info/exclude').write_text('site/generated.html\n')
        self.push_from_peer({'README.md': 'peer readme\n', 'docs/guide.md': 'peer guide\n',
                             'site/new.html': 'peer page\n', 'site/generated.html': 'peer generated\n'}, 'docs: Peer pages')
        self.write({'site/index.html': 'untouched draft\n'})
        for name, staged in (('README.md', False), ('docs/guide.md', True), ('site/new.html', False),
                             ('site/generated.html', False)):
            with self.subTest(name=name):
                original = self.read(name)
                self.write({name: 'local draft\n'})
                if staged: self.git('add', '--', name)
                self.refused('^Main moved under local edits to ' + re.escape(name) + ';')
                self.assertEqual((self.read(name), self.read('site/index.html')), ('local draft\n', 'untouched draft\n'))
                self.restore(name, original, staged)
        self.write({'site/generated.html': 'ignored but mine\n'})
        with patch.object(release.Release, 'local_changes', return_value={}), \
                patch.object(release.os.path, 'lexists', return_value=False), patch.object(release.time, 'sleep'):
            self.refused('^Git refused to fast-forward main')
        self.assertEqual(self.read('site/generated.html'), 'ignored but mine\n')
        (self.root / 'site/generated.html').unlink()
        runner = self.runner(); runner.prepare()
        self.released(runner)
        self.assertEqual((self.git('show', 'HEAD:README.md'), self.read('site/index.html')), ('peer readme', 'untouched draft\n'))

    def test_resume_after_a_kill_keeps_peer_edits_out_of_the_version_commit(self):
        self.commit('perf: Paint sooner')
        runner = self.automatic(); original = runner.git
        def killed(*args, **kwargs):
            if args[0] == 'update-ref': raise OSError('power lost before main moved')
            return original(*args, **kwargs)
        with patch.object(runner, 'git', side_effect=killed):
            with self.assertRaises(OSError): runner.prepare()
        for item in runner.locks: item.close()
        self.write({'README.md': 'peer staged\n', 'Sources/App.swift': 'peer source\n'}); self.git('add', 'README.md')
        resumed = self.automatic()
        with self.assertRaisesRegex(release.Failure, 'Unexpected local edits'): resumed.prepare()
        self.assertEqual(self.read('Sources/App.swift'), 'peer source\n')
        self.write({'Sources/App.swift': 'let app = 1\n'})
        resumed.prepare()
        self.released(resumed)
        self.assertEqual((resumed.state['id'], [item['version'] for item in self.notes()]), (runner.state['id'], ['1.0.1']))
        self.assertEqual(self.git('status', '--porcelain', '--untracked-files=no'), 'M  README.md')

    def test_source_refresh_tolerates_docs_edits_and_refuses_source_edits(self):
        self.stopped_patch_release(); self.commit('fix(engine): build with the new SDK')
        self.write({'Sources/App.swift': 'peer source\n', 'docs/guide.md': 'guide draft\n'})
        self.refused('^Source refresh requires clean main.*: Sources/App.swift$',
                     lambda: release.Release(self.root, refresh_source=True))
        self.write({'Sources/App.swift': 'let app = 1\n'})
        refreshed = self.refresh(); refreshed.refresh_inputs()
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.git('rev-parse', 'origin/main'))
        self.assertEqual(self.git('log', '-1', '--format=%s', 'HEAD'), 'chore(release): 1.0.1 notes')
        self.assertEqual(self.read('docs/guide.md'), 'guide draft\n')



class EngineWorkspaceChoice(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.runner = release.Release(self.base / "repo")
        self.source = self.base / "source"
        overlay = self.source / "Engine/ParcHost/overlay.json"
        overlay.parent.mkdir(parents=True)
        overlay.write_text('{"version": 1}')
        self.run = self.base / "run"
        self.run.mkdir()
        self.local = self.runner.root / "work/engine"
        self.home = self.base / "home"
        self.fallback = self.home / "ParcBuild/engine"

    def choose(self, registered, override=None, command=None):
        for workspace in registered:
            workspace.mkdir(parents=True, exist_ok=True)
            (workspace / ".parc-engine-source.json").write_text(json.dumps({
                "overlay": {"identity": release.sha(self.source / "Engine/ParcHost/overlay.json")}}))
        seal = self.run / "engine-artifacts.json"
        seal.write_text('{}')
        self.runner.state = {"run": str(self.run), "source": str(self.source)}
        self.runner.command = Mock(return_value="", side_effect=command)
        self.runner.git = Mock(return_value="")
        tool = Mock(SHIPPING_CONFIGURATION="shipping")
        tool.load_lock.return_value = ({}, "lock")
        with patch.dict(release.os.environ, {"PARC_ENGINE_WORKSPACE": str(override) if override else ""}), \
                patch.object(Path, "home", return_value=self.home), \
                patch.object(release, "module", return_value=tool), \
                patch.object(self.runner, "move_engine_to_lock", side_effect=lambda script, workspace, lock: workspace):
            self.runner.engine()
        return Path(self.runner.state["workspace"])

    def test_explicit_workspace_wins_over_registered_defaults(self):
        explicit = self.base / "explicit"
        self.assertEqual(self.choose([self.local, self.fallback, explicit], explicit), explicit)

    def test_checkout_workspace_wins_over_home_workspace(self):
        self.assertEqual(self.choose([self.local, self.fallback]), self.local)

    def test_home_workspace_is_used_when_checkout_workspace_is_unregistered(self):
        self.local.mkdir(parents=True)
        (self.local / "unowned").write_text("preserve")
        self.assertEqual(self.choose([self.fallback]), self.fallback)
        self.assertEqual((self.local / "unowned").read_text(), "preserve")

    def test_empty_defaults_start_at_checkout_workspace(self):
        def command(args, **kwargs):
            if "sync" in args:
                self.local.mkdir(parents=True)
                (self.local / ".parc-engine-source.json").write_text('{}')
            return ""
        self.assertEqual(self.choose([], command=command), self.local)
        self.assertEqual(self.runner.command.call_args_list[0].kwargs["name"], "engine-sync")


class InterruptedOverlayCheck(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.runner = release.Release(self.tmp.name, 'patch', refresh_source=True)
        self.addCleanup(lambda: [item.close() for item in self.runner.locks])
        run = self.runner.base / 'interrupted'
        self.prior = {
            'id': 'interrupted', 'run': str(run), 'source': str(run / 'source'),
            'status': 'running', 'stage': 'engine', 'release_type': 'patch',
            'completed': ['source'], 'version': {'version': '1.8.2', 'build': 22},
            'command_pid': 999999,
            'command': ['python3', str(run / 'source/scripts/engine-source.py'),
                        'overlay-check'],
        }
        release.save(self.runner.current, self.prior)

    def test_dead_check_or_tool_allows_refresh_without_claiming_success_or_bumping(self):
        restore = [release.sys.executable, str(self.runner.root / 'scripts/signing-backup.py'), 'restore']
        for command in (self.prior['command'], ['xcrun', 'notarytool', 'history'], restore,
                        ['brew', 'install', '--cask', '1password-cli']):
            with self.subTest(command=command):
                release.save(self.runner.current, dict(self.prior, command=command))
                with patch.object(release.os, 'kill', side_effect=ProcessLookupError), \
                     patch.object(release.os, 'killpg', side_effect=ProcessLookupError):
                    self.runner.start()
                self.assertEqual(self.runner.state['version'], self.prior['version'])
                self.assertEqual(self.runner.state['completed'], ['source'])
                self.assertIsNone(self.runner.state['command_pid'])
                self.assertIsNone(self.runner.state['last_command_exit'])
                self.assertEqual(self.runner.state['interrupted_command']['command'], command)
                for item in self.runner.locks: item.close()
                self.runner.locks.clear()

    def test_live_pid_or_surviving_group_refuses_refresh(self):
        for pid_error, group_error in ((None, ProcessLookupError),
                                       (ProcessLookupError, None),
                                       (PermissionError, ProcessLookupError)):
            with self.subTest(pid_error=pid_error, group_error=group_error):
                release.save(self.runner.current, self.prior)
                with patch.object(release.os, 'kill', side_effect=pid_error), \
                     patch.object(release.os, 'killpg', side_effect=group_error):
                    with self.assertRaises((release.Failure, PermissionError)):
                        self.runner.start()
                self.assertEqual(json.loads(self.runner.current.read_text())['command_pid'], 999999)
                for item in self.runner.locks: item.close()
                self.runner.locks.clear()

    def test_cancelled_shipping_build_awaiting_recovery_allows_refresh(self):
        Path(self.prior['run']).mkdir(parents=True, exist_ok=True)
        release.save(self.runner.current, dict(self.prior, status='stopped', command_pid=None,
                                               command=['git', 'fetch'], interrupted_process_group=999998))
        self.runner.start()
        self.assertEqual(self.runner.state['interrupted_process_group'], 999998)
        self.assertTrue(self.runner.state['interrupted_inputs_refreshed'])
        self.assertEqual(self.runner.state['completed'], ['source'])

    def test_dead_cancelled_shipping_build_hands_refresh_to_recovery(self):
        shipping = ['python3', self.prior['command'][1], 'shipping-build', '--workspace', '/Volumes/Parc']
        release.save(self.runner.current, dict(self.prior, status='stopped', command=shipping))
        with patch.object(release.os, 'kill', side_effect=ProcessLookupError), \
             patch.object(release.os, 'killpg', side_effect=ProcessLookupError):
            self.runner.start()
        self.assertIsNone(self.runner.state['command_pid'])
        self.assertEqual(self.runner.state['interrupted_process_group'], 999999)
        self.assertTrue(self.runner.state['interrupted_inputs_refreshed'])
        self.assertNotIn('interrupted_command', self.runner.state)
        self.assertEqual(self.runner.state['version'], self.prior['version'])

    def test_live_cancelled_shipping_build_still_refuses_refresh(self):
        shipping = ['python3', self.prior['command'][1], 'shipping-build']
        release.save(self.runner.current, dict(self.prior, status='stopped', command=shipping))
        with patch.object(release.os, 'kill'), patch.object(release.os, 'killpg', side_effect=ProcessLookupError):
            with self.assertRaisesRegex(release.Failure, 'still alive'):
                self.runner.start()
        saved = json.loads(self.runner.current.read_text())
        self.assertEqual(saved['command_pid'], 999999)
        self.assertNotIn('interrupted_process_group', saved)

    def test_mutating_or_foreign_command_keeps_existing_recovery_guard(self):
        for script, operation in ((self.prior['command'][1], 'overlay-apply'),
                                  ('/other/engine-source.py', 'shipping-build'),
                                  ('/other/engine-source.py', 'overlay-check')):
            with self.subTest(operation=operation, script=script):
                release.save(self.runner.current,
                             dict(self.prior, command=['python3', script, operation]))
                with patch.object(release.os, 'kill') as probe:
                    with self.assertRaisesRegex(release.Failure, 'stopped engine'):
                        self.runner.start()
                    probe.assert_not_called()
                self.assertEqual(json.loads(self.runner.current.read_text())['command_pid'], 999999)
                for item in self.runner.locks: item.close()
                self.runner.locks.clear()


class Pipeline(RepositoryFixture):
    def test_publish_then_immediate_install_and_resume_without_rebuild(self):
        calls = []
        runner = release.Release(self.root, 'minor')
        runner.preflight = Mock()
        runner.env["GH_TOKEN"] = "fixture-token"
        runner.finish = lambda: runner.checkpoint(status="complete")
        def prepare():
            calls.append('source')
            runner.checkpoint(commit=self.git('rev-parse','HEAD'), source=str(self.root), source_frozen=False, tag='v1.1.0')
        runner.prepare = prepare
        def engine():
            calls.append('engine'); manifest = Path(runner.state['run']) / 'engine.json'; manifest.write_text('{}')
            runner.checkpoint(manifest=str(manifest), manifest_sha256=release.sha(manifest))
        runner.engine = engine
        runner.package = lambda: calls.append('publish')
        def appcast():
            calls.append('appcast'); feed = Path(runner.state['run']) / 'appcast.xml'; feed.write_text('<rss/>')
            runner.checkpoint(appcast=str(feed), appcast_sha256=release.sha(feed))
        runner.appcast = appcast
        runner.install = Mock(side_effect=AssertionError('Release must never install or launch'))
        def fail_tap():
            calls.append('tap'); raise release.Failure('interrupted tap publication')
        runner.tap = fail_tap
        with patch.object(release_lease, 'acquire', return_value='lease'), patch.object(release_lease, 'release'):
            self.assertEqual(runner.run(), 1)
            runner.tap = lambda: calls.append('tap')
            with patch.object(release_inputs, 'verify'):
                self.assertEqual(runner.run(), 0)
        runner.install.assert_not_called()
        self.assertEqual(runner.state['completed'], ['source', 'engine', 'package', 'appcast', 'homebrew'])
        self.assertEqual(calls, ['source','engine','publish','appcast','tap','tap'])

    def test_appcast_rerun_signs_with_the_same_date_and_a_changed_feed_is_refused(self):
        runner = self.runner()
        runner.checkpoint(source=str(self.root), version={'version': '1.1.0', 'build': 2},
                          package=str(Path(runner.state['run']) / 'package/development'))
        commands = []
        def command(args, **kwargs):
            commands.append(args)
            Path(args[4]).write_text(' '.join(map(str, args[2:])))
        runner.command = command
        runner.appcast(); first = runner.state['appcast_sha256']
        runner.appcast()
        self.assertEqual(commands[0], commands[1])
        self.assertEqual(runner.state['appcast_sha256'], first)
        self.assertEqual(Path(commands[0][3]).name, 'Parc-1.1.0-arm64.zip')
        self.assertEqual(commands[0][5:], ['--published', runner.state['appcast_published']])
        Path(runner.state['appcast']).write_text('<rss>edited</rss>')
        manifest = Path(runner.state['run']) / 'engine.json'; manifest.write_text('{}')
        runner.checkpoint(completed=['source', 'engine', 'package', 'appcast'], commit=self.git('rev-parse', 'HEAD'),
                          manifest=str(manifest), manifest_sha256=release.sha(manifest))
        del runner.command
        for handle in runner.locks: handle.close()
        runner.locks.clear()
        runner.preflight = Mock(); runner.tap = Mock(); runner.env['GH_TOKEN'] = 'fixture-token'
        with patch.object(release_lease, 'acquire', return_value='lease'), patch.object(release_inputs, 'verify'):
            self.assertEqual(runner.run(), 1)
        runner.tap.assert_not_called()
        self.assertIn('Completed appcast changed', runner.state['error'])

    def test_finish_requires_the_public_latest_release_to_serve_this_appcast(self):
        runner = self.runner()
        runner.checkpoint(tag='v1.1.0', appcast_sha256='a' * 64)
        feed = {'name': 'appcast.xml', 'digest': 'sha256:' + 'a' * 64}
        for tag, assets, served in (('v1.1.0', [feed], True), ('v1.0.9', [feed], False),
                                    ('v1.1.0', [dict(feed, digest='sha256:' + 'b' * 64)], False), ('v1.1.0', [], False)):
            runner.github = Mock(return_value=json.dumps({'tag_name': tag, 'assets': assets}))
            with self.subTest(tag=tag, assets=assets):
                if served:
                    runner.verify_feed()
                else:
                    with self.assertRaisesRegex(release.Failure, "does not serve this release's appcast"):
                        runner.verify_feed()
                runner.github.assert_called_once_with('api', 'repos/etsenake/parc-releases/releases/latest')

    def test_preflight_restores_a_missing_sparkle_key_or_stops(self):
        home = Path(self.tmp.name); (home / '.config/parc').mkdir(parents=True)
        identity = 'Developer ID Application: Fixture (' + release.TEAM + ')'
        (home / '.config/parc/signing-identity').write_text(identity + '\n')
        op = '/usr/local/bin/op'
        for tool, has_identity, has_key, restored in ((op, True, False, True), (op, True, False, False),
                                                      (None, True, False, False), (op, False, True, True)):
            runner = self.runner(); runner.auth = Mock(); keychain = {'identity': has_identity, 'key': has_key}; commands = []
            def command(args, **kwargs):
                commands.append([str(arg) for arg in args])
                if commands[-1][-1] == 'restore':
                    keychain.update(identity=True, key=keychain['key'] or restored)
                found = 'find-identity' in commands[-1] and keychain['identity']
                return '1) ABC "' + identity + '"' if found else ''
            runner.command = command
            with self.subTest(op=tool, identity=has_identity, key=has_key, restored=restored), \
                    patch.object(Path, 'home', return_value=home), \
                    patch.object(release.platform, 'system', return_value='Darwin'), \
                    patch.object(release.platform, 'machine', return_value='arm64'), \
                    patch.object(release.shutil, 'which', side_effect=lambda name: tool if name == 'op' else '/opt/homebrew/bin/brew'), \
                    patch.object(release.sparkle, 'has_key', side_effect=lambda: keychain['key']), \
                    patch.object(release, 'metal_toolchain_ready', return_value=True):
                if restored:
                    runner.preflight()
                    self.assertEqual(runner.env['PARC_SIGN_IDENTITY'], identity)
                else:
                    with self.assertRaisesRegex(release.Failure, "Sparkle's update signing key"):
                        runner.preflight()
                restores = [args for args in commands if args[-1] == 'restore']
                self.assertEqual(len(restores), 1 if tool else 0)
            for handle in runner.locks: handle.close()

    def test_preflight_downloads_a_missing_metal_toolchain_or_stops_before_any_build(self):
        for downloads in (True, False):
            runner = self.runner(); runner.auth = Mock(); commands = []; toolchain = {'ready': False}
            def command(args, **kwargs):
                commands.append([str(arg) for arg in args])
                if commands[-1][:2] == ['xcodebuild', '-downloadComponent']:
                    toolchain['ready'] = downloads
                if 'find-identity' in commands[-1]:
                    raise release.Failure('stop after the toolchain check')
                return ''
            runner.command = command
            with self.subTest(downloads=downloads), \
                    patch.object(release.platform, 'system', return_value='Darwin'), \
                    patch.object(release.platform, 'machine', return_value='arm64'), \
                    patch.object(release.shutil, 'which', return_value='/opt/homebrew/bin/brew'), \
                    patch.object(release, 'metal_toolchain_ready', side_effect=lambda env: toolchain['ready']):
                expected = 'stop after the toolchain check' if downloads else 'xcodebuild -downloadComponent MetalToolchain'
                with self.assertRaisesRegex(release.Failure, expected):
                    runner.preflight()
                self.assertIn(['xcodebuild', '-downloadComponent', 'MetalToolchain'], commands)
                self.assertEqual(any('find-identity' in args for args in commands), downloads)
            for handle in runner.locks: handle.close()

    def test_preflight_names_the_xcode_setup_it_cannot_do_itself(self):
        runner = self.runner(); runner.auth = Mock()
        def command(args, **kwargs):
            if args == ['xcodebuild', '-checkFirstLaunchStatus']:
                raise release.Failure('Command failed (69)')
            return ''
        runner.command = command
        with patch.object(release.platform, 'system', return_value='Darwin'), \
                patch.object(release.platform, 'machine', return_value='arm64'), \
                patch.object(release.shutil, 'which', return_value='/opt/homebrew/bin/brew'), \
                self.assertRaisesRegex(release.Failure, 'sudo xcodebuild -runFirstLaunch'):
            runner.preflight()
        for handle in runner.locks: handle.close()

    def test_preflight_installs_a_missing_github_cli_before_logging_in(self):
        for installs in (True, False):
            runner = self.runner(); runner.auth = Mock(side_effect=release.Failure('stop after logging in'))
            tools = {'brew': '/opt/homebrew/bin/brew'}; commands = []
            def command(args, **kwargs):
                commands.append([str(arg) for arg in args])
                if commands[-1] == ['brew', 'install', 'gh'] and installs:
                    tools['gh'] = '/opt/homebrew/bin/gh'
                return ''
            runner.command = command
            with self.subTest(installs=installs), \
                    patch.object(release.platform, 'system', return_value='Darwin'), \
                    patch.object(release.platform, 'machine', return_value='arm64'), \
                    patch.object(release.shutil, 'which', side_effect=tools.get):
                with self.assertRaisesRegex(release.Failure, 'stop after logging in' if installs else 'GitHub CLI'):
                    runner.preflight()
                self.assertEqual(commands, [['brew', 'install', 'gh']])
                self.assertEqual(runner.auth.called, installs)
            for handle in runner.locks: handle.close()

    def test_metal_check_runs_the_compiler_not_the_placeholder_xcode_ships(self):
        with patch.object(release.subprocess, 'run', return_value=Mock(returncode=1)) as run:
            self.assertFalse(release.metal_toolchain_ready())
        self.assertEqual(run.call_args.args[0], ['xcrun', 'metal', '--version'])

    def test_preflight_restores_a_failing_notary_profile_or_stops(self):
        home = Path(self.tmp.name); (home / '.config/parc').mkdir(parents=True)
        identity = 'Developer ID Application: Fixture (' + release.TEAM + ')'
        (home / '.config/parc/signing-identity').write_text(identity + '\n')
        for tool, works, restored in (('/usr/local/bin/op', True, False), ('/usr/local/bin/op', False, True),
                                      ('/usr/local/bin/op', False, False), (None, False, True)):
            runner = self.runner(); runner.auth = Mock(); profile = {'works': works}; commands = []
            def command(args, **kwargs):
                commands.append([str(arg) for arg in args])
                if commands[-1][-1] == 'restore':
                    profile['works'] = restored
                if 'history' in commands[-1] and not profile['works']:
                    raise release.Failure('Command failed (69)')
                return '1) ABC "' + identity + '"' if 'find-identity' in commands[-1] else ''
            runner.command = command
            with self.subTest(op=tool, works=works, restored=restored), \
                    patch.object(Path, 'home', return_value=home), \
                    patch.object(release.platform, 'system', return_value='Darwin'), \
                    patch.object(release.platform, 'machine', return_value='arm64'), \
                    patch.object(release.shutil, 'which', side_effect=lambda name: tool if name == 'op' else '/opt/homebrew/bin/brew'), \
                    patch.object(release.sparkle, 'has_key', return_value=True), \
                    patch.object(release, 'metal_toolchain_ready', return_value=True):
                if works or (tool and restored):
                    runner.preflight()
                    self.assertEqual(runner.state['notary_profile'], 'parc-notary')
                else:
                    with self.assertRaisesRegex(release.Failure, 'notarytool profile parc-notary .* not restored'):
                        runner.preflight()
                histories = [args for args in commands if 'history' in args]
                self.assertEqual(len([args for args in commands if args[-1] == 'restore']), 0 if works or not tool else 1)
                self.assertEqual(len(histories), 1 if works or not tool else 2)
                self.assertTrue(all(args[args.index('--keychain-profile') + 1] == 'parc-notary' for args in histories))
            for handle in runner.locks: handle.close()

    def signing(self, keychain, tools, commands, profile=None):
        identity = 'Developer ID Application: Fixture (' + release.TEAM + ')'
        def command(args, **kwargs):
            commands.append([str(arg) for arg in args])
            if commands[-1] == ['brew', 'install', '--cask', '1password-cli']:
                if not keychain.get('installable', True):
                    raise release.Failure('Command failed (1)')
                tools['op'] = '/opt/homebrew/bin/op'
            if commands[-1][-1] == 'restore':
                keychain.update(identity=True, valid=True, key=True)
                if profile is not None:
                    profile['works'] = True
            if 'history' in commands[-1] and profile is not None and not profile['works']:
                raise release.Failure('Command failed (69)')
            if 'find-identity' in commands[-1] and keychain['identity']:
                if '-v' in commands[-1]:
                    return '1) ABC "' + identity + '"' if keychain['valid'] else '0 valid identities found'
                return '1) ABC "' + identity + '"' + ('' if keychain['valid'] else ' (CSSMERR_TP_NOT_TRUSTED)')
            return ''
        return identity, command

    def preflight_patches(self, home, keychain, tools):
        return (patch.object(Path, 'home', return_value=home),
                patch.object(release.platform, 'system', return_value='Darwin'),
                patch.object(release.platform, 'machine', return_value='arm64'),
                patch.object(release.shutil, 'which', side_effect=tools.get),
                patch.object(release.sparkle, 'has_key', side_effect=lambda: keychain['key']),
                patch.object(release, 'metal_toolchain_ready', return_value=True))

    def test_preflight_installs_the_1password_cli_before_restoring(self):
        home = Path(self.tmp.name)
        for installable, missing in ((True, 'key'), (False, 'key'), (True, 'profile'), (False, 'profile')):
            keychain = {'identity': True, 'valid': True, 'key': missing != 'key', 'installable': installable}
            profile = {'works': missing != 'profile'}
            tools = {'brew': '/opt/homebrew/bin/brew', 'gh': '/opt/homebrew/bin/gh'}; commands = []
            runner = self.runner(); runner.auth = Mock()
            identity, runner.command = self.signing(keychain, tools, commands, profile)
            with self.subTest(installable=installable, missing=missing), contextlib.ExitStack() as stack:
                for patcher in self.preflight_patches(home, keychain, tools):
                    stack.enter_context(patcher)
                if installable:
                    runner.preflight()
                    self.assertEqual(runner.env['PARC_SIGN_IDENTITY'], identity)
                else:
                    expected = "Sparkle's update signing key" if missing == 'key' else 'notarytool profile parc-notary'
                    with self.assertRaisesRegex(release.Failure, expected):
                        runner.preflight()
                install = commands.index(['brew', 'install', '--cask', '1password-cli'])
                restores = [index for index, args in enumerate(commands) if args[-1] == 'restore']
                self.assertEqual(len(restores), 1 if installable else 0)
                self.assertTrue(all(index > install for index in restores))
            for handle in runner.locks: handle.close()

    def test_preflight_installs_a_missing_developer_id_intermediate(self):
        home = Path(self.tmp.name)
        for completes, op in ((True, None), (False, '/opt/homebrew/bin/op'), (False, None)):
            keychain = {'identity': True, 'valid': False, 'key': True, 'installable': False}
            tools = {'brew': '/opt/homebrew/bin/brew', 'gh': '/opt/homebrew/bin/gh', 'op': op}; commands = []
            runner = self.runner(); runner.auth = Mock()
            identity, runner.command = self.signing(keychain, tools, commands)
            installs = []
            def install(identities, log):
                installs.append(identities)
                if not completes:
                    raise ValueError('Certificate operation failed: curl')
                keychain['valid'] = True
                return ['DeveloperIDG2CA.cer']
            with self.subTest(completes=completes, op=op), contextlib.ExitStack() as stack:
                for patcher in self.preflight_patches(home, keychain, tools):
                    stack.enter_context(patcher)
                stack.enter_context(patch.object(release.developer_id, 'install_intermediates', side_effect=install))
                if completes or op:
                    runner.preflight()
                    self.assertEqual(runner.env['PARC_SIGN_IDENTITY'], identity)
                else:
                    with self.assertRaisesRegex(release.Failure, 'unavailable or expired'):
                        runner.preflight()
                self.assertEqual(installs, [[identity]])
                self.assertEqual(len([args for args in commands if args[-1] == 'restore']), 1 if op and not completes else 0)
            for handle in runner.locks: handle.close()

    def test_tap_stage_hands_the_appcast_to_the_publisher(self):
        runner = self.runner()
        runner.checkpoint(source=str(self.root), tag='v1.1.0', version={'version': '1.1.0', 'build': 2},
                          appcast='/run/appcast.xml')
        (Path(self.tmp.name) / 'homebrew-tap').mkdir()
        commands = []
        def command(args, **kwargs):
            commands.append([str(arg) for arg in args])
            if 'ls-remote' in commands[-1]: return 'f' * 40 + '\trefs/heads/main'
            if 'rev-parse' in commands[-1]: return 'f' * 40
            return self.tmp.name if commands[-1][:2] == ['brew', '--repo'] else ''
        runner.command = command
        with patch.object(Path, 'home', return_value=Path(self.tmp.name)):
            runner.tap()
        publish = next(args for args in commands if args[1].endswith('publish-homebrew.py'))
        self.assertEqual(publish[2:], ['v1.1.0', '--tap', str(Path(self.tmp.name) / 'homebrew-tap'),
                                       '--artifact-only', '--resume', '--appcast', '/run/appcast.xml'])


class Install(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name); self.package = self.home / 'package'; self.package.mkdir()
        self.app = self.home / 'Applications/Parc.app'; self.app.mkdir(parents=True)
        (self.app / 'code').write_text('old')
        (self.package / 'Parc.app').mkdir(); (self.package / 'Parc.app/code').write_text('new')
        self.report = {'app_version': {'version':'1.1.0','build':2}}
        (self.package / 'package-report.json').write_text(json.dumps(self.report))
        self.profile = self.home / 'Library/Application Support/Parc'; self.profile.mkdir(parents=True)
        (self.profile / 'Cookies').write_bytes(b'encrypted personal data')
        self.receipts = self.home / 'receipts'
        self.check = Mock()
        def record(package, app, tag, commit, output, seconds):
            self.assertEqual((app / 'code').read_text(), 'new')
            self.assertEqual((self.profile / 'Cookies').read_bytes(), b'encrypted personal data')
            result = {'status':'passed'}; output.write_text(json.dumps(result)); return result
        self.check.record.side_effect = record
        self.addCleanup(patch.stopall)
        patch.object(Path, 'home', return_value=self.home).start()
        patch.object(release_install, 'checker', return_value=self.check).start()
        patch.object(release_install, 'stop_app').start()
        def command(args, **kwargs):
            if args[0] == 'ditto':
                src, dst = map(Path, args[1:]); shutil.copytree(src,dst) if src.is_dir() else shutil.copy2(src,dst)
            return subprocess.CompletedProcess(args, 0)
        patch.object(release_install.subprocess, 'run', side_effect=command).start()

    def test_fresh_replacement_preserves_profile_and_rollback_and_resumes(self):
        release_install.install(self.package,'v1.1.0','commit',self.receipts,self.app)
        self.assertEqual((self.receipts / 'previous-Parc.app/code').read_text(), 'old')
        self.assertEqual((self.receipts / 'profile-backup/Cookies').read_bytes(), b'encrypted personal data')
        release_install.install(self.package,'v1.1.0','commit',self.receipts,self.app)
        self.assertEqual(self.check.record.call_count,1)

    def test_failed_startup_is_not_retried(self):
        def fail(*args, **kwargs):
            output = args[4]; result={'status':'failed'}; output.write_text(json.dumps(result)); return result
        self.check.record.side_effect=fail
        with self.assertRaisesRegex(ValueError,'Startup observation'):
            release_install.install(self.package,'v1.1.0','commit',self.receipts,self.app)
        self.check.publisher.verify_acceptance.side_effect=ValueError('failed evidence')
        with self.assertRaisesRegex(ValueError,'failed evidence'):
            release_install.install(self.package,'v1.1.0','commit',self.receipts,self.app)
        self.assertEqual(self.check.record.call_count,1)

    def test_prelaunch_signature_failure_restores_previous_app(self):
        def verify(app, report, strict):
            if app == self.app and (app / 'code').read_text() == 'new': raise ValueError('bad signature')
        self.check.verify_installed.side_effect=verify
        with self.assertRaisesRegex(ValueError,'bad signature'):
            release_install.install(self.package,'v1.1.0','commit',self.receipts,self.app)
        self.assertEqual((self.app / 'code').read_text(),'old')
        self.check.record.assert_not_called()


class Launcher(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name); (self.base / 'scripts').mkdir()
        shutil.copy2(Path(release.__file__).with_name('release.sh'), self.base / 'scripts/release.sh')
        self.path, self.brew = self.base / 'path', self.base / 'brew'
        self.python(self.path / 'python3', (3, 9, 6))

    def python(self, path, version):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('#!/bin/sh\nif [ "$1" = -c ]; then exec "' + sys.executable + '" -c '
                        '"import sys; sys.version_info = ' + repr(version) + '; exec(sys.argv[1])" "$2"; fi\n'
                        'echo "$0 $*"\n')
        path.chmod(0o755)

    def launch(self):
        return subprocess.run(['/bin/bash', str(self.base / 'scripts/release.sh'), '--type', 'patch'],
                              env={'PATH': str(self.path) + ':/usr/bin:/bin', 'HOMEBREW_PREFIX': str(self.brew)},
                              capture_output=True, text=True)

    def test_finds_python_3_12_or_later_when_python3_is_older(self):
        for suitable in (self.brew / 'bin/python3.13', self.brew / 'opt/python@3.13/libexec/bin/python3'):
            with self.subTest(suitable=suitable):
                shutil.rmtree(self.brew, ignore_errors=True)
                self.python(self.brew / 'bin/python3.11', (3, 11, 9)); self.python(suitable, (3, 13, 1))
                launched = self.launch()
                self.assertEqual((launched.returncode, launched.stdout.strip()),
                                 (0, str(suitable) + ' ' + str(self.base / 'scripts/release.py') + ' --type patch'))

    def test_prefers_a_suitable_python3_on_path(self):
        self.python(self.path / 'python3', (3, 12, 0)); self.python(self.brew / 'bin/python3.13', (3, 13, 1))
        self.assertEqual(self.launch().stdout.split()[0], str(self.path / 'python3'))

    def test_stops_clearly_without_a_suitable_interpreter(self):
        self.python(self.brew / 'bin/python3.11', (3, 11, 9))
        launched = self.launch()
        self.assertEqual((launched.returncode, launched.stdout), (1, ''))
        self.assertIn('need Python 3.12 or later', launched.stderr)

    def test_release_py_refuses_an_older_interpreter_before_doing_anything(self):
        with patch.object(release.sys, 'version_info', (3, 9, 6)), patch.object(release, 'Release') as runner, \
                self.assertRaisesRegex(SystemExit, 'bash scripts/release.sh'):
            release.main()
        runner.assert_not_called()


class RemoteTransactions(unittest.TestCase):
    def test_foreign_lease_never_stolen(self):
        with patch.object(release_lease,'api',side_effect=[{'object':{'sha':'foreign'}},{'message':'{"owner":"other"}'}]) as api:
            with self.assertRaisesRegex(ValueError,'Another Mac'): release_lease.acquire('me','commit')
        self.assertEqual(api.call_count,2)

    def test_lease_creation_conflict_is_not_retried(self):
        with patch.object(release_lease,'api',side_effect=[RuntimeError('HTTP404'),{'sha':'mine'},RuntimeError('HTTP422')]) as api:
            with self.assertRaisesRegex(RuntimeError,'422'): release_lease.acquire('me','commit')
        self.assertEqual(api.call_count,3)

    def test_released_assets_are_immutable(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'app.zip'; path.write_bytes(b'package')
            value={'target_commitish':'commit','assets':[{'name':'app.zip','digest':'sha256:wrong'}]}
            with patch.object(release_assets.subprocess,'check_output',return_value=json.dumps(value)), patch.object(release_assets.subprocess,'run') as run:
                with self.assertRaisesRegex(ValueError,'differs'): release_assets.reconcile('v1.1.0','commit',[path])
                run.assert_not_called()


if __name__ == '__main__': unittest.main()
