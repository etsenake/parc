from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import native


class FakeBuild:
    def __init__(self, fail_on=None):
        self.commands = []
        self.fail_on = fail_on

    def __call__(self, argv, **kwargs):
        self.commands.append(list(argv))
        if self.fail_on and argv[0] == self.fail_on:
            raise subprocess.CalledProcessError(1, argv)
        if argv[0] in ("swiftc", "clang"):
            Path(argv[argv.index("-o") + 1]).write_text(f"built {len(self.commands)}")
        return subprocess.CompletedProcess(argv, 0)


class NamingTests(unittest.TestCase):
    def test_swift_tools_are_bare_executables(self):
        self.assertEqual(native.output_name("parcperf", Path("parcperf.swift")), "parcperf")

    def test_objc_and_c_sources_become_dylibs(self):
        self.assertEqual(native.output_name("parcframes", Path("parcframes.m")), "parcframes.dylib")
        self.assertEqual(native.output_name("parcsample", Path("parcsample.c")), "parcsample.dylib")

    def test_other_sources_are_refused(self):
        with self.assertRaises(ValueError):
            native.output_name("tool", Path("tool.py"))
        with self.assertRaises(ValueError):
            native.command_templates(Path("tool"))

    def test_every_native_source_has_a_build(self):
        sources = sorted(path for path in native.NATIVE.iterdir() if not path.name.startswith("."))
        self.assertEqual([source.name for source in sources],
                         ["parcframes.m", "parcmark.m", "parcperf.swift", "parcsample.c", "parctabs.m",
                          "xbench_probe.swift"])
        for source in sources:
            self.assertTrue(native.command_templates(source))

    def test_tools_live_in_the_worktree_build_folder(self):
        self.assertEqual(native.TOOLS, native.ROOT / "build" / "perf-tools")
        self.assertTrue((native.ROOT / "tests" / "Performance" / "native.py").is_file())


class CommandTests(unittest.TestCase):
    def test_swift_matches_ardia(self):
        self.assertEqual(native.build_commands(Path("/s/parcperf.swift"), Path("/o/parcperf")),
                         [["swiftc", "-O", "/s/parcperf.swift", "-o", "/o/parcperf"]])

    def test_objc_matches_ardia_and_is_signed_ad_hoc(self):
        self.assertEqual(native.build_commands(Path("/s/parctabs.m"), Path("/o/parctabs.dylib")), [
            ["clang", "-dynamiclib", "-fobjc-arc", "-framework", "AppKit", "-framework", "QuartzCore",
             "-arch", "arm64", "/s/parctabs.m", "-o", "/o/parctabs.dylib"],
            ["codesign", "--force", "--sign", "-", "/o/parctabs.dylib"],
        ])

    def test_c_needs_no_objc_or_frameworks(self):
        self.assertEqual(native.build_commands(Path("/s/parcsample.c"), Path("/o/parcsample.dylib")), [
            ["clang", "-dynamiclib", "-arch", "arm64", "/s/parcsample.c", "-o", "/o/parcsample.dylib"],
            ["codesign", "--force", "--sign", "-", "/o/parcsample.dylib"],
        ])

    def test_paths_with_spaces_stay_single_arguments(self):
        commands = native.build_commands(Path("/a b/parcmark.m"), Path("/c d/parcmark.dylib"))
        self.assertIn("/a b/parcmark.m", commands[0])
        self.assertEqual(commands[1][-1], "/c d/parcmark.dylib")


class CacheKeyTests(unittest.TestCase):
    def test_same_source_and_commands_give_the_same_key(self):
        templates = native.command_templates(Path("x.m"))
        self.assertEqual(native.cache_key(b"int x;", templates), native.cache_key(b"int x;", templates))
        self.assertEqual(len(native.cache_key(b"int x;", templates)), 64)

    def test_source_changes_change_the_key(self):
        templates = native.command_templates(Path("x.m"))
        self.assertNotEqual(native.cache_key(b"int x;", templates), native.cache_key(b"int y;", templates))

    def test_build_flag_changes_change_the_key(self):
        self.assertNotEqual(native.cache_key(b"int x;", native.command_templates(Path("x.m"))),
                            native.cache_key(b"int x;", native.command_templates(Path("x.c"))))

    def test_key_does_not_depend_on_where_it_is_built(self):
        templates = native.command_templates(Path("/one/x.swift"))
        self.assertEqual(templates, native.command_templates(Path("/two/x.swift")))


class CompiledTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="parc-native-test-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.tools = self.root / "build" / "perf-tools"
        tools = patch.object(native, "TOOLS", self.tools)
        tools.start()
        self.addCleanup(tools.stop)

    def source(self, name, text):
        path = self.root / name
        path.write_text(text)
        return path

    def build(self, name, source, fake):
        with patch.object(native.subprocess, "run", side_effect=fake):
            return native.compiled(name, source)

    def test_swift_tool_builds_once_and_is_cached(self):
        source = self.source("parcperf.swift", "print(1)\n")
        fake = FakeBuild()
        binary = self.build("parcperf", source, fake)
        self.assertEqual(binary, self.tools / "parcperf")
        self.assertTrue(binary.is_file())
        self.assertEqual(len(fake.commands), 1)
        self.assertEqual(fake.commands[0][:3], ["swiftc", "-O", str(source.resolve())])
        again = FakeBuild()
        self.assertEqual(self.build("parcperf", source, again), binary)
        self.assertEqual(again.commands, [])

    def test_dylib_is_signed_before_it_replaces_the_cached_copy(self):
        source = self.source("parcframes.m", "int x;\n")
        fake = FakeBuild()
        binary = self.build("parcframes", source, fake)
        self.assertEqual(binary, self.tools / "parcframes.dylib")
        self.assertEqual([command[0] for command in fake.commands], ["clang", "codesign"])
        built = Path(fake.commands[0][-1])
        self.assertEqual(fake.commands[1][-1], str(built))
        self.assertEqual(built.name, "parcframes.dylib")
        self.assertNotEqual(built, binary)
        self.assertFalse(built.parent.exists())

    def test_source_change_rebuilds(self):
        source = self.source("parcmark.m", "int x;\n")
        self.build("parcmark", source, FakeBuild())
        source.write_text("int y;\n")
        fake = FakeBuild()
        self.build("parcmark", source, fake)
        self.assertEqual(len(fake.commands), 2)

    def test_missing_stamp_or_binary_rebuilds(self):
        source = self.source("parcsample.c", "int x;\n")
        binary = self.build("parcsample", source, FakeBuild())
        native.stamp_path(binary).unlink()
        fake = FakeBuild()
        self.build("parcsample", source, fake)
        self.assertEqual(len(fake.commands), 2)
        binary.unlink()
        fake = FakeBuild()
        self.build("parcsample", source, fake)
        self.assertEqual(len(fake.commands), 2)

    def test_stamp_records_the_cache_key(self):
        source = self.source("parctabs.m", "int x;\n")
        binary = self.build("parctabs", source, FakeBuild())
        key = native.cache_key(source.read_bytes(), native.command_templates(source))
        self.assertEqual(native.stamp_path(binary).read_text().strip(), key)
        self.assertTrue(native.is_current(binary, key))

    def test_failed_build_leaves_no_binary_stamp_or_scratch(self):
        source = self.source("parcframes.m", "int x;\n")
        with self.assertRaises(subprocess.CalledProcessError):
            self.build("parcframes", source, FakeBuild(fail_on="codesign"))
        self.assertEqual(list(self.tools.iterdir()), [])

    def test_failed_rebuild_keeps_the_previous_tool(self):
        source = self.source("parcperf.swift", "print(1)\n")
        binary = self.build("parcperf", source, FakeBuild())
        before = binary.read_text()
        source.write_text("print(2)\n")
        with self.assertRaises(subprocess.CalledProcessError):
            self.build("parcperf", source, FakeBuild(fail_on="swiftc"))
        self.assertEqual(binary.read_text(), before)
        self.assertFalse(native.is_current(binary, native.cache_key(source.read_bytes(),
                                                                    native.command_templates(source))))

    def test_dylib_refuses_swift(self):
        source = self.source("parcperf.swift", "print(1)\n")
        with self.assertRaises(ValueError):
            native.dylib("parcperf", source)

    def test_dylib_builds_injected_libraries(self):
        source = self.source("parcsample.c", "int x;\n")
        with patch.object(native.subprocess, "run", side_effect=FakeBuild()):
            self.assertEqual(native.dylib("parcsample", source), self.tools / "parcsample.dylib")


if __name__ == "__main__":
    unittest.main()
