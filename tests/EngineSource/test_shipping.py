import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("shipping_source", ROOT / "scripts/engine-source.py")
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class ShippingTests(unittest.TestCase):
    def setUp(self):
        sdk = patch.object(engine, "ensure_xcode", return_value=None)
        sdk.start()
        self.addCleanup(sdk.stop)
        profile = patch.object(engine, "ensure_pgo_profile", return_value=None)
        profile.start()
        self.addCleanup(profile.stop)
        builtins = patch.object(engine, "ensure_v8_builtins_profile", return_value=None)
        builtins.start()
        self.addCleanup(builtins.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name).resolve()
        self.lock, self.sha = engine.load_lock()
        self.state = {"schema_version": 1, "workspace": str(self.workspace), "lock_sha256": self.sha,
                      "phase": "built", "symbol_level": 0, "source_fingerprint": "source-a",
                      "overlay": {"identity": "overlay-a"}}
        engine.write_marker(self.workspace, self.state)
        (self.workspace / ".parc-operation.lock").touch()
        self.output = self.workspace / "chromium/src/out" / engine.SHIPPING_CONFIGURATION
        self.output.parent.mkdir(parents=True)
        self.development = self.output.parent / "Release_GN_arm64"
        self.development.mkdir()
        (self.development / "args.gn").write_bytes(b"development arguments")
        self.arguments = b'is_component_build=false\nis_debug=false\ntarget_cpu="arm64"\n'

    def build(self, side_effect=None, *, generate_only=False):
        with patch.object(engine, "host_report", return_value={"blockers": []}), \
             patch.object(engine, "verify_workspace"), \
             patch.object(engine, "recorded_overlay", return_value={"identity": "overlay-a"}), \
             patch.object(engine, "shipping_arguments", return_value=self.arguments), \
             patch.object(engine, "run", side_effect=side_effect) as run:
            engine.shipping_build(self.workspace, self.lock, self.sha, 0, 4, generate_only=generate_only)
            return run.call_args_list

    def test_build_preserves_development_receipt_and_objects(self):
        before = (self.workspace / engine.MARKER).read_bytes()
        calls = self.build()
        self.assertEqual((self.workspace / engine.MARKER).read_bytes(), before)
        self.assertEqual((self.development / "args.gn").read_bytes(), b"development arguments")
        self.assertEqual(calls[0].args[0][-2:], ["gen", "out/" + engine.SHIPPING_CONFIGURATION])
        self.assertEqual(calls[1].args[0][-1], "parc/helper:parc_helper")
        self.assertNotIn("parc_native_window_tests", calls[1].args[0])
        self.assertEqual(engine.verify_shipping_build(self.workspace, self.sha, self.state)["phase"], "built")

    def test_returned_build_failure_is_resumable_but_not_packagable(self):
        def failure(argv, cwd, env):
            if argv[0].endswith("autoninja"):
                raise subprocess.CalledProcessError(1, argv)
        with self.assertRaises(subprocess.CalledProcessError):
            self.build(failure)
        receipt = engine.read_shipping_marker(self.workspace, self.sha, self.state)
        self.assertEqual(receipt["phase"], "build-failed")
        with self.assertRaisesRegex(engine.Refusal, "completed shipping"):
            engine.verify_shipping_build(self.workspace, self.sha, self.state)
        self.build()
        engine.verify_shipping_build(self.workspace, self.sha, self.state)

    def test_generation_does_not_compile_or_claim_a_completed_engine(self):
        calls = self.build(generate_only=True)
        self.assertEqual(len(calls), 1)
        self.assertEqual(engine.read_shipping_marker(self.workspace, self.sha, self.state)["phase"], "generated")
        with self.assertRaisesRegex(engine.Refusal, "completed shipping"):
            engine.verify_shipping_build(self.workspace, self.sha, self.state)
        self.build()
        engine.verify_shipping_build(self.workspace, self.sha, self.state)

    def test_old_overlay_or_changed_args_cannot_be_sealed(self):
        self.build()
        for key, value in (("overlay", {"identity": "overlay-b"}), ("source_fingerprint", "source-b")):
            changed = copy.deepcopy(self.state); changed[key] = value
            with self.assertRaisesRegex(engine.Refusal, "completed shipping"):
                engine.verify_shipping_build(self.workspace, self.sha, changed)
        (self.output / "args.gn").write_bytes(b"is_component_build=true")
        with self.assertRaisesRegex(engine.Refusal, "completed shipping"):
            engine.verify_shipping_build(self.workspace, self.sha, self.state)
        with self.assertRaisesRegex(engine.Refusal, "arguments changed"):
            self.build()

    def test_foreign_output_is_preserved_and_dead_build_resumes(self):
        self.output.mkdir()
        with self.assertRaisesRegex(engine.Refusal, "without its ownership"):
            self.build()
        self.output.rmdir()
        self.build()
        receipt = engine.read_shipping_marker(self.workspace, self.sha, self.state)
        receipt["phase"] = "build-in-progress"
        engine.write_marker(self.workspace, receipt, engine.SHIPPING_MARKER)
        self.build()
        self.assertEqual(engine.read_shipping_marker(self.workspace, self.sha, self.state)["phase"], "built")

    def emulate_previous_recipe(self):
        receipt = engine.read_shipping_marker(self.workspace, self.sha, self.state)
        old_arguments = b"chrome_pgo_phase=0\n"
        (self.output / "args.gn").write_bytes(old_arguments)
        receipt.update(gn_defines=engine.SHIPPING_DEFINES.replace("chrome_pgo_phase=2", "chrome_pgo_phase=0"),
                       args_sha256=engine.digest(old_arguments), phase="build-in-progress")
        engine.write_marker(self.workspace, receipt, engine.SHIPPING_MARKER)

    def test_changed_shipping_recipe_rebuilds_existing_output(self):
        self.build()
        self.emulate_previous_recipe()
        calls = self.build()
        self.assertEqual(calls[0].args[0][-2:], ["gen", "out/" + engine.SHIPPING_CONFIGURATION])
        self.assertEqual((self.output / "args.gn").read_bytes(), self.arguments)
        receipt = engine.read_shipping_marker(self.workspace, self.sha, self.state)
        self.assertEqual((receipt["phase"], receipt["args_sha256"]), ("built", engine.digest(self.arguments)))
        engine.verify_shipping_build(self.workspace, self.sha, self.state)

    def test_changed_shipping_recipe_preserves_hand_edited_arguments(self):
        self.build()
        self.emulate_previous_recipe()
        (self.output / "args.gn").write_bytes(b"hand edited\n")
        with self.assertRaisesRegex(engine.Refusal, "arguments changed"):
            self.build()
        self.assertEqual((self.output / "args.gn").read_bytes(), b"hand edited\n")

    def emulate_previous_lock(self, args_bytes=b"is_component_build=false\n"):
        previous = copy.deepcopy(self.lock)
        previous["build"]["gn_defines"] = ('is_component_build=true is_official_build=false '
                                           'target_cpu="arm64" enable_dsyms=false use_remoteexec=false')
        path = self.workspace / "previous-source-lock.json"
        path.write_text(json.dumps(previous, indent=2) + "\n")
        previous_sha = engine.digest(path.read_bytes())
        self.state["lock_sha256"] = previous_sha
        engine.write_marker(self.workspace, self.state)
        receipt = engine.read_shipping_marker(self.workspace, self.sha, self.state)
        (self.output / "args.gn").write_bytes(args_bytes)
        receipt.update(lock_sha256=previous_sha, args_sha256=engine.digest(args_bytes),
                       gn_defines=('is_component_build=false is_official_build=false '
                                   'target_cpu="arm64" enable_dsyms=false use_remoteexec=false'))
        engine.write_marker(self.workspace, receipt, engine.SHIPPING_MARKER)
        return path

    def reconfigure(self, previous):
        with patch.object(engine, "verify_workspace"), \
             patch.object(engine, "shipping_arguments", return_value=self.arguments):
            return engine.reconfigure(self.workspace, self.lock, self.sha, previous)

    def test_reconfigure_requires_new_shipping_build_before_sealing(self):
        self.build()
        previous = self.emulate_previous_lock()
        report = self.reconfigure(previous)
        self.assertEqual(report["shipping"], {"phase": "reconfigured", "arguments_changed": True})
        self.assertEqual((self.output / "args.gn").read_bytes(), self.arguments)
        self.assertEqual(engine.read_marker(self.workspace, self.sha)["phase"], "synced")
        self.state = engine.read_marker(self.workspace, self.sha)
        receipt = engine.read_shipping_marker(self.workspace, self.sha, self.state)
        self.assertEqual((receipt["gn_defines"], receipt["args_sha256"]),
                         (engine.SHIPPING_DEFINES, engine.digest(self.arguments)))
        with self.assertRaisesRegex(engine.Refusal, "completed shipping"):
            engine.verify_shipping_build(self.workspace, self.sha, self.state)
        with self.assertRaisesRegex(engine.Refusal, "normal engine source generation"):
            self.build()
        self.state["phase"] = "generated"
        engine.write_marker(self.workspace, self.state)
        calls = self.build()
        self.assertEqual(calls[0].args[0][-2:], ["gen", "out/" + engine.SHIPPING_CONFIGURATION])
        engine.verify_shipping_build(self.workspace, self.sha, self.state)

    def test_reconfigure_keeps_unchanged_shipping_arguments_built(self):
        self.build()
        previous = self.emulate_previous_lock(self.arguments)
        report = self.reconfigure(previous)
        self.assertEqual(report["shipping"], {"phase": "built", "arguments_changed": False})
        self.state = engine.read_marker(self.workspace, self.sha)
        engine.verify_shipping_build(self.workspace, self.sha, self.state)

    def test_reconfigure_resumes_after_args_write_but_preserves_foreign_args(self):
        self.build()
        previous = self.emulate_previous_lock()
        (self.output / "args.gn").write_bytes(self.arguments)
        self.assertEqual(self.reconfigure(previous)["shipping"]["phase"], "reconfigured")
        self.state = engine.read_marker(self.workspace, self.sha)
        self.state["phase"] = "built"
        engine.write_marker(self.workspace, self.state)
        self.build()
        previous = self.emulate_previous_lock()
        (self.output / "args.gn").write_bytes(b"is_component_build=true\n")
        before = (self.workspace / engine.MARKER).read_bytes()
        with self.assertRaisesRegex(engine.Refusal, "differ from their receipt"):
            self.reconfigure(previous)
        self.assertEqual((self.output / "args.gn").read_bytes(), b"is_component_build=true\n")
        self.assertEqual((self.workspace / engine.MARKER).read_bytes(), before)

    def test_dead_shipping_build_can_be_reconfigured(self):
        self.build()
        previous = self.emulate_previous_lock()
        receipt = json.loads((self.workspace / engine.SHIPPING_MARKER).read_text())
        engine.write_marker(self.workspace, dict(receipt, phase="build-in-progress"), engine.SHIPPING_MARKER)
        self.reconfigure(previous)
        self.assertEqual(json.loads((self.workspace / engine.SHIPPING_MARKER).read_text())["phase"], "reconfigured")

    def test_shipping_environment_is_local_noncomponent(self):
        env = engine.shipping_environment(self.workspace, self.lock, 1)
        self.assertIn("is_component_build=false", env["GN_DEFINES"])
        self.assertIn("dcheck_always_on=false", env["GN_DEFINES"].split())
        self.assertIn("is_official_build=true", env["GN_DEFINES"].split())
        self.assertIn("chrome_pgo_phase=2", env["GN_DEFINES"].split())
        self.assertIn("disable_fieldtrial_testing_config=true", env["GN_DEFINES"].split())
        self.assertIn("symbol_level=1", env["GN_DEFINES"])
        self.assertIn("use_remoteexec=false", env["GN_DEFINES"])
        self.assertEqual(env["GN_OUT_CONFIGS"], "Release_GN_arm64")


class PGOProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name).resolve()
        self.build_dir = self.workspace / "chromium/src/chrome/build"
        self.build_dir.mkdir(parents=True)
        self.name = engine.SHIPPING_PGO_PROFILE["name"]
        (self.build_dir / "mac-arm.pgo.txt").write_text(self.name + "\n")
        self.profile = self.build_dir / "pgo_profiles" / self.name
        self.content = b"profile data"
        self.pin = patch.dict(engine.SHIPPING_PGO_PROFILE, sha256=engine.digest(self.content))
        self.pin.start()
        self.addCleanup(self.pin.stop)

    def download(self, argv, cwd, env):
        self.profile.parent.mkdir(exist_ok=True)
        self.profile.write_bytes(self.content)

    def test_missing_profile_is_downloaded_and_checked(self):
        with patch.object(engine, "run", side_effect=self.download) as run:
            self.assertEqual(engine.ensure_pgo_profile(self.workspace, {}), self.profile)
        argv = run.call_args.args[0]
        self.assertEqual(argv[1:4], ["tools/update_pgo_profiles.py", "--target=mac-arm", "update"])
        self.assertEqual(run.call_args.args[1], self.workspace / "chromium/src")

    def test_present_profile_is_not_downloaded_again(self):
        self.download(None, None, None)
        with patch.object(engine, "run", side_effect=AssertionError("downloaded again")):
            engine.ensure_pgo_profile(self.workspace, {})

    def test_wrong_profile_contents_are_refused(self):
        self.profile.parent.mkdir()
        self.profile.write_bytes(b"other data")
        with patch.object(engine, "run"), self.assertRaisesRegex(engine.Refusal, "digest mismatch"):
            engine.ensure_pgo_profile(self.workspace, {})

    def test_chromium_naming_another_profile_is_refused(self):
        (self.build_dir / "mac-arm.pgo.txt").write_text("chrome-mac-arm-other.profdata\n")
        with patch.object(engine, "run", side_effect=AssertionError("downloaded")), \
             self.assertRaisesRegex(engine.Refusal, "different PGO profile"):
            engine.ensure_pgo_profile(self.workspace, {})


if __name__ == "__main__":
    unittest.main()


class V8BuiltinsProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name).resolve()
        self.v8 = self.workspace / "chromium/src/v8"
        (self.v8 / "include").mkdir(parents=True)
        self.write_version("15.7.112.43")
        self.profile = self.v8 / "tools/builtins-pgo/profiles" / engine.SHIPPING_V8_BUILTINS_PROFILE["name"]
        self.content = b"builtins profile"
        self.pin = patch.dict(engine.SHIPPING_V8_BUILTINS_PROFILE, version="15.7.112.43",
                              sha256=engine.digest(self.content))
        self.pin.start()
        self.addCleanup(self.pin.stop)

    def write_version(self, version):
        major, minor, build, patch_level = version.split(".")
        (self.v8 / "include/v8-version.h").write_text(
            f"#define V8_MAJOR_VERSION {major}\n#define V8_MINOR_VERSION {minor}\n"
            f"#define V8_BUILD_NUMBER {build}\n#define V8_PATCH_LEVEL {patch_level}\n")

    def download(self, argv, cwd, env):
        self.profile.parent.mkdir(parents=True, exist_ok=True)
        self.profile.write_bytes(self.content)

    def test_missing_profile_is_downloaded_for_the_pinned_v8_and_checked(self):
        with patch.object(engine, "run", side_effect=self.download) as run:
            self.assertEqual(engine.ensure_v8_builtins_profile(self.workspace, {}), self.profile)
        argv = run.call_args.args[0]
        self.assertEqual(argv[1:3], ["v8/tools/builtins-pgo/download_profiles.py", "download"])
        self.assertIn("--check-v8-revision", argv)
        self.assertEqual(argv[argv.index("--depot-tools") + 1], str(self.workspace / "depot_tools"))
        self.assertEqual(run.call_args.args[1], self.workspace / "chromium/src")

    def test_present_profile_is_not_downloaded_again(self):
        self.download(None, None, None)
        with patch.object(engine, "run", side_effect=AssertionError("downloaded again")):
            engine.ensure_v8_builtins_profile(self.workspace, {})

    def test_wrong_profile_contents_are_refused(self):
        self.profile.parent.mkdir(parents=True)
        self.profile.write_bytes(b"other data")
        with patch.object(engine, "run"), self.assertRaisesRegex(engine.Refusal, "digest mismatch"):
            engine.ensure_v8_builtins_profile(self.workspace, {})

    def test_another_v8_version_is_refused_before_downloading(self):
        self.write_version("15.8.1.0")
        with patch.object(engine, "run", side_effect=AssertionError("downloaded")), \
             self.assertRaisesRegex(engine.Refusal, "differs from the shipping recipe"):
            engine.ensure_v8_builtins_profile(self.workspace, {})

