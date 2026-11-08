"""Release-engine packaging checks with fixture packages and Git repositories; no engine runs."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_packager", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)

GIT_ENV = {"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
           "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.com",
           "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.com"}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def commit(repository: Path, files: dict) -> str:
    environment = {**os.environ, **GIT_ENV}
    if not (repository / ".git").exists():
        subprocess.run(["git", "init", "-q", str(repository)], check=True, env=environment)
    for name, text in files.items():
        (repository / name).parent.mkdir(parents=True, exist_ok=True)
        (repository / name).write_text(text)
    subprocess.run(["git", "-C", str(repository), "add", "-A"], check=True, env=environment)
    subprocess.run(["git", "-C", str(repository), "commit", "-qm", "fixture"], check=True, env=environment)
    return subprocess.check_output(["git", "-C", str(repository), "rev-parse", "HEAD"], text=True,
                                   env=environment).strip()


class ReleaseEngineTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="parc-release-engine-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.repo = self.root / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "scripts/engine-source.py").write_bytes((REPO / "scripts/engine-source.py").read_bytes())
        source = self.repo / "Engine/ParcHost/parc_native_host.mm"
        source.parent.mkdir(parents=True)
        source.write_text("overlay input")
        patch_file = self.repo / "Engine/ParcHost/integration/native-host.patch"
        patch_file.parent.mkdir(parents=True)
        patch_file.write_text("overlay patch")
        self.overlay = {"files": [{"source": "Engine/ParcHost/parc_native_host.mm",
                                   "target": "cef/libcef/browser/parc_native_host.mm", "sha256": digest(source)}],
                        "patches": [{"source": "Engine/ParcHost/integration/native-host.patch",
                                     "sha256": digest(patch_file),
                                     "files": [{"target": "cef/BUILD.gn"}]}]}
        self.write_overlay()
        self.package = self.root / "package"
        self.package.mkdir()
        self.report = {"schema_version": 1, "layout": "standalone-app",
                       "build_classification": "release-noncomponent", "distribution_eligible": True,
                       "engine_build_flags": {"is_component_build": False, "is_official_build": True,
                                              "ffmpeg_branding": "Chromium", "symbol_level": 0},
                       "widevine": {"host_signatures": "unsigned"},
                       "overlay": {"identity": digest(self.repo / "Engine/ParcHost/overlay.json")},
                       "source_lock_sha256": "lock"}

    def write_overlay(self):
        (self.repo / "Engine/ParcHost/overlay.json").write_text(json.dumps(self.overlay))

    def write_lock(self, lock: dict):
        path = self.repo / "Engine/source-lock.json"
        path.write_text(json.dumps(lock))
        self.report["source_lock_sha256"] = digest(path)

    def write_report(self, **changes):
        (self.package / "package-report.json").write_text(json.dumps({**self.report, **changes}))

    def test_release_report_accepts_only_this_checkouts_standalone_engine(self):
        self.write_lock({"cef": {"commit": "a"}})
        self.write_report()
        self.assertEqual(pkg.release_report(self.repo, self.package)["layout"], "standalone-app")
        refusals = {"non-component": [{"layout": "cef-component-development"},
                                      {"build_classification": "development-component"},
                                      {"distribution_eligible": False},
                                      {"engine_build_flags": {"is_component_build": True}}],
                    "not the current shipping": [
                        {"engine_build_flags": {"is_component_build": False, "is_official_build": False}},
                        {"engine_build_flags": {"is_component_build": False, "ffmpeg_branding": "Chrome"}}],
                    "Widevine": [{"widevine": {"host_signatures": "signed"}}, {"widevine": {}}],
                    "different engine overlay": [{"overlay": {"identity": "other"}}],
                    "different source lock": [{"source_lock_sha256": "other"}]}
        for message, cases in refusals.items():
            for changes in cases:
                with self.subTest(changes=changes):
                    self.write_report(**changes)
                    with self.assertRaisesRegex(pkg.Refusal, message):
                        pkg.release_report(self.repo, self.package)

    def test_local_test_report_allows_a_newer_overlay_but_not_a_different_lock(self):
        self.write_lock({"cef": {"commit": "a"}})
        self.write_report(overlay={"identity": "older overlay"},
                          engine_build_flags={"is_component_build": False, "is_official_build": False})
        (self.repo / "Engine/ParcHost/parc_native_host.mm").write_text("engine-internal change")
        self.assertEqual(pkg.release_report(self.repo, self.package, local_test=True)["overlay"],
                         {"identity": "older overlay"})
        with self.assertRaisesRegex(pkg.Refusal, "current shipping"):
            pkg.release_report(self.repo, self.package)
        for changes, message in (({"source_lock_sha256": "other"}, "different source lock"),
                                 ({"layout": "cef-component-development"}, "non-component"),
                                 ({"widevine": {"host_signatures": "signed"}}, "Widevine"),
                                 ({"engine_release": {"local_test": {}}}, "not a release engine")):
            self.write_report(overlay={"identity": "older overlay"}, **changes)
            with self.subTest(changes=changes), self.assertRaisesRegex(pkg.Refusal, message):
                pkg.release_report(self.repo, self.package, local_test=True)

    def test_changed_since_names_edited_and_new_headers(self):
        released = commit(self.repo, {"Engine/ParcNative/page_host.h": "api",
                                      "Engine/ParcNative/native_engine_entry.h": "entry"})
        names = ["Engine/ParcNative/page_host.h", "Engine/ParcNative/native_engine_entry.h"]
        self.assertEqual(pkg.changed_since(self.repo, released, names), [])
        (self.repo / "Engine/ParcNative/page_host.h").write_text("api plus a new method")
        (self.repo / "Engine/ParcNative/new_api.h").write_text("new")
        self.assertEqual(pkg.changed_since(self.repo, released, names + ["Engine/ParcNative/new_api.h"]),
                         ["Engine/ParcNative/page_host.h", "Engine/ParcNative/new_api.h"])

    def test_release_report_refuses_engine_source_edited_without_a_new_overlay(self):
        self.write_lock({"cef": {"commit": "a"}})
        self.write_report()
        for name in ("parc_native_host.mm", "integration/native-host.patch"):
            path = self.repo / "Engine/ParcHost" / name
            original = path.read_text()
            path.write_text(original + " edited")
            with self.subTest(name=name), self.assertRaisesRegex(pkg.Refusal, "without a new overlay"):
                pkg.release_report(self.repo, self.package)
            path.write_text(original)

    def pinned_workspace(self):
        workspace = self.root / "workspace"
        chromium = workspace / "chromium/src"
        chromium.mkdir(parents=True)
        pinned_chromium = commit(chromium, {"LICENSE": "chromium license",
                                            "chrome/app/app-entitlements.plist": "entitlements",
                                            "chrome/tools/build/mac/infoplist_strings_util.cc": "usage"})
        cef = chromium / "cef"
        pinned_cef = commit(cef, {"LICENSE.txt": "cef license", "include/cef_application_mac.h": "header"})
        # Later working-tree and history changes must not reach the package.
        commit(cef, {"include/cef_application_mac.h": "later header"})
        (cef / "include/cef_application_mac.h").write_text("edited header")
        self.write_lock({"cef": {"commit": pinned_cef}, "chromium": {"commit": pinned_chromium}})
        return workspace

    def test_pinned_source_reads_the_lock_commits_not_the_working_tree(self):
        workspace = self.pinned_workspace()
        source = pkg.pinned_source(self.repo, workspace, self.root / "pinned")
        self.assertEqual((source / "cef/include/cef_application_mac.h").read_text(), "header")
        self.assertEqual((source / "cef/LICENSE.txt").read_text(), "cef license")
        self.assertEqual((source / "LICENSE").read_text(), "chromium license")
        self.assertEqual((source / "chrome/app/app-entitlements.plist").read_text(), "entitlements")
        self.assertEqual((source / "chrome/tools/build/mac/infoplist_strings_util.cc").read_text(), "usage")

    def test_pinned_source_refuses_overlay_patched_inputs_and_missing_commits(self):
        workspace = self.pinned_workspace()
        self.overlay["patches"][0]["files"].append({"target": "cef/include/cef_application_mac.h"})
        self.write_overlay()
        with self.assertRaisesRegex(pkg.Refusal, "overlay changes a pinned packaging input"):
            pkg.pinned_source(self.repo, workspace, self.root / "pinned-1")
        self.overlay["patches"][0]["files"].pop()
        self.write_overlay()
        self.write_lock({"cef": {"commit": "0" * 40}, "chromium": {"commit": "0" * 40}})
        with self.assertRaisesRegex(pkg.Refusal, "at the pinned"):
            pkg.pinned_source(self.repo, workspace, self.root / "pinned-2")

    def test_release_framework_code_must_match_its_report(self):
        framework = self.package / pkg.RELEASE_FRAMEWORK
        library = framework / "Versions/A/Libraries/libfixture.dylib"
        library.parent.mkdir(parents=True)
        library.write_bytes(b"\xcf\xfa\xed\xfe fixture")
        (framework / "Versions/A/Resources").mkdir()
        (framework / "Versions/A/Resources/data.pak").write_bytes(b"resource")
        name = library.relative_to(self.package).as_posix()
        with patch.object(pkg, "run") as run:
            pkg.verify_release_framework(self.package, {"signed_images": {name: digest(library)}})
            self.assertEqual(run.call_args.args[:4], ("/usr/bin/codesign", "--verify", "--deep", "--strict"))
            for images in ({name: "0" * 64}, {}, {name: digest(library), name + "2": "0" * 64}):
                with self.subTest(images=images), self.assertRaisesRegex(pkg.Refusal, "differs from its package report"):
                    pkg.verify_release_framework(self.package, {"signed_images": images})

    def test_release_build_cli_refuses_mixed_or_missing_options_before_work(self):
        base = ["release-build", "--release-package", str(self.package), "--release-tag", "app-x",
                "--release-commit", "a" * 40, "--engine-workspace", str(self.root), "--output", str(self.root / "out")]
        cases = {"not --engine-dir": base + ["--engine-dir", str(self.root)],
                 "takes --release-package": base[:1] + base[3:],
                 "does not add Widevine": base + ["--widevine-sign-command", str(self.root / "signer")],
                 "cannot be distributions": base + ["--local-test", "--purpose", "distribution"],
                 "full commit": [value if value != "a" * 40 else "abc" for value in base],
                 "applies to --local-test only": base + ["--allow-changed-headers"],
                 "release-build only": ["build", "--engine-dir", str(self.root), "--manifest", str(self.root / "m.json"),
                                        "--release-tag", "app-x"],
                 "apply to release-build only": ["build", "--engine-dir", str(self.root),
                                                 "--manifest", str(self.root / "m.json"), "--local-test"],
                 "requires --engine-dir": ["seal-engine", "--manifest", str(self.root / "m.json")]}
        for message, argv in cases.items():
            with self.subTest(message=message), patch.object(pkg, "release_engine") as release, \
                    patch.object(pkg, "build_app") as build, contextlib.redirect_stderr(io.StringIO()) as error:
                self.assertEqual(pkg.main(argv), 1)
                self.assertIn(message, error.getvalue())
                release.assert_not_called()
                build.assert_not_called()

    def test_distribution_purpose_reaches_the_reused_engine_packager(self):
        output = self.root / 'distribution'
        verifier = object()
        with patch.object(pkg, 'release_engine', return_value=(self.root, self.root, {}, verifier)), \
                patch.object(pkg, 'build_app') as build, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(pkg.main(['release-build', '--release-package', str(self.package),
                '--release-tag', 'app-fixture', '--release-commit', 'a' * 40,
                '--engine-workspace', str(self.root), '--output', str(output),
                '--purpose', 'distribution', '--sign-identity', 'Developer ID Application: Fixture']), 0)
            self.assertEqual(build.call_args.kwargs['purpose'], 'distribution')


if __name__ == "__main__":
    unittest.main()
