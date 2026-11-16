#!/usr/bin/env python3
"""Package only the focused native runtime app using Parc's sealed-engine code.

Requires a completed source build including the internal test helper and
its ordinary production seal-engine manifest. Never invokes GN/Ninja or runs an
app. Source/output ownership, full framework/component closure and signing use
the same implementation as scripts/build.py.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import tempfile

APP = "parc_native_runtime_tests"
TEST_EXPORTS = {"_parc_test_http_auth", "_parc_test_cancel_http_auth",
                "_parc_test_extension_actions", "_parc_test_cancel_extension_actions",
                "_parc_test_video_pip", "_parc_test_cancel_video_pip"}


def validate_output(output, repo, engine, package):
    package.validate_output(output, repo, engine)
    if (repo.is_relative_to(output) or
            (output.is_relative_to(repo) and not output.is_relative_to(repo / "build"))):
        raise package.Refusal("Repository output is allowed only under its build directory")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine-dir", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True,
                        help="Fresh development directory containing the runtime app and sibling libraries")
    parser.add_argument("--sign-identity", default="-")
    args = parser.parse_args()
    test_dir = Path(__file__).resolve().parent
    repo = test_dir.parents[1]
    spec = importlib.util.spec_from_file_location("parc_package", repo / "scripts/build.py")
    package = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(package)
    engine = package.explicit_path(args.engine_dir)
    output = validate_output(args.output, repo, engine, package)
    source = engine.parent.parent
    manifest_path = package.explicit_path(args.manifest)
    helpers = []
    with package.engine_lock(engine):
        manifest = package.read_json(manifest_path)
        package.verify_manifest(manifest, engine, repo)
        binary = engine / package.FRAMEWORK / package.ENGINE_NAME
        if not TEST_EXPORTS <= package.exported_symbols(binary):
            raise package.Refusal("Real engine lacks the native runtime test driver")
        inputs = [test_dir / "main_mac.mm", test_dir / "runtime_driver.h", repo / "tests/Support/TestFailure.h",
                  repo / ('Sources/ParcHelper/main.cc'),
                  repo / "scripts/build.py",
                  test_dir / "fixtures/extension-action/manifest.json",
                  repo / "Sources/ParcEngine/VideoPiPWindow.h",
                  repo / "Sources/ParcEngine/VideoPiPWindow.m"]
        media = source / "media/test/data/bear.webm"
        media_sha = package.sha(media)
        proof = {str(path.relative_to(repo)): package.sha(path) for path in inputs}
        with tempfile.TemporaryDirectory(prefix=".parc-runtime-package-", dir=output.parent) as temporary:
            stage = Path(temporary)
            development = stage / "development"
            app = development / (APP + ".app")
            contents = app / "Contents"
            frameworks = contents / "Frameworks"
            (contents / "MacOS").mkdir(parents=True)
            frameworks.mkdir()
            copied_engine = package.copy_engine(engine, app, manifest)
            resources = contents / "Resources/EngineLicenses"
            resources.mkdir(parents=True)
            shutil.copy2(source / "LICENSE", resources / "Chromium-LICENSE.txt")
            fixture = contents / "Resources/NativeExtensionActionFixture"
            fixture.mkdir()
            shutil.copy2(test_dir / "fixtures/extension-action/manifest.json", fixture / "manifest.json")
            media_resources = contents / "Resources/NativeVideoFixture"
            media_resources.mkdir()
            shutil.copy2(media, media_resources / "bear.webm")
            if package.sha(media_resources / "bear.webm") != media_sha:
                raise package.Refusal("Packaged video fixture differs from pinned source")
            common = ["-arch", "arm64", "-mmacosx-version-min=13.0", "-std=c++23", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-O2"]
            native_root = source / ('parc/native')
            package.run("xcrun", "clang++", *common, "-fobjc-arc", "-fblocks",
                        "-I", source, "-I", engine / "gen",
                        "-I", repo / "Sources/ParcEngine", "-I", native_root,
                        "-x", "objective-c++", test_dir / "main_mac.mm",
                        repo / "Sources/ParcEngine/VideoPiPWindow.m",
                        "-framework", "AppKit", "-framework", "QuartzCore",
                        "-o", contents / "MacOS" / APP)
            helper_binary = stage / "helper"
            helper = engine / manifest["helper"]["image"]
            if package.sha(helper) != manifest["helper"]["sha256"]:
                raise package.Refusal("GN helper differs from sealed engine")
            shutil.copy2(helper, helper_binary)
            binary_path = contents / "MacOS" / APP
            if any(not package.system_library(load) for load in package.inspect_macho(binary_path)["loads"]):
                raise package.Refusal("Runtime executable directly links non-system code before dlopen")
            for suffix, id_suffix, jit in package.HELPERS:
                name = APP + " Helper" + suffix
                helper = frameworks / (name + ".app")
                (helper / "Contents/MacOS").mkdir(parents=True)
                shutil.copy2(helper_binary, helper / "Contents/MacOS" / name)
                info = package.info_plist(name, "org.parc.native-runtime-tests.helper" + id_suffix)
                info.update(LSUIElement=True, LSFileQuarantineEnabled=True,
                            LSEnvironment={"MallocNanoZone": "0"})
                if id_suffix == ".alerts":
                    info["NSUserNotificationAlertStyle"] = "alert"
                package.plist(helper / "Contents/Info.plist", info)
                helpers.append((helper, jit, suffix == package.CDM_HELPER))
            info = package.info_plist(APP, "org.parc.native-runtime-tests")
            info.update(NSPrincipalClass="PCRuntimeApplication", LSEnvironment={"MallocNanoZone": "0"})
            package.plist(contents / "Info.plist", info)
            main_entitlements = plistlib.loads((source / "chrome/app/app-entitlements.plist").read_bytes())
            if args.sign_identity == "-":
                main_entitlements["com.apple.security.cs.disable-library-validation"] = True
            main_ent = stage / "main-entitlements.plist"
            package.plist(main_ent, main_entitlements)
            package.run("/usr/bin/xattr", "-cr", development)
            images = package.verify_development_layout(app, manifest)
            def sign(path, entitlements=None):
                command = ["/usr/bin/codesign", "--force", "--sign", args.sign_identity, "--options", "runtime"]
                if args.sign_identity != "-":
                    command.append("--timestamp")
                if entitlements:
                    command += ["--entitlements", entitlements]
                package.run(*command, path)
            for name in sorted(images, key=lambda value: (-value.count("/"), value)):
                path = development / name
                if path.parent.name != "MacOS":
                    sign(path)
            sign(frameworks / package.FRAMEWORK)
            for helper, jit, hosts_cdm in helpers:
                ent = {"com.apple.security.cs.allow-jit": True} if jit else {}
                if args.sign_identity == "-" or hosts_cdm:
                    ent["com.apple.security.cs.disable-library-validation"] = True
                ent_path = stage / (helper.stem + ".plist")
                package.plist(ent_path, ent)
                sign(helper, ent_path)
            sign(app, main_ent)
            package.run("/usr/bin/codesign", "--verify", "--strict", "--deep", app)
            for name in manifest["components"]:
                package.run("/usr/bin/codesign", "--verify", "--strict", development / name)
            images = package.verify_development_layout(app, manifest)
            if not TEST_EXPORTS <= package.exported_symbols(frameworks / package.FRAMEWORK / package.ENGINE_NAME):
                raise package.Refusal("Packaged test exports are absent")
            package.verify_manifest(manifest, engine, repo)
            if package.sha(media) != media_sha:
                raise package.Refusal("Pinned media fixture changed while packaging")
            if proof != {str(path.relative_to(repo)): package.sha(path) for path in inputs}:
                raise package.Refusal("Runner inputs changed while packaging")
            report = {"schema_version": 1, "app": str(output / (APP + ".app")), "input_sha256": proof,
                      "development_directory": str(output), "layout": 'chromium-component-development',
                      "purpose": "development", "build_classification": manifest["build_classification"],
                      "engine_build_flags": manifest["engine_build_flags"],
                      "distribution_eligible": manifest["distribution_eligible"],
                      "engine_copy_sha256_before_signing": copied_engine,
                      "engine_manifest_sha256": package.sha(manifest_path),
                      "images": images, "synthetic_controller_cases": 3,
                      "optional_suites": ["extension-actions", "video-pip"],
                      "video_fixture_sha256": media_sha,
                      "runtime_executed": False, "network_401_407_verified": False}
            with (development / "runtime-package-report.json").open("x") as stream:
                json.dump(report, stream, indent=2)
                stream.write("\n")
            package.publish_development_directory(development, output)
    print(output / (APP + ".app"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
