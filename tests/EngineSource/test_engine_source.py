"""Offline safety tests. No Git command, network, sync, or build is executed."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("engine_source", ROOT / "scripts/engine-source.py")
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
PREVIOUS_DEFINES = ('is_component_build=true is_official_build=false target_cpu="arm64" '
                    'enable_dsyms=false use_remoteexec=false')


class EngineSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.workspace = self.base / "engine"
        self.lock, self.sha = engine.load_lock()
        self.good_host = {"blockers": [], "free_bytes": 200_000_000_000}
        self.env = engine.environment(self.workspace, self.lock, 0)

    def owned(self, phase="synced"):
        self.workspace.mkdir()
        state = {"schema_version": 1, "workspace": str(self.workspace),
                 "lock_sha256": self.sha, "phase": phase, "symbol_level": 0,
                 "source_fingerprint": "recorded-source", "repositories": ["chromium/src"]}
        engine.write_marker(self.workspace, state)
        return state

    def test_new_external_path_and_repository_boundary(self):
        self.assertEqual(engine.safe_path(str(self.workspace)), self.workspace)
        work = ROOT / "work"
        work.mkdir(exist_ok=True)
        in_repo = work / "engine-boundary-test"
        self.assertEqual(engine.safe_path(str(in_repo)), in_repo.resolve())
        for path in [ROOT, work, ROOT / "build/engine", ROOT / "Sources/engine",
                     ROOT.parent, Path.home(), Path("relative"), self.base / "../escape"]:
            with self.subTest(path=path), self.assertRaises(engine.Refusal):
                engine.safe_path(str(path))

    def test_symlinked_workspace_ancestor_and_internal_tool_are_refused(self):
        actual = self.base / "actual"
        actual.mkdir()
        link = self.base / "link"
        link.symlink_to(actual, target_is_directory=True)
        with self.assertRaises(engine.Refusal):
            engine.safe_path(str(link / "engine"))
        self.owned()
        (self.workspace / "depot_tools").symlink_to(actual, target_is_directory=True)
        with self.assertRaises(engine.Refusal):
            engine.internal_path(self.workspace / "depot_tools/gclient", self.workspace)

    def test_unsafe_upstream_path_characters_refused(self):
        for suffix in ["white space", "injection;touch", "$(command)", "a\nb"]:
            with self.subTest(suffix=suffix), self.assertRaises(engine.Refusal):
                engine.safe_path(str(self.base / suffix))

    def test_capacity_failure_precedes_workspace_or_process_creation(self):
        with patch.object(engine, "host_report", return_value={"blockers": ["Insufficient space"]}), patch.object(engine, "run") as run:
            with self.assertRaisesRegex(engine.Refusal, "Insufficient space"):
                engine.execute(self.workspace, self.lock, self.sha, "sync", 0, 4)
        self.assertFalse(self.workspace.exists())
        run.assert_not_called()

    def test_existing_arbitrary_tree_is_never_adopted_or_erased(self):
        self.workspace.mkdir()
        file = self.workspace / "valuable-source.txt"
        file.write_text("keep this")
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "run") as run:
            with self.assertRaises(engine.Refusal):
                engine.execute(self.workspace, self.lock, self.sha, "sync", 0, 4)
        self.assertEqual(file.read_text(), "keep this")
        self.assertFalse((self.workspace / engine.MARKER).exists())
        run.assert_not_called()

    def test_initial_sync_creates_exclude_parent_without_git_templates(self):
        chromium = self.workspace / "chromium/src"
        calls = []

        def empty_template_git(argv, cwd, env, capture=False):
            calls.append(argv)
            if argv[:len(engine.GIT)] == engine.GIT and "init" in argv:
                checkout = Path(argv[-1])
                if checkout.name == "cef":
                    # This must be created by the bootstrap before nested CEF
                    # init; Git init with an empty template did not create it.
                    exclude = chromium / ".git/info/exclude"
                    self.assertIn("/cef/", exclude.read_text().splitlines())
                checkout.mkdir(parents=True)
                (checkout / ".git").mkdir()
                self.assertFalse((checkout / ".git/info").exists())
            return b""

        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_repository"), patch.object(engine, "synced_repositories", return_value=["chromium/src", "chromium/src/cef"]), patch.object(engine, "tree_fingerprint", return_value="initial-source"), patch.object(engine, "run", side_effect=empty_template_git):
            engine.execute(self.workspace, self.lock, self.sha, "sync", 0, 4)
        self.assertEqual(len(calls), 15)
        self.assertEqual((chromium / ".git/info/exclude").read_text(), "\n/cef/\n")
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "synced")

    def test_marker_cannot_be_reused_at_another_path_or_lock(self):
        state = self.owned()
        with self.assertRaises(engine.Refusal):
            engine.read_marker(self.workspace, "changed-lock")
        state["workspace"] = str(self.base / "elsewhere")
        engine.write_marker(self.workspace, state)
        with self.assertRaises(engine.Refusal):
            engine.read_marker(self.workspace, self.sha)

    def test_incomplete_operation_is_preserved_without_commands(self):
        self.owned("sync-in-progress")
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "run") as run:
            with self.assertRaisesRegex(engine.Refusal, "Partial operation"):
                engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        run.assert_not_called()
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "sync-in-progress")

    def test_changed_source_stops_build_before_generation(self):
        self.owned()
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace", side_effect=engine.Refusal("Source changes detected")), patch.object(engine, "run") as run:
            with self.assertRaisesRegex(engine.Refusal, "Source changes"):
                engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        run.assert_not_called()
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "synced")

    def test_bootstrap_precedes_generation_without_updating_tools_checkout(self):
        self.owned()
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace"), patch.object(engine, "tree_fingerprint", return_value="generated"), patch.object(engine, "run") as run:
            engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        calls = [call.args[0] for call in run.call_args_list]
        self.assertEqual(calls[0], [str(self.workspace / "depot_tools/ensure_bootstrap")])
        self.assertEqual(calls[1], ["/bin/bash", "cef_create_projects.sh"])
        self.assertTrue(calls[2][0].endswith("/autoninja"))
        self.assertNotIn("update_depot_tools", str(calls))

    def test_generate_stops_before_compiling_development_engine(self):
        self.owned()
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace"), patch.object(engine, "tree_fingerprint", return_value="generated"), patch.object(engine, "run") as run:
            engine.execute(self.workspace, self.lock, self.sha, "generate", 0, 4)
        calls = [call.args[0] for call in run.call_args_list]
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[1], ["/bin/bash", "cef_create_projects.sh"])
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "generated")

    def test_returned_generation_failure_records_state_and_resumes_unchanged(self):
        self.owned()
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace"), patch.object(engine, "tree_fingerprint", return_value="failed-generation"), patch.object(engine, "run", side_effect=[b"", OSError("generation failed")]):
            with self.assertRaises(OSError):
                engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        state = engine.read_marker(self.workspace, self.sha)
        self.assertEqual(state["phase"], "generation-failed")
        self.assertEqual(state["source_fingerprint"], "failed-generation")
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace") as verify, patch.object(engine, "tree_fingerprint", return_value="generated"), patch.object(engine, "run") as run:
            engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        verify.assert_called_once()
        self.assertEqual(run.call_count, 3)
        state = engine.read_marker(self.workspace, self.sha)
        self.assertEqual(state["phase"], "built")
        self.assertNotIn("generation_error", state)

    def test_changed_failed_generation_cannot_resume(self):
        self.owned("generation-failed")
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace", side_effect=engine.Refusal("Source changes")), patch.object(engine, "run") as run:
            with self.assertRaisesRegex(engine.Refusal, "Source changes"):
                engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        run.assert_not_called()

    def test_interrupted_generation_remains_incomplete(self):
        self.owned()
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace"), patch.object(engine, "run", side_effect=[b"", KeyboardInterrupt]):
            with self.assertRaises(KeyboardInterrupt):
                engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "generation-in-progress")

    def test_bootstrap_failure_does_not_begin_generation(self):
        self.owned()
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace"), patch.object(engine, "run", side_effect=OSError("bootstrap failed")) as run:
            with self.assertRaises(OSError):
                engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "synced")

    def test_repeat_build_never_regenerates_or_mutates_source(self):
        self.owned("built")
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace"), patch.object(engine, "run") as run:
            engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        self.assertEqual(run.call_count, 1)
        self.assertTrue(run.call_args.args[0][0].endswith("/autoninja"))

    def test_owned_unchanged_dependency_sync_resumes_without_git_checkout(self):
        self.owned("dependency-sync-failed")
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace") as verify, patch.object(engine, "verify_repository"), patch.object(engine, "synced_repositories", return_value=["chromium/src"]), patch.object(engine, "tree_fingerprint", return_value="new-baseline"), patch.object(engine, "run") as run:
            engine.execute(self.workspace, self.lock, self.sha, "sync", 0, 4)
        verify.assert_called_once()
        self.assertEqual(run.call_count, 3)
        for call in run.call_args_list:
            self.assertNotIn("checkout", call.args[0])
            self.assertNotIn("fetch", call.args[0])
            self.assertNotIn("init", call.args[0])
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "synced")

    def test_edited_partial_sync_is_preserved_and_cannot_resume(self):
        self.owned("dependency-sync-failed")
        with patch.object(engine, "host_report", return_value=self.good_host), patch.object(engine, "verify_workspace", side_effect=engine.Refusal("Source changes")), patch.object(engine, "run") as run:
            with self.assertRaisesRegex(engine.Refusal, "Source changes"):
                engine.execute(self.workspace, self.lock, self.sha, "sync", 0, 4)
        run.assert_not_called()
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "dependency-sync-failed")

    def test_dependency_inventory_rejects_escape_paths(self):
        self.workspace.mkdir()
        data = {"solutions": {"../../outside": {"scm": "git"}}}
        (self.workspace / "dependency-sync.json").write_text(json.dumps(data))
        with self.assertRaises(engine.Refusal):
            engine.synced_repositories(self.workspace)

    def test_script_tampering_detected_before_execution(self):
        repo = self.base / "tools"
        (repo / ".git").mkdir(parents=True)
        script = repo / "gclient"
        script.write_bytes(b"tampered")
        item = {"commit": "a" * 40, "url": "https://official.invalid/repo", "files": {"gclient": engine.digest(b"original")}}
        with patch.object(engine, "run", side_effect=[b"a" * 40 + b"\n", b"https://official.invalid/repo\n", b""]):
            with self.assertRaisesRegex(engine.Refusal, "digest mismatch"):
                engine.verify_repository(repo, item, self.env)

    def test_dirty_tool_checkout_refused(self):
        repo = self.base / "tools"
        (repo / ".git").mkdir(parents=True)
        item = {"commit": "a" * 40, "url": "https://official.invalid/repo"}
        with patch.object(engine, "run", side_effect=[b"a" * 40 + b"\n", b"https://official.invalid/repo\n", b" M gclient\n"]):
            with self.assertRaisesRegex(engine.Refusal, "Modified checkout"):
                engine.verify_repository(repo, item, self.env)

    def test_source_fingerprint_detects_content_change_with_same_status(self):
        root = self.workspace / "chromium/src"
        (root / ".git").mkdir(parents=True)
        file = root / "new.cc"
        file.write_text("version one")
        def read_only_git(argv, cwd, env, capture):
            if "ls-files" in argv:
                return b"new.cc\0"
            return b"same-head-and-status"
        with patch.object(engine, "run", side_effect=read_only_git):
            before = engine.tree_fingerprint(self.workspace, self.env, ["chromium/src"])
            file.write_text("version two")
            after = engine.tree_fingerprint(self.workspace, self.env, ["chromium/src"])
        self.assertNotEqual(before, after)

    def test_plan_is_pinned_without_reset_cleanup_or_moving_tools(self):
        plan = engine.command_plan(self.workspace, self.lock, 4)
        all_args = [arg for commands in plan.values() for command in commands for arg in command["argv"]]
        for forbidden in ["reset", "clean", "revert", "stash", "--force", "--reset", "--force-clean", "--delete_unversioned_trees", "origin/main", "origin/master"]:
            self.assertNotIn(forbidden, all_args)
        fetches = [c["argv"] for c in plan["sync"] if "fetch" in c["argv"]]
        # Chromium must shallow-fetch by tag when pinned; raw SHA stalls on googlesource.
        chromium_fetch = next(cmd for cmd in fetches if cmd[-2:] == ["tag", self.lock["chromium"]["tag"]])
        self.assertIn("--depth=1", chromium_fetch)
        self.assertEqual({cmd[-1] for cmd in fetches if "tag" not in cmd},
                         {self.lock[key]["commit"] for key in ("cef", "depot_tools")})
        self.assertNotIn("latest", engine.gclient_text(self.lock))
        sync = next(c["argv"] for c in plan["sync"] if "sync" in c["argv"])
        self.assertIn("--nohooks", sync)
        self.assertIn("src@" + self.lock["chromium"]["commit"], sync)
        self.assertIn("--no-history", sync)
        self.assertEqual(plan["build"][-1]["argv"][-3:], ["-j", "4", "cef_framework"])

    def test_environment_excludes_ambient_code_and_remote_build_injection(self):
        with patch.dict("os.environ", {"GN_DEFINES": "bad", "PYTHONPATH": "/bad", "GIT_CONFIG_COUNT": "99", "RBE_instance": "paid", "UV_NATIVE_TLS": "0"}):
            env = engine.environment(self.workspace, self.lock, 0)
        self.assertEqual(env["HOME"], engine.os.environ.get("HOME", str(Path.home())))
        self.assertNotIn("PYTHONPATH", env)
        self.assertNotIn("GIT_CONFIG_COUNT", env)
        self.assertNotIn("RBE_instance", env)
        self.assertEqual(env["DEPOT_TOOLS_UPDATE"], "0")
        self.assertEqual(env["UV_NATIVE_TLS"], "1")
        self.assertIn("symbol_level=0", env["GN_DEFINES"])
        self.assertIn("enable_dsyms=false", env["GN_DEFINES"])
        self.assertIn("use_remoteexec=false", env["GN_DEFINES"])

    def test_development_and_shipping_engines_use_official_check_and_trial_policy(self):
        shipping = engine.shipping_environment(self.workspace, self.lock, 0)["GN_DEFINES"].split()
        for define in ("dcheck_always_on=false", "disable_fieldtrial_testing_config=true"):
            self.assertIn(define, self.lock["build"]["gn_defines"].split())
            self.assertIn(define, self.env["GN_DEFINES"].split())
            self.assertIn(define, shipping)

    def test_development_and_shipping_engines_use_macos_codecs_without_patented_decoders(self):
        shipping = engine.shipping_environment(self.workspace, self.lock, 0)["GN_DEFINES"].split()
        for define in ("proprietary_codecs=true", 'ffmpeg_branding="Chromium"',
                       "enable_ffmpeg_video_decoders=false", "media_use_openh264=false",
                       "enable_hangout_services_extension=true"):
            self.assertIn(define, self.lock["build"]["gn_defines"].split())
            self.assertIn(define, self.env["GN_DEFINES"].split())
            self.assertIn(define, shipping)

    def test_development_and_shipping_engines_build_fairplay_platform_codecs(self):
        # FairPlay's Dolby Vision (encrypted only) and AC-3/E-AC-3 decode.
        shipping = engine.shipping_environment(self.workspace, self.lock, 0)["GN_DEFINES"].split()
        for define in ("enable_platform_dolby_vision=true",
                       "enable_platform_encrypted_dolby_vision=true",
                       "enable_platform_ac3_eac3_audio=true"):
            self.assertIn(define, self.lock["build"]["gn_defines"].split())
            self.assertIn(define, self.env["GN_DEFINES"].split())
            self.assertIn(define, shipping)

    def previous_lock(self, **build):
        previous = copy.deepcopy(self.lock)
        previous["build"]["gn_defines"] = PREVIOUS_DEFINES
        previous["build"].update(build)
        path = self.base / "previous-source-lock.json"
        path.write_text(json.dumps(previous, indent=2) + "\n")
        return path, engine.digest(path.read_bytes())

    def owned_with_lock(self, lock_sha, phase="built"):
        self.workspace.mkdir()
        (self.workspace / ".parc-operation.lock").touch()
        state = {"schema_version": 1, "workspace": str(self.workspace), "lock_sha256": lock_sha,
                 "phase": phase, "symbol_level": 0, "source_fingerprint": "recorded-source",
                 "repositories": ["chromium/src"], "generation_error": "old",
                 "overlay": {"identity": "overlay-a", "record_sha256": "record-a"}}
        engine.write_marker(self.workspace, state)
        return state

    def test_changed_lock_refusal_names_reconfigure(self):
        self.owned_with_lock("0" * 64)
        with self.assertRaisesRegex(engine.Refusal, "reconfigure"):
            engine.read_marker(self.workspace, self.sha)

    def test_reconfigure_adopts_defines_only_lock_and_regenerates(self):
        previous_path, previous_sha = self.previous_lock()
        before = self.owned_with_lock(previous_sha)
        with patch.object(engine, "verify_workspace") as verify:
            report = engine.reconfigure(self.workspace, self.lock, self.sha, previous_path)
        self.assertEqual(verify.call_args.args[1]["build"]["gn_defines"],
                         json.loads(previous_path.read_text())["build"]["gn_defines"])
        self.assertEqual((report["previous_lock_sha256"], report["lock_sha256"], report["phase"]),
                         (previous_sha, self.sha, "synced"))
        self.assertIsNone(report["shipping"])
        state = engine.read_marker(self.workspace, self.sha)
        self.assertEqual(state["phase"], "synced")
        self.assertNotIn("generation_error", state)
        for key in ("source_fingerprint", "repositories", "overlay", "symbol_level"):
            self.assertEqual(state[key], before[key])
        with patch.object(engine, "host_report", return_value=self.good_host), \
                patch.object(engine, "verify_workspace"), \
                patch.object(engine, "recorded_overlay", return_value=None), \
                patch.object(engine, "tree_fingerprint", return_value="generated"), \
                patch.object(engine, "run") as run:
            engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        calls = [call.args for call in run.call_args_list]
        self.assertEqual(calls[1][0], ["/bin/bash", "cef_create_projects.sh"])
        self.assertIn("dcheck_always_on=false", calls[1][2]["GN_DEFINES"].split())
        self.assertIn("disable_fieldtrial_testing_config=true", calls[1][2]["GN_DEFINES"].split())
        self.assertTrue(calls[2][0][0].endswith("/autoninja"))
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "built")

    def test_reconfigure_adopts_changed_disk_floors(self):
        previous_path, previous_sha = self.previous_lock()
        previous = json.loads(previous_path.read_text())
        previous["storage"] = {**previous["storage"], "build_minimum_free_bytes": 50000000000}
        previous_path.write_text(json.dumps(previous, indent=2) + "\n")
        self.owned_with_lock(engine.digest(previous_path.read_bytes()))
        with patch.object(engine, "verify_workspace"):
            report = engine.reconfigure(self.workspace, self.lock, self.sha, previous_path)
        self.assertEqual(report["phase"], "synced")
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "synced")

    def test_reconfigure_refuses_other_changes_and_partial_state(self):
        other_path, other_sha = self.previous_lock(configuration="Release_GN_arm64", target="cef",
                                                   default_symbol_level=1)
        self.owned_with_lock(other_sha)
        receipt = (self.workspace / engine.MARKER).read_bytes()
        with patch.object(engine, "verify_workspace") as verify:
            with self.assertRaisesRegex(engine.Refusal, "only accepts"):
                engine.reconfigure(self.workspace, self.lock, self.sha, other_path)
            with self.assertRaisesRegex(engine.Refusal, "current source lock"):
                engine.reconfigure(self.workspace, self.lock, self.sha, ROOT / "Engine/source-lock.json")
            with self.assertRaisesRegex(engine.Refusal, "absolute"):
                engine.reconfigure(self.workspace, self.lock, self.sha, Path("previous-source-lock.json"))
            previous_path, previous_sha = self.previous_lock()
            with self.assertRaisesRegex(engine.Refusal, "source lock does not match"):
                engine.reconfigure(self.workspace, self.lock, self.sha, previous_path)
            state = json.loads(receipt)
            state.update(lock_sha256=previous_sha, phase="generation-in-progress")
            engine.write_marker(self.workspace, state)
            receipt = (self.workspace / engine.MARKER).read_bytes()
            with self.assertRaisesRegex(engine.Refusal, "Partial operation"):
                engine.reconfigure(self.workspace, self.lock, self.sha, previous_path)
        verify.assert_not_called()
        self.assertEqual((self.workspace / engine.MARKER).read_bytes(), receipt)

    def test_reconfigure_rerun_after_success_is_refused_without_writes(self):
        previous_path, previous_sha = self.previous_lock()
        self.owned_with_lock(previous_sha)
        with patch.object(engine, "verify_workspace"):
            engine.reconfigure(self.workspace, self.lock, self.sha, previous_path)
        receipt = (self.workspace / engine.MARKER).read_bytes()
        with patch.object(engine, "verify_workspace") as verify:
            with self.assertRaisesRegex(engine.Refusal, "already records the current source lock"):
                engine.reconfigure(self.workspace, self.lock, self.sha, previous_path)
        verify.assert_not_called()
        self.assertEqual((self.workspace / engine.MARKER).read_bytes(), receipt)

    def test_reconfigure_refused_while_another_operation_holds_the_lock(self):
        previous_path, previous_sha = self.previous_lock()
        self.owned_with_lock(previous_sha)
        receipt = (self.workspace / engine.MARKER).read_bytes()
        with (self.workspace / ".parc-operation.lock").open("r") as other:
            engine.fcntl.flock(other, engine.fcntl.LOCK_EX | engine.fcntl.LOCK_NB)
            with patch.object(engine, "verify_workspace") as verify:
                with self.assertRaisesRegex(engine.Refusal, "Another operation"):
                    engine.reconfigure(self.workspace, self.lock, self.sha, previous_path)
        verify.assert_not_called()
        self.assertEqual((self.workspace / engine.MARKER).read_bytes(), receipt)

    def test_reconfigure_refuses_previous_lock_below_symlinked_ancestor(self):
        previous_path, _ = self.previous_lock()
        link = self.base / "linked"
        link.symlink_to(self.base, target_is_directory=True)
        paths = [link / previous_path.name]
        if Path("/tmp").is_symlink():
            paths.append(Path("/tmp") / previous_path.name)
        for path in paths:
            with self.subTest(path=path), self.assertRaisesRegex(engine.Refusal, "absolute non-symlink"):
                engine.reconfigure(self.workspace, self.lock, self.sha, path)

    def test_receipt_write_replaces_temp_left_by_a_killed_write(self):
        self.workspace.mkdir()
        for name in (engine.MARKER, engine.SHIPPING_MARKER):
            with self.subTest(name=name):
                (self.workspace / (name + ".tmp")).write_text('{"partial"')
                engine.write_marker(self.workspace, {"schema_version": 1, "name": name}, name)
                self.assertEqual(json.loads((self.workspace / name).read_text())["name"], name)
                self.assertFalse((self.workspace / (name + ".tmp")).exists())
        outside = self.base / "outside.json"
        outside.write_text("keep")
        (self.workspace / (engine.MARKER + ".tmp")).symlink_to(outside)
        with self.assertRaisesRegex(engine.Refusal, "Symlinked internal path"):
            engine.write_marker(self.workspace, {"schema_version": 1}, engine.MARKER)
        self.assertEqual(outside.read_text(), "keep")

    def test_build_rereads_receipt_once_operation_lock_is_held(self):
        self.owned()
        real_flock = engine.fcntl.flock

        def concurrent_apply(stream, operation):
            real_flock(stream, operation)
            state = json.loads((self.workspace / engine.MARKER).read_text())
            engine.write_marker(self.workspace, dict(state, phase="overlay-applying"))
        with patch.object(engine, "host_report", return_value=self.good_host), \
                patch.object(engine.fcntl, "flock", side_effect=concurrent_apply), \
                patch.object(engine, "verify_workspace") as verify, patch.object(engine, "run") as run:
            with self.assertRaisesRegex(engine.Refusal, "Partial operation"):
                engine.execute(self.workspace, self.lock, self.sha, "build", 0, 4)
        verify.assert_not_called()
        run.assert_not_called()
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "overlay-applying")

    def test_reconfigure_cli_requires_previous_lock_only_for_reconfigure(self):
        output = io.StringIO()
        with contextlib.redirect_stderr(output), patch.object(engine, "overlay") as overlay:
            self.assertEqual(engine.main(["reconfigure", "--workspace", str(self.workspace)]), 2)
            self.assertEqual(engine.main(["plan", "--workspace", str(self.workspace),
                                          "--previous-lock", str(self.base / "lock.json")]), 2)
            self.assertEqual(engine.main(["overlay-check", "--workspace", str(self.workspace),
                                          "--manifest", str(self.base / "overlay.json"),
                                          "--previous-lock", str(self.base / "lock.json")]), 2)
        overlay.assert_not_called()
        self.assertIn("requires --previous-lock", output.getvalue())
        self.assertEqual(output.getvalue().count("only accepted by reconfigure"), 2)
        self.assertFalse(self.workspace.exists())

    def test_plan_prints_blockers_without_mutation_or_execution(self):
        report = {"blockers": ["Insufficient space"], "free_bytes": 1}
        output = io.StringIO()
        with patch.object(engine, "host_report", return_value=copy.deepcopy(report)), patch.object(engine, "run") as run, contextlib.redirect_stdout(output):
            code = engine.main(["plan", "--workspace", str(self.workspace)])
        self.assertEqual(code, 0)
        self.assertFalse(json.loads(output.getvalue())["ready"])
        self.assertFalse(self.workspace.exists())
        run.assert_not_called()

    def test_mutating_cli_cannot_override_failed_preflight(self):
        output = io.StringIO()
        with patch.object(engine, "host_report", return_value={"blockers": ["no space"]}), patch.object(engine, "execute") as execute, contextlib.redirect_stdout(output):
            code = engine.main(["sync", "--workspace", str(self.workspace)])
        self.assertEqual(code, 2)
        execute.assert_not_called()
        self.assertFalse(self.workspace.exists())


if __name__ == "__main__":
    unittest.main()
