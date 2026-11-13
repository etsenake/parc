import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("cache_source", ROOT / "scripts/engine-source.py")
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class CacheTests(unittest.TestCase):
    def setUp(self):
        sdk = patch.object(engine, "ensure_sdk", return_value=None)
        sdk.start()
        self.addCleanup(sdk.stop)
        self.temp = tempfile.TemporaryDirectory(prefix="parc-cache-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.src = self.root / "chromium/src"
        self.config = self.src / "build/config/siso"
        self.config.mkdir(parents=True)
        self.rc = self.config / ".sisorc"
        self.env = {"TMPDIR": str(self.root), "GN_DEFINES": "use_remoteexec=false"}
        self.lock, _ = engine.load_lock()

    def configure(self):
        self.rc.write_text('ninja -reapi_address=cache.test:50051 -reapi_instance=main '
                           '-reapi_insecure=true -re_exec_enable=true\n')

    def test_no_backend_preserves_both_recipes(self):
        plans = [engine.command_plan(self.root, self.lock, 7)["build"][-1],
                 engine.shipping_command_plan(self.root, 7, self.lock)[-1]]
        for plan in plans:
            with patch.object(engine.subprocess, "run") as run:
                engine.run(plan["argv"], self.src, self.env)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0], plan["argv"])
            self.assertEqual(run.call_args.kwargs["env"], self.env)

    def test_both_recipes_use_cache_without_remote_execution(self):
        self.configure()
        before = self.rc.read_bytes()
        for plan in [engine.command_plan(self.root, self.lock, 7)["build"][-1],
                     engine.shipping_command_plan(self.root, 7, self.lock)[-1]]:
            with patch.object(engine.subprocess, "run") as run:
                engine.run(plan["argv"], self.src, self.env)
            argv = run.call_args.args[0]
            self.assertEqual(argv[:2], [str(self.src / "third_party/siso/cipd/siso"), "ninja"])
            for flag in ["-re_exec_enable=false", "-reapi_insecure=true", "-reapi_instance=main",
                         "-re_cache_enable_write=true", "-output_local_strategy=full", "-local_jobs=7"]:
                self.assertIn(flag, argv)
            self.assertNotIn("-re_exec_enable=true", argv)
            self.assertNotIn("--offline", argv)
            self.assertEqual(run.call_args.kwargs["env"]["SISO_PROJECT"], "parc")
            self.assertEqual(run.call_args.kwargs["env"]["GN_DEFINES"], self.env["GN_DEFINES"])
            self.assertEqual(argv[-2:], plan["argv"][-2:])
        self.assertEqual(self.rc.read_bytes(), before)
        self.assertFalse((self.config / "parc_cache.star").exists())

    def test_outage_retries_local_and_preserves_local_failure(self):
        self.configure()
        argv = ["/tools/autoninja", "-C", "out/release", "-j", "7", "parc"]
        for failure in [OSError("unreachable"), subprocess.CalledProcessError(1, ["siso"])]:
            with patch.object(engine.subprocess, "run", side_effect=[failure, None]) as run:
                engine.run(argv, self.src, self.env)
            self.assertEqual(run.call_args.args[0], argv)
        with patch.object(engine.subprocess, "run", side_effect=subprocess.CalledProcessError(1, argv)):
            with self.assertRaises(subprocess.CalledProcessError):
                engine.run(argv, self.src, self.env)

    def test_unconfigured_and_invalid_backend_stay_local(self):
        for text in ['ninja -re_exec_enable=true', 'ninja -reapi_address=host', 'ninja "']:
            self.rc.write_text(text)
            self.assertEqual(engine.cache_backend(self.src), [])

    def test_cache_rules_hash_sdk_and_compiler_and_keep_links_local(self):
        rules = [{"name": "clang/" + name, "inputs": ["compiler"], "remote": True}
                 for name in ["cc", "cxx", "cxx_module", "objc", "objcxx", "link", "asm"]]
        original = SimpleNamespace(step_config=json.dumps({"rules": [{"name": "codesign", "remote": False}],
                                  "platforms": {}, "input_deps": {}}), filegroups={"compiler": {}}, handlers={})
        scope = {"load": lambda *a, **k: None, "json": SimpleNamespace(encode=json.dumps, decode=json.loads),
                 "module": lambda name, **kwargs: SimpleNamespace(**kwargs), "upstream_init": lambda ctx: original,
                 "clang_unix": SimpleNamespace(rules=lambda ctx: rules, input_deps=lambda ctx: {"compiler": ["libcxx"]}),
                 "gn_logs": SimpleNamespace(read=lambda ctx: {"mac_sdk_path": "sdk/MacOSX.sdk"})}
        exec((ROOT / "scripts/siso/cache.star").read_text(), scope)
        result = scope["init"](SimpleNamespace(fs=SimpleNamespace(canonpath=lambda p: p)))
        steps = json.loads(result.step_config)
        self.assertEqual([r["name"] for r in steps["rules"]],
                         ["clang/cc", "clang/cxx", "clang/cxx_module", "clang/objc", "clang/objcxx", "codesign"])
        for rule in steps["rules"][:5]:
            self.assertTrue(rule["remote"])
            self.assertIn("./sdk/MacOSX.sdk:parc_sdk", rule["inputs"])
            self.assertIn("third_party/llvm-build/Release+Asserts:headers", rule["inputs"])
            self.assertNotIn("remote_wrapper", rule)
        self.assertEqual(result.filegroups["./sdk/MacOSX.sdk:parc_sdk"]["includes"], ["*"])
        self.assertFalse(steps["rules"][-1]["remote"])
