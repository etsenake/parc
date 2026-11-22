from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]


@unittest.skipUnless(platform.system() == "Darwin" and shutil.which("xcrun"),
                     "requires the macOS compiler tools")
class NativePageHostExportTests(unittest.TestCase):
    def test_swift_can_link_the_hidden_visibility_native_component(self):
        with tempfile.TemporaryDirectory(prefix="parc-page-host-link-") as directory:
            root = Path(directory)
            library = root / "libParcPageHost.dylib"
            source = root / "main.swift"
            source.write_text(
                "import AppKit\n"
                "let view = NSView()\n"
                "print((view as? PCNativePageHost)?.contentView as Any)\n"
            )

            def compile_source(*arguments):
                result = subprocess.run(["xcrun", *map(str, arguments)],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0,
                                 result.stdout + result.stderr)

            compile_source(
                "clang++", "-arch", "arm64", "-std=c++20",
                "-mmacosx-version-min=13.0", "-dynamiclib",
                "-fobjc-arc", "-fblocks", "-fvisibility=hidden",
                "-Wall", "-Wextra", "-Werror",
                REPO / "Engine/ParcNative/page_host.mm",
                REPO / "Engine/ParcNative/pane_compositor_view.mm",
                REPO / "Engine/ParcNative/dialog_style.mm",
                "-framework", "AppKit", "-framework", "QuartzCore", "-o", library,
            )
            compile_source(
                "swiftc", "-target", "arm64-apple-macos13.0",
                "-import-objc-header", REPO / "Engine/ParcNative/page_host.h",
                source, library, "-o", root / "PageHostConsumer",
            )
            exports = subprocess.check_output(
                ["xcrun", "nm", "-gU", str(library)], text=True)
            self.assertIn("_OBJC_CLASS_$_PCNativePageHost", exports)
            self.assertIn("_OBJC_METACLASS_$_PCNativePageHost", exports)
            self.assertNotIn("PCNativePaneCompositorView", exports)


if __name__ == "__main__":
    unittest.main()
