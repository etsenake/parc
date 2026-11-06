"""Exercise the portable checker with a fake compiler, never an app or engine."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/check-swift.py"
FAKE_XCRUN = """#!/usr/bin/env python3
import os, pathlib, sys
args = sys.argv[1:]
if '--find' in args:
    if os.environ.get('FAKE_ADD_BEFORE_COMPILER'):
        pathlib.Path(os.environ['FAKE_ADD_BEFORE_COMPILER']).write_text('struct Added {}\\n')
    print('/fake/Xcode.app/swiftc')
elif '--version' in args:
    print('Test Swift compiler')
elif '--show-sdk-path' in args:
    print('/fake/SDK/MacOSX.sdk')
else:
    print('test compiler diagnostics')
    if os.environ.get('FAKE_MUTATE_INPUT'):
        path = pathlib.Path(os.environ['FAKE_MUTATE_INPUT'])
        path.write_text(path.read_text() + '// changed during check\\n')
    if os.environ.get('FAKE_ADD_SOURCE'):
        pathlib.Path(os.environ['FAKE_ADD_SOURCE']).write_text('struct Added {}\\n')
    sys.exit(int(os.environ.get('FAKE_COMPILER_EXIT', '0')))
"""


class CheckSwiftTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="parc checker ")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name).resolve()
        self.repo = root / "Parc checkout"
        self.chromium = root / "engine source/chromium/src"
        self.headers = self.chromium / "cef/include"
        self.output = root / "check receipts"
        for name, content in {
            "Sources/ParcCore/Model.swift": "struct Model {}\n",
            "Sources/ParcApp/App.swift": "struct App {}\n",
            "Sources/ParcEngine/ParcEngine.h": "#import <Cocoa/Cocoa.h>\n",
            "Engine/ParcNative/native_appkit_bridge.h": "#pragma once\n",
            "Engine/source-lock.json": "{}\n",
        }.items():
            file = self.repo / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(content)
        self.headers.mkdir(parents=True)
        (self.headers / "cef_application_mac.h").write_text("#pragma once\n")
        subprocess.run(["git", "init", "--quiet", str(self.repo)], check=True)
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True)
        subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                        "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
                        "commit", "--quiet", "-m", "fixture"], cwd=self.repo, check=True)
        bin_dir = root / "fake tools"
        bin_dir.mkdir()
        for name, content in {
            "xcrun": FAKE_XCRUN,
            "xcodebuild": "#!/bin/sh\nprintf 'Test Xcode\\n'\n",
        }.items():
            executable = bin_dir / name
            executable.write_text(content)
            executable.chmod(0o755)
        self.env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"]}
        self.env.pop("PARC_CHROMIUM_SOURCE", None)
        for name in ("FAKE_MUTATE_INPUT", "FAKE_ADD_SOURCE", "FAKE_COMPILER_EXIT", "FAKE_ADD_BEFORE_COMPILER"):
            self.env.pop(name, None)

    def run_check(self, *extra, headers=True):
        command = [sys.executable, str(SCRIPT), "--repo", str(self.repo),
                   "--output-dir", str(self.output), "--label", "case"]
        if headers:
            command += ["--chromium-source", str(self.chromium)]
        return subprocess.run(command + list(extra), cwd=Path(self.temp.name), env=self.env,
                              text=True, capture_output=True)

    def receipt(self):
        return json.loads((self.output / "case/result.json").read_text())

    def test_plan_preserves_space_paths_and_writes_nothing(self):
        result = self.run_check("--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertFalse(self.output.exists())
        self.assertFalse(plan["executed"])
        self.assertEqual(plan["source_count"], 2)
        self.assertIn(str(self.repo / "Sources/ParcApp/App.swift"), plan["command"])
        self.assertIn(str(self.headers), plan["command"])
        for flag in ("-warnings-as-errors", "-whole-module-optimization", "-typecheck"):
            self.assertIn(flag, plan["command"])

    def test_sil_retains_finished_row_flags(self):
        result = self.run_check("--mode", "sil", "--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        command = json.loads(result.stdout)["command"]
        self.assertNotIn("-typecheck", command)
        self.assertEqual(command[command.index("-emit-sil"):command.index("-emit-sil") + 4],
                         ["-emit-sil", "-Onone", "-o", "/dev/null"])

    def test_no_implicit_engine_or_package_selection(self):
        result = self.run_check("--plan", headers=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("no engine is guessed", result.stderr)
        self.assertFalse(self.output.exists())

    def test_explicit_headers_override_environment(self):
        self.env["PARC_CHROMIUM_SOURCE"] = "/missing/stale/workspace"
        result = self.run_check("--cef-include", str(self.headers), "--plan", headers=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["cef_include"], str(self.headers))

    def test_environment_can_select_engine(self):
        self.env["PARC_CHROMIUM_SOURCE"] = str(self.chromium)
        result = self.run_check("--plan", headers=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["cef_include"], str(self.headers))

    def test_missing_headers_fail_before_output_creation(self):
        (self.headers / "cef_application_mac.h").unlink()
        result = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertIn("Required compiler input", result.stderr)
        self.assertFalse(self.output.exists())

    def test_success_records_toolchain_inputs_and_diagnostics(self):
        # Apple's /usr/bin/git also dispatches through the selected developer
        # directory, so use its real path while substituting only the compiler.
        self.env["DEVELOPER_DIR"] = (subprocess.check_output(["xcode-select", "-p"], text=True).strip()
                                     if sys.platform == "darwin" else "/chosen/developer")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.receipt()
        self.assertTrue(receipt["passed"])
        self.assertTrue(receipt["inputs_unchanged"])
        self.assertTrue(receipt["head_unchanged"])
        self.assertEqual(receipt["toolchain"]["DEVELOPER_DIR"], self.env["DEVELOPER_DIR"])
        self.assertEqual(receipt["compiler_exit"], 0)
        self.assertIn(str(self.headers / "cef_application_mac.h"), receipt["inputs"])
        self.assertIn("test compiler diagnostics", (self.output / "case/compiler.log").read_text())

    def test_compiler_failure_is_preserved(self):
        self.env["FAKE_COMPILER_EXIT"] = "7"
        result = self.run_check()
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertFalse(self.receipt()["passed"])
        self.assertEqual(self.receipt()["compiler_exit"], 7)

    def test_changed_input_invalidates_successful_compiler(self):
        self.env["FAKE_MUTATE_INPUT"] = str(self.headers / "cef_application_mac.h")
        result = self.run_check()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.receipt()["compiler_exit"], 0)
        self.assertFalse(self.receipt()["passed"])
        self.assertFalse(self.receipt()["inputs_unchanged"])

    def test_added_source_invalidates_successful_compiler(self):
        self.env["FAKE_ADD_SOURCE"] = str(self.repo / "Sources/ParcApp/Added.swift")
        result = self.run_check()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.receipt()["inputs_unchanged"])

    def test_added_source_before_compiler_cannot_silently_enter_receipt(self):
        added = self.repo / "Sources/ParcApp/Added.swift"
        self.env["FAKE_ADD_BEFORE_COMPILER"] = str(added)
        result = self.run_check()
        self.assertEqual(result.returncode, 2, result.stderr)
        receipt = self.receipt()
        self.assertFalse(receipt["inputs_unchanged"])
        self.assertNotIn(str(added), receipt["inputs"])
        self.assertNotIn(str(added), receipt["command"])
        self.assertEqual(receipt["source_count"], 2)

    def test_receipts_are_never_overwritten(self):
        first = self.run_check()
        self.assertEqual(first.returncode, 0, first.stderr)
        original = (self.output / "case/result.json").read_bytes()
        second = self.run_check()
        self.assertEqual(second.returncode, 2)
        self.assertIn("already exists", second.stderr)
        self.assertEqual((self.output / "case/result.json").read_bytes(), original)

    def test_label_cannot_escape_receipt_parent(self):
        result = self.run_check("--label", "../escape", "--plan")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
