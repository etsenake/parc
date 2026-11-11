"""Seal direct-engine fixtures without compiling or loading Chromium."""
import importlib.util
from pathlib import Path
import tempfile
import plistlib
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("direct_packager", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


class DirectEngineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.framework = self.root / pkg.FRAMEWORK
        for name in (pkg.ENGINE_NAME, "Resources/resources.pak", "Resources/chrome_100_percent.pak",
                     "Resources/chrome_200_percent.pak", "Resources/icudtl.dat",
                     "Resources/v8_context_snapshot.arm64.bin", "Resources/en.lproj/locale.pak",
                     "Libraries/libvk_swiftshader.dylib", "Libraries/libvulkan.dylib",
                     "Libraries/vk_swiftshader_icd.json"):
            target = self.framework / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"fixture")
        version = self.framework / "Versions/A"
        version.mkdir(parents=True)
        for name in (pkg.ENGINE_NAME, "Resources", "Libraries"):
            (self.framework / name).rename(version / name)
            (self.framework / name).symlink_to("Versions/Current/" + name)
        (self.framework / "Versions/Current").symlink_to("A")
        (version / "Resources/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.cef.framework", "CFBundleExecutable": pkg.ENGINE_NAME}))
        (self.root / "parc_helper").write_bytes(b"helper")
        (self.root / "parc_helper").chmod(0o755)
        self.loads = {}

    def seal(self, shipping=False):
        closure = pkg.dependency_closure
        def inspect(path):
            return {"id": None, "loads": self.loads.get(path.name, []), "rpaths": []}
        with patch.object(pkg, "exported_symbols", return_value=pkg.PUBLIC_SYMBOLS), \
                patch.object(pkg, "is_macho", return_value=True), \
                patch.object(pkg, "dependency_closure", side_effect=lambda root, seeds: closure(root, seeds, inspect)):
            return pkg.seal_framework(self.root, {"use_static_angle": True, "distribution_eligible": shipping})

    def test_direct_shipping_seals_helper_without_cef_sandbox(self):
        manifest = self.seal(shipping=True)
        self.assertEqual(manifest["engine_runtime"], "chromium-direct")
        self.assertEqual(manifest["helper"]["sha256"], pkg.sha(self.root / "parc_helper"))
        self.assertEqual(manifest["components"], {})
        self.assertIn("parc_helper", manifest["images"])

    def test_component_seatbelt_is_included_and_engine_dependency_is_refused(self):
        (self.root / "libseatbelt.dylib").write_bytes(b"seatbelt")
        self.loads["parc_helper"] = ["@rpath/libseatbelt.dylib"]
        manifest = self.seal()
        self.assertIn("libseatbelt.dylib", manifest["components"])
        self.loads["libseatbelt.dylib"] = ["@rpath/libbase.dylib"]
        (self.root / "libbase.dylib").write_bytes(b"base")
        with self.assertRaisesRegex(pkg.Refusal, "pre-sandbox"):
            self.seal()

    def test_framework_identity_and_version_are_enforced(self):
        info = self.framework / "Resources/Info.plist"
        original = info.read_bytes()
        info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "other.framework", "CFBundleExecutable": pkg.ENGINE_NAME}))
        with self.assertRaisesRegex(pkg.Refusal, "identity"):
            self.seal()
        info.write_bytes(original)
        (self.framework / "Versions/Current").unlink()
        (self.framework / "Versions/B").symlink_to("A")
        (self.framework / "Versions/Current").symlink_to("B")
        with self.assertRaisesRegex(pkg.Refusal, "Versions/A"):
            self.seal()

    def test_direct_helper_contract_refuses_missing_cdm_or_alerts_routes(self):
        files = {
            "content/public/app/mac_helpers.gni": 'content_mac_helpers = [\n["default", "", ""], ["renderer", ".renderer", " (Renderer)"], ["gpu", "", " (GPU)"],\n]',
            "parc/helper/BUILD.gn": 'executable("parc_helper") { deps = [ "//sandbox/mac:seatbelt" ] }',
            "parc/parc_content_clients.cc": 'constexpr char kMacHelperSuffixCdm[] = " (CDM)"; SetCdmServiceChildFlags( HelperExecutablePath(chrome::kMacHelperSuffixAlerts)',
            "parc/parc_bundle_mac.mm": 'name + " Helper"',
            "chrome/common/chrome_constants.cc": 'kMacHelperSuffixAlerts[] = " (Alerts)";',
        }
        for name, text in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        pkg.check_helper_contract(self.root)
        for name in ("parc/helper/BUILD.gn", "parc/parc_content_clients.cc", "parc/parc_bundle_mac.mm", "chrome/common/chrome_constants.cc"):
            path = self.root / name
            original = path.read_text()
            path.write_text("")
            with self.assertRaisesRegex(pkg.Refusal, "routing|Seatbelt"):
                pkg.check_helper_contract(self.root)
            path.write_text(original)

    def test_release_rejects_swapped_helper(self):
        package = self.root / "package"
        engine = package / "Parc.app/Contents/Frameworks"
        helper = engine / "Parc Helper.app/Contents/MacOS/Parc Helper"
        helper.parent.mkdir(parents=True)
        helper.write_bytes(b"signed helper")
        name = helper.relative_to(package).as_posix()
        report = {"signed_images": {name: pkg.sha(helper)}}
        with patch.object(pkg, "run"):
            pkg.verify_release_helper(package, report)
            helper.write_bytes(b"swapped")
            with self.assertRaisesRegex(pkg.Refusal, "helper differs"):
                pkg.verify_release_helper(package, report)

    def test_ambiguous_engine_is_refused(self):
        (self.framework / "Libraries/libcef_sandbox.dylib").write_bytes(b"stale")
        with self.assertRaisesRegex(pkg.Refusal, "Retired sandbox"):
            self.seal()

    def test_missing_gn_helper_cannot_be_sealed(self):
        (self.root / "parc_helper").unlink()
        with self.assertRaisesRegex(pkg.Refusal, "GN helper"):
            self.seal()

    def test_helper_cannot_link_framework_before_sandbox(self):
        self.loads["parc_helper"] = ["@rpath/" + pkg.FRAMEWORK + "/" + pkg.ENGINE_NAME]
        with self.assertRaisesRegex(pkg.Refusal, "pre-sandbox"):
            self.seal()

    def test_bootstrap_rejects_lookalike_seatbelt_path(self):
        with self.assertRaisesRegex(pkg.Refusal, "pre-sandbox"):
            pkg.check_bootstrap_graph({"parc_helper": {"loads": ["@rpath/other/libseatbelt.dylib"]}})

    def test_release_layout_uses_signed_default_helper(self):
        target = self.root / "Parc Helper.app/Contents/MacOS/Parc Helper"
        target.parent.mkdir(parents=True)
        (self.root / "parc_helper").rename(target)
        manifest = self.seal(shipping=True)
        self.assertEqual(manifest["helper"]["image"], target.relative_to(self.root).as_posix())
