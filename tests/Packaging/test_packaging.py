"""Offline artifact/deployment tests. They do not build or execute Chromium."""
import fcntl
import importlib.util
import json
import os
import shutil
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_packager", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.engine = self.root / "engine"
        self.engine.mkdir()

    def image(self, name):
        path = self.engine / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"\xcf\xfa\xed\xfe" + name.encode())
        return path

    def test_parse_actual_load_command_shape_and_spaces(self):
        text = """file:
Load command 1
          cmd LC_ID_DYLIB
      cmdsize 80
         name @rpath/A Framework.framework/A Framework (offset 24)
Load command 2
          cmd LC_LOAD_WEAK_DYLIB
         name /usr/lib/libSystem.B.dylib (offset 24)
Load command 3
          cmd LC_RPATH
         path @loader_path/../Frameworks (offset 12)
Load command 4
          cmd LC_REEXPORT_DYLIB
         name @rpath/libcomponent.dylib (offset 24)
"""
        info = pkg.parse_macho(text)
        self.assertEqual(info["id"], "@rpath/A Framework.framework/A Framework")
        self.assertEqual(info["loads"], ["/usr/lib/libSystem.B.dylib", "@rpath/libcomponent.dylib"])
        self.assertEqual(info["rpaths"], ["@loader_path/../Frameworks"])

    def test_cyclic_component_closure_and_system_exclusion(self):
        first, second = self.image("liba.dylib"), self.image("libb.dylib")
        definitions = {
            first: {"id": "@rpath/liba.dylib", "rpaths": [], "loads": ["@rpath/libb.dylib", "/usr/lib/libSystem.B.dylib"]},
            second: {"id": "@rpath/libb.dylib", "rpaths": [], "loads": ["@rpath/liba.dylib"]},
        }
        graph = pkg.dependency_closure(self.engine, [first], definitions.__getitem__)
        self.assertEqual(set(graph), {"liba.dylib", "libb.dylib"})
        self.assertEqual(graph["liba.dylib"]["resolved"], {"@rpath/libb.dylib": "libb.dylib"})

    def test_unresolved_weak_dependency_is_not_silently_omitted(self):
        first = self.image("main")
        with self.assertRaisesRegex(pkg.Refusal, "Unresolved"):
            pkg.dependency_closure(self.engine, [first], lambda p: {"id": None, "rpaths": [], "loads": ["@rpath/missing.dylib"]})

    def test_escape_and_ambiguous_runpath_refused(self):
        image = self.image("main")
        outside = self.root / "external.dylib"
        outside.write_bytes(b"x")
        with self.assertRaisesRegex(pkg.Refusal, "escapes"):
            pkg.resolve_dependency(str(outside), image, {"rpaths": []}, self.engine)
        self.image("liba.dylib")
        self.image("other/liba.dylib")
        with self.assertRaisesRegex(pkg.Refusal, "ambiguous"):
            pkg.resolve_dependency("@rpath/liba.dylib", image, {"rpaths": ["@loader_path/other"]}, self.engine)

    def test_final_bundle_does_not_use_output_root_fallback(self):
        image = self.image("main")
        self.image("liba.dylib")
        with self.assertRaisesRegex(pkg.Refusal, "Unresolved"):
            pkg.resolve_dependency("@rpath/liba.dylib", image, {"rpaths": []}, self.engine, output_fallback=False)
        actual = pkg.resolve_dependency("@rpath/liba.dylib", image, {"rpaths": ["@loader_path/."]}, self.engine, output_fallback=False)
        self.assertEqual(actual, self.engine / "liba.dylib")

    def test_resource_hash_and_versioned_framework_symlinks(self):
        bundle = self.engine / "Example.framework"
        resources = bundle / "Versions/A/Resources"
        resources.mkdir(parents=True)
        (resources / "resources.pak").write_bytes(b"first")
        (bundle / "Versions/Current").symlink_to("A")
        (bundle / "Resources").symlink_to("Versions/Current/Resources")
        before = pkg.inventory_tree(bundle)
        self.assertEqual(before["Resources"], {"symlink": "Versions/Current/Resources"})
        (resources / "resources.pak").write_bytes(b"second")
        self.assertNotEqual(before, pkg.inventory_tree(bundle))

    def test_escaping_or_absolute_resource_symlink_refused(self):
        (self.engine / "outside").symlink_to("../")
        with self.assertRaisesRegex(pkg.Refusal, "escapes"):
            pkg.inventory_tree(self.engine)
        (self.engine / "outside").unlink()
        (self.engine / "outside").symlink_to(self.root)
        with self.assertRaisesRegex(pkg.Refusal, "Absolute"):
            pkg.inventory_tree(self.engine)

    def test_missing_objc_export_rejected_even_if_c_entrypoints_present(self):
        exports = {s for s in pkg.PUBLIC_SYMBOLS if s.startswith("_parc_")}
        with self.assertRaisesRegex(pkg.Refusal, "OBJC_CLASS"):
            pkg.require_exports(exports)
        pkg.require_exports(pkg.PUBLIC_SYMBOLS)

    def test_missing_native_page_host_export_is_rejected_before_app_link(self):
        exports = pkg.PUBLIC_SYMBOLS - {"_OBJC_CLASS_$_PCNativePageHost"}
        with self.assertRaisesRegex(pkg.Refusal, "PCNativePageHost"):
            pkg.require_exports(exports)

    def test_manifest_never_accepts_other_output_or_mutated_resource(self):
        manifest = {"schema_version": 1, "engine_dir": str(self.engine), "framework": {"file": "old"}}
        with self.assertRaisesRegex(pkg.Refusal, "directory mismatch"):
            pkg.verify_manifest(manifest, self.root, self.root)
        with patch.object(pkg, "make_manifest", return_value={**manifest, "framework": {"file": "new"}}):
            with self.assertRaisesRegex(pkg.Refusal, "changed"):
                pkg.verify_manifest(manifest, self.engine, self.root)

    def test_stale_or_forged_classification_seals_refused_before_packaging(self):
        current = {"schema_version": 1, "engine_dir": str(self.engine),
                   "engine_build_flags": {"target_cpu": "arm64", "is_component_build": True,
                                          "is_official_build": False, "is_debug": False,
                                          "enable_dsyms": False, "symbol_level": 0},
                   "build_classification": "development-component", "distribution_eligible": False}
        stale = {k: v for k, v in current.items()
                 if k not in ("engine_build_flags", "build_classification", "distribution_eligible")}
        cases = [stale, {**current, "distribution_eligible": True},
                 {**current, "build_classification": "distribution"},
                 {**current, "engine_build_flags": {**current["engine_build_flags"], "is_official_build": True}}]
        for manifest in cases:
            with self.subTest(manifest=manifest):
                before = set(self.root.iterdir())
                with patch.object(pkg, "make_manifest", return_value=current), \
                        patch.object(pkg, "copy_engine") as copy, patch.object(pkg, "run") as run:
                    with self.assertRaisesRegex(pkg.Refusal, "changed after sealing"):
                        pkg.build_app(self.root, self.engine, manifest, self.root / "development", "-")
                copy.assert_not_called()
                run.assert_not_called()
                self.assertEqual(set(self.root.iterdir()), before)
        with patch.object(pkg, "make_manifest", return_value=current):
            pkg.verify_manifest(current, self.engine, self.root)

    def test_framework_inventory_matches_actual_angle_linkage_mode(self):
        framework = self.engine / pkg.FRAMEWORK
        self.image(pkg.FRAMEWORK + "/" + pkg.ENGINE_NAME)
        for name in ("resources.pak", "chrome_100_percent.pak", "chrome_200_percent.pak",
                     "icudtl.dat", "v8_context_snapshot.bin", "en.lproj/locale.pak"):
            path = framework / "Resources" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"runtime data")
        for name in ("libcef_sandbox.dylib", "libvk_swiftshader.dylib", "libvulkan.dylib"):
            self.image(pkg.FRAMEWORK + "/Libraries/" + name)
        (framework / "Libraries/vk_swiftshader_icd.json").write_text("{}")
        exports = pkg.PUBLIC_SYMBOLS | {"_cef_sandbox_initialize", "_cef_sandbox_destroy"}
        closure = pkg.dependency_closure
        def inspect_fixture(path):
            return {"id": None, "loads": [], "rpaths": []}
        with patch.object(pkg, "verify_workspace", return_value=(self.root, {"use_static_angle": True, "distribution_eligible": False})) as source, \
                patch.object(pkg, "exported_symbols", return_value=exports), \
                patch.object(pkg, "dependency_closure", side_effect=lambda root, seeds: closure(root, seeds, inspect_fixture)):
            manifest = pkg.make_manifest(self.engine, self.root)
            self.assertTrue(manifest["use_static_angle"])
            source.return_value = (self.root, {"use_static_angle": False, "distribution_eligible": False})
            with self.assertRaisesRegex(pkg.Refusal, "libEGL"):
                pkg.make_manifest(self.engine, self.root)
            for name in ("libEGL.dylib", "libGLESv2.dylib"):
                self.image(pkg.FRAMEWORK + "/Libraries/" + name)
            manifest = pkg.make_manifest(self.engine, self.root)
            self.assertFalse(manifest["use_static_angle"])
            self.assertIn(pkg.FRAMEWORK + "/Libraries/libEGL.dylib", manifest["images"])

    def test_output_never_replaces_arbitrary_app_or_enters_sources(self):
        existing = self.root / "development"
        existing.mkdir()
        (existing / "user-file").write_text("keep")
        with self.assertRaisesRegex(pkg.Refusal, "already exists"):
            pkg.validate_output(existing, self.root, self.engine)
        self.assertEqual((existing / "user-file").read_text(), "keep")
        (self.root / "Sources").mkdir()
        with self.assertRaisesRegex(pkg.Refusal, "overlaps"):
            pkg.validate_output(self.root / "Sources/development", self.root, self.engine)

    def test_obsolete_app_output_requires_explicit_development_directory(self):
        output = self.root / "Parc.app"
        with self.assertRaisesRegex(pkg.Refusal, "fresh development directory, not an .app"):
            pkg.validate_output(output, self.root, self.engine)
        self.assertFalse(output.exists())

    def test_directory_publication_is_whole_and_never_overwrites(self):
        stage = self.root / "stage"
        stage.mkdir()
        (stage / "Parc.app").mkdir()
        (stage / "component.dylib").write_bytes(b"component")
        (stage / "package-report.json").write_text("{}")
        output = self.root / "published"
        # Even a concurrently created empty output must survive publication.
        output.mkdir()
        with self.assertRaises(OSError):
            pkg.publish_development_directory(stage, output)
        self.assertTrue(stage.is_dir())
        self.assertEqual(list(output.iterdir()), [])
        output.rmdir()
        pkg.publish_development_directory(stage, output)
        self.assertFalse(stage.exists())
        self.assertEqual({p.name for p in output.iterdir()},
                         {"Parc.app", "component.dylib", "package-report.json"})

    def test_development_resolution_uses_order_and_no_root_fallback(self):
        image = self.engine / "liba.dylib"
        executable = self.engine / "Parc.app/Contents/MacOS/Parc"
        owned = self.image("libb.dylib")
        external = self.root / "libb.dylib"
        external.write_bytes(b"must not load")
        self.assertEqual(pkg.resolve_development_dependency(
            "@rpath/libb.dylib", image, executable, [self.engine, self.root], self.engine), owned)
        with self.assertRaisesRegex(pkg.Refusal, "escapes development"):
            pkg.resolve_development_dependency(
                "@rpath/libb.dylib", image, executable, [self.root, self.engine], self.engine)
        with self.assertRaisesRegex(pkg.Refusal, "Unresolved development"):
            pkg.resolve_development_dependency("@rpath/libb.dylib", image, executable, [], self.engine)
        alias = self.engine / "escaped.dylib"
        alias.symlink_to(external)
        with self.assertRaisesRegex(pkg.Refusal, "escapes development"):
            pkg.resolve_development_dependency("@loader_path/escaped.dylib", image, executable, [], self.engine)

    def test_paths_reject_parent_segments_and_symlink_ancestors(self):
        for path in ("../file", "/absolute", "a/../file", "a/./b"):
            with self.assertRaises(pkg.Refusal):
                pkg.relative(path)
        alias = self.root / "alias"
        alias.symlink_to(self.engine, target_is_directory=True)
        with self.assertRaisesRegex(pkg.Refusal, "Symlinked"):
            pkg.explicit_path(alias / "Parc.app")

    def test_seal_refuses_running_source_tool_lock(self):
        engine = self.root / "workspace/chromium/src/out/Release_GN_arm64"
        engine.mkdir(parents=True)
        lock = self.root / "workspace/.parc-operation.lock"
        with lock.open("w") as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            with self.assertRaisesRegex(pkg.Refusal, "busy"):
                with pkg.engine_lock(engine):
                    self.fail("should not enter a running build")
        with pkg.engine_lock(engine):
            pass

    def test_workspace_requires_completed_phase_current_overlay_and_abi_header(self):
        self.check_workspace_contract(direct=False)

    def test_direct_canonical_lock_seals_without_cef(self):
        self.check_workspace_contract(direct=True)

    def check_workspace_contract(self, *, direct):
        repo = self.root / "repo"
        (repo / "scripts").mkdir(parents=True)
        shutil.copyfile(REPO / "scripts/engine-source.py", repo / "scripts/engine-source.py")
        (repo / "Engine/ParcHost").mkdir(parents=True)
        (repo / "Engine/ParcNative").mkdir()
        lock = {"build": {"configuration": "Release_GN_arm64"}, "cef": {"commit": "c"}, "chromium": {"commit": "h"}, "depot_tools": {"commit": "d"}}
        if direct:
            lock = json.loads((REPO / "tests/Packaging/fixtures/direct-source-lock.json").read_text())
            self.assertNotIn("cef", lock)
            self.assertEqual(lock["schema_version"], 2)
            self.assertEqual(lock["build"]["targets"], ["//parc:parc_framework", "//parc/helper:parc_helper"])
        lock_path = repo / "Engine/source-lock.json"
        lock_path.write_text(json.dumps(lock))
        overlay = repo / "Engine/ParcHost/overlay.json"
        overlay.write_text("{}")
        workspace = self.root / "workspace"
        source = workspace / "chromium/src"
        engine = source / "out/Release_GN_arm64"
        engine.mkdir(parents=True)
        if direct:
            (engine / "parc_helper").write_bytes(b"GN helper")
        args_path = engine / "args.gn"
        args_text = ('target_cpu="arm64"\nis_component_build=true\nis_official_build=false\n'
                     'dcheck_always_on=false\ndisable_fieldtrial_testing_config=true\n'
                     'proprietary_codecs=true\nffmpeg_branding="Chromium"\n'
                     'enable_ffmpeg_video_decoders=false\nmedia_use_openh264=false\n'
                     'enable_hangout_services_extension=true\n'
                     'is_debug=false\nenable_dsyms=false\nsymbol_level=0\n')
        args_path.write_text(args_text)
        gl_flags = engine / "gen/ui/gl/buildflags.h"
        gl_flags.parent.mkdir(parents=True)
        gl_flags.write_text("#define BUILDFLAG_INTERNAL_USE_STATIC_ANGLE() (1)\n")
        trial_flags = engine / "gen/components/variations/service/buildflags.h"
        trial_flags.parent.mkdir(parents=True)
        trial_text = "#define BUILDFLAG_INTERNAL_FIELDTRIAL_TESTING_ENABLED() (0)\n"
        trial_flags.write_text(trial_text)
        (workspace / ".parc-overlays").mkdir()
        records = {}
        header_names = ["native_engine_entry.h", "native_appkit_bridge.h"]
        if direct:
            header_names.append("native_application_protocols.h")
        for name in header_names:
            native = repo / "Engine/ParcNative" / name
            native.write_text(name)
            target = ("parc/native/" if direct else "cef/libcef/browser/parc_native/") + name
            upstream = source / target
            upstream.parent.mkdir(parents=True, exist_ok=True)
            upstream.write_text(name)
            records[target] = {"output_sha256": pkg.sha(upstream), "mode": upstream.stat().st_mode & 0o777}
        identity = pkg.sha(overlay)
        record_path = workspace / ".parc-overlays" / (identity + ".json")
        record_path.write_text(json.dumps({"identity": identity, "targets": records}))
        proofs = pkg.PROOF_FILES
        if direct:
            proofs = tuple(name for name in proofs if not name.startswith("cef/")) + (
                "parc/BUILD.gn", "parc/framework.exports", "parc/helper/BUILD.gn", "parc/helper/main.cc",
                "parc/parc_content_clients.cc", "parc/parc_bundle_mac.mm", "chrome/common/chrome_constants.cc")
        for name in proofs:
            target = source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("pinned input")
        state = {"schema_version": 1, "workspace": str(workspace), "phase": "generated",
                 "lock_sha256": pkg.sha(lock_path), "source_fingerprint": "f", "symbol_level": 0,
                 "overlay": {"identity": identity, "record_sha256": pkg.sha(record_path)}}
        marker = workspace / ".parc-engine-source.json"
        def save():
            marker.write_text(json.dumps(state))
        save()
        with self.assertRaisesRegex(pkg.Refusal, "successful"):
            pkg.verify_workspace(engine, repo)
        state["phase"] = "built"
        save()
        with patch.object(pkg, "check_helper_contract"), patch.object(pkg, "verify_source_baseline"):
            _, proof = pkg.verify_workspace(engine, repo)
            self.assertEqual(proof["engine_build_flags"],
                             {"target_cpu": "arm64", "is_component_build": True,
                              "is_official_build": False, "dcheck_always_on": False,
                              "disable_fieldtrial_testing_config": True, "proprietary_codecs": True,
                              "ffmpeg_branding": "Chromium", "enable_ffmpeg_video_decoders": False,
                              "media_use_openh264": False, "enable_hangout_services_extension": True,
                              "is_debug": False, "enable_dsyms": False, "symbol_level": 0})
            if direct:
                self.assertEqual(set(proof["upstream"]), {"chromium", "depot_tools"})
                self.assertFalse(any(name.startswith("cef/") for name in proof["proof_files"]))
            self.assertEqual(proof["build_classification"], "development-component")
            self.assertIs(proof["distribution_eligible"], False)
            self.assertEqual(proof["proof_files"]["out/Release_GN_arm64/args.gn"], pkg.sha(args_path))
            self.assertEqual(
                proof["proof_files"]["out/Release_GN_arm64/gen/components/variations/service/buildflags.h"],
                pkg.sha(trial_flags))
            for altered in (args_text.replace("is_official_build=false\n", ""),
                            args_text.replace("is_official_build=false", "is_official_build=true"),
                            args_text.replace("dcheck_always_on=false\n", ""),
                            args_text.replace("dcheck_always_on=false", "dcheck_always_on=true"),
                            args_text.replace("disable_fieldtrial_testing_config=true\n", ""),
                            args_text.replace("disable_fieldtrial_testing_config=true",
                                              "disable_fieldtrial_testing_config=false"),
                            args_text.replace("proprietary_codecs=true\n", ""),
                            args_text.replace('ffmpeg_branding="Chromium"', 'ffmpeg_branding="Chrome"'),
                            args_text.replace("enable_ffmpeg_video_decoders=false",
                                              "enable_ffmpeg_video_decoders=true"),
                            args_text.replace("media_use_openh264=false\n", ""),
                            args_text.replace("is_component_build=true", "is_component_build=false")):
                with self.subTest(args=altered):
                    args_path.write_text(altered)
                    with self.assertRaisesRegex(pkg.Refusal, "Generated engine configuration"):
                        pkg.verify_workspace(engine, repo)
            args_path.write_text(args_text)
            trial_flags.write_text(trial_text.replace("(0)", "(1)"))
            with self.assertRaisesRegex(pkg.Refusal, "field-trial testing config"):
                pkg.verify_workspace(engine, repo)
            trial_flags.write_text(trial_text)
            native.write_text("mismatched executable header")
            with self.assertRaisesRegex(pkg.Refusal, "ABI header"):
                pkg.verify_workspace(engine, repo)
            native.write_text(name)
            upstream.write_text("changed reviewed source")
            with self.assertRaisesRegex(pkg.Refusal, "Applied source"):
                pkg.verify_workspace(engine, repo)
        state["overlay"]["identity"] = "0" * 64
        save()
        with self.assertRaisesRegex(pkg.Refusal, "reviewed overlay"):
            pkg.verify_workspace(engine, repo)


if __name__ == "__main__":
    unittest.main()
