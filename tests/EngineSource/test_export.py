import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from test_engine_source import engine, ROOT

spec = importlib.util.spec_from_file_location("overlay_export", ROOT / "scripts/engine-overlay-export.py")
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class ExportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.inputs = self.root / "inputs"
        self.inputs.mkdir()
        self.output = self.root / "export"
        self.manifest = self.inputs / "overlay.json"
        self.lock, _ = engine.load_lock()
        self.before = b"// shared context\nold\n"
        self.after = b"// shared context\nnew\n"
        self.owned = b"// owned source\n"
        self.spec = dict(schema_version=1, id="parc-export-fixture", version=660,
                         upstream={"chromium": self.lock["chromium"]["commit"]},
                         build_targets=["//parc:fixture"], files=[], patches=[])
        data = exporter.contextual_diff("chrome/test.cc", self.before, self.after)
        (self.inputs / "test.patch").write_bytes(data)
        self.spec["patches"].append(dict(source="test.patch", sha256=engine.digest(data), files=[
            dict(target="chrome/test.cc", before_sha256=engine.digest(self.before), after_sha256=engine.digest(self.after))]))
        (self.inputs / "owned.cc").write_bytes(self.owned)
        self.spec["files"].append(dict(source="owned.cc", target="parc/owned.cc", sha256=engine.digest(self.owned)))
        self.save()
        self.blobs = {"before": self.before, "after": self.after, "owned": self.owned, "plain": b"unchanged\n"}
        self.context = patch.object(exporter, "git", side_effect=self.git)
        self.context.start()
        self.addCleanup(self.context.stop)
        self.branch = exporter.Branch(self.root / "chromium", "base", "branch")

    def git(self, repository, *args):
        if args == ("rev-parse", "--show-toplevel"):
            return str(repository).encode() + b"\n"
        if args[0] == "rev-parse":
            return (self.lock["chromium"]["commit"] if args[-1] == "base^{commit}" else "b" * 40).encode() + b"\n"
        if args[0] == "merge-base":
            return b""
        if args[0] == "ls-tree":
            before = args[-1] == self.lock["chromium"]["commit"]
            tree = {"chrome/test.cc": ("100644", "before" if before else "after"),
                    "chrome/plain.cc": ("100644", "plain")}
            if not before:
                tree["parc/owned.cc"] = ("100644", "owned")
            return b"".join(f"{mode} blob {oid}\t{path}\0".encode() for path, (mode, oid) in tree.items())
        if args[0] == "cat-file":
            data = self.blobs[args[-1]]
            return str(len(data)).encode() if args[1] == "-s" else data
        self.fail(f"Unexpected command: {args}")

    def save(self):
        self.manifest.write_text(json.dumps(self.spec) + "\n")

    def call(self, **kwargs):
        return exporter.export(self.manifest, self.lock, kwargs.get("branches", {"": self.branch}),
                               kwargs.get("output", self.output))

    def refused(self, message):
        with self.assertRaisesRegex(exporter.Refusal, message):
            self.call()
        self.assertFalse(self.output.exists())

    def snapshot(self, root):
        return {str(p.relative_to(root)): (p.read_bytes(), p.stat().st_mode & 0o777)
                for p in root.rglob("*") if p.is_file()}

    def test_export_is_deterministic_and_keeps_review_identity(self):
        original = self.snapshot(self.inputs)
        report = self.call()
        self.assertTrue(report["equivalent"])
        other = self.root / "second"
        self.call(output=other)
        self.assertEqual(self.snapshot(self.output), self.snapshot(other))
        candidate = json.loads((self.output / "overlay.json").read_bytes())
        self.assertEqual(candidate["version"], 660)
        self.assertEqual(candidate["build_targets"], self.spec["build_targets"])
        self.assertEqual(self.snapshot(self.inputs), original)

    def test_uninventoried_branch_change_fails_equivalence(self):
        self.branch.after["chrome/plain.cc"] = ("100644", "blob", "after")
        self.refused("differs.*chrome/plain.cc")

    def test_byte_and_mode_mismatches_fail_equivalence(self):
        for entry in [("100644", "blob", "before"), ("100755", "blob", "after")]:
            with self.subTest(entry=entry):
                self.branch.after["chrome/test.cc"] = entry
                self.refused("differs.*chrome/test.cc")

    def test_new_executable_and_deleted_file_are_not_exportable(self):
        self.branch.after["parc/owned.cc"] = ("100755", "blob", "owned")
        self.refused("differs.*parc/owned.cc")
        self.branch.after["parc/owned.cc"] = ("100644", "blob", "owned")
        del self.branch.after["chrome/plain.cc"]
        self.refused("differs.*chrome/plain.cc")

    def test_current_manifest_validation_is_reused(self):
        for mutation in ("input", "before", "after", "duplicate", "pin"):
            original = copy.deepcopy(self.spec)
            if mutation == "input":
                self.spec["patches"][0]["sha256"] = "0" * 64
            elif mutation in {"before", "after"}:
                self.spec["patches"][0]["files"][0][mutation + "_sha256"] = "0" * 64
            elif mutation == "duplicate":
                self.spec["files"].append(copy.deepcopy(self.spec["files"][0]))
            else:
                self.spec["upstream"]["chromium"] = "0" * 40
            self.save()
            self.refused("digest|Duplicate|commits")
            self.spec = original
        self.save()

    def test_wrong_base_and_unsupported_objects_are_refused(self):
        self.branch.base = "0" * 40
        self.refused("pinned")
        self.branch.base = self.lock["chromium"]["commit"]
        for mode, kind in [("120000", "blob"), ("160000", "commit")]:
            self.branch.after["parc/owned.cc"] = (mode, kind, "owned")
            self.refused("Unsupported Git")

    def test_binary_invalid_utf8_and_oversized_sources_fail(self):
        for data, error in [(b"nul\0", exporter.Refusal), (b"\xff", UnicodeError),
                            (b"x" * (8 * 1024 * 1024 + 1), exporter.Refusal)]:
            self.blobs["owned"] = data
            with self.assertRaises(error):
                self.call()
            self.assertFalse(self.output.exists())

    def test_unsafe_targets_and_output_paths_are_refused(self):
        self.branch.after["DEPS"] = ("100644", "blob", "owned")
        self.refused("bootstrap")
        del self.branch.after["DEPS"]
        self.output.mkdir()
        with self.assertRaises(FileExistsError):
            self.call()
        self.output.rmdir()
        self.output.symlink_to(self.inputs, target_is_directory=True)
        with self.assertRaisesRegex(exporter.Refusal, "non-symlink"):
            self.call()

    def test_existing_executable_mode_is_preserved(self):
        self.branch.before["chrome/test.cc"] = ("100755", "blob", "before")
        self.branch.after["chrome/test.cc"] = ("100755", "blob", "after")
        self.assertTrue(self.call()["equivalent"])

    def test_missing_newline_roundtrips_and_contextless_rewrite_refuses(self):
        for before, after in [(b"context\nold", b"context\nnew"), (b"context\nold\n", b"context\nnew"),
                              (b"context\nold", b"context\nnew\n")]:
            data = exporter.contextual_diff("file.cc", before, after)
            self.assertEqual(engine.apply_context_patch(data.decode(), {"file.cc": before}), {"file.cc": after})
        with self.assertRaisesRegex(exporter.Refusal, "context"):
            exporter.contextual_diff("file.cc", b"old\n", b"new\n")

    def test_explicit_dependency_tree_uses_same_validator(self):
        dependency = copy.copy(self.branch)
        dependency.before = {name.removeprefix("chrome/"): entry for name, entry in self.branch.before.items() if name.startswith("chrome/")}
        dependency.after = {name.removeprefix("chrome/"): entry for name, entry in self.branch.after.items() if name.startswith("chrome/")}
        dependency.repository = self.root / "dependency"
        self.branch.before = {name: entry for name, entry in self.branch.before.items() if not name.startswith("chrome/")}
        self.branch.after = {name: entry for name, entry in self.branch.after.items() if not name.startswith("chrome/")}
        self.assertTrue(self.call(branches={"": self.branch, "chrome": dependency})["equivalent"])

    def test_dependency_cannot_shadow_tracked_parent_source(self):
        overlap = {"": self.branch, "chrome": self.branch}
        overlap["chrome"] = copy.copy(self.branch)
        with self.assertRaisesRegex(exporter.Refusal, "Overlapping"):
            self.call(branches=overlap)

    def test_repository_root_manifest_and_separate_output(self):
        self.spec["source_root"] = "repository"
        self.save()
        with patch.object(exporter.engine, "REPO", self.inputs):
            self.assertTrue(self.call()["equivalent"])
            with self.assertRaisesRegex(exporter.Refusal, "separate"):
                self.call(output=self.branch.repository / "review")

    def test_git_reads_cannot_lazy_fetch_or_prompt(self):
        self.context.stop()
        with patch.object(exporter.subprocess, "run") as run:
            exporter.git(self.root, "cat-file", "blob", "a" * 40)
        self.assertEqual(run.call_args.kwargs["env"]["GIT_NO_LAZY_FETCH"], "1")
        self.assertEqual(run.call_args.kwargs["env"]["GIT_TERMINAL_PROMPT"], "0")
        self.assertIn("--no-replace-objects", run.call_args.args[0])

    def test_patch_size_tracks_changed_lines(self):
        before = b"".join(f"// source line {i}\n".encode() for i in range(20000))
        after = before.replace(b"// source line 10000\n", b"// revised line 10000\n")
        data = exporter.contextual_diff("large.cc", before, after)
        self.assertLess(len(data), 1000)

    def test_manifest_change_during_export_is_refused(self):
        prepare = exporter.engine.prepare_overlay
        def changed(*args, **kwargs):
            result = prepare(*args, **kwargs)
            result[0]["identity"] = "0" * 64
            return result
        with patch.object(exporter.engine, "prepare_overlay", side_effect=changed):
            self.refused("Manifest changed")

    def test_git_reads_resolve_refs_and_enforce_ancestry(self):
        calls = []
        def nonancestor(repository, *args):
            calls.append(args)
            if args[0] == "merge-base":
                raise exporter.subprocess.CalledProcessError(1, "git")
            return self.git(repository, *args)
        with patch.object(exporter, "git", side_effect=nonancestor):
            with self.assertRaises(exporter.subprocess.CalledProcessError):
                exporter.Branch(self.root, "base", "branch")
        self.assertTrue(any(args[:2] == ("merge-base", "--is-ancestor") for args in calls))
        self.assertFalse(any(args[0] == "ls-tree" for args in calls))

    def test_dependency_base_is_bound_to_gitlink(self):
        dependency = copy.copy(self.branch)
        self.branch.before["third_party/dependency"] = ("160000", "commit", "0" * 40)
        self.branch.after["third_party/dependency"] = self.branch.before["third_party/dependency"]
        with self.assertRaisesRegex(exporter.Refusal, "pinned gitlink"):
            self.call(branches={"": self.branch, "third_party/dependency": dependency})

    def test_non_root_repository_is_refused(self):
        def enclosing(repository, *args):
            return str(repository.parent).encode() if args == ("rev-parse", "--show-toplevel") else self.git(repository, *args)
        with patch.object(exporter, "git", side_effect=enclosing):
            with self.assertRaisesRegex(exporter.Refusal, "repository root"):
                exporter.Branch(self.root, "base", "branch")

    def test_output_parent_traversal_and_case_aliases_are_refused(self):
        for output in (self.root / "other/../chromium/review", self.branch.repository.parent / "CHROMIUM/review"):
            with self.subTest(output=output), self.assertRaisesRegex(exporter.Refusal, "non-symlink|separate"):
                self.call(output=output)
            self.assertFalse(output.exists())

    def test_failed_publication_removes_empty_claim(self):
        with patch.object(exporter.os, "replace", side_effect=OSError("fixture failure")):
            with self.assertRaisesRegex(OSError, "fixture failure"):
                self.call()
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob(".parc-export-*")))

    def test_empty_residual_obeys_existing_validator(self):
        self.branch.after = dict(self.branch.before)
        self.spec["files"] = []
        self.spec["patches"][0]["files"][0]["after_sha256"] = engine.digest(self.before)
        no_op = b"--- a/chrome/test.cc\n+++ b/chrome/test.cc\n@@ -1,2 +1,2 @@\n // shared context\n old\n"
        (self.inputs / "test.patch").write_bytes(no_op)
        self.spec["patches"][0]["sha256"] = engine.digest(no_op)
        self.save()
        self.refused("Empty source overlay")

    def test_cli_rejects_malformed_and_duplicate_dependencies(self):
        import contextlib
        import io
        arguments = ["--repository", str(self.branch.repository), "--branch", "branch",
                     "--manifest", str(self.manifest), "--output", str(self.output)]
        for values in (["missing"], ["third_party/dep=base"],
                       ["third_party/dep=base..branch", "third_party/dep=base..branch"]):
            with self.subTest(values=values), contextlib.redirect_stderr(io.StringIO()):
                extra = [arg for value in values for arg in ("--dependency", value)]
                self.assertEqual(exporter.main(arguments + extra), 2)
            self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
