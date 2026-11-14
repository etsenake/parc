import contextlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import call, patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_packager_icons", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


class PackagingIconTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="parc-package-icons-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / "repo"
        shutil.copytree(REPO / "Resources/AppIcons", self.repo / "Resources/AppIcons")
        (self.repo / "Resources/ThemeTextures").mkdir()
        shutil.copy2(REPO / "Resources/ThemeTextures/grain.png", self.repo / "Resources/ThemeTextures")
        shutil.copytree(REPO / "Sources/WhatsNew", self.repo / "Sources/WhatsNew")
        shutil.copy2(REPO / "app-version.json", self.repo / "app-version.json")
        (self.repo / "Engine").mkdir()
        shutil.copy2(REPO / "Engine/source-lock.json", self.repo / "Engine/source-lock.json")
        for name in ("native_engine_entry.h", "native_appkit_bridge.h", "native_application_protocols.h"):
            target = self.repo / "Engine/ParcNative" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("fixture header")
        for name, text in {"ParcEngine/ParcEngine.m": '#include "native_engine_entry.h"\n',
                           "ParcEngine/ParcEngine.h": "fixture header",
                           "ParcCore/Model.swift": "fixture model",
                           "ParcApp/main.swift": "fixture application",
                           "ParcDockTile/ParcDockTile.m": "fixture Dock plugin",
                           "ParcRestart/main.c": "fixture restart helper"}.items():
            target = self.repo / "Sources" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        self.engine = self.root / "workspace/chromium/src/out/Release_GN_arm64"
        self.engine.mkdir(parents=True)
        source = self.engine.parent.parent
        for name in ("LICENSE",):
            target = source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("fixture license")
        entitlements = source / "chrome/app/app-entitlements.plist"
        entitlements.parent.mkdir(parents=True)
        entitlements.write_bytes(plistlib.dumps({"com.apple.security.device.camera": True}))
        self.chromium_usage = source / "chrome/tools/build/mac/infoplist_strings_util.cc"
        self.chromium_usage.parent.mkdir(parents=True)
        self.chromium_usage.write_text("".join(f'        {{"{key}", permission_reason}},\n' for key in (
            "NSAudioCaptureUsageDescription", "NSBluetoothAlwaysUsageDescription",
            "NSBluetoothPeripheralUsageDescription", "NSCameraUsageDescription",
            "NSLocalNetworkUsageDescription", "NSLocationUsageDescription",
            "NSMicrophoneUsageDescription", "NSWebBrowserPublicKeyCredentialUsageDescription")))
        self.manifest = {"source_lock_sha256": "fixture-lock", "overlay": {"identity": "fixture-overlay"},
                         "engine_build_flags": {"target_cpu": "arm64", "is_component_build": True,
                                                "is_official_build": False, "is_debug": False,
                                                "enable_dsyms": False, "symbol_level": 0},
                         "build_classification": "development-component", "distribution_eligible": False, "components": {}}
        helper = self.engine / "parc_helper"
        helper.write_bytes(b"GN-built helper")
        helper.chmod(0o755)
        self.manifest.update(engine_runtime="chromium-direct", helper={"image": "parc_helper", "sha256": pkg.sha(helper), "mode": 0o755})
        self.sparkle = self.root / "sparkle"
        framework = self.sparkle / pkg.SPARKLE
        for name in ("Sparkle", "Autoupdate", "Updater.app/Contents/MacOS/Updater", "Headers/Sparkle.h",
                     "PrivateHeaders/SPUInstallationType.h", "Modules/module.modulemap",
                     "XPCServices/Installer.xpc/Contents/MacOS/Installer", "Resources/Info.plist"):
            target = framework / "Versions/B" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("fixture Sparkle")
            top = framework / name.split("/")[0]
            if not top.is_symlink():
                top.symlink_to("Versions/Current/" + name.split("/")[0])
        (framework / "Versions/Current").symlink_to("B")
        self.commands = []
        self.signed_entitlements = []
        fetch = patch.object(pkg.sparkle, "fetch", return_value=self.sparkle)
        fetch.start()
        self.addCleanup(fetch.stop)

    @staticmethod
    def fake_icons(resources):
        (resources / "Parc.icns").write_bytes(b"fixture icon")
        return "Parc.icns"

    def fake_run(self, *args, **kwargs):
        values = tuple(str(value) for value in args)
        self.commands.append(values)
        if values[:2] in (("xcrun", "clang"), ("xcrun", "clang++"), ("xcrun", "swiftc")):
            Path(values[values.index("-o") + 1]).write_bytes(b"explicit compiler fixture")
        if values[0] == "/usr/bin/lipo" and "-output" in values:
            Path(values[values.index("-output") + 1]).write_bytes(b"thin fixture")
        if values[0] == "/usr/bin/codesign" and "--entitlements" in values:
            self.signed_entitlements.append((values[-1], plistlib.loads(Path(values[values.index("--entitlements") + 1]).read_bytes())))
        return ""

    def fake_copy_engine(self, engine, app, manifest):
        self.assertEqual(engine, self.engine)
        self.assertEqual(manifest, self.manifest)
        framework = app / "Contents/Frameworks" / pkg.FRAMEWORK
        (framework / "Versions/A/Resources").mkdir(parents=True)
        (framework / "Versions/A" / pkg.ENGINE_NAME).write_bytes(b"explicit independent engine fixture")
        (framework / "Versions/Current").symlink_to("A")
        (framework / pkg.ENGINE_NAME).symlink_to("Versions/Current/" + pkg.ENGINE_NAME)
        (framework / "Resources").symlink_to("Versions/Current/Resources")
        return {"fixture": "pre-sign-copy-hash"}

    @staticmethod
    def fake_signing_team(identity, probe):
        assert probe.is_file()
        return None if identity == "-" or "self-signed" in identity else "FIXTURETEAM"

    @contextlib.contextmanager
    def fixture_tools(self, real_icons=False):
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(pkg, "run", self.fake_run))
            stack.enter_context(patch.object(pkg, "copy_engine", self.fake_copy_engine))
            if not real_icons:
                stack.enter_context(patch.object(pkg.app_icons, "package_app_icons", side_effect=self.fake_icons))
            stack.enter_context(patch.object(pkg, "inspect_macho", return_value={"loads": ["/usr/lib/libSystem.B.dylib"]}))
            stack.enter_context(patch.object(pkg, "verify_development_layout", return_value={}))
            stack.enter_context(patch.object(pkg, "exported_symbols", return_value=pkg.PUBLIC_SYMBOLS))
            stack.enter_context(patch.object(pkg, "signing_team", self.fake_signing_team))
            verified = stack.enter_context(patch.object(pkg, "verify_manifest"))
            yield verified

    def test_direct_packaging_requires_application_protocol_header_before_copy(self):
        (self.repo / "Sources/ParcEngine/ParcEngine.h").write_text('#import "native_application_protocols.h"\n')
        (self.repo / "Engine/ParcNative/native_application_protocols.h").unlink()
        with self.fixture_tools(), patch.object(pkg, "copy_engine") as copy:
            with self.assertRaisesRegex(pkg.Refusal, "application protocol header"):
                pkg.build_app(self.repo, self.engine, self.manifest, self.root / "direct-missing", "-")
        copy.assert_not_called()

    def test_gn_helpers_are_copied_without_compilation(self):
        (self.repo / "Sources/ParcEngine/ParcEngine.h").write_text('#import "native_application_protocols.h"\n')
        (self.repo / "Engine/ParcNative/native_application_protocols.h").write_text("#pragma once\n")
        helper = self.engine / "parc_helper"
        helper.write_bytes(b"GN-built helper")
        helper.chmod(0o755)
        self.manifest.update(engine_runtime="chromium-direct", helper={
            "image": "parc_helper", "sha256": pkg.sha(helper), "mode": 0o755})
        self.commands = []
        self.signed_entitlements = []
        output = self.root / "direct"
        with self.fixture_tools():
            pkg.build_app(self.repo, self.engine, self.manifest, output, "-")
        for suffix, _, _ in pkg.HELPERS:
            name = "Parc Helper" + suffix
            bundle = output / "Parc.app/Contents/Frameworks" / (name + ".app")
            self.assertEqual((bundle / "Contents/MacOS" / name).read_bytes(), b"GN-built helper")
        self.assertFalse(any(command[:2] == ("xcrun", "clang++") for command in self.commands))
        self.assertFalse((output / "Parc.app/Contents/Resources/EngineLicenses/CEF-LICENSE.txt").exists())

    def test_debug_and_release_have_same_real_icon_and_preserve_helper_signing_contract(self):
        icons = []
        families = []
        for configuration in ("debug", "release"):
            output_dir = self.root / configuration
            app = output_dir / "Parc.app"
            with self.fixture_tools(real_icons=True) as verified:
                report = pkg.build_app(self.repo, self.engine, self.manifest, output_dir, "-", configuration)
                self.assertEqual(verified.call_args_list, [call(self.manifest, self.engine, self.repo)] * 2)
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            self.assertEqual(info["CFBundleIconFile"], "Parc.icns")
            self.assertEqual(info["NSDockTilePlugIn"], "ParcDockTile.plugin")
            self.assertEqual(info["LSEnvironment"], {"MallocNanoZone": "0"})
            self.assertEqual(info["CFBundleIdentifier"], "org.parc.Browser")
            lock = json.loads((REPO / "Engine/source-lock.json").read_text())
            self.assertEqual(info["ParcChromiumVersion"], lock["chromium"]["tag"])
            self.assertFalse([key for key in info if key.startswith("SU")])
            self.assertEqual(report["sparkle"], {"version": pkg.sparkle.VERSION, "sha256": pkg.sparkle.SHA256,
                                                 "update_feed": None})
            embedded = app / "Contents/Frameworks" / pkg.SPARKLE
            self.assertEqual(sorted(path.name for path in embedded.iterdir()),
                             ["Autoupdate", "Resources", "Sparkle", "Updater.app", "Versions"])
            self.assertEqual(sorted(path.name for path in (embedded / "Versions/B").iterdir()),
                             ["Autoupdate", "Resources", "Sparkle", "Updater.app"])
            for binary in ("Sparkle", "Autoupdate", "Updater.app/Contents/MacOS/Updater"):
                self.assertEqual((embedded / "Versions/B" / binary).read_bytes(), b"thin fixture")
            self.assertEqual(info["CFBundleURLTypes"][0]["CFBundleURLSchemes"], ["http", "https"])
            self.assertEqual(info["LSApplicationCategoryType"], "public.app-category.productivity")
            documents = {kind for document in info["CFBundleDocumentTypes"]
                         for kind in document["LSItemContentTypes"]}
            self.assertEqual(documents, {"public.html", "public.xhtml"})
            self.assertTrue(all(document["CFBundleTypeRole"] == "Viewer"
                                and document["LSHandlerRank"] == "Alternate"
                                for document in info["CFBundleDocumentTypes"]))
            for folder in ("Desktop", "Documents", "Downloads"):
                self.assertIn(folder, info[f"NS{folder}FolderUsageDescription"])
            for key in ("NSAudioCaptureUsageDescription", "NSBluetoothAlwaysUsageDescription",
                        "NSBluetoothPeripheralUsageDescription", "NSCameraUsageDescription",
                        "NSLocalNetworkUsageDescription", "NSLocationUsageDescription",
                        "NSLocationWhenInUseUsageDescription", "NSMicrophoneUsageDescription",
                        "NSWebBrowserPublicKeyCredentialUsageDescription"):
                self.assertTrue(info[key].strip(), key)
            plugin = app / "Contents/PlugIns" / info["NSDockTilePlugIn"]
            plugin_info = plistlib.loads((plugin / "Contents/Info.plist").read_bytes())
            self.assertEqual(plugin_info["CFBundlePackageType"], "BNDL")
            self.assertEqual(plugin_info["CFBundleIdentifier"], "org.parc.Browser.DockTile")
            self.assertEqual(plugin_info["NSPrincipalClass"], "ParcDockTile")
            self.assertTrue((plugin / "Contents/MacOS" / plugin_info["CFBundleExecutable"]).is_file())
            icon = app / "Contents/Resources" / info["CFBundleIconFile"]
            data = icon.read_bytes()
            self.assertEqual(data[:4], b"icns")
            self.assertEqual(struct.unpack(">I", data[4:8])[0], len(data))
            icons.append(data)
            self.assertIn("A clean slate", (app / "Contents/Resources/WhatsNew.html").read_text())
            self.assertEqual(report["configuration"], configuration)
            self.assertEqual(report["layout"], "chromium-direct-component-development")
            self.assertEqual(report["app"], str(app))
            self.assertEqual(report["engine_copy_sha256_before_signing"], {"fixture": "pre-sign-copy-hash"})
            self.assertEqual(json.loads((output_dir / "package-report.json").read_text()), report)
            self.assertEqual(report["purpose"], "development")
            self.assertEqual(report["engine_build_flags"], self.manifest["engine_build_flags"])
            self.assertEqual(report["build_classification"], "development-component")
            self.assertIs(report["distribution_eligible"], False)
            self.assertEqual(report["application_icon"], {"file": "Parc.icns", "sha256": pkg.sha(icon)})
            self.assertFalse(report["executed"])
            self.assertFalse(report["runtime_verified"])
            self.assertEqual(report["widevine"], {
                "cdm": "downloaded by the component updater, not bundled", "cdm_helper": "Parc Helper (CDM)",
                "helper_library_validation": "disabled on every helper without a Team ID",
                "host_signatures": "unsigned",
                "unsigned_reason": "no VMP certificate or signing service was configured"})
            catalog = json.loads((self.repo / "Resources/AppIcons/catalog.json").read_text())
            self.assertEqual(catalog["default"], "Original")
            family = {}
            for variant in catalog["variants"]:
                native = app / "Contents/Resources/AppIcons" / (variant + ".icns")
                native_bytes = native.read_bytes()
                self.assertEqual(native_bytes[:4], b"icns")
                self.assertEqual(struct.unpack(">I", native_bytes[4:8])[0], len(native_bytes))
                family[variant] = native_bytes
                decoded = output_dir / (variant + ".iconset")
                subprocess.run(["/usr/bin/iconutil", "--convert", "iconset", "--output", str(decoded), str(native)], check=True)
                expected = {}
                for points in (16, 32, 128, 256, 512):
                    for scale in (1, 2):
                        suffix = "@2x" if scale == 2 else ""
                        expected[f"icon_{points}x{points}{suffix}.png"] = (points * scale, points * scale)
                self.assertEqual({path.name for path in decoded.iterdir()}, set(expected))
                for name, dimensions in expected.items():
                    self.assertEqual(struct.unpack(">II", (decoded / name).read_bytes()[16:24]), dimensions)
                self.assertEqual((app / "Contents/Resources/AppIcons" / (variant + ".png")).read_bytes(),
                                 (self.repo / "Resources/AppIcons" / (variant + ".png")).read_bytes())
            self.assertEqual(data, family["Original"])
            self.assertEqual(len(set(family.values())), len(catalog["variants"]))
            families.append(family)
            self.assertFalse(any("LegacyCore" in str(path) for path in app.rglob("*")))
            for suffix, id_suffix, jit in pkg.HELPERS:
                helper = app / "Contents/Frameworks" / ("Parc Helper" + suffix + ".app")
                helper_info = plistlib.loads((helper / "Contents/Info.plist").read_bytes())
                self.assertEqual(helper_info["CFBundleIdentifier"], "org.parc.Browser.helper" + id_suffix)
                self.assertEqual(helper_info["LSEnvironment"], {"MallocNanoZone": "0"})
                self.assertEqual(helper_info.get("NSUserNotificationAlertStyle"), "alert" if id_suffix == ".alerts" else None)
                if id_suffix == ".alerts":
                    self.assertEqual(helper_info["CFBundleIconFile"], info["CFBundleIconFile"])
                    self.assertEqual((helper / "Contents/Resources" / helper_info["CFBundleIconFile"]).read_bytes(), data)
        self.assertEqual(icons[0], icons[1])
        self.assertEqual(families[0], families[1])
        compiles = [cmd for cmd in self.commands if cmd[:2] == ("xcrun", "swiftc")]
        self.assertFalse(any("install_name_tool" in str(arg) for cmd in self.commands for arg in cmd))
        self.assertEqual(len(compiles), 2)
        for compile in compiles:
            self.assertEqual(compile[compile.index(str(self.sparkle)) - 1], "-F")
            self.assertEqual(compile[compile.index("Sparkle") - 1], "-framework")
        self.assertTrue(all("-v" in cmd for cmd in compiles))
        self.assertIn("-g", compiles[0]); self.assertIn("-Onone", compiles[0]); self.assertNotIn("-O", compiles[0])
        self.assertIn("-O", compiles[1]); self.assertNotIn("-Onone", compiles[1]); self.assertNotIn("-g", compiles[1])
        self.assertIn("-whole-module-optimization", compiles[1]); self.assertNotIn("-whole-module-optimization", compiles[0])
        signs = [cmd for cmd in self.commands if cmd[0] == "/usr/bin/codesign" and "--sign" in cmd]
        self.assertEqual(len(signs), 28)
        self.assertTrue(all("--deep" not in cmd for cmd in signs))
        signed_paths = [Path(cmd[-1]) for cmd in signs]
        plugins = [path for path in signed_paths if path.name == "ParcDockTile.plugin"]
        self.assertEqual(len(plugins), 2)
        restarters = [path for path in signed_paths if path.name == "ParcRestart"]
        self.assertEqual(len(restarters), 2)
        for restarter in restarters:
            self.assertLess(signed_paths.index(restarter), signed_paths.index(restarter.parents[2]))
        for plugin in plugins:
            self.assertLess(signed_paths.index(plugin), signed_paths.index(plugin.parents[2]))
        updaters = [path for path in signed_paths if path.name == "Updater.app"]
        self.assertEqual(len(updaters), 2)
        for updater in updaters:
            framework, app = updater.parents[2], updater.parents[5]
            self.assertEqual(framework.name, pkg.SPARKLE)
            self.assertLess(signed_paths.index(updater), signed_paths.index(framework))
            self.assertLess(signed_paths.index(framework), signed_paths.index(app))
        for path, ent in self.signed_entitlements:
            self.assertTrue(ent["com.apple.security.cs.disable-library-validation"])
            if "Parc Helper" in path:
                self.assertEqual(bool(ent.get("com.apple.security.cs.allow-jit")), "Renderer)" in path or "GPU)" in path)
            else:
                self.assertTrue(ent["com.apple.security.device.camera"])

    def test_release_default_keeps_certificate_signing_independent_of_optimization(self):
        output = self.root / "certificate-development"
        app = output / "Parc.app"
        with self.fixture_tools():
            report = pkg.build_app(self.repo, self.engine, self.manifest, output, "fixture certificate identity")
        self.assertEqual(report["configuration"], "release")
        self.assertEqual(report["purpose"], "development")
        self.assertEqual(report["build_classification"], "development-component")
        self.assertIs(report["distribution_eligible"], False)
        helpers = {Path(path).name: ent for path, ent in self.signed_entitlements if "Parc Helper" in path}
        jit = {"com.apple.security.cs.allow-jit": True}
        self.assertEqual(helpers, {"Parc Helper.app": {}, "Parc Helper (Renderer).app": jit,
                                   "Parc Helper (GPU).app": jit, "Parc Helper (Alerts).app": {},
                                   "Parc Helper (CDM).app": {"com.apple.security.cs.disable-library-validation": True},
                                   "Parc Helper (Aperitif).app": {}, "Parc Helper (Aperitif Renderer).app": jit,
                                   "Parc Helper (Aperitif GPU).app": jit})
        main = [ent for path, ent in self.signed_entitlements if Path(path).name == "Parc.app"]
        self.assertEqual(main, [{"com.apple.security.device.camera": True}])
        self.assertEqual(report["widevine"]["host_signatures"], "unsigned")
        self.assertEqual(report["widevine"]["cdm_helper"], "Parc Helper (CDM)")
        self.assertEqual(report["widevine"]["helper_library_validation"], "disabled only on the CDM helper")
        self.assertFalse(list(app.rglob("*.sig")))
        signs = [cmd for cmd in self.commands if cmd[0] == "/usr/bin/codesign" and "--sign" in cmd]
        self.assertTrue(all("--timestamp" in cmd for cmd in signs))

    def test_only_distribution_packages_follow_the_update_feed(self):
        self.manifest.update(build_classification="release-noncomponent", distribution_eligible=True,
                             engine_build_flags={**self.manifest["engine_build_flags"], "is_component_build": False})
        output = self.root / "distribution"
        with self.fixture_tools():
            report = pkg.build_app(self.repo, self.engine, self.manifest, output, "fixture certificate identity",
                                   purpose="distribution")
        info = plistlib.loads((output / "Parc.app/Contents/Info.plist").read_bytes())
        self.assertEqual({key: info[key] for key in info if key.startswith("SU")}, {
            "SUFeedURL": "https://github.com/etsenake/parc-releases/releases/latest/download/appcast.xml",
            "SUPublicEDKey": pkg.sparkle.PUBLIC_ED_KEY, "SUEnableAutomaticChecks": True,
            "SUAutomaticallyUpdate": True, "SUScheduledCheckInterval": 14400})
        self.assertEqual(report["sparkle"]["update_feed"], info["SUFeedURL"])

    def test_self_signed_certificate_keeps_library_validation_off_without_timestamps(self):
        output = self.root / "self-signed-development"
        with self.fixture_tools():
            report = pkg.build_app(self.repo, self.engine, self.manifest, output, "fixture self-signed identity")
        self.assertIsNone(report["signing_team"])
        self.assertEqual(report["signing_identity"], "fixture self-signed identity")
        for path, ent in self.signed_entitlements:
            self.assertTrue(ent["com.apple.security.cs.disable-library-validation"], path)
        self.assertEqual(report["widevine"]["helper_library_validation"], "disabled on every helper without a Team ID")
        signs = [cmd for cmd in self.commands if cmd[0] == "/usr/bin/codesign" and "--sign" in cmd]
        self.assertTrue(signs)
        self.assertTrue(all("--timestamp=none" in cmd and "--timestamp" not in cmd for cmd in signs))

    def test_release_engine_source_and_verifier_replace_the_workspace(self):
        source = self.root / "pinned"
        shutil.copytree(self.engine.parent.parent, source, ignore=shutil.ignore_patterns("out"))
        (self.engine.parent.parent / "chrome/app/app-entitlements.plist").unlink()
        verified = []
        self.manifest = {**self.manifest, "engine_release": {"tag": "fixture"}}
        with self.fixture_tools() as workspace_verify:
            report = pkg.build_app(self.repo, self.engine, self.manifest,
                                   self.root / "release-development", "-", source=source,
                                   verify=lambda *args: verified.append(args))
        workspace_verify.assert_not_called()
        self.assertEqual(len(verified), 2)
        self.assertEqual(report["engine_release"], {"tag": "fixture"})

    def test_usage_description_chromium_declares_but_parc_lacks_refuses_packaging(self):
        with self.chromium_usage.open("a") as text:
            text.write('        {"NSFutureSensorUsageDescription", permission_reason},\n')
        with self.fixture_tools(), \
                self.assertRaisesRegex(pkg.Refusal, "lacks usage descriptions Chromium declares: "
                                                    "NSFutureSensorUsageDescription$"):
            pkg.build_app(self.repo, self.engine, self.manifest, self.root / "development", "-")

    def test_widevine_signatures_precede_apple_signing_and_are_rechecked_after(self):
        flags = {**self.manifest["engine_build_flags"], "is_component_build": False}
        self.manifest = {**self.manifest, "engine_build_flags": flags,
                         "build_classification": "release-noncomponent", "distribution_eligible": True}
        output = self.root / "signed-widevine"
        signature = b"fixture VMP signature "

        class FixtureSigner:
            kind = "fixture"

            def write(self, binary, path, flags):
                path.write_bytes(signature + bytes([flags]))

        def fixture_verify(binary, data, flags, now=None):
            self.assertEqual(data, signature + bytes([flags]))
            return {"flags": flags, "body_sha512": "fixture", "signature_sha256": "fixture", "certificate": {}}

        write_signatures, check_signatures = pkg.widevine_host_signatures, pkg.verify_widevine_signatures

        def record_write(*args):
            self.commands.append(("widevine-sign",))
            return write_signatures(*args)

        def record_check(*args):
            self.commands.append(("widevine-verify",))
            return check_signatures(*args)

        with self.fixture_tools(), patch.object(pkg.widevine_vmp, "verify", side_effect=fixture_verify), \
                patch.object(pkg, "widevine_host_signatures", side_effect=record_write), \
                patch.object(pkg, "verify_widevine_signatures", side_effect=record_check):
            report = pkg.build_app(self.repo, self.engine, self.manifest, output, "fixture certificate identity",
                                   widevine=FixtureSigner())
        names = [command[0] for command in self.commands]
        self.assertEqual((names.count("widevine-sign"), names.count("widevine-verify")), (1, 1))
        first_sign = next(index for index, command in enumerate(self.commands)
                          if command[0] == "/usr/bin/codesign" and "--sign" in command)
        deep_check = next(index for index, command in enumerate(self.commands)
                          if command[:4] == ("/usr/bin/codesign", "--verify", "--deep", "--strict"))
        self.assertLess(names.index("widevine-sign"), first_sign)
        self.assertGreater(names.index("widevine-verify"), deep_check)
        self.assertEqual(report["layout"], "standalone-app")
        self.assertEqual(report["widevine"]["host_signatures"], "signed")
        self.assertEqual(report["widevine"]["signer"], "fixture")
        framework = f"Contents/Frameworks/{pkg.FRAMEWORK}/Versions/A/Resources/{pkg.ENGINE_NAME}.sig"
        helper = "Contents/Resources/Parc Helper (CDM).sig"
        self.assertEqual({name: item["flags"] for name, item in report["widevine"]["signatures"].items()},
                         {framework: 1, helper: 0})
        for name in (framework, helper):
            self.assertTrue((output / "Parc.app" / name).is_file())

    def test_invalid_configuration_refused_before_source_or_output_mutation(self):
        with patch.object(pkg, "validate_output") as validate:
            with self.assertRaisesRegex(pkg.Refusal, "Unsupported application configuration"):
                pkg.build_app(self.repo, self.engine, self.manifest, self.root / "development", "-", "profiling")
        validate.assert_not_called()
        self.assertFalse((self.root / "development").exists())

    def test_invalid_icon_catalog_cannot_publish_or_copy_engine(self):
        path = self.repo / "Resources/AppIcons/catalog.json"
        catalog = json.loads(path.read_text())
        catalog["default"] = "../Original"
        path.write_text(json.dumps(catalog))
        with patch.object(pkg, "verify_manifest"), patch.object(pkg, "copy_engine") as copying:
            with self.assertRaisesRegex(ValueError, "Invalid application icon catalog"):
                pkg.build_app(self.repo, self.engine, self.manifest, self.root / "development", "-")
        copying.assert_not_called()
        self.assertFalse((self.root / "development").exists())
        self.assertFalse(list(self.root.glob(".parc-package-*")))

    def test_missing_original_artwork_cannot_publish_or_copy_engine(self):
        (self.repo / "Resources/AppIcons/Original.png").unlink()
        with patch.object(pkg, "verify_manifest"), patch.object(pkg, "copy_engine") as copying:
            with self.assertRaises(FileNotFoundError):
                pkg.build_app(self.repo, self.engine, self.manifest, self.root / "development", "-")
        copying.assert_not_called()
        self.assertFalse((self.root / "development").exists())

    def test_icon_export_failure_never_publishes(self):
        with patch.object(pkg.app_icons, "package_app_icons", side_effect=subprocess.CalledProcessError(1, "iconutil")), \
                patch.object(pkg, "verify_manifest"), \
                patch.object(pkg, "copy_engine") as copying:
            with self.assertRaises(subprocess.CalledProcessError):
                pkg.build_app(self.repo, self.engine, self.manifest, self.root / "development", "-")
        copying.assert_not_called()
        self.assertFalse((self.root / "development").exists())

    def test_cli_keeps_explicit_output_and_passes_configuration(self):
        for configuration in (None, "debug", "release"):
            destination = self.root / str(configuration)
            destination.mkdir()
            output = destination / "development"
            manifest = destination / "engine.json"
            manifest.write_text(json.dumps(self.manifest))
            args = ["build", "--engine-dir", str(self.engine), "--manifest", str(manifest), "--output", str(output)]
            if configuration:
                args += ["--configuration", configuration]
            with patch.object(pkg, "ROOT", self.repo), patch.object(pkg, "engine_lock", return_value=contextlib.nullcontext()), \
                    patch.object(pkg, "verify_manifest"), patch.object(pkg, "build_app", return_value={"fixture": True}) as build:
                self.assertEqual(pkg.main(args), 0)
                build.assert_called_once_with(self.repo, self.engine, self.manifest, output, "-",
                                              configuration or "release", purpose="development", widevine=None)
            self.assertFalse((destination / "package-report.json").exists())

    def test_cli_unknown_configuration_rejected_before_engine_lock(self):
        with patch.object(pkg, "engine_lock") as lock:
            with self.assertRaises(SystemExit) as raised:
                pkg.main(["build", "--engine-dir", str(self.engine), "--manifest", str(self.root / "m.json"), "--configuration", "other"])
        self.assertEqual(raised.exception.code, 2)
        lock.assert_not_called()

    def test_distribution_refused_before_any_output_even_with_release_and_certificate(self):
        for configuration in ("debug", "release"):
            for identity in ("-", "Developer ID Application: Fixture"):
                with self.subTest(configuration=configuration, identity=identity):
                    output = self.root / "development"
                    before = set(self.root.iterdir())
                    forged = {**self.manifest, "distribution_eligible": True,
                              "build_classification": "distribution"}
                    with patch.object(pkg, "verify_manifest") as verify, \
                            patch.object(pkg, "validate_output") as validate, \
                            patch.object(pkg, "copy_engine") as copy, patch.object(pkg, "run") as run:
                        with self.assertRaisesRegex(pkg.Refusal, "Distribution requires"):
                            pkg.build_app(self.repo, self.engine, forged, output, identity,
                                          configuration, purpose="distribution")
                    verify.assert_not_called()
                    validate.assert_not_called()
                    copy.assert_not_called()
                    run.assert_not_called()
                    self.assertEqual(set(self.root.iterdir()), before)
                    self.assertFalse(output.exists())

    def test_cli_distribution_refused_before_lock_or_output(self):
        for command in ("seal-engine", "build"):
            with self.subTest(command=command):
                manifest = self.root / "new-engine.json"
                output = self.root / "development"
                args = [command, "--engine-dir", str(self.engine), "--manifest", str(manifest),
                        "--purpose", "distribution", "--configuration", "release",
                        "--sign-identity", "Developer ID Application: Fixture"]
                if command == "build":
                    args += ["--output", str(output)]
                before = set(self.root.iterdir())
                with patch.object(pkg, "engine_lock") as lock, \
                        patch.object(pkg, "make_manifest") as seal, \
                        patch.object(pkg, "build_app") as build:
                    self.assertEqual(pkg.main(args), 1)
                lock.assert_not_called()
                seal.assert_not_called()
                build.assert_not_called()
                self.assertEqual(set(self.root.iterdir()), before)
                self.assertFalse(manifest.exists())
                self.assertFalse(output.exists())
                self.assertFalse((self.root / "package-report.json").exists())


if __name__ == "__main__":
    unittest.main()
