#!/usr/bin/env python3
import json
from pathlib import Path
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
        self.assertIsNone(notes.check('# Please enter the commit message\n\nci: Run tests\n'))
        for generated in ("Merge branch 'main' into topic", 'Revert "feat: Add"', 'Reapply "feat: Add"', 'fixup! feat: Add',
                          'squash! fix: Keep', 'amend! fix: Keep'):
            self.assertIsNone(notes.check(generated), generated)
        error = notes.check('Record monitored 1.8.2 release\n')
        self.assertIn('type(scope)!: summary', error)
        self.assertIn('rejected: Record monitored 1.8.2 release', error)
        self.assertIn('rejected: (empty)', notes.check('# only comments\n'))


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

    def test_last_release_skips_untagged_versions(self):
        self.commit('chore(release): 1.0.1'); self.commit('feat: Add')
        self.assertEqual(notes.last_release(self.root, 'HEAD'), 'v1.0.0')
        self.git('tag', 'app-20261110-abc'); self.git('tag', 'v1.1.0')
        self.assertEqual(notes.last_release(self.root, 'HEAD'), 'v1.1.0')

    def test_nothing_since_tag(self):
        self.commit('docs: Explain releases'); self.commit('Unconventional history')
        self.assertIsNone(notes.bump(notes.changes(self.root, 'v1.0.0', 'HEAD')))


if __name__ == '__main__':
    unittest.main()
