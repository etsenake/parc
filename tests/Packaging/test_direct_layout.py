import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("direct_layout", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


class DirectLayoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.app = self.root / "Parc.app"
        self.images = {}
        self.executables = set()
        self.main = self.add("Parc.app/Contents/MacOS/Parc", executable=True)
        framework_name = pkg.FRAMEWORK + "/" + pkg.ENGINE_NAME
        self.add("Parc.app/Contents/Frameworks/" + framework_name)
        self.add("libseatbelt.dylib")
        self.helper_info = {"id": None, "loads": ["@rpath/libseatbelt.dylib"], "rpaths": [
            "@executable_path/../../../" + pkg.FRAMEWORK + "/Libraries",
            "@executable_path/../../../../../.."]}
        self.helpers = []
        for suffix, _, _ in pkg.HELPERS:
            name = "Parc Helper" + suffix
            path = self.add("Parc.app/Contents/Frameworks/" + name + ".app/Contents/MacOS/" + name, executable=True)
            self.images[path] = dict(self.helper_info)
            self.helpers.append(path)
        self.manifest = {"engine_runtime": "chromium-direct", "components": {"libseatbelt.dylib": {}},
                         "helper": {"image": "parc_helper"}, "images": {
            framework_name: {"id": None, "loads": [], "rpaths": [], "resolved": {}},
            "libseatbelt.dylib": {"id": None, "loads": [], "rpaths": [], "resolved": {}},
            "parc_helper": {**self.helper_info, "resolved": {"@rpath/libseatbelt.dylib": "libseatbelt.dylib"}},
        }}

    def add(self, name, *, executable=False):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"inert image fixture")
        self.images[path] = {"id": None, "loads": [], "rpaths": []}
        if executable:
            self.executables.add(path)
        return path

    def audit(self):
        with patch.object(pkg, "is_macho", side_effect=lambda path: path in self.images), \
                patch.object(pkg, "inspect_macho", side_effect=lambda path: self.images[path]), \
                patch.object(pkg, "macho_layout", side_effect=lambda path: {"file_type": 2 if path in self.executables else 6}):
            return pkg.verify_development_layout(self.app, self.manifest)

    def test_all_five_helpers_resolve_the_sealed_sibling_seatbelt(self):
        audited = self.audit()
        for helper in self.helpers:
            self.assertIn(helper.relative_to(self.root).as_posix(), audited)

    def test_shadow_seatbelt_cannot_replace_the_sealed_library(self):
        self.add("Parc.app/Contents/Frameworks/" + pkg.FRAMEWORK + "/Libraries/libseatbelt.dylib")
        with self.assertRaisesRegex(pkg.Refusal, "Engine dependency changed"):
            self.audit()

    def test_changed_helper_rpaths_are_refused(self):
        self.images[self.helpers[-1]] = {**self.helper_info, "rpaths": ["@executable_path"]}
        with self.assertRaisesRegex(pkg.Refusal, "load commands changed"):
            self.audit()

    def test_changed_helper_load_graph_is_refused(self):
        self.images[self.helpers[-1]] = {**self.helper_info, "loads": ["@rpath/libbase.dylib"]}
        with self.assertRaisesRegex(pkg.Refusal, "pre-sandbox"):
            self.audit()
