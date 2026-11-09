#!/usr/bin/env python3
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
import release_notes as notes


def change(kind, summary, scope=None, breaking=False):
    return {'type': kind, 'scope': scope, 'summary': summary, 'breaking': breaking}


class Parse(unittest.TestCase):
    def test_subject_forms(self):
        self.assertEqual(notes.parse('feat(sidebar): Show Update Complete'),
                         change('feat', 'Show Update Complete', 'sidebar'))
        self.assertEqual(notes.parse('fix: Keep tabs\n\nBody text.'), change('fix', 'Keep tabs'))
        self.assertEqual(notes.parse('refactor(engine)!: Drop the old host'),
                         change('refactor', 'Drop the old host', 'engine', True))

    def test_breaking_footer(self):
        for footer in ('BREAKING CHANGE: profiles move', 'BREAKING-CHANGE: profiles move'):
            self.assertTrue(notes.parse('feat: Move profiles\n\n' + footer)['breaking'])
        self.assertFalse(notes.parse('feat: Move profiles\n\nMentions BREAKING CHANGE: inline')['breaking'])

    def test_unparseable_subjects(self):
        for subject in ('Release Parc 1.8.2', 'feature: Add', 'feat:missing space', 'feat(): Empty scope',
                        'feat(two words): Summary', 'Feat: Capitalised type', 'feat: ', '',
                        "Merge branch 'main'", 'Revert "feat: Add"'):
            self.assertIsNone(notes.parse(subject), subject)

    def test_hook_check(self):
        self.assertIsNone(notes.check('docs(ledger): Claim a family\n'))
        for undo in ('Revert "feat: Add"', 'Reapply "feat: Add"'):
            self.assertIsNone(notes.check(undo), undo)
        for merge in ("Merge branch 'main' into topic", "Merge tag 'v1.0.0'\n\nParc 1.0.0\n"):
            self.assertIsNone(notes.check(merge, merge=True), merge)
        self.assertEqual(notes.check("Merge tag 'v1.0.0'\n\nParc 1.0.0\n"), "Merge tag 'v1.0.0' [2 lines]")
        self.assertEqual(notes.check('Merge the sidebar work'), 'Merge the sidebar work')
        self.assertEqual(notes.check('Record monitored 1.8.2 release\n'), 'Record monitored 1.8.2 release')
        self.assertEqual(notes.check('fix: Keep tabs\n\nThe body.\n'), 'fix: Keep tabs [2 lines]')
        self.assertEqual(notes.check('fix: Keep tabs\n\nCo-Authored-By: A <a@example.invalid>\n'), 'fix: Keep tabs [2 lines]')
        self.assertEqual(notes.check('Revert "feat: Add"\n\nThis reverts commit abc.\n'), 'Revert "feat: Add" [2 lines]')
        self.assertEqual(notes.check('# Sidebar\n\nfix: Keep tabs\n'), '# Sidebar [2 lines]')
        self.assertEqual(notes.check('fixup! fix: Keep'), 'fixup! fix: Keep')
        self.assertEqual(notes.check(''), '(empty)')


class Bump(unittest.TestCase):
    def test_precedence(self):
        fix, feat, perf = change('fix', 'a'), change('feat', 'b'), change('perf', 'c')
        self.assertEqual(notes.bump([fix, feat, change('chore', 'd', breaking=True)]), 'major')
        self.assertEqual(notes.bump([fix, perf, feat]), 'minor')
        self.assertEqual(notes.bump([change('docs', 'd'), perf]), 'patch')
        self.assertEqual(notes.bump([fix]), 'patch')

    def test_nothing_to_release(self):
        self.assertIsNone(notes.bump([]))
        self.assertIsNone(notes.bump([change(kind, 'x') for kind in ('docs', 'chore', 'refactor', 'ci', 'test')]))


class Notes(unittest.TestCase):
    def test_entry_keeps_only_user_facing_changes_and_breaking_work(self):
        found = [change('feat', 'New'), change('chore', 'Tidy'), change('refactor', 'Move', breaking=True),
                 change('perf', 'Faster'), change('docs', 'Doc')]
        release = notes.entry('2.0.0', 9, '2026-11-10', found)
        self.assertEqual([item['summary'] for item in release['changes']], ['New', 'Move', 'Faster'])
        self.assertEqual(set(release), {'version', 'build', 'date', 'changes'})

    def test_sections_order_and_scopes(self):
        release = notes.entry('2.0.0', 9, '2026-11-10', [
            change('fix', 'Keep tabs', 'sidebar'), change('feat', 'Add Easels'), change('perf', 'Open faster'),
            change('feat', 'Move profiles', 'profiles', True), change('fix', 'Second fix')])
        self.assertEqual(notes.markdown(release), '\n'.join([
            '### Heads up', '', '- **profiles:** Move profiles', '',
            '### New', '', '- Add Easels', '',
            '### Fixed', '', '- **sidebar:** Keep tabs', '- Second fix', '',
            '### Faster', '', '- Open faster']))
        self.assertEqual(notes.markdown(notes.entry('1.0.1', 2, '2026-11-10', [])), '')

    def test_record_is_newest_first_idempotent_and_replaces_unshipped_versions(self):
        first = notes.entry('1.9.0', 10, '2026-11-10', [change('feat', 'A')])
        second = notes.entry('1.9.1', 11, '2026-11-11', [change('fix', 'B')])
        once = notes.record(notes.record({'releases': []}, first, '1.8.2'), second, '1.9.0')
        self.assertEqual([item['version'] for item in once['releases']], ['1.9.1', '1.9.0'])
        self.assertEqual(notes.record(once, second, '1.9.0'), once)
        # 1.9.1 was committed by a superseded run but never tagged; 1.10.0 covers its changes.
        third = notes.entry('1.10.0', 12, '2026-11-12', [change('fix', 'B'), change('feat', 'C')])
        self.assertEqual(notes.record(once, third, '1.9.0'), {'releases': [third, first]})

    def test_files_rerun_never_duplicates(self):
        release = notes.entry('1.9.0', 10, '2026-11-10', [change('feat', 'Show What’s New', 'updates')])
        once = notes.files({'releases': []}, release, '1.8.2')
        self.assertEqual(notes.files(json.loads(once['release-notes.json']), release, '1.8.2'), once)
        self.assertEqual(json.loads(once['release-notes.json']), {'releases': [release]})
        self.assertEqual(once['CHANGELOG.md'],
                         '# Changelog\n\n## 1.9.0 (2026-11-10)\n\n### New\n\n- **updates:** Show What’s New\n')
        quiet = notes.files({'releases': []}, notes.entry('1.9.1', 11, '2026-11-11', []), '1.9.0')
        self.assertIn('## 1.9.1 (2026-11-11)\n\nNo user-facing changes.\n', quiet['CHANGELOG.md'])

    def test_display_capitalizes_the_first_letter_and_storage_keeps_the_subject(self):
        subject = 'make Edit Theme… work from the command bar'
        release = notes.entry('1.9.0', 10, '2026-11-10', [change('fix', subject, 'command-bar')])
        once = notes.files({'releases': []}, release, '1.8.2')
        self.assertEqual(json.loads(once['release-notes.json'])['releases'][0]['changes'][0]['summary'], subject)
        self.assertIn('\n- **command-bar:** Make Edit Theme… work from the command bar\n', once['CHANGELOG.md'])
        self.assertEqual([notes.display(text) for text in ('', 'macOS menus stay put', 'iCloud tabs load')],
                         ['', 'macOS menus stay put', 'iCloud tabs load'])


class History(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.git('init', '-b', 'main'); self.git('config', 'core.hooksPath', '/dev/null')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'user.name', 'Fixture'); self.git('config', 'user.email', 'fixture@example.invalid')
        self.commit('Release Parc 1.0.0'); self.git('tag', 'v1.0.0')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.DEVNULL, text=True).strip()

    def commit(self, message):
        self.git('commit', '--allow-empty', '-m', message)

    def test_range_is_oldest_first_and_skips_merges_and_unparseable(self):
        self.commit('fix(tabs): Keep pinned tabs'); self.commit('Tidy up without a type')
        self.git('checkout', '-b', 'topic'); self.commit('perf: Paint sooner')
        self.git('checkout', 'main'); self.commit('feat: Add Easels')
        self.git('merge', '--no-ff', '-m', 'feat: Merge commit that must not count', 'topic')
        found = notes.changes(self.root, 'v1.0.0', 'HEAD')
        self.assertEqual(sorted(item['summary'] for item in found), ['Add Easels', 'Keep pinned tabs', 'Paint sooner'])
        self.assertEqual(found[0]['summary'], 'Keep pinned tabs')
        self.assertEqual(notes.bump(found), 'minor')

    def test_revert_in_range_cancels_and_reapply_restores(self):
        self.commit('feat(sidebar): Pin tabs\n\nBREAKING CHANGE: pins move'); self.commit('fix: Keep tabs')
        self.commit('Revert "feat(sidebar): Pin tabs"')
        self.assertEqual(notes.bump(notes.changes(self.root, 'v1.0.0', 'HEAD')), 'patch')
        self.commit('Reapply "feat(sidebar): Pin tabs"')
        found = notes.changes(self.root, 'v1.0.0', 'HEAD')
        self.assertEqual([item['summary'] for item in found], ['Keep tabs', 'Pin tabs'])
        self.assertEqual(notes.bump(found), 'major')
        self.commit('Revert "Reapply "feat(sidebar): Pin tabs""')
        self.assertEqual(notes.bump(notes.changes(self.root, 'v1.0.0', 'HEAD')), 'patch')

    def test_git_before_2_43_reverting_a_revert_reapplies(self):
        self.commit('feat: Pin tabs'); self.commit('Revert "feat: Pin tabs"')
        self.commit('Revert "Revert "feat: Pin tabs""')
        self.assertEqual([item['summary'] for item in notes.changes(self.root, 'v1.0.0', 'HEAD')], ['Pin tabs'])
        # git 2.43+ leaves a revert of that form nested, and either git may write it.
        self.commit('Revert "Revert "Revert "feat: Pin tabs"""')
        self.assertEqual(notes.changes(self.root, 'v1.0.0', 'HEAD'), [])

    def test_a_repeated_revert_keeps_the_change_to_reapply(self):
        self.commit('feat: Pin tabs'); self.commit('Revert "feat: Pin tabs"'); self.commit('Revert "feat: Pin tabs"')
        self.commit('Reapply "feat: Pin tabs"')
        self.assertEqual([item['summary'] for item in notes.changes(self.root, 'v1.0.0', 'HEAD')], ['Pin tabs'])

    def test_undoing_a_change_from_an_earlier_release(self):
        self.commit('feat: Pin tabs'); self.git('tag', 'v1.1.0')
        self.commit('Revert "feat: Pin tabs"'); self.commit('Revert "Revert "feat: Pin tabs""')
        self.assertEqual(notes.changes(self.root, 'v1.1.0', 'HEAD'), [])
        self.commit('Revert "Reapply "feat: Pin tabs""'); self.git('tag', 'v1.1.1')
        # Pin tabs was out of 1.1.1, so restoring it ships again whatever depth git wrote.
        self.commit('Reapply "Reapply "feat: Pin tabs""')
        self.assertEqual([item['summary'] for item in notes.changes(self.root, 'v1.1.1', 'HEAD')], ['Pin tabs'])

    def test_last_release_skips_untagged_versions(self):
        self.commit('chore(release): 1.0.1'); self.commit('feat: Add')
        self.assertEqual(notes.last_release(self.root, 'HEAD'), 'v1.0.0')
        self.git('tag', 'app-20261110-abc'); self.git('tag', 'v1.1.0')
        self.assertEqual(notes.last_release(self.root, 'HEAD'), 'v1.1.0')

    def test_nothing_since_tag(self):
        self.commit('docs: Explain releases'); self.commit('Unconventional history')
        self.assertIsNone(notes.bump(notes.changes(self.root, 'v1.0.0', 'HEAD')))


class Hooks(unittest.TestCase):
    """The tracked hooks in a real clone with an origin and a linked worktree; history predating the rule is on origin."""
    def setUp(self):
        source = Path(__file__).resolve().parents[2]
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        folder = Path(self.tmp.name)
        self.root, self.topic = folder / 'repo', folder / 'topic'
        (self.root / 'scripts').mkdir(parents=True)
        shutil.copytree(source / '.githooks', self.root / '.githooks')
        shutil.copy2(source / 'scripts/release_notes.py', self.root / 'scripts')
        self.git('init', '-b', 'main'); self.git('config', 'core.hooksPath', '/dev/null')
        self.git('config', 'user.name', 'Fixture'); self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'commit.gpgsign', 'false'); self.git('add', '-A')
        self.git('commit', '-m', 'Unconventional history from before the rule', '-m', 'With a body.')
        self.git('init', '--bare', str(folder / 'origin.git'))
        self.git('remote', 'add', 'origin', str(folder / 'origin.git')); self.git('push', 'origin', 'main')
        self.git('config', 'core.hooksPath', '.githooks')
        self.git('worktree', 'add', '-b', 'topic', str(self.topic))

    def git(self, *args, cwd=None):
        return subprocess.run(['git', *args], cwd=cwd or self.root, capture_output=True, text=True)

    def tree_commit(self, parent, *messages):
        """A commit made with commit-tree, which never runs commit-msg."""
        args = [part for message in messages for part in ('-m', message)]
        return self.git('commit-tree', 'HEAD^{tree}', '-p', parent, *args).stdout.strip()

    def short(self, commit):
        return self.git('rev-parse', '--short', commit).stdout.strip()

    def test_commit_msg_in_checkout_and_worktree(self):
        for cwd in (self.root, self.topic):
            rejected = self.git('commit', '--allow-empty', '-m', 'Tidy', cwd=cwd)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn('rejected: Tidy', rejected.stderr)
            self.assertIn('for example: fix(sidebar): Keep pinned tabs after a restart', rejected.stderr)
            body = self.git('commit', '--allow-empty', '-m', 'fix: Keep tabs', '-m', 'Because.', cwd=cwd)
            self.assertIn('rejected: fix: Keep tabs [2 lines]', body.stderr)
            trailer = self.git('commit', '--allow-empty', '-m', 'fix: Keep tabs',
                               '--trailer', 'Co-Authored-By: A <a@example.invalid>', cwd=cwd)
            self.assertIn('rejected: fix: Keep tabs [2 lines]', trailer.stderr)
            fake_merge = self.git('commit', '--allow-empty', '-m', 'Merge the sidebar work', '-m', 'Because.', cwd=cwd)
            self.assertIn('rejected: Merge the sidebar work [2 lines]', fake_merge.stderr)
        for number, comment in enumerate(('#', ';')):
            (self.topic / 'tabs').write_text(f'pinned {number}\n'); self.git('add', 'tabs', cwd=self.topic)
            edited = self.git('-c', 'core.editor=true', '-c', 'core.commentChar=' + comment,
                              'commit', '-v', '-e', '-m', 'fix: Keep tabs', cwd=self.topic)
            self.assertEqual(edited.returncode, 0, edited.stderr)
        self.assertEqual(self.git('revert', '--no-commit', 'HEAD', cwd=self.topic).returncode, 0)
        self.assertEqual(self.git('commit', '-m', 'Revert "fix: Keep tabs"', cwd=self.topic).returncode, 0)
        self.git('tag', '-a', 'v1.0.0', '-m', 'Parc 1.0.0', 'topic')
        merged = self.git('merge', '--no-ff', '--no-edit', 'v1.0.0')
        self.assertEqual(merged.returncode, 0, merged.stderr)
        self.assertEqual(self.git('log', '-1', '--format=%B').stdout.strip(), "Merge tag 'v1.0.0'\n\nParc 1.0.0")

    def test_pre_push_checks_only_commits_new_to_every_remote(self):
        first = self.git('rev-parse', 'HEAD').stdout.strip()
        good = self.tree_commit(first, 'fix: Keep tabs')
        self.assertEqual(self.git('push', 'origin', good + ':refs/heads/main').returncode, 0)
        bad = self.tree_commit(good, 'Tidy')
        later = self.tree_commit(bad, 'feat: Add Easels')
        refused = self.git('push', 'origin', later + ':refs/heads/main')
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn('Push refused; reword these commits and push again:\n  ' + self.short(bad) + ' Tidy\n', refused.stderr)
        self.assertNotIn(self.short(later), refused.stderr)
        self.assertIn('Commit messages are one line', refused.stderr)
        self.assertNotEqual(self.git('push', 'origin', bad + ':refs/heads/new').returncode, 0)
        self.assertEqual(self.git('push', 'origin', good + ':refs/heads/copy').returncode, 0)
        self.assertEqual(self.git('push', 'origin', ':refs/heads/copy').returncode, 0)
        forced = self.tree_commit(first, 'fix: Keep tabs', 'Co-Authored-By: A <a@example.invalid>')
        refused = self.git('push', '--force', 'origin', forced + ':refs/heads/main')
        self.assertIn('  ' + self.short(forced) + ' fix: Keep tabs [2 lines]\n', refused.stderr)
        self.assertEqual(self.git('ls-remote', 'origin', 'refs/heads/main').stdout.split()[0], good)
        fake_merge = self.tree_commit(good, 'Merge the sidebar work', 'Because.')
        self.assertIn(self.short(fake_merge) + ' Merge the sidebar work [2 lines]',
                      self.git('push', 'origin', fake_merge + ':refs/heads/main').stderr)
        merge = self.git('commit-tree', 'HEAD^{tree}', '-p', good, '-p', first,
                         '-m', "Merge branch 'topic'", '-m', 'Conflicts noted by git.').stdout.strip()
        self.assertEqual(self.git('push', 'origin', merge + ':refs/heads/main').returncode, 0)
        self.assertEqual(self.git('push', 'origin', 'origin/main^{/fix: Keep}:refs/heads/spaced').returncode, 0)

    def test_pre_push_reads_the_stored_message(self):
        kept = self.git('commit', '--allow-empty', '-m', '# Sidebar', '-m', 'fix: Keep tabs')
        self.assertEqual(kept.returncode, 0, kept.stderr)
        refused = self.git('push', 'origin', 'main')
        self.assertIn(self.short('main') + ' # Sidebar [2 lines]', refused.stderr)

    def test_pre_push_in_worktree_catches_gits_default_revert(self):
        (self.topic / 'tabs').write_text('pinned\n'); self.git('add', 'tabs', cwd=self.topic)
        self.assertEqual(self.git('commit', '-m', 'fix: Keep tabs', cwd=self.topic).returncode, 0)
        self.assertEqual(self.git('revert', '--no-edit', 'HEAD', cwd=self.topic).returncode, 0)
        refused = self.git('push', 'origin', 'topic', cwd=self.topic)
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn(self.short('topic') + ' Revert "fix: Keep tabs" [2 lines]', refused.stderr)
        self.git('reset', '--hard', 'HEAD~1', cwd=self.topic)
        self.git('revert', '--no-commit', 'HEAD', cwd=self.topic)
        self.assertEqual(self.git('commit', '-m', 'Revert "fix: Keep tabs"', cwd=self.topic).returncode, 0)
        pushed = self.git('push', 'origin', 'topic', cwd=self.topic)
        self.assertEqual(pushed.returncode, 0, pushed.stderr)


if __name__ == '__main__':
    unittest.main()
