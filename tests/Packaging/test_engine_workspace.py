import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("engine_workspace", REPO / "scripts/engine_workspace.py")
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
spec = importlib.util.spec_from_file_location("parc_packager", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)
spec = importlib.util.spec_from_file_location("engine_artifacts", REPO / "scripts/engine-artifacts.py")
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "repo"
        (self.repo / "Engine/ParcHost").mkdir(parents=True)
        self.source = self.root / "original"
        self.source.mkdir()
        self.engine = ws._engine(self.repo)
        self.lock, _ = self.engine.load_lock(REPO / ('Engine/source-lock.json'))
        for name, path in self.engine.locations(self.source, self.lock).items():
            path.mkdir(parents=True, exist_ok=True)
            self.git(path, "init", "-q")
            self.git(path, "config", "user.email", "fixture@example.invalid")
            self.git(path, "config", "user.name", "Fixture")
            self.git(path, "remote", "add", "origin", self.lock[name]["url"])
            (path / "README").write_text(name)
            if name == "chromium":
                (path / ".gitignore").write_text('/out/\n')
            self.git(path, "add", ".")
            self.git(path, "commit", "-qm", "fixture")
            self.lock[name]["commit"] = self.git(path, "rev-parse", "HEAD").strip()
            self.lock[name]["files"] = {}
        (self.repo / "Engine/source-lock.json").write_bytes(ws.canonical_json(self.lock))
        (self.source / "chromium/.gclient").write_text(self.engine.gclient_text(self.lock))
        (self.source / ".parc-operation.lock").touch()
        (self.source / "tmp").mkdir()
        self.output = self.source / "chromium/src/out/Release_GN_arm64"
        self.output.mkdir(parents=True)
        (self.output / "args.gn").write_text("is_component_build = true\n")
        (self.output / "cached.o").write_bytes(b"cached object with absolute old path " + str(self.source).encode())
        (self.output / "toolchain.ninja").write_text("command = ../../../../Applications/Xcode.app/tool\n")
        (self.repo / "Engine/owned.txt").write_text("reviewed overlay\n")
        manifest = {"schema_version": 1, "id": "parc-native-host", "version": 1,
                    "source_root": "repository", "upstream": {name: self.lock[name]["commit"] for name in (('chromium',))},
                    "files": [{"source": "Engine/owned.txt", "target": 'parc/owned.txt', "sha256": ws._sha(b"reviewed overlay\n")}]}
        self.manifest = self.repo / ('Engine/ParcHost/overlay.json')
        self.manifest.write_bytes(ws.canonical_json(manifest))
        self.state = {"schema_version": 1, "workspace": str(self.source),
                      "lock_sha256": ws._sha((self.repo / "Engine/source-lock.json").read_bytes()),
                      "phase": "generated", "symbol_level": 0,
                      "repositories": ['chromium/src']}
        record, writes = self.engine.prepare_overlay(self.source, self.lock, self.state, self.manifest)
        for target, data in writes.items():
            self.engine.target_path(self.source, target).parent.mkdir(parents=True, exist_ok=True)
            self.engine.target_path(self.source, target).write_bytes(data)
        (self.source / ".parc-overlays").mkdir()
        raw = self.engine.overlay_record_bytes(record)
        (self.source / ".parc-overlays" / (record["identity"] + ".json")).write_bytes(raw)
        self.state["overlay"] = {"identity": record["identity"], "record_sha256": ws._sha(raw)}
        arguments = self.engine.engine_arguments(self.lock, self.engine.environment(self.source, self.lock, 0)["GN_DEFINES"])
        (self.output / "args.gn").write_bytes(arguments)
        self.state.update(engine_mode="direct", build_targets=self.lock["build"]["targets"],
                          args_sha256=self.engine.digest(arguments))
        self.update_receipt()

    def git(self, root, *args):
        return subprocess.check_output(["/usr/bin/git", "-c", "core.hooksPath=/dev/null", *args], cwd=root, text=True, stderr=subprocess.DEVNULL)

    def update_receipt(self):
        self.state["source_fingerprint"] = self.engine.tree_fingerprint(self.source, self.engine.environment(self.source, self.lock, 0), self.state["repositories"])
        (self.source / self.engine.MARKER).write_bytes(ws.canonical_json(self.state))

    def snapshot(self):
        return ws.snapshot_metadata(self.source, self.repo)

    def extract(self, metadata=None):
        metadata = metadata or self.snapshot()
        restored = self.root / "restored"
        shutil.copytree(self.source, restored, symlinks=True)
        for value in metadata["archive_excludes"]:
            (restored / value).unlink()
        for value, target in metadata["symlink_rewrites"].items():
            (restored / value).unlink()
            (restored / value).symlink_to(target)
        (restored / ws.SNAPSHOT_FILE).write_bytes(ws.canonical_json(metadata))
        return restored, metadata

    def adopt(self, restored, metadata, **kwargs):
        arguments = {"verified_archive_sha256": "a" * 64, "expected_archive_sha256": "a" * 64,
                     "expected_metadata_sha256": ws._sha(ws.canonical_json(metadata)), "repo": self.repo}
        arguments.update(kwargs)
        return ws.adopt_workspace(restored, metadata, **arguments)

    def test_generated_never_becomes_built_and_objects_keep_nanosecond_mtime(self):
        timestamp = 1_771_234_567_123_456_789
        source_object = self.output / "cached.o"
        os.utime(source_object, ns=(timestamp, timestamp))
        restored, metadata = self.extract()
        result = self.adopt(restored, metadata)
        state, _ = ws._read(restored / self.engine.MARKER)
        self.assertEqual((result["original_phase"], state["phase"]), ("generated", "synced"))
        self.assertEqual(state["workspace"], str(restored))
        self.assertEqual(state["source_fingerprint"], self.state["source_fingerprint"])
        self.assertEqual((restored / "chromium/src/out/Release_GN_arm64/cached.o").read_bytes(), source_object.read_bytes())
        self.assertEqual((restored / "chromium/src/out/Release_GN_arm64/cached.o").stat().st_mtime_ns, timestamp)
        self.assertEqual((restored / "chromium/src/README").stat().st_mtime_ns, (self.source / "chromium/src/README").stat().st_mtime_ns)

    def test_built_receipt_downgrades_even_at_same_original_path_on_new_host(self):
        self.state["phase"] = "built"
        self.update_receipt()
        metadata = self.snapshot()
        (self.source / ws.SNAPSHOT_FILE).write_bytes(ws.canonical_json(metadata))
        result = self.adopt(self.source, metadata)
        self.assertEqual((result["original_phase"], result["phase"]), ("built", "synced"))

    def test_staging_records_final_path(self):
        restored, metadata = self.extract()
        destination = self.root / "new-depth/engine"
        destination.parent.mkdir()
        self.adopt(restored, metadata, destination=destination)
        state, _ = ws._read(restored / self.engine.MARKER)
        self.assertEqual(state["workspace"], str(destination))
        self.assertFalse(destination.exists())

    def test_existing_destination_is_not_adopted(self):
        restored, metadata = self.extract()
        with self.assertRaisesRegex(ws.Refusal, "already exist"):
            self.adopt(restored, metadata, destination=self.source)

    def test_unauthenticated_digest_refused_before_any_receipt_change(self):
        restored, metadata = self.extract()
        before = (restored / self.engine.MARKER).read_bytes()
        for supplied in ("", "b" * 64, True):
            with self.subTest(supplied=supplied), self.assertRaisesRegex(ws.Refusal, "Authenticated"):
                self.adopt(restored, metadata, verified_archive_sha256=supplied)
        self.assertEqual((restored / self.engine.MARKER).read_bytes(), before)

    def test_metadata_is_bound_to_authenticated_inventory(self):
        restored, metadata = self.extract()
        with self.assertRaisesRegex(ws.Refusal, "not bound"):
            self.adopt(restored, metadata, expected_metadata_sha256="b" * 64)
        changed = copy.deepcopy(metadata)
        changed["original_workspace"] = "/not/the/original"
        with self.assertRaisesRegex(ws.Refusal, "not bound"):
            self.adopt(restored, changed)

    def test_wrong_original_path_refused(self):
        self.state["workspace"] = "/wrong/path"
        self.update_receipt()
        with self.assertRaisesRegex(ws.Refusal, "different original"):
            self.snapshot()

    def test_repository_path_and_symlinked_destination_refused(self):
        restored, metadata = self.extract()
        with self.assertRaisesRegex(ws.Refusal, "outside"):
            self.adopt(restored, metadata, destination=self.repo / "unsafe")
        (self.root / "alias").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ws.Refusal, "Symlinked"):
            self.adopt(restored, metadata, destination=self.root / "alias/new")

    def test_stale_overlay_refused(self):
        restored, metadata = self.extract()
        manifest = json.loads(self.manifest.read_bytes())
        manifest["version"] += 1
        self.manifest.write_bytes(ws.canonical_json(manifest))
        with self.assertRaisesRegex(ws.Refusal, "stale"):
            self.adopt(restored, metadata)

    def test_changed_source_lock_refused(self):
        restored, metadata = self.extract()
        (self.repo / "Engine/source-lock.json").write_bytes(ws.canonical_json(self.lock) + b"\n")
        with self.assertRaisesRegex(ws.Refusal, "matching lock"):
            self.adopt(restored, metadata)

    def test_changed_source_fingerprint_refused_before_receipt_write(self):
        restored, metadata = self.extract()
        before = (restored / self.engine.MARKER).read_bytes()
        (restored / "chromium/src/README").write_text("changed after verified extraction")
        with self.assertRaisesRegex(ws.Refusal, "Source/dependency changes"):
            self.adopt(restored, metadata)
        self.assertEqual((restored / self.engine.MARKER).read_bytes(), before)

    def test_changed_overlay_input_refused(self):
        restored, metadata = self.extract()
        (self.repo / "Engine/owned.txt").write_text("unreviewed")
        with self.assertRaisesRegex(ws.Refusal, "input digest"):
            self.adopt(restored, metadata)

    def test_toolchain_graph_digest_checked(self):
        restored, metadata = self.extract()
        (restored / "chromium/src/out/Release_GN_arm64/toolchain.ninja").write_text("changed")
        with self.assertRaisesRegex(ws.Refusal, "Toolchain/graph fingerprint"):
            self.adopt(restored, metadata)

    def test_shipping_stale_in_progress_is_preserved_as_history_never_built(self):
        shipping = {"schema_version": 1, "workspace": str(self.source), "phase": "build-in-progress",
                    "lock_sha256": self.state["lock_sha256"], "source_fingerprint": "f" * 64}
        (self.source / self.engine.SHIPPING_MARKER).write_bytes(ws.canonical_json(shipping))
        restored, metadata = self.extract()
        self.adopt(restored, metadata)
        current, _ = ws._read(restored / self.engine.SHIPPING_MARKER)
        self.assertEqual(current["phase"], "generation-failed")
        self.assertEqual(current["relocation"]["original_phase"], "build-in-progress")
        self.assertEqual(metadata["shipping_receipt"], shipping)

    def test_absolute_ignored_log_rewritten_without_changing_source_proof(self):
        log = self.source / "tmp/siso.log"
        log.write_text("diagnostic")
        (self.output / "siso.INFO").symlink_to(log)
        restored, metadata = self.extract()
        self.assertIn("chromium/src/out/Release_GN_arm64/siso.INFO", metadata["symlink_rewrites"])
        self.adopt(restored, metadata)
        self.assertEqual((restored / "chromium/src/out/Release_GN_arm64/siso.INFO").resolve(), restored / "tmp/siso.log")

    def test_absolute_source_link_refused_instead_of_forging_new_fingerprint(self):
        (self.source / "chromium/src/source-link").symlink_to(self.source / "chromium/src/README")
        self.update_receipt()
        with self.assertRaisesRegex(ws.Refusal, "baseline fingerprint"):
            self.snapshot()

    def test_known_generated_external_links_are_recorded_and_omitted(self):
        links = self.output / "sdk/xcode_links"
        links.mkdir(parents=True)
        (links / "MacOSX27.0.sdk").symlink_to("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
        (self.output / "siso.INFO").symlink_to("/var/folders/unavailable/siso.log")
        (self.output / "siso.0.INFO").symlink_to("/var/folders/unavailable/siso.Joshs-MacBook-Air.log.INFO")
        restored, metadata = self.extract()
        self.assertEqual(len(metadata["archive_excludes"]), 3)
        self.adopt(restored, metadata)
        self.assertFalse((restored / "chromium/src/out/Release_GN_arm64/siso.INFO").is_symlink())

    def test_unknown_external_dependency_refused(self):
        (self.source / "external").symlink_to("/unrepresented/toolchain")
        with self.assertRaisesRegex(ws.Refusal, "Unrepresented external"):
            self.snapshot()

    def test_external_git_object_store_refused(self):
        path = self.source / "chromium/src/.git/objects/info/alternates"
        path.write_text("/outside/objects\n")
        with self.assertRaisesRegex(ws.Refusal, "External Git storage"):
            self.snapshot()

    def test_active_or_failed_sync_snapshot_not_adoptable(self):
        for phase in ("sync-in-progress", "dependency-sync-failed", "overlay-applying", "generation-in-progress"):
            self.state["phase"] = phase
            self.update_receipt()
            with self.subTest(phase=phase), self.assertRaisesRegex(ws.Refusal, "complete source receipt"):
                self.snapshot()

    def test_git_worktree_redirection_refused(self):
        restored, metadata = self.extract()
        self.git(restored / "chromium/src", "config", "core.worktree", str(self.source / "chromium/src"))
        with self.assertRaisesRegex(ws.Refusal, "External Git configuration"):
            self.adopt(restored, metadata)

    def test_packing_a_snapshot_lets_packaging_read_the_engine_but_still_stops_builds(self):
        loader, during = artifacts.module, []

        def module(name):
            loaded = loader(name)
            if name == "artifact_archive":
                archive = loaded.create_archive

                def packing(*args, **kwargs):
                    try:
                        with pkg.engine_lock(self.output):
                            during.append("packaged")
                    except pkg.Refusal as error:
                        during.append(str(error))
                    try:
                        self.engine.overlay(self.source, self.lock, self.state["lock_sha256"], self.manifest, True)
                    except self.engine.Refusal as error:
                        during.append(str(error))
                    return archive(*args, **kwargs)
                loaded.create_archive = packing
            return loaded

        output = self.root / "snapshot"
        with patch.object(artifacts, "module", side_effect=module), patch.object(artifacts, "ROOT", self.repo), \
                patch("builtins.print"):
            code = artifacts.main(["create-workspace", "--workspace", str(self.source), "--output", str(output),
                                   "--name", "engine-workspace"])
        self.assertEqual(during, ["packaged", "Another operation is using this workspace"])
        self.assertEqual(code, 0)
        self.assertTrue((output / "engine-workspace.manifest.json").is_file())

    def test_packaging_checks_never_rewrite_the_git_index_a_packer_is_reading(self):
        readme = self.source / "chromium/src/README"
        stale = readme.stat().st_mtime_ns - 100_000_000_000
        os.utime(readme, ns=(stale, stale))
        index = self.source / "chromium/src/.git/index"
        before = index.stat()
        pkg.verify_source_baseline(REPO, self.source, self.lock, self.state)
        after = index.stat()
        self.assertEqual((after.st_ino, after.st_mtime_ns, after.st_size),
                         (before.st_ino, before.st_mtime_ns, before.st_size))


if __name__ == "__main__":
    unittest.main()
