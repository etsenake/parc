import copy
import contextlib
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from test_engine_source import engine


class OverlayTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.workspace = self.base / "engine"
        self.root = self.workspace / "chromium/src"
        (self.root / "parc").mkdir(parents=True)
        (self.workspace / ".parc-operation.lock").touch()
        self.inputs = self.base / "reviewed"
        self.inputs.mkdir()
        self.manifest = self.inputs / "overlay.json"
        self.lock, self.sha = engine.load_lock()
        self.state = {"schema_version": 1, "workspace": str(self.workspace),
                      "lock_sha256": self.sha, "phase": "synced", "symbol_level": 0,
                      "source_fingerprint": "baseline", "repositories": ["chromium/src"]}
        engine.write_marker(self.workspace, self.state)
        self.before = b"group(\"parc\") {\n  deps = []\n}\n"
        self.after = b"group(\"parc\") {\n  deps = [ \":parc_fixture\" ]\n}\n"
        self.target = self.root / "parc/BUILD.gn"
        self.target.write_bytes(self.before)
        self.spec = {"schema_version": 1, "id": "parc-native-host", "version": 1,
                     "upstream": {n: self.lock[n]["commit"] for n in ("chromium",)},
                     "build_targets": ["//parc:parc_fixture"], "files": [], "patches": []}
        self.add_file("source.mm", "parc/native/parc.mm", b"// owned Objective-C++\n")
        self.add_patch("build.patch", "parc/BUILD.gn", self.before, self.after)
        self.save()
        self.context = contextlib.ExitStack()
        self.addCleanup(self.context.close)
        self.verify = self.context.enter_context(patch.object(engine, "verify_workspace"))
        self.context.enter_context(patch.object(engine, "tree_fingerprint", return_value="overlay-tree"))
        self.run = self.context.enter_context(patch.object(engine, "run"))

    def add_file(self, source, target, data):
        (self.inputs / source).write_bytes(data)
        self.spec["files"].append({"source": source, "target": target, "sha256": engine.digest(data)})

    def add_patch(self, source, target, before, after):
        import difflib
        data = "".join(difflib.unified_diff(before.decode().splitlines(True), after.decode().splitlines(True),
                                         fromfile="a/" + target, tofile="b/" + target)).encode()
        (self.inputs / source).write_bytes(data)
        self.spec["patches"].append({"source": source, "sha256": engine.digest(data), "files": [
            {"target": target, "before_sha256": engine.digest(before), "after_sha256": engine.digest(after)}]})

    def save(self):
        self.manifest.write_text(json.dumps(self.spec, indent=2) + "\n")

    def call(self, apply=True):
        return engine.overlay(self.workspace, self.lock, self.sha, self.manifest, apply)

    def snapshot(self):
        return {str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob("*") if p.is_file()}

    def assert_unchanged_refusal(self):
        before = self.snapshot()
        with self.assertRaises(engine.Refusal):
            self.call()
        self.assertEqual(self.snapshot(), before)
        self.run.assert_not_called()

    def test_dry_run_checks_all_bytes_without_creating_files(self):
        before = self.snapshot()
        report = self.call(False)
        self.assertFalse(report["applied"])
        self.assertEqual(report["build_targets"], ["//parc:parc_fixture"])
        self.assertEqual(self.snapshot(), before)
        self.run.assert_not_called()

    def test_apply_records_originals_and_same_manifest_is_idempotent(self):
        self.target.chmod(0o640)
        report = self.call()
        self.assertTrue(report["applied"])
        self.assertEqual(self.target.read_bytes(), self.after)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o640)
        state = engine.read_marker(self.workspace, self.sha)
        record = engine.recorded_overlay(self.workspace, state)
        self.assertEqual(record["targets"]["parc/BUILD.gn"]["original"], self.before.decode())
        self.assertIsNone(record["targets"]["parc/native/parc.mm"]["original"])
        before = self.snapshot()
        self.assertTrue(self.call()["applied"])
        self.assertEqual(self.snapshot(), before)

    def test_update_reconstructs_original_and_retires_only_owned_sources(self):
        self.call()
        unrelated = self.root / "valuable.cc"
        unrelated.write_text("user work preserved")
        self.spec["version"] = 2
        self.spec["files"] = []
        self.spec["patches"] = []
        self.add_file("replacement.mm", "parc/native/new_host.mm", b"// next version\n")
        self.save()
        self.call()
        self.assertEqual(self.target.read_bytes(), self.before)
        self.assertFalse((self.root / "parc/native/parc.mm").exists())
        self.assertEqual((self.root / "parc/native/new_host.mm").read_bytes(), b"// next version\n")
        self.assertEqual(unrelated.read_text(), "user work preserved")

    def test_aggregate_record_can_exceed_an_individual_source_limit(self):
        before = b"//" + b"x" * (4 * 1024 * 1024) + b"\nold\n"
        after = before[:-4] + b"new\n"
        for index in range(2):
            target = f"parc/large{index}.cc"
            (self.root / target).write_bytes(before)
            self.add_patch(f"large{index}.patch", target, before, after)
        self.save()
        self.assertTrue(self.call()["applied"])
        state = engine.read_marker(self.workspace, self.sha)
        path = self.workspace / ".parc-overlays" / (state["overlay"]["identity"] + ".json")
        self.assertGreater(path.stat().st_size, 8 * 1024 * 1024)
        self.assertEqual(engine.recorded_overlay(self.workspace, state)["version"], 1)
        self.assertTrue(self.call()["applied"])
        self.spec["version"] = 2
        self.spec["files"] = []
        self.spec["patches"] = []
        self.add_file("next.mm", "parc/native/next.mm", b"// next\n")
        self.save()
        self.assertTrue(self.call()["applied"])
        for index in range(2):
            self.assertEqual((self.root / f"parc/large{index}.cc").read_bytes(), before)

    def test_individual_source_limit_is_not_relaxed_for_aggregate_records(self):
        self.add_file("oversized.mm", "parc/native/oversized.mm", b"x" * (8 * 1024 * 1024 + 1))
        self.save()
        self.assert_unchanged_refusal()

    def test_aggregate_limit_is_checked_before_dry_run_or_apply_writes(self):
        before = self.snapshot()
        with patch.object(engine, "OVERLAY_RECORD_LIMIT", 1):
            for apply in (False, True):
                with self.assertRaisesRegex(engine.Refusal, "Aggregate overlay record"):
                    self.call(apply)
                self.assertEqual(self.snapshot(), before)
        self.run.assert_not_called()

    def test_update_uses_preimage_not_previous_patched_text(self):
        self.call()
        self.spec["version"] = 2
        self.spec["patches"] = []
        next_text = self.after.replace(b"//parc:parc_fixture", b"parc_fixture_v2")
        self.add_patch("v2.patch", "parc/BUILD.gn", self.before, next_text)
        self.save()
        self.call()
        self.assertEqual(self.target.read_bytes(), next_text)

    def test_update_preserves_unchanged_mapped_and_patched_file_timestamps(self):
        self.add_file("header.h", "parc/native/parc.h", b"// unchanged header\n")
        self.save()
        self.call()
        unchanged = [self.target, self.root / "parc/native/parc.h"]
        for path in unchanged:
            os.utime(path, ns=(1_600_000_000_000_000_000,) * 2)
        before = {path: path.stat() for path in unchanged}
        self.spec["version"] = 2
        replacement = b"// changed implementation\n"
        (self.inputs / "source.mm").write_bytes(replacement)
        self.spec["files"][0]["sha256"] = engine.digest(replacement)
        self.save()
        self.call()
        for path, old in before.items():
            with self.subTest(path=path):
                current = path.stat()
                self.assertEqual(current.st_mtime_ns, old.st_mtime_ns)
                self.assertEqual(current.st_ctime_ns, old.st_ctime_ns)
                self.assertEqual(current.st_ino, old.st_ino)
        self.assertEqual((self.root / "parc/native/parc.mm").read_bytes(), replacement)
        engine.recorded_overlay(self.workspace, engine.read_marker(self.workspace, self.sha))

    def test_source_write_still_restores_required_mode_for_identical_bytes(self):
        self.target.chmod(0o600)
        engine.write_source(self.target, self.before, 0o640)
        self.assertEqual(self.target.read_bytes(), self.before)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o640)

    def test_all_patch_results_checked_before_any_source_is_written(self):
        self.spec["patches"][0]["files"][0]["after_sha256"] = "0" * 64
        self.save()
        self.assert_unchanged_refusal()

    def test_ordered_patch_chain_uses_each_reviewed_intermediate(self):
        final = b"group(\"parc\") {\n  deps = [ \":parc_fixture\", \":tests\" ]\n}\n"
        self.add_patch("tests.patch", "parc/BUILD.gn", self.after, final)
        self.save()
        self.assertTrue(self.call()["applied"])
        self.assertEqual(self.target.read_bytes(), final)
        record = engine.recorded_overlay(
            self.workspace, engine.read_marker(self.workspace, self.sha))
        self.assertEqual(record["targets"]["parc/BUILD.gn"]["original"],
                         self.before.decode())
        self.spec["version"] = 2
        self.spec["patches"].reverse()
        self.save()
        self.assert_unchanged_refusal()

    def test_patch_chain_rejects_alias_same_patch_and_owned_overlap(self):
        original = copy.deepcopy(self.spec)
        final = b"group(\"parc\") {\n  deps = [ \":parc_fixture\", \":tests\" ]\n}\n"

        self.add_patch("tests.patch", "parc/BUILD.gn", self.after, final)
        alias = self.spec["patches"][-1]
        alias_source = self.inputs / alias["source"]
        data = alias_source.read_bytes().replace(b"parc/BUILD.gn",
                                                  b"parc/build.gn")
        alias_source.write_bytes(data)
        alias["sha256"] = engine.digest(data)
        alias["files"][0]["target"] = "parc/build.gn"
        self.save()
        self.assert_unchanged_refusal()

        self.spec = copy.deepcopy(original)
        self.spec["patches"][0]["files"].append(
            copy.deepcopy(self.spec["patches"][0]["files"][0]))
        self.save()
        self.assert_unchanged_refusal()

        self.spec = copy.deepcopy(original)
        self.spec["patches"] = []
        owned = b"// owned Objective-C++\n"
        self.add_patch("owned.patch", "parc/native/parc.mm", owned,
                       owned + b"// changed\n")
        self.save()
        self.assert_unchanged_refusal()

    def test_bad_input_hash_wrong_upstream_or_duplicate_target_fail_closed(self):
        original = copy.deepcopy(self.spec)
        for change in ("hash", "upstream", "duplicate"):
            with self.subTest(change=change):
                self.spec = copy.deepcopy(original)
                if change == "hash":
                    self.spec["files"][0]["sha256"] = "0" * 64
                elif change == "upstream":
                    self.spec["upstream"]["cef"] = "0" * 40
                else:
                    self.spec["files"].append(copy.deepcopy(self.spec["files"][0]))
                self.save()
                self.assert_unchanged_refusal()

    def test_unreviewed_existing_file_is_not_overwritten(self):
        file = self.root / self.spec["files"][0]["target"]
        file.parent.mkdir(parents=True)
        file.write_bytes(b"other work")
        self.assert_unchanged_refusal()

    def test_unrelated_changes_or_incomplete_sync_prevent_overlay(self):
        self.verify.side_effect = engine.Refusal("Source changes detected")
        self.assert_unchanged_refusal()
        self.verify.side_effect = None
        engine.write_marker(self.workspace, dict(self.state, phase="sync-in-progress"))
        self.assert_unchanged_refusal()

    def test_active_operation_is_never_touched(self):
        with (self.workspace / ".parc-operation.lock").open("rb") as guard:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assert_unchanged_refusal()

    def test_paths_cannot_escape_or_change_bootstrap_inputs(self):
        for target in ("../outside", "/absolute", "parc/../../outside", "parc/.git/config",
                       "DEPS", "out/Release_GN_arm64/args.gn"):
            with self.subTest(target=target):
                self.spec["files"][0]["target"] = target
                self.save()
                self.assert_unchanged_refusal()
        self.spec["files"][0]["target"] = "parc/new.mm"
        self.spec["files"][0]["source"] = "../outside.mm"
        self.save()
        self.assert_unchanged_refusal()

    def test_source_and_destination_symlinks_refused(self):
        source = self.inputs / "source.mm"
        source.unlink()
        source.symlink_to(self.target)
        self.assert_unchanged_refusal()
        source.unlink()
        source.write_bytes(b"// owned Objective-C++\n")
        (self.root / "parc/native").symlink_to(self.inputs, target_is_directory=True)
        self.assert_unchanged_refusal()

    def test_repository_source_root_shares_files_without_path_escape(self):
        self.spec["source_root"] = "repository"
        for item in self.spec["files"] + self.spec["patches"]:
            item["source"] = "reviewed/" + item["source"]
        self.save()
        with patch.object(engine, "REPO", self.base):
            self.assertFalse(self.call(False)["applied"])
            self.spec["files"][0]["source"] = "../outside.mm"
            self.save()
            self.assert_unchanged_refusal()
        self.spec["files"][0]["source"] = "reviewed/source.mm"
        self.save()
        self.assert_unchanged_refusal()

    def test_non_directory_target_parent_refused_before_earlier_writes(self):
        (self.root / "parc/native").write_text("valuable file")
        self.assert_unchanged_refusal()

    def test_case_alias_targets_and_command_arguments_refused(self):
        self.add_file("other.mm", "parc/native/PARC.mm", b"// alias\n")
        self.save()
        self.assert_unchanged_refusal()
        self.spec["files"].pop()
        for target in ("--flag", "foo;touch", "../../target", "//cef:target", "cef"):
            self.spec["build_targets"] = [target]
            self.save()
            self.assert_unchanged_refusal()

    def test_altered_old_output_or_record_prevents_update(self):
        self.call()
        self.spec["version"] = 2
        self.save()
        self.target.write_bytes(b"new manual edits\n")
        self.assert_unchanged_refusal()
        self.target.write_bytes(self.after)
        state = engine.read_marker(self.workspace, self.sha)
        record = self.workspace / ".parc-overlays" / (state["overlay"]["identity"] + ".json")
        record.write_bytes(record.read_bytes() + b" ")
        self.assert_unchanged_refusal()

    def test_same_version_different_review_cannot_replace_overlay(self):
        self.call()
        self.spec["build_targets"] = ["other_target"]
        self.save()
        self.assert_unchanged_refusal()

    def test_write_failure_rolls_back_applied_files_and_marker(self):
        final = b"group(\"parc\") {\n  deps = [ \":parc_fixture\", \":tests\" ]\n}\n"
        self.add_patch("tests.patch", "parc/BUILD.gn", self.after, final)
        self.save()
        original_write = engine.write_source
        calls = 0
        def fail_second(*args):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("simulated disk failure")
            return original_write(*args)
        with patch.object(engine, "write_source", side_effect=fail_second):
            with self.assertRaisesRegex(OSError, "disk failure"):
                self.call()
        self.assertEqual(self.target.read_bytes(), self.before)
        self.assertFalse((self.root / "parc/native/parc.mm").exists())
        self.assertEqual(engine.read_marker(self.workspace, self.sha), self.state)

    def test_process_interruption_can_resume_same_manifest(self):
        with patch.object(engine, "write_source", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.call()
        state = engine.read_marker(self.workspace, self.sha)
        self.assertEqual(state["phase"], "overlay-applying")
        self.assertRegex(state.get("pending_overlay", ""), r"^[0-9a-f]{64}$")
        report = self.call()
        self.assertTrue(report["applied"])
        self.assertEqual(self.target.read_bytes(), self.after)
        self.assertTrue((self.root / "parc/native/parc.mm").is_file())
        finished = engine.read_marker(self.workspace, self.sha)
        self.assertEqual(finished["phase"], "synced")
        self.assertNotIn("pending_overlay", finished)

    def test_build_appends_reviewed_target_and_validates_generator_result(self):
        self.call()
        with patch.object(engine, "host_report", return_value={"blockers": []}):
            engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        self.assertEqual(self.run.call_count, 3)
        self.assertEqual(self.run.call_args.args[0][-2:], ["parc/helper:parc_helper", "parc:parc_fixture"])
        state = engine.read_marker(self.workspace, self.sha)
        engine.write_marker(self.workspace, dict(state, phase="synced"))
        def changed_by_generation(argv, *args):
            if "gen" in argv:
                self.target.write_bytes(b"unexpected upstream patch\n")
        self.run.reset_mock()
        self.run.side_effect = changed_by_generation
        with patch.object(engine, "host_report", return_value={"blockers": []}), self.assertRaises(engine.Refusal):
            engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        self.assertEqual(self.run.call_count, 2)
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "generation-in-progress")

    def test_returned_generation_failure_preserves_overlay_on_retry(self):
        self.call()
        original = engine.read_marker(self.workspace, self.sha)["overlay"]
        def fail_generator(argv, *args):
            if "gen" in argv:
                raise subprocess.CalledProcessError(1, argv)
        self.run.side_effect = fail_generator
        with patch.object(engine, "host_report", return_value={"blockers": []}):
            with self.assertRaises(subprocess.CalledProcessError):
                engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
            failed = engine.read_marker(self.workspace, self.sha)
            self.assertEqual(failed["phase"], "generation-failed")
            self.assertEqual(failed["overlay"], original)
            self.assertEqual(self.target.read_bytes(), self.after)
            engine.recorded_overlay(self.workspace, failed)
            self.run.reset_mock(side_effect=True)
            engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        self.assertEqual(self.run.call_count, 3)
        self.assertEqual(self.run.call_args.args[0][-2:], ["parc/helper:parc_helper", "parc:parc_fixture"])
        built = engine.read_marker(self.workspace, self.sha)
        self.assertEqual(built["phase"], "built")
        self.assertEqual(built["overlay"], original)
        self.assertNotIn("generation_error", built)
        self.assertEqual(self.target.read_bytes(), self.after)


class ContextPatchTests(unittest.TestCase):
    def test_git_style_multiple_hunks_and_missing_final_newline(self):
        source = b"a\nb\nc\nd\ne\nf"
        delta = ("diff --git a/x.cc b/x.cc\nindex aaaaaaa..bbbbbbb 100644\n"
                 "--- a/x.cc\n+++ b/x.cc\n@@ -1,2 +1,2 @@\n a\n-b\n+B\n"
                 "@@ -5,2 +5,2 @@\n e\n-f\n\\ No newline at end of file\n+F\n\\ No newline at end of file\n")
        self.assertEqual(engine.apply_context_patch(delta, {"x.cc": source}), {"x.cc": b"a\nB\nc\nd\ne\nF"})

    def test_mismatch_fuzzy_hunk_mode_binary_and_undeclared_file_refused(self):
        normal = "--- a/x.cc\n+++ b/x.cc\n@@ -1,2 +1,2 @@\n a\n-b\n+B\n"
        for delta in [normal.replace(" a\n", " z\n"), normal.replace("-1,2", "-2,2"),
                      "old mode 100644\nnew mode 100755\n" + normal,
                      "GIT binary patch\n", normal.replace("b/x.cc", "b/y.cc"),
                      normal.replace("@@ -1,2 +1,2 @@\n a\n-b\n+B", "@@ -2 +2 @@\n-b\n+B")]:
            with self.subTest(delta=delta), self.assertRaises(engine.Refusal):
                engine.apply_context_patch(delta, {"x.cc": b"a\nb\n"})


if __name__ == "__main__":
    unittest.main()
