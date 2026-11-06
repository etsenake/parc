"""Copy and load real Mach-O fixtures in CEF's unchanged component layout.

These libraries are controlled test inputs, not Chromium. Nothing is rewritten,
and the original output is unavailable when the copied app/helpers are executed.
"""
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_development_layout", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


@unittest.skipUnless(sys.platform == "darwin", "real Mach-O tests require macOS")
class DevelopmentLayoutTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.engine = self.root / "engine-output"
        self.framework = self.engine / pkg.FRAMEWORK
        self.version = self.framework / "Versions/A"
        (self.version / "Libraries").mkdir(parents=True)
        (self.framework / "Versions/Current").symlink_to("A")
        (self.framework / pkg.ENGINE_NAME).symlink_to("Versions/Current/" + pkg.ENGINE_NAME)
        (self.framework / "Libraries").symlink_to("Versions/Current/Libraries")
        component = self.root / "component.c"
        component.write_text("int component_value(void) { return 42; }\n")
        self.component = self.engine / "libcomponent.dylib"
        self.clang("-dynamiclib", component, "-Wl,-install_name,@rpath/libcomponent.dylib",
                   "-Wl,-rpath,@loader_path/.", "-Wl,-rpath,@loader_path/../../..", "-o", self.component)
        framework_source = self.root / "framework.c"
        framework_source.write_text("extern int component_value(void); int fixture_value(void) { return component_value(); }\n")
        self.framework_binary = self.version / pkg.ENGINE_NAME
        self.clang("-dynamiclib", framework_source, self.component,
                   "-Wl,-install_name,@executable_path/../Frameworks/" + pkg.FRAMEWORK + "/" + pkg.ENGINE_NAME,
                   "-Wl,-rpath,@loader_path/../../../../../..", "-Wl,-rpath,@loader_path/.",
                   "-Wl,-rpath,@loader_path/../../..", "-o", self.framework_binary)
        sandbox_source = self.root / "sandbox.c"
        sandbox_source.write_text("extern int component_value(void); int sandbox_value(void) { return component_value(); }\n")
        self.sandbox = self.version / "Libraries/libcef_sandbox.dylib"
        # Like the actual sandbox, this has no development-root RPATH of its own.
        self.clang("-dynamiclib", sandbox_source, self.component,
                   "-Wl,-install_name,@rpath/libcef_sandbox.dylib",
                   "-Wl,-rpath,@loader_path/.", "-Wl,-rpath,@loader_path/../../..", "-o", self.sandbox)
        self.manifest = self.seal()

    def clang(self, *args):
        subprocess.run(["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=13.0",
                        *map(str, args)], check=True, capture_output=True)

    def seal(self, extra=()):
        graph = pkg.dependency_closure(self.engine, [self.framework_binary, self.sandbox, *extra])
        return {"framework": pkg.inventory_tree(self.framework), "images": graph,
                "components": {name: {"sha256": pkg.sha(self.engine / name),
                                       "mode": (self.engine / name).stat().st_mode & 0o777}
                               for name in graph if not name.startswith(pkg.FRAMEWORK + "/")}}

    def compile_app(self, app, *, helper_rpath=True):
        executable = app / "Contents/MacOS" / app.stem
        executable.parent.mkdir(parents=True)
        (app / "Contents/Frameworks").mkdir()
        source = self.root / (app.stem + ".c")
        if app.stem == "Parc":
            source.write_text("extern int fixture_value(void); int main(void) { return fixture_value() != 42; }\n")
            self.clang(source, self.framework_binary, "-Wl,-rpath,@executable_path/../Frameworks", "-o", executable)
        else:
            source.write_text('#include <dlfcn.h>\nint main(int argc,char** argv) { if(argc!=2)return 2; '
                              'void* lib=dlopen(argv[1],RTLD_NOW); if(!lib)return 3; '
                              'int(*value)(void)=dlsym(lib,"fixture_value"); return !value||value()!=42; }\n')
            self.clang(source, "-o", executable)
        helper = app / "Contents/Frameworks" / (app.stem + " Helper.app/Contents/MacOS") / (app.stem + " Helper")
        helper.parent.mkdir(parents=True)
        helper_source = self.root / "helper.c"
        helper_source.write_text('#include <dlfcn.h>\nint main(int argc,char** argv) { if(argc!=2)return 2; '
                                 'void* lib=dlopen(argv[1],RTLD_NOW); if(!lib)return 3; '
                                 'int(*value)(void)=dlsym(lib,"sandbox_value"); return !value||value()!=42; }\n')
        rpath = ["-Wl,-rpath,@executable_path/../../../../../.."] if helper_rpath else []
        self.clang(helper_source, *rpath, "-o", helper)
        return executable, helper

    def test_unchanged_app_and_sandbox_first_helpers_load_without_original_output(self):
        originals = {name: (self.engine / name).read_bytes() for name in self.manifest["images"]}
        layouts = []
        for app_name in ("Parc", "parc_native_runtime_tests"):
            app = self.root / ("development-" + app_name) / (app_name + ".app")
            self.compile_app(app)
            copied = pkg.copy_engine(self.engine, app, self.manifest)
            for name, data in originals.items():
                target = pkg.development_engine_path(app, name)
                self.assertEqual(target.read_bytes(), data)
                self.assertEqual(copied[target.relative_to(app.parent).as_posix()], pkg.sha(self.engine / name))
            images = pkg.verify_development_layout(app, self.manifest)
            self.assertIn("libcomponent.dylib", images)
            self.assertFalse((app / "Contents/Frameworks/libcomponent.dylib").exists())
            for name in images:
                if (app.parent / name).parent.name == "MacOS":
                    continue  # These untouched fixture executables retain their linker signature.
                subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app.parent / name)],
                               check=True, capture_output=True)
            pkg.verify_development_layout(app, self.manifest)
            layouts.append(app)
        for name, data in originals.items():
            self.assertEqual((self.engine / name).read_bytes(), data)
        self.engine.rename(self.root / "unavailable-original-output")
        for app in layouts:
            moved = self.root / (app.parent.name + "-moved")
            pkg.publish_development_directory(app.parent, moved)
            app = moved / app.name
            pkg.verify_development_layout(app, self.manifest)
            framework = app / "Contents/Frameworks" / pkg.FRAMEWORK
            executable = app / "Contents/MacOS" / app.stem
            result = subprocess.run([str(executable), str(framework / pkg.ENGINE_NAME)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            helper = app / "Contents/Frameworks" / (app.stem + " Helper.app/Contents/MacOS") / (app.stem + " Helper")
            # This process loads only the sandbox, before any framework RPATH exists.
            result = subprocess.run([str(helper), str(framework / "Libraries/libcef_sandbox.dylib")], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_restart_helper_is_audited_without_loading_the_browser_engine(self):
        app = self.root / "development/Parc.app"
        self.compile_app(app)
        pkg.copy_engine(self.engine, app, self.manifest)
        restart = app / "Contents/MacOS/ParcRestart"
        self.clang(REPO / "Sources/ParcRestart/main.c", "-Wall", "-Wextra", "-Werror", "-o", restart)
        self.assertEqual(pkg.inspect_macho(restart)["rpaths"], [])
        images = pkg.verify_development_layout(app, self.manifest)
        self.assertIn("Parc.app/Contents/MacOS/ParcRestart", images)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(restart)],
                       check=True, capture_output=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(restart)],
                       check=True, capture_output=True)
        self.assertIn("Parc.app/Contents/MacOS/ParcRestart",
                      pkg.verify_development_layout(app, self.manifest))

    def test_missing_helper_root_rpath_is_not_masked_by_framework(self):
        app = self.root / "development/Parc.app"
        self.compile_app(app, helper_rpath=False)
        pkg.copy_engine(self.engine, app, self.manifest)
        with self.assertRaisesRegex(pkg.Refusal, "Unresolved development dependency"):
            pkg.verify_development_layout(app, self.manifest)

    def test_dock_plugin_is_audited_as_a_bundle(self):
        app = self.root / "development/Parc.app"
        self.compile_app(app)
        pkg.copy_engine(self.engine, app, self.manifest)
        plugin = app / "Contents/PlugIns/ParcDockTile.plugin/Contents/MacOS/ParcDockTile"
        plugin.parent.mkdir(parents=True)
        source = self.root / "dock-plugin.c"
        source.write_text("int dock_value(void) { return 42; }\n")
        self.clang("-bundle", source, "-o", plugin)
        self.assertEqual(struct.unpack("<8I", plugin.read_bytes()[:32])[3], 8)  # MH_BUNDLE
        images = pkg.verify_development_layout(app, self.manifest)
        self.assertIn(plugin.relative_to(app.parent).as_posix(), images)

    def test_copy_refuses_changed_sealed_component(self):
        app = self.root / "development/Parc.app"
        self.compile_app(app)
        self.component.write_bytes(self.component.read_bytes() + b"changed after seal")
        with self.assertRaisesRegex(pkg.Refusal, "Copied component differs"):
            pkg.copy_engine(self.engine, app, self.manifest)

    @unittest.skipUnless(os.environ.get("PARC_CHROMIUM_SOURCE"), "set PARC_CHROMIUM_SOURCE for pinned LLD fixture")
    def test_sectionless_component_keeps_bytes_and_loads_without_rewriting(self):
        tools = Path(os.environ["PARC_CHROMIUM_SOURCE"]) / "third_party/llvm-build/Release+Asserts/bin"
        assembly = self.root / "empty.s"
        assembly.write_text("")
        obj = self.root / "empty.o"
        subprocess.run([str(tools / "clang"), "-target", "arm64-apple-macos13.0", "-c", str(assembly), "-o", str(obj)],
                       check=True, capture_output=True)
        image = self.engine / "libempty.dylib"
        sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
        version = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"], text=True).strip()
        subprocess.run([str(tools / "ld64.lld"), "-dylib", "-arch", "arm64", "-platform_version", "macos", "13.0", version,
                        "-dead_strip", "-syslibroot", sdk, "-lSystem", "-install_name", "@rpath/libempty.dylib",
                        "-rpath", "@loader_path/.", "-rpath", "@loader_path/../../..", "-o", str(image), str(obj)],
                       check=True, capture_output=True)
        self.assertTrue(pkg.macho_layout(image)["sectionless_dylib"])
        original = image.read_bytes()
        self.manifest = self.seal([image])
        app = self.root / "development/Parc.app"
        self.compile_app(app)
        pkg.copy_engine(self.engine, app, self.manifest)
        copied = app.parent / image.name
        self.assertEqual(copied.read_bytes(), original)
        pkg.verify_development_layout(app, self.manifest)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(copied)], check=True, capture_output=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(copied)], check=True, capture_output=True)
        self.engine.rename(self.root / "unavailable-original-output")
        result = subprocess.run([sys.executable, "-c", "import ctypes,sys; ctypes.CDLL(sys.argv[1])", str(copied)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(pkg.inspect_macho(copied)["rpaths"], ["@loader_path/.", "@loader_path/../../.."])

    def test_structural_validation_rejects_bad_header_and_segment_bounds(self):
        original = self.component.read_bytes()
        for name, offset, value, fmt in (("unmapped-header", 32 + 48, 0, "<Q"),
                                        ("segment-outside-file", 32 + 48, len(original) + 1, "<Q"),
                                        ("load-table-outside-file", 20, len(original), "<I")):
            with self.subTest(name=name):
                corrupt = self.root / (name + ".dylib")
                data = bytearray(original)
                struct.pack_into(fmt, data, offset, value)
                corrupt.write_bytes(data)
                with self.assertRaises(pkg.Refusal):
                    pkg.inspect_macho(corrupt)


if __name__ == "__main__":
    unittest.main()
