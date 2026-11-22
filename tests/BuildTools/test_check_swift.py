from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
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
    if os.environ.get('FAKE_COMPILER_WARNING'):
        print(os.environ['FAKE_COMPILER_WARNING'])
    if '--scratch-path' in args:
        scratch = pathlib.Path(args[args.index('--scratch-path') + 1])
        (scratch / 'objects').mkdir(parents=True)
        if os.environ.get('FAKE_RECORD_SCRATCH'):
            pathlib.Path(os.environ['FAKE_RECORD_SCRATCH']).write_text(str(scratch))
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
        self.headers = self.repo / "Engine/ParcNative"
        self.output = root / "check receipts"
        for name, content in {
            "Sources/ParcCore/Model.swift": "struct Model {}\n",
            "Sources/ParcKit/Kit.swift": "struct Kit {}\n",
            "Sources/ParcNotes/Notes.swift": "struct Notes {}\n",
            "Sources/ParcEasels/Easels.swift": "struct Easels {}\n",
            "Sources/ParcLibrary/Library.swift": "struct Library {}\n",
            "Sources/ParcCommandBar/CommandBar.swift": "struct CommandBar {}\n",
            "Sources/ParcSidebar/Sidebar.swift": "struct Sidebar {}\n",
            "Sources/ParcSettings/Settings.swift": "struct Settings {}\n",
            "Sources/ParcOnboarding/Onboarding.swift": "struct Onboarding {}\n",
            "Sources/Parc/App.swift": "struct App {}\n",
            "Sources/ParcMain/main.swift": "print(1)\n",
            "Sources/ParcEngine/ParcEngine.h": "#import <Cocoa/Cocoa.h>\n",
            "Package.swift": "// swift-tools-version: 6.2\n",
            "Package.resolved": "{}\n",
            "Engine/ParcNative/native_appkit_bridge.h": "#pragma once\n",
            "Engine/source-lock.json": "{}\n",
            ".gitignore": "/build/\n",
        }.items():
            file = self.repo / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(content)
        self.headers.mkdir(parents=True, exist_ok=True)
        (self.headers / "native_application_protocols.h").write_text("#pragma once\n")
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
        for name in ("FAKE_MUTATE_INPUT", "FAKE_ADD_SOURCE", "FAKE_COMPILER_EXIT", "FAKE_ADD_BEFORE_COMPILER",
                     "FAKE_COMPILER_WARNING", "FAKE_RECORD_SCRATCH"):
            self.env.pop(name, None)

    def run_check(self, *extra, headers=True):
        command = [sys.executable, str(SCRIPT), "--repo", str(self.repo),
                   "--output-dir", str(self.output), "--label", "case"]
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
        self.assertEqual(plan["source_count"], 11)
        command = plan["command"]
        self.assertEqual(command[:3], ["xcrun", "swift", "build"])
        self.assertEqual(command[command.index("--package-path") + 1], str(self.repo))
        self.assertEqual(command[command.index("--target") + 1], "Parc")
        self.assertEqual(command[command.index("--configuration") + 1], "debug")
        self.assertIn("--disable-keychain", command)
        self.assertNotIn("--scratch-path", command)

    def test_direct_bridge_needs_no_engine_tree(self):
        facade = self.repo / "Sources/ParcEngine/ParcEngine.h"
        facade.write_text('#import "native_application_protocols.h"\n')
        header = self.repo / "Engine/ParcNative/native_application_protocols.h"
        header.write_text("#import <Foundation/Foundation.h>\n")
        result = self.run_check("--plan", headers=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual(plan["bridge_headers"], str(header.parent))
        self.assertIn(str(header), plan["inputs"])

    def test_direct_bridge_missing_declaration_fails_before_output(self):
        (self.repo / "Sources/ParcEngine/ParcEngine.h").write_text('#import "native_application_protocols.h"\n')
        header = self.headers / "native_application_protocols.h"
        header.unlink()
        result = self.run_check("--plan", headers=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("native_application_protocols.h", result.stderr)
        self.assertFalse(self.output.exists())

    def test_sil_mode_is_a_whole_module_debug_build(self):
        result = self.run_check("--mode", "sil", "--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        command = json.loads(result.stdout)["command"]
        self.assertEqual(command[command.index("--configuration") + 1], "debug")
        self.assertEqual(command[command.index("-Xswiftc") + 1], "-whole-module-optimization")
        self.assertEqual(Path(command[command.index("--scratch-path") + 1]).parent, self.output / "case")

    def test_release_mode_builds_the_release_configuration_for_arm64(self):
        result = self.run_check("--mode", "release", "--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        command = json.loads(result.stdout)["command"]
        self.assertEqual(command[command.index("--configuration") + 1], "release")
        self.assertEqual(command[command.index("--arch") + 1], "arm64")
        self.assertEqual(command[command.index("-debug-info-format") + 1], "none")
        self.assertNotIn("-Xswiftc", command)

    def test_release_mode_writes_its_build_only_to_a_removed_directory(self):
        recorded = Path(self.temp.name) / "scratch record"
        self.env["FAKE_RECORD_SCRATCH"] = str(recorded)
        result = self.run_check("--mode", "release")
        self.assertEqual(result.returncode, 0, result.stderr)
        scratch = Path(recorded.read_text())
        self.assertEqual(scratch.parent, self.output / "case")
        self.assertFalse(scratch.exists())
        self.assertEqual(sorted(path.name for path in (self.output / "case").iterdir()),
                         ["compiler.log", "result.json", "start.json"])

    def test_warning_left_by_compiler_fails_the_check(self):
        warning = (f"{self.repo}/Sources/Parc/App.swift:3:47: warning: passing non-Sendable parameter "
                   "'open' to function expecting a '@Sendable' closure")
        self.env["FAKE_COMPILER_WARNING"] = warning
        for mode in ("typecheck", "sil", "release"):
            with self.subTest(mode=mode):
                result = self.run_check("--mode", mode, "--label", mode)
                self.assertEqual(result.returncode, 1, result.stderr)
                receipt = json.loads((self.output / mode / "result.json").read_text())
                self.assertEqual(receipt["compiler_exit"], 0)
                self.assertFalse(receipt["passed"])
                self.assertEqual(receipt["warnings"], [warning])
                self.assertIn(warning, result.stderr)
                self.assertIn("FAIL", result.stdout)

    def test_changed_input_outranks_a_warning(self):
        self.env["FAKE_COMPILER_WARNING"] = "App.swift:1:1: warning: unused"
        self.env["FAKE_MUTATE_INPUT"] = str(self.headers / "native_application_protocols.h")
        result = self.run_check()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.receipt()["warnings"], ["App.swift:1:1: warning: unused"])

    def test_missing_headers_fail_before_output_creation(self):
        (self.headers / "native_application_protocols.h").unlink()
        result = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertIn("Required compiler input", result.stderr)
        self.assertFalse(self.output.exists())

    def test_success_records_toolchain_inputs_and_diagnostics(self):
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
        self.assertEqual(receipt["warnings"], [])
        self.assertIn(str(self.headers / "native_application_protocols.h"), receipt["inputs"])
        self.assertIn(str(self.repo / "Package.resolved"), receipt["inputs"])
        self.assertIn("test compiler diagnostics", (self.output / "case/compiler.log").read_text())

    def test_compiler_failure_is_preserved(self):
        self.env["FAKE_COMPILER_EXIT"] = "7"
        result = self.run_check()
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertFalse(self.receipt()["passed"])
        self.assertEqual(self.receipt()["compiler_exit"], 7)

    def test_changed_input_invalidates_successful_compiler(self):
        self.env["FAKE_MUTATE_INPUT"] = str(self.headers / "native_application_protocols.h")
        result = self.run_check()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.receipt()["compiler_exit"], 0)
        self.assertFalse(self.receipt()["passed"])
        self.assertFalse(self.receipt()["inputs_unchanged"])

    def test_added_source_invalidates_successful_compiler(self):
        self.env["FAKE_ADD_SOURCE"] = str(self.repo / "Sources/Parc/Added.swift")
        result = self.run_check()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.receipt()["inputs_unchanged"])

    def test_added_source_before_compiler_cannot_silently_enter_receipt(self):
        added = self.repo / "Sources/Parc/Added.swift"
        self.env["FAKE_ADD_BEFORE_COMPILER"] = str(added)
        result = self.run_check()
        self.assertEqual(result.returncode, 2, result.stderr)
        receipt = self.receipt()
        self.assertFalse(receipt["inputs_unchanged"])
        self.assertNotIn(str(added), receipt["inputs"])
        self.assertNotIn(str(added), receipt["command"])
        self.assertEqual(receipt["source_count"], 11)

    def test_release_archive_without_git_compiles_by_input_hashes(self):
        archive = Path(self.temp.name).resolve() / "release archive"
        shutil.copytree(self.repo, archive, ignore=shutil.ignore_patterns(".git"))
        self.repo = archive
        self.assertEqual(self.run_check("--mode", "release", "--label", "plain").returncode, 2)
        result = self.run_check("--mode", "release", "--source-archive")
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.receipt()
        self.assertTrue(receipt["passed"])
        self.assertIsNone(receipt["git_before"])
        self.assertIn(str(archive / "Sources/Parc/App.swift"), receipt["inputs"])
        self.env["FAKE_MUTATE_INPUT"] = str(archive / "Sources/Parc/App.swift")
        changed = self.run_check("--mode", "release", "--source-archive", "--label", "changed")
        self.assertEqual(changed.returncode, 2, changed.stderr)

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
