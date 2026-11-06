"""Standalone packaging checks; no browser or engine build is executed."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("shipping_packager", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


class ShippingPackagingTests(unittest.TestCase):
    def setUp(self):
        self.shipping = {"build_classification": "release-noncomponent", "distribution_eligible": True,
                         "engine_build_flags": {"is_component_build": False}, "components": {}}

    def test_component_build_cannot_become_distribution_by_signing(self):
        component = {**self.shipping, "engine_build_flags": {"is_component_build": True}}
        for manifest in (component, {**self.shipping, "components": {"liba.dylib": {}}},
                         {**self.shipping, "distribution_eligible": False}):
            with self.assertRaisesRegex(pkg.Refusal, "non-component"):
                pkg.require_package_purpose("distribution", manifest, "Developer ID Application: Example")

    def test_shipping_requires_release_and_certificate(self):
        for identity, mode in (("-", "release"), ("", "release"), ("Developer ID", "debug")):
            with self.assertRaisesRegex(pkg.Refusal, "certificate-backed"):
                pkg.require_package_purpose("distribution", self.shipping, identity, mode)
        pkg.require_package_purpose("distribution", self.shipping, "Developer ID", "release")
        pkg.require_package_purpose("development", self.shipping, "-", "debug")

    def test_standalone_load_graph_cannot_escape_to_sibling_library(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); app = root / "Parc.app"
            executable = app / "Contents/MacOS/Parc"
            framework = app / "Contents/Frameworks" / pkg.FRAMEWORK / pkg.ENGINE_NAME
            sibling = root / "libexternal.dylib"
            for path in (executable, framework, sibling):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"\xcf\xfa\xed\xfe" + path.name.encode())
            empty = {"id": None, "loads": [], "rpaths": []}
            definitions = {executable: {"id": None, "loads": ["@rpath/libexternal.dylib"],
                                        "rpaths": ["@executable_path/../../.."]},
                           framework: empty, sibling: empty}
            manifest = {**self.shipping, "images": {}}
            with patch.object(pkg, "inspect_macho", side_effect=definitions.__getitem__), \
                    patch.object(pkg, "macho_layout", return_value={"file_type": 2}):
                with self.assertRaisesRegex(pkg.Refusal, "escapes"):
                    pkg.verify_development_layout(app, manifest)
                # The same original paths remain valid for a component development directory.
                pkg.verify_development_layout(app, {**manifest, "distribution_eligible": False})


if __name__ == "__main__":
    unittest.main()
