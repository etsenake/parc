from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]


@unittest.skipUnless(platform.system() == "Darwin" and shutil.which("xcrun"),
                     "requires the macOS compiler tools")
class NativeContentDropExportTests(unittest.TestCase):
    def test_swift_links_only_the_public_engine_factory(self):
        with tempfile.TemporaryDirectory(prefix="parc-content-drop-link-") as directory:
            root = Path(directory)
            native = REPO / "Engine/ParcNative"
            includes = root / "ui/base/cocoa"
            includes.mkdir(parents=True)
            (includes / "content_drop_router.h").symlink_to(native / "content_drop_router.h")
            component = root / "libDropComponent.dylib"
            engine = root / "libDropEngine.dylib"
            header = root / "Bridge.h"
            header.write_text('#import "content_drop_router.h"\n'
                              '#import "content_drop_bridge.h"\n')

            def compile_source(*arguments, succeeds=True):
                result = subprocess.run(["xcrun", *map(str, arguments)],
                                        text=True, capture_output=True)
                if succeeds:
                    self.assertEqual(result.returncode, 0,
                                     result.stdout + result.stderr)
                else:
                    self.assertNotEqual(result.returncode, 0)
                return result

            common = ["clang++", "-arch", "arm64", "-std=c++20",
                      "-mmacosx-version-min=13.0", "-dynamiclib",
                      "-fobjc-arc", "-fblocks", "-fvisibility=hidden",
                      "-Wall", "-Wextra", "-Werror", "-I", root,
                      "-I", native, "-framework", "AppKit"]
            compile_source(*common, native / "content_drop_router.mm", "-o", component)
            compile_source(*common, native / "content_drop_bridge.mm",
                           component, "-o", engine)
            consumer = root / "Consumer.swift"
            consumer.write_text(
                "import AppKit\n"
                "@MainActor func receive(_ info: NSDraggingInfo) {\n"
                " let router = PCCreateNativeContentDropRouter(NSView())\n"
                " _ = router.claimed; _ = router.operation\n"
                " _ = router.begin(info); _ = router.update(info)\n"
                " _ = router.prepare(info); _ = router.perform(info); router.end()\n"
                "}\n"
            )
            swift = ["swiftc", "-target", "arm64-apple-macos13.0",
                     "-warnings-as-errors", "-I", native,
                     "-import-objc-header", header, consumer,
                     engine, "-o", root / "Consumer"]
            compile_source(*swift)
            exports = subprocess.check_output(
                ["xcrun", "nm", "-gU", str(engine)], text=True)
            self.assertIn("_PCCreateNativeContentDropRouter", exports)
            self.assertNotIn("_OBJC_CLASS_$_PCNativeContentDropRouter", exports)

            consumer.write_text(consumer.read_text().replace(
                "PCCreateNativeContentDropRouter(NSView())",
                "PCNativeContentDropRouter(view: NSView())"))
            rejected = compile_source(*swift, succeeds=False)
            self.assertIn("_OBJC_CLASS_$_PCNativeContentDropRouter", rejected.stderr)
            self.assertIn("Undefined symbols", rejected.stderr)


if __name__ == "__main__":
    unittest.main()
