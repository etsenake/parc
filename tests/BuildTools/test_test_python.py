from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/test-python.py"


class ParallelRunnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name) / "suite"
        self.folder.mkdir()
        (self.folder / "helper.py").write_text("VALUE = 3\n")
        (self.folder / "test_plain.py").write_text(textwrap.dedent("""
            import unittest
            import helper

            class Plain(unittest.TestCase):
                def test_imports_sibling_module(self):
                    self.assertEqual(helper.VALUE, 3)

                def test_second(self):
                    pass

                @unittest.skip("fixture skip")
                def test_skipped(self):
                    pass
        """))
        (self.folder / "test_fixture.py").write_text(textwrap.dedent("""
            import unittest

            class Shared(unittest.TestCase):
                @classmethod
                def setUpClass(cls):
                    cls.calls = getattr(cls, "calls", 0) + 1

                def test_one(self):
                    self.assertEqual(self.calls, 1)

                def test_two(self):
                    self.assertEqual(self.calls, 1)
        """))

    def run_runner(self, *extra):
        return subprocess.run([sys.executable, SCRIPT, self.folder, "--jobs", "3", *extra],
                              capture_output=True, text=True, timeout=120)

    def test_passing_folder_reports_every_test_and_keeps_class_fixtures_together(self):
        result = self.run_runner("--durations", "2")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Ran 5 tests", result.stdout)
        self.assertIn("OK (skipped=1)", result.stdout)
        self.assertIn("test_fixture.Shared", result.stdout)

    def test_tests_compile_through_the_warning_shim(self):
        (self.folder / "test_path.py").write_text(textwrap.dedent(f"""
            import shutil
            import unittest

            class Compilers(unittest.TestCase):
                def test_xcrun_is_the_shim(self):
                    self.assertEqual(shutil.which("xcrun"), {str(SCRIPT.parents[1] / "tests/Support/compilers/xcrun")!r})
        """))
        result = self.run_runner()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Ran 6 tests", result.stdout)

    def test_failure_and_import_error_fail_the_run_with_details(self):
        (self.folder / "test_broken.py").write_text(textwrap.dedent("""
            import unittest

            class Broken(unittest.TestCase):
                def test_wrong(self):
                    self.assertEqual(1, 2)
        """))
        (self.folder / "test_unimportable.py").write_text("import missing_module_for_fixture\n")
        result = self.run_runner()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("FAIL: test_wrong", result.stdout)
        self.assertIn("missing_module_for_fixture", result.stdout)
        self.assertIn("FAILED (problems=2, skipped=1)", result.stdout)


if __name__ == "__main__":
    unittest.main()
