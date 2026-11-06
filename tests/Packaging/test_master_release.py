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
        (self.root / 'Resources').mkdir(); (self.root / 'Resources/icon').write_bytes(b'icon')
        self.git('add', '.'); self.git('commit', '-m', 'Initial fixture')
        subprocess.run(['git', 'init', '--bare', str(self.remote)], capture_output=True, check=True)
        self.git('remote', 'add', 'origin', str(self.remote)); self.git('push', '-u', 'origin', 'main')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.DEVNULL, text=True).strip()

    def runner(self):
        runner = release.Release(self.root, 'minor'); runner.start()
        self.addCleanup(lambda: [item.close() for item in runner.locks])
        return runner

    def test_semantic_bumps(self):
        for kind, expected in [('major','2.0.0'),('minor','1.1.0'),('patch','1.0.1')]:
            self.assertEqual(release.next_version('1.0.0', kind), expected)

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
        def fail_install():
            calls.append('install'); raise release.Failure('interrupted install')
        runner.install = fail_install
        runner.tap = lambda: calls.append('tap')
        with patch.object(release_lease, 'acquire', return_value='lease'), patch.object(release_lease, 'release'):
            self.assertEqual(runner.run(), 1)
            runner.install = lambda: calls.append('install')
            with patch.object(release_inputs, 'verify'):
                self.assertEqual(runner.run(), 0)
        self.assertEqual(calls, ['source','engine','publish','install','install','tap'])


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
