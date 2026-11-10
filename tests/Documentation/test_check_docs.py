#!/usr/bin/env python3
"""Exercise documentation limits and pre-push enforcement in disposable repositories."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2]
CHECKER = SOURCE / "scripts/check-docs.py"


class Repository(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "core.hooksPath", "/dev/null")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "user.name", "Documentation fixture")
        self.git("config", "user.email", "fixture@example.invalid")

    def git(self, *args, check=True):
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True, check=check)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def commit(self, message="docs: Update documentation"):
        self.git("add", "-A")
        self.git("commit", "-m", message)
        return self.git("rev-parse", "HEAD").stdout.strip()

    def run_check(self, ref=None):
        args = [sys.executable, str(CHECKER), "--repo", str(self.root)]
        if ref:
            args.extend(["--ref", ref])
        return subprocess.run(args, capture_output=True, text=True)


class DocumentLimits(Repository):
    def test_exact_boundary_with_and_without_final_newline(self):
        for ending in ("", "\n", "\r\n"):
            with self.subTest(ending=repr(ending)):
                self.write("docs/nested/guide.MD", "\n".join(["line"] * 500) + ending)
                self.assertEqual(self.run_check().returncode, 0)
                self.write("docs/nested/guide.MD", "\n".join(["line"] * 501) + ending)
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("docs/nested/guide.MD: 501 lines (maximum 500)", result.stderr)

    def test_all_markdown_locations_case_and_new_files_are_checked(self):
        for name in ("AGENTS.md", "Engine/guide.md", "tests/README.Md",
                     ".cursor/rules/docs.MDC", "docs/guide.MARKDOWN"):
            self.write(name, "line\n" * 501)
        self.write("ordinary.py", "line\n" * 1000)
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr.count("501 lines"), 5)
        self.assertNotIn("ordinary.py", result.stderr)
        self.commit()
        result = self.run_check("HEAD")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr.count("501 lines"), 5)
        self.assertIn("docs/guide.MARKDOWN: 501 lines", result.stderr)

    def test_ignored_outputs_are_excluded_but_tracked_ignored_files_count(self):
        self.write(".gitignore", "/build/\n")
        self.write("build/untracked.md", "line\n" * 501)
        self.assertEqual(self.run_check().returncode, 0)
        self.git("add", "--force", "build/untracked.md")
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_changelogs_are_exempt_in_working_and_committed_trees(self):
        for name in ("CHANGELOG.md", "docs/Changelog.MARKDOWN"):
            self.write(name, "Release history\n" * 1200)
        self.assertEqual(self.run_check().returncode, 0)
        self.commit()
        self.assertEqual(self.run_check("HEAD").returncode, 0)
        self.write("docs/guide.md", "Guide\n" * 501)
        self.assertNotEqual(self.run_check().returncode, 0)
        self.commit()
        self.assertNotEqual(self.run_check("HEAD").returncode, 0)

    def test_missing_tracked_document_is_a_working_tree_deletion(self):
        path = self.write("README.md", "line\n" * 501)
        self.commit()
        path.unlink()
        self.assertEqual(self.run_check().returncode, 0)
        self.assertNotEqual(self.run_check("HEAD").returncode, 0)

    def test_committed_tree_does_not_read_working_file_or_new_untracked_docs(self):
        self.write("README.md", "Short guide.\n")
        good = self.commit()
        self.write("README.md", "line\n" * 501)
        bad = self.commit()
        self.write("README.md", "Short again.\n")
        self.assertEqual(self.run_check().returncode, 0)
        self.assertNotEqual(self.run_check(bad).returncode, 0)
        self.write("new.md", "line\n" * 501)
        self.assertEqual(self.run_check(good).returncode, 0)
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_annotated_tag_resolves_to_its_document_tree(self):
        self.write("README.md", "line\n" * 500)
        self.commit()
        self.git("tag", "-a", "v1", "-m", "fixture")
        self.assertEqual(self.run_check("v1").returncode, 0)

    def test_spaces_and_newlines_in_paths_survive_git_tree_reading(self):
        name = "docs/a space\nand newline.MDC"
        self.write(name, "line\n" * 501)
        self.commit()
        result = self.run_check("HEAD")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(name + ": 501 lines", result.stderr)

    def test_symlinks_cannot_bypass_the_limit(self):
        self.write("large.txt", "line\n" * 501)
        (self.root / "guide.md").symlink_to("large.txt")
        self.assertIn("regular files", self.run_check().stderr)
        self.commit()
        self.assertIn("regular files", self.run_check("HEAD").stderr)

    def test_invalid_ref_fails_instead_of_checking_current_files(self):
        self.write("README.md", "Short.\n")
        self.commit()
        result = self.run_check("no-such-ref")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Documentation check failed", result.stderr)


class PushLimits(Repository):
    def setUp(self):
        super().setUp()
        shutil.copytree(SOURCE / ".githooks", self.root / ".githooks")
        (self.root / "scripts").mkdir()
        for name in ("release_notes.py", "check-docs.py"):
            shutil.copy2(SOURCE / "scripts" / name, self.root / "scripts" / name)
        self.write("README.md", "Short guide.\n")
        self.base = self.commit()
        origin = Path(self.temp.name) / "origin.git"
        self.git("init", "--bare", str(origin))
        self.git("remote", "add", "origin", str(origin))
        self.git("push", "origin", "main")
        self.git("config", "core.hooksPath", ".githooks")

    def test_push_checks_the_requested_commit_not_shortened_working_copy(self):
        self.write("README.md", "line\n" * 501)
        bad = self.commit()
        self.write("README.md", "Short working copy.\n")
        result = self.git("push", "origin", bad + ":refs/heads/main", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("README.md: 501 lines", result.stderr)
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/main").stdout.split()[0], self.base)

    def test_good_push_ignores_oversized_working_changes(self):
        self.write("README.md", "Another short guide.\n")
        good = self.commit()
        self.write("README.md", "line\n" * 501)
        result = self.git("push", "origin", good + ":refs/heads/main", check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/main").stdout.split()[0], good)

    def test_all_pushed_refs_are_checked(self):
        self.write("README.md", "line\n" * 501)
        bad = self.commit()
        self.write("README.md", "Short now.\n")
        good = self.commit()
        result = self.git("push", "origin", good + ":refs/heads/good", bad + ":refs/heads/bad", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("README.md: 501 lines", result.stderr)
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/good", "refs/heads/bad").stdout, "")

    def test_deleting_a_remote_ref_does_not_check_the_checkout(self):
        self.git("push", "origin", self.base + ":refs/heads/remove")
        self.write("README.md", "line\n" * 501)
        result = self.git("push", "origin", ":refs/heads/remove", check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/remove").stdout, "")

    def test_conventional_commit_rejection_still_precedes_document_validation(self):
        bad = self.git("commit-tree", "HEAD^{tree}", "-p", self.base, "-m", "Unconventional message").stdout.strip()
        result = self.git("push", "origin", bad + ":refs/heads/main", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Push refused; reword these commits", result.stderr)
        self.assertIn("Unconventional message", result.stderr)
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/main").stdout.split()[0], self.base)


if __name__ == "__main__":
    unittest.main()
