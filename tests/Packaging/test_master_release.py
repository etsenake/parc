"""Inert release transactions: real disposable Git repos, fake Apple/Brew edges."""
import hashlib
import json
from pathlib import Path
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


class Repository(unittest.TestCase):
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

    def stopped_patch_release(self):
        """A 1.0.1 release of 'fix: Keep tabs' that stopped on a compiler error."""
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

    def test_refresh_lists_the_fixes_it_freezes_and_keeps_later_commits_out(self):
        self.stopped_patch_release()
        self.commit('fix(engine): build with the new SDK'); checked = self.git('rev-parse', 'HEAD')
        self.commit('feat: Later work'); later = self.git('rev-parse', 'HEAD')
        refreshed = self.refresh(checked)
        with patch.object(release_inputs, 'create', side_effect=OSError('power lost after publishing the notes')):
            with self.assertRaises(OSError): refreshed.refresh_inputs()
        for item in refreshed.locks: item.close()
        # A plain resume finishes the refresh instead of building the commit main has moved past.
        refreshed = release.Release(self.root); refreshed.preflight = Mock(); refreshed.env['GH_TOKEN'] = 'fixture-token'
        with patch.dict(release.os.environ), patch.object(release_lease, 'acquire', return_value='lease'):
            with patch.object(refreshed, 'engine', side_effect=release.Failure('compiler error again')):
                self.assertEqual(refreshed.run(), 1)
        self.assertIsNone(refreshed.state['refresh_commit'])
        notes = refreshed.state['commit']
        self.assertEqual(self.git('rev-parse', notes + '^'), checked)
        self.assertEqual(self.git('log', '-1', '--format=%s %P', 'origin/main'),
                         'Merge chore(release): 1.0.1 notes ' + later + ' ' + notes)
        # The rerun reused the published notes commit and merge.
        self.assertEqual(sorted(self.git('log', '--format=%s', checked + '..origin/main').splitlines()),
                         ['Merge chore(release): 1.0.1 notes', 'chore(release): 1.0.1 notes', 'feat: Later work'])
        self.assertTrue(subprocess.run(['git', 'merge-base', '--is-ancestor', later, notes], cwd=self.root).returncode)
        # The GitHub text and What's New page come from the frozen source's notes, which main shares.
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
        refreshed = self.refresh(); refreshed.refresh_inputs()
        self.assertEqual(self.git('rev-parse', 'origin/main'), refreshed.state['commit'])
        self.assertEqual(self.git('log', '-1', '--format=%s %P', 'origin/main'), 'chore(release): 1.0.1 notes ' + fixed)

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
        # The superseded 1.0.1 was committed but never tagged, so 1.1.0 replaces its notes.
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
        commit = self.git('rev-parse', 'HEAD'); runner.prepare()
        self.assertEqual(runner.state['commit'], commit)
        self.assertEqual(runner.state['version']['version'], '1.1.0')

    def test_dirty_main_is_preserved(self):
        runner = self.runner(); target = self.root / 'Resources/icon'; target.write_bytes(b'other owner')
        with self.assertRaisesRegex(release.Failure, 'clean main'): runner.prepare()
        self.assertEqual(target.read_bytes(), b'other owner')
        self.assertNotIn('version', runner.state)

    def test_nonblocking_lock_prevents_overlapping_run(self):
        first = self.runner(); second = release.Release(self.root, 'minor')
        with self.assertRaisesRegex(release.Failure, 'already active'): second.start()
        for item in second.locks: item.close()
        self.assertEqual(first.state['release_type'], 'minor')

    def commit(self, message):
        self.git('commit', '--allow-empty', '-m', message); self.git('push', 'origin', 'main')

    def automatic(self):
        runner = release.Release(self.root); runner.start()
        self.addCleanup(lambda: [item.close() for item in runner.locks])
        return runner

    def notes(self):
        return json.loads((self.root / 'release-notes.json').read_text())['releases']

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
            if args[0] == 'commit': raise OSError('power lost before commit')
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

    def race(self, runner, killed_after_merge=False):
        """Prepares while a peer pushes a feat just before the version commit's first push."""
        peer = Path(self.tmp.name) / 'peer'
        subprocess.run(['git', 'clone', '-q', str(self.remote), str(peer)], check=True)
        original = runner.git; pushes = []
        def racing(*args, **kwargs):
            if args[0] == 'push':
                pushes.append(args)
                if len(pushes) == 1:
                    # The peer's notes edit conflicts with the version commit's.
                    (peer / 'release-notes.json').write_text('{"releases":[]}\n')
                    for command in (['-c', 'user.name=Peer', '-c', 'user.email=peer@example.invalid', 'commit',
                                     '-qam', 'feat: Land late'], ['push', '-q', 'origin', 'main']):
                        subprocess.run(['git', *command], cwd=peer, check=True, capture_output=True)
                elif killed_after_merge:
                    raise OSError('power lost before the merged version commit was pushed')
            return original(*args, **kwargs)
        with patch.object(runner, 'git', side_effect=racing):
            runner.prepare()

    def test_commits_landing_before_the_push_ship_with_their_notes_and_bump(self):
        self.commit('fix: Keep tabs')
        runner = self.automatic()
        with self.assertRaises(OSError):
            self.race(runner, killed_after_merge=True)
        for item in runner.locks: item.close()
        resumed = self.automatic(); resumed.prepare()
        [entry] = self.notes()
        self.assertEqual((entry['version'], [item['summary'] for item in entry['changes']]),
                         ('1.1.0', ['Keep tabs', 'Land late']))
        self.assertEqual(len(self.git('log', '-1', '--format=%p').split()), 2)
        self.assertEqual(self.git('log', '-1', '--format=%s'), 'chore(release): 1.1.0')
        self.assertEqual(self.git('log', '--format=%s', 'v1.0.0..').count('chore(release): 1.1.0'), 1)
        self.assertEqual(json.loads(self.git('show', 'origin/main:app-version.json')), {'version': '1.1.0', 'build': 2})
        self.assertEqual((resumed.state['release_type'], resumed.state['tag']), ('minor', 'v1.1.0'))
        self.assertTrue(resumed.published(resumed.state['commit']))

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

    def test_dead_check_allows_refresh_without_claiming_success_or_bumping(self):
        with patch.object(release.os, 'kill', side_effect=ProcessLookupError), \
             patch.object(release.os, 'killpg', side_effect=ProcessLookupError):
            self.runner.start()
        self.assertEqual(self.runner.state['version'], self.prior['version'])
        self.assertEqual(self.runner.state['completed'], ['source'])
        self.assertIsNone(self.runner.state['command_pid'])
        self.assertIsNone(self.runner.state['last_command_exit'])
        self.assertEqual(self.runner.state['interrupted_overlay_check']['command'],
                         self.prior['command'])

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

    def test_mutating_or_foreign_command_keeps_existing_recovery_guard(self):
        for script, operation in ((self.prior['command'][1], 'shipping-build'),
                                  (self.prior['command'][1], 'overlay-apply'),
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


class Pipeline(Repository):
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
        # (op installed, identity present, key present, what restore brings back)
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
                    patch.object(release.sparkle, 'has_key', side_effect=lambda: keychain['key']):
                if restored:
                    runner.preflight()
                    self.assertEqual(runner.env['PARC_SIGN_IDENTITY'], identity)
                else:
                    with self.assertRaisesRegex(release.Failure, "Sparkle's update signing key"):
                        runner.preflight()
                restores = [args for args in commands if args[-1] == 'restore']
                self.assertEqual(len(restores), 1 if tool else 0)
            for handle in runner.locks: handle.close()

    def test_preflight_restores_a_failing_notary_profile_or_stops(self):
        home = Path(self.tmp.name); (home / '.config/parc').mkdir(parents=True)
        identity = 'Developer ID Application: Fixture (' + release.TEAM + ')'
        (home / '.config/parc/signing-identity').write_text(identity + '\n')
        # (op installed, profile works, what restore brings back)
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
                    patch.object(release.sparkle, 'has_key', return_value=True):
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
