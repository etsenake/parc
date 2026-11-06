#!/usr/bin/env python3
"""Exercise runtime output guards with the real production path validator.

Uses disposable filesystem fixtures only; never copies an engine or signs an app.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TEST_DIR = Path(__file__).resolve().parent
runtime = load("native_runtime_package", TEST_DIR / "package.py")
package = load("parc_package", TEST_DIR.parents[1] / "scripts/build.py")


class OutputGuardTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / "repo"
        self.engine = self.root / "engine"
        self.repo.mkdir()
        self.engine.mkdir()
        (self.repo / "build").mkdir()

    def output(self, parent):
        parent.mkdir(parents=True, exist_ok=True)
        return parent / "runtime-development"

    def check(self, output, engine=None):
        return runtime.validate_output(output, self.repo, engine or self.engine, package)

    def test_allows_fresh_ignored_build_output(self):
        output = self.output(self.repo / "build" / "runtime-test")
        self.assertEqual(self.check(output), output)
        self.assertFalse(output.exists())

    def test_allows_fresh_external_output(self):
        output = self.output(self.root / "external")
        self.assertEqual(self.check(output), output)

    def test_refuses_other_repository_subtrees(self):
        for name in ("Sources", "Engine", "Resources", "tests", "scripts", "build-other", ""):
            with self.subTest(name=name):
                with self.assertRaises(package.Refusal):
                    self.check(self.output(self.repo / name))

    def test_refuses_repository_ancestor(self):
        output = self.output(self.root / "ancestor")
        nested_repo = output / "repo"
        with self.assertRaises(package.Refusal):
            runtime.validate_output(output, nested_repo, self.engine, package)

    def test_refuses_engine_output(self):
        with self.assertRaises(package.Refusal):
            self.check(self.output(self.engine / "nested"))

    def test_refuses_engine_inside_build(self):
        engine = self.repo / "build" / "engine"
        with self.assertRaises(package.Refusal):
            self.check(self.output(engine / "nested"), engine)

    def test_refuses_engine_ancestor(self):
        output = self.output(self.repo / "build" / "runtime-test")
        with self.assertRaises(package.Refusal):
            self.check(output, output / "engine")

    def test_refuses_existing_directory_or_file_without_changing_it(self):
        output = self.output(self.repo / "build" / "existing")
        output.mkdir()
        marker = output / "marker"
        marker.write_text("preserve")
        with self.assertRaises(package.Refusal):
            self.check(output)
        self.assertEqual(marker.read_text(), "preserve")
        file_output = self.output(self.repo / "build" / "existing-file")
        file_output.write_text("preserve file")
        with self.assertRaises(package.Refusal):
            self.check(file_output)
        self.assertEqual(file_output.read_text(), "preserve file")

    def test_refuses_missing_parent_and_obsolete_app_output(self):
        with self.assertRaises(package.Refusal):
            self.check(self.repo / "build" / "absent" / "development")
        for name in (runtime.APP + ".app", "Other.app"):
            with self.assertRaisesRegex(package.Refusal, "fresh development directory, not an .app"):
                self.check(self.repo / "build" / name)

    def test_refuses_relative_and_parent_traversal(self):
        with self.assertRaises(package.Refusal):
            self.check(Path("build") / (runtime.APP + ".app"))
        with self.assertRaises(package.Refusal):
            self.check(self.repo / "build" / ".." / "build" / (runtime.APP + ".app"))

    def test_refuses_symlinked_parent(self):
        destination = self.root / "external"
        destination.mkdir()
        link = self.repo / "build" / "linked"
        link.symlink_to(destination, target_is_directory=True)
        with self.assertRaises(package.Refusal):
            self.check(link / (runtime.APP + ".app"))

    def test_refuses_existing_and_dangling_output_symlinks(self):
        for target in (self.engine, self.root / "absent"):
            with self.subTest(target=target):
                output = self.repo / "build" / (runtime.APP + ".app")
                output.symlink_to(target, target_is_directory=True)
                with self.assertRaises(package.Refusal):
                    self.check(output)
                output.unlink()


if __name__ == "__main__":
    unittest.main()
