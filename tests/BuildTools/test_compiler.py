from __future__ import annotations

import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
SHIM = SCRIPTS.parent / "tests/Support/compilers/xcrun"


def load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


compiler = load("parc_compiler_test", "compiler.py")
SENDABLE = ("/Users/me/Parc checkout/Sources/ParcApp/Peek.swift:418:47: warning: passing non-Sendable "
            "parameter 'open' to function expecting a '@Sendable' closure")


def tool(*lines: str, stream: str = "stdout", code: int = 0) -> list[str]:
    script = f"import sys\nfor line in {list(lines)!r}:\n    print(line, file=sys.{stream})\nsys.exit({code})\n"
    return [sys.executable, "-c", script]


class CompilerWarningTests(unittest.TestCase):
    def test_finds_only_compiler_warning_lines(self):
        output = "\n".join([
            SENDABLE,
            "410 |     func movePeekParentHere(_ parent: UUID, then open: @escaping () -> Void) -> Bool {",
            "    |                                               `- warning: passing non-Sendable parameter",
            "<unknown>:0: warning: unknown option ignored",
            "warning: unknown argument '-frobnicate'",
            "clang: warning: -lfoo: 'linker' input unused [-Wunused-command-line-argument]",
            "cc: warning: -Wl,-rpath,/a: 'linker' input unused",
            "c++: warning: -Wl,-rpath,/a: 'linker' input unused",
            "libtool: warning: 'e.o' has no symbols",
            "Sources/ParcRestart/main.c:12: warning: implicit conversion",
            "ld: warning: duplicate -rpath '/a' ignored",
            "/repo/Package.swift: Parc-product: ld: warning: duplicate -rpath '/a' ignored",
            "ld: fatal warning(s) induced error (-fatal_warnings)",
            "Sources/ParcApp/App.swift:3:1: error: cannot find 'x' in scope",
            "1 warning generated.",
        ])
        self.assertEqual(compiler.warnings(output), [
            SENDABLE,
            "<unknown>:0: warning: unknown option ignored",
            "warning: unknown argument '-frobnicate'",
            "clang: warning: -lfoo: 'linker' input unused [-Wunused-command-line-argument]",
            "cc: warning: -Wl,-rpath,/a: 'linker' input unused",
            "c++: warning: -Wl,-rpath,/a: 'linker' input unused",
            "libtool: warning: 'e.o' has no symbols",
            "Sources/ParcRestart/main.c:12: warning: implicit conversion",
            "ld: warning: duplicate -rpath '/a' ignored",
            "/repo/Package.swift: Parc-product: ld: warning: duplicate -rpath '/a' ignored",
        ])

    def test_undecodable_output_still_reaches_the_scan(self):
        script = "import sys\nsys.stderr.buffer.write(b'a.swift:1:2: warning: \\xff bad byte\\n')\n"
        with self.assertRaises(compiler.Warnings) as raised:
            compiler.run([sys.executable, "-c", script])
        self.assertIn("a.swift:1:2: warning:", str(raised.exception))

    def test_captured_compile_returns_output_when_clean(self):
        self.assertEqual(compiler.run(tool("deps.o: main.c")), "deps.o: main.c\n")

    def test_captured_compile_rejects_a_warning_on_either_stream(self):
        for stream in ("stdout", "stderr"):
            with self.subTest(stream=stream), self.assertRaises(compiler.Warnings) as raised:
                compiler.run(tool(SENDABLE, stream=stream))
            self.assertIn(SENDABLE, str(raised.exception))
            self.assertIsInstance(raised.exception, ValueError)

    def test_captured_failure_keeps_compiler_errors(self):
        with self.assertRaises(subprocess.CalledProcessError) as raised:
            compiler.run(tool("main.c:1:1: error: nope", stream="stderr", code=3))
        self.assertEqual(raised.exception.returncode, 3)
        self.assertIn("error: nope", raised.exception.stderr)

    def test_streamed_compile_echoes_each_stream_and_rejects_a_warning(self):
        script = (f"import sys\nprint('swift-frontend -frontend -c', flush=True)\n"
                  f"print({SENDABLE!r}, file=sys.stderr, flush=True)\n")
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                self.assertRaises(compiler.Warnings) as raised:
            compiler.run([sys.executable, "-c", script], capture=False)
        self.assertEqual(out.getvalue(), "swift-frontend -frontend -c\n")
        self.assertEqual(err.getvalue(), SENDABLE + "\n")
        self.assertIn(SENDABLE, str(raised.exception))

    def test_a_reader_that_goes_away_cannot_stall_the_compiler(self):
        class Closed(io.StringIO):
            def write(self, text):
                raise BrokenPipeError(32, "Broken pipe")

        script = "import sys\nfor n in range(200000):\n    print('line', n)\nprint('a.c:1:1: warning: late')\n"
        outcome = []
        def run():
            with contextlib.redirect_stdout(Closed()):
                outcome.append(compiler.forward([sys.executable, "-c", script]))
        worker = threading.Thread(target=run)
        worker.start()
        worker.join(60)
        self.assertFalse(worker.is_alive())
        self.assertEqual(outcome, [(0, ["a.c:1:1: warning: late"])])

    def test_streamed_failure_raises_its_exit_status(self):
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(subprocess.CalledProcessError) as raised:
            compiler.run(tool("main.c:1:1: error: nope", code=4), capture=False)
        self.assertEqual(raised.exception.returncode, 4)

    def test_streamed_clean_compile_passes(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(compiler.run(tool("Apple Swift version 6"), capture=False), "")


class TestRunnerShimTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="parc compiler shim ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def shim(self, *arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run([str(SHIM), *arguments], cwd=self.root, text=True, capture_output=True, timeout=120)

    def source(self, text: str) -> str:
        (self.root / "main.c").write_text(text)
        return "main.c"

    def test_clean_compile_keeps_its_streams_and_status(self):
        result = self.shim("clang", self.source("int main(void) { return 0; }\n"), "-o", "clean")
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))
        self.assertTrue((self.root / "clean").is_file())

    def test_softened_compiler_warning_fails_without_warnings_as_errors(self):
        result = self.shim("clang", "-Wall", "-c", self.source("int main(void) { int unused; return 0; }\n"))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("warning: unused variable 'unused'", result.stderr)
        self.assertIn("clang -Wall reported 1 warning(s); Parc treats every compiler and linker warning as an error",
                      result.stderr)

    def test_linker_warning_fails(self):
        result = self.shim("--sdk", "macosx", "clang", self.source("int main(void) { return 0; }\n"),
                           "-Wl,-rpath,/a", "-Wl,-rpath,/a", "-o", "linked")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("ld: warning: duplicate -rpath '/a' ignored", result.stderr)
        self.assertIn("clang main.c reported 1 warning(s)", result.stderr)

    def test_compiler_errors_keep_the_compiler_status_and_message(self):
        result = self.shim("--sdk", "macosx", "clang", "-c", self.source("int main(void) { return missing; }\n"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("error: use of undeclared identifier 'missing'", result.stderr)
        self.assertNotIn("Parc treats", result.stderr)

    def test_other_tools_pass_straight_through(self):
        result = self.shim("--show-sdk-path")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.strip().endswith(".sdk"))


class PackagingCompilerTests(unittest.TestCase):
    def test_packaging_routes_every_compiler_through_the_warning_check(self):
        build = load("parc_build_compiler_test", "build.py")
        commands = [("xcrun", "swiftc", "-v", "main.swift"), ("xcrun", "clang", "-Werror", "main.c")]
        for command in commands:
            for capture in (True, False):
                with self.subTest(command=command, capture=capture), \
                        patch.object(build.compiler, "run", return_value="checked") as checked:
                    self.assertEqual(build.run(*command, capture=capture), "checked")
                    checked.assert_called_once_with(list(command), capture=capture)
        with patch.object(build.compiler, "run") as checked, \
                patch.object(build.subprocess, "check_output", return_value="signed") as other:
            self.assertEqual(build.run("/usr/bin/codesign", "-dv", "Parc.app"), "signed")
        checked.assert_not_called()
        other.assert_called_once()

    def test_package_builds_never_wait_on_the_keychain(self):
        for configuration in ("debug", "release"):
            with self.subTest(configuration=configuration):
                self.assertIn("--disable-keychain", compiler.swift_build(Path("/repo"), configuration))

    def test_release_package_builds_are_arm64_without_debug_info(self):
        command = compiler.swift_build(Path("/repo"), "release", scratch=Path("/scratch"))
        self.assertEqual(command[command.index("--arch") + 1], "arm64")
        self.assertEqual(command[command.index("-debug-info-format") + 1], "none")
        self.assertEqual(command[command.index("--scratch-path") + 1], "/scratch")

    def test_package_builds_keep_linker_defaults_of_the_old_link(self):
        command = compiler.swift_build(Path("/repo"), "debug")
        self.assertIn("--disable-dead-strip", command)
        self.assertIn("--disable-local-rpath", command)

    def test_package_objects_come_from_the_product_link_file_list(self):
        with tempfile.TemporaryDirectory() as temporary:
            scratch = Path(temporary)
            objects = [scratch / "objects dir" / "Parc.o", scratch / "ParcCore.o"]
            for path in objects:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"object")
            listing = scratch / "out/Intermediates.noindex/Parc.build/Release/Parc-p.build/Objects-normal/arm64/Parc.LinkFileList"
            listing.parent.mkdir(parents=True)
            listing.write_text(" ".join(f'"{path}"' for path in objects))
            self.assertEqual(compiler.package_objects(scratch, "release"), objects)

    def test_missing_link_file_list_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, "link file list"):
                compiler.package_objects(Path(temporary), "release")


if __name__ == "__main__":
    unittest.main()
