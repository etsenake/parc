import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("engine_storage", ROOT / "scripts/engine_storage.py")
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


class StorageTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="parc-storage-test-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.repo = self.root / "repo"
        (self.repo / "Engine/ParcHost").mkdir(parents=True)
        (self.repo / "Engine/source-lock.json").write_text('{"lock": 1}\n')
        (self.repo / "Engine/ParcHost/overlay.json").write_text('{"version": 2}\n')
        self.wanted = storage.target(self.repo)
        self.share = self.root / "share"
        self.share.mkdir()
        self.config = {**storage.DEFAULTS, "schema_version": 1, "share": "nfs://nas.test/engine",
                       "mount_point": str(self.share), "local_workspace": str(self.root / "local/engine")}
        self.store = storage.Store(self.config, self.repo, log=lambda message: None)
        self.store.image_workspace = self.root / "image/engine"
        self.store.volume = self.root / "image"
        self.logs = []
        self.store.log = self.logs.append
        for name in ("sleep",):
            patcher = patch.object(storage.time, name)
            patcher.start()
            self.addCleanup(patcher.stop)

    def receipt(self, workspace, lock=None, overlay=None, phase="built", version=None):
        workspace.mkdir(parents=True, exist_ok=True)
        identity = overlay or self.wanted["overlay_identity"]
        (workspace / storage.RECEIPT).write_text(json.dumps({
            "schema_version": 1, "lock_sha256": lock or self.wanted["lock_sha256"],
            "overlay": {"identity": identity},
            "source_fingerprint": "f" * 64, "phase": phase, "workspace": str(workspace)}))
        records = workspace / ".parc-overlays"
        records.mkdir(exist_ok=True)
        (records / (identity + ".json")).write_text(json.dumps({
            "identity": identity, "version": version if version is not None else (2 if overlay is None else 1)}))

    def snapshot(self, overlay=None, size=1 << 20, version=None):
        current = self.store.current
        current.mkdir(parents=True)
        (current / "pin.json").write_text("{}")
        (current / "metadata.json").write_text(json.dumps({
            "lock_sha256": self.wanted["lock_sha256"], "overlay_identity": overlay or self.wanted["overlay_identity"],
            "overlay_version": version if version is not None else (2 if overlay is None else 1),
            "workspace_bytes": size}))

    def test_missing_settings_leave_scripts_unchanged(self):
        self.assertIsNone(storage.load_config(self.root / "absent.json"))

    def test_matching_local_workspace_works_offline(self):
        self.receipt(self.store.local)
        with patch.object(storage, "mount_share", return_value=False) as mount:
            choice = self.store.resolve()
        self.assertEqual((choice["mode"], choice["workspace"]), ("local", str(self.store.local)))
        self.assertEqual(mount.call_args.args[1], 15)

    def test_matching_local_workspace_ignores_a_snapshot_without_a_handoff(self):
        self.receipt(self.store.local)
        self.snapshot()
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "restore", side_effect=AssertionError("restored")):
            self.assertEqual(self.store.resolve()["mode"], "local")

    def test_handoff_from_another_mac_is_taken_once_even_at_the_same_version(self):
        self.receipt(self.store.local)
        self.snapshot()
        metadata = json.loads((self.store.current / "metadata.json").read_text())
        (self.store.current / "metadata.json").write_text(json.dumps({**metadata, "handoff": {"from_host": "other-mac"}}))
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "restore", return_value=True):
            self.assertEqual(self.store.resolve()["mode"], "restored")
            self.assertEqual(self.store.snapshot()["handoff"]["taken_by"], self.store.host)
            self.assertEqual(self.store.resolve()["mode"], "local")

    def test_own_handoff_is_not_taken_back(self):
        self.receipt(self.store.local)
        self.snapshot()
        metadata = json.loads((self.store.current / "metadata.json").read_text())
        (self.store.current / "metadata.json").write_text(json.dumps({**metadata, "handoff": {"from_host": self.store.host}}))
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "restore", side_effect=AssertionError("restored")):
            self.assertEqual(self.store.resolve()["mode"], "local")

    def release_state(self, completed=("source",), status="stopped"):
        run = self.repo / "build/releases/20261112T000000Z-abcd1234"
        (run / "source").mkdir(parents=True)
        (run / "source/file.txt").write_text("frozen")
        state = {"id": run.name, "run": str(run), "source": str(run / "source"), "status": status,
                 "workspace": str(self.store.local), "completed": list(completed), "stage": "engine",
                 "engine_seal_path": str(run / "engine-artifacts.json"), "tap": str(Path.home() / "homebrew-tap"),
                 "command_pid": 999, "pid": 998}
        (run / "state.json").write_text(json.dumps(state))
        (self.repo / "build/releases/current.json").write_text(json.dumps(state))
        return state

    def test_handoff_packs_the_engine_and_hands_the_stopped_release_over(self):
        self.receipt(self.store.local, phase="generated")
        state = self.release_state()

        def create(*args, **kwargs):
            output = Path(args[args.index("--output") + 1])
            (output / "engine-workspace.manifest.json").write_text("{}")
            (output / "engine-workspace.inventory.jsonl").write_text('{"size": 5}\n')
            return json.dumps({"metadata_sha256": "a" * 64})

        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "engine_tool", side_effect=create):
            outcome = self.store.publish(self.store.local, handoff=True)
        self.assertTrue(outcome["handoff"])
        self.assertEqual(self.store.snapshot()["handoff"]["from_host"], self.store.host)
        handed = json.loads((self.share / "handoff/current/handoff.json").read_text())
        self.assertEqual((handed["release_id"], handed["from_root"]), (state["id"], str(self.repo)))
        self.assertTrue((self.share / "handoff/current/run/source/file.txt").is_file())
        self.assertEqual(json.loads((self.repo / "build/releases/current.json").read_text())["status"], "handed-off")

    def test_handoff_refuses_a_release_past_its_engine(self):
        self.receipt(self.store.local)
        self.release_state(completed=("source", "engine"))
        with patch.object(storage, "mount_share", return_value=True):
            with self.assertRaises(storage.StorageError):
                self.store.publish(self.store.local, handoff=True)

    def test_other_mac_takes_the_release_with_its_own_paths(self):
        other_root, other_home = "/Users/someone/parc", "/Users/someone"
        handoff = self.share / "handoff/current"
        run = handoff / "run"
        (run / "source").mkdir(parents=True)
        state = {"id": "20261112T000000Z-abcd1234", "run": other_root + "/build/releases/20261112T000000Z-abcd1234",
                 "source": other_root + "/build/releases/20261112T000000Z-abcd1234/source", "status": "handed-off",
                 "workspace": other_home + "/ParcBuild/engine", "tap": other_home + "/homebrew-tap",
                 "completed": ["source"], "command_pid": 999, "storage_upload": {"pid": 5}}
        (run / "state.json").write_text(json.dumps(state))
        (handoff / "handoff.json").write_text(json.dumps({"release_id": state["id"], "from_host": "other-mac",
                                                          "from_root": other_root, "from_home": other_home}))
        restored = {"workspace": str(self.store.local), "mode": "restored", "reason": "", "attached": False}
        with patch.object(storage, "mount_share", return_value=True), patch.object(storage, "run"), \
                patch.object(self.store, "resolve", return_value=restored) as resolve:
            taken = self.store.take_release()
        resolve.assert_called_once_with("snapshot")
        local_run = self.repo / "build/releases" / state["id"]
        self.assertEqual(taken["run"], str(local_run))
        self.assertEqual(taken["source"], str(local_run / "source"))
        self.assertEqual(taken["workspace"], str(self.store.local))
        self.assertEqual(taken["tap"], str(Path.home() / "homebrew-tap"))
        self.assertEqual((taken["status"], taken["storage_mode"]), ("stopped", "restored"))
        self.assertNotIn("command_pid", taken)
        self.assertNotIn("storage_upload", taken)
        self.assertEqual(json.loads((self.repo / "build/releases/current.json").read_text())["id"], state["id"])
        self.assertEqual(json.loads((handoff / "handoff.json").read_text())["taken_by"], self.store.host)
        self.assertIsNone(self.store.take_release())

    def test_take_over_clears_another_macs_record_and_checks_the_image(self):
        self.store.bundle.mkdir()
        self.store.holder.write_text(json.dumps({"host": "other-mac"}))
        plist = storage.plistlib.dumps({"system-entities": [{"mount-point": str(self.store.volume)}]}).decode()
        attached = storage.subprocess.CompletedProcess([], 0, plist, "")
        with patch.object(storage, "mounted", side_effect=lambda path, kind=None: False), \
                patch.object(storage, "run", return_value=attached), \
                patch.object(self.store, "check_volume") as check:
            self.assertTrue(self.store.attach(take_over=True))
        check.assert_called_once()
        self.assertEqual(json.loads(self.store.holder.read_text())["host"], self.store.host)

    def test_publish_removes_interrupted_uploads(self):
        self.receipt(self.store.local)
        leftover = self.store.snapshots / ".new-20260101T000000"
        leftover.mkdir(parents=True)

        def create(*args, **kwargs):
            output = Path(args[args.index("--output") + 1])
            (output / "engine-workspace.manifest.json").write_text("{}")
            (output / "engine-workspace.inventory.jsonl").write_text('{"size": 1}\n')
            return json.dumps({"metadata_sha256": "a" * 64})

        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "engine_tool", side_effect=create):
            self.store.publish(self.store.local)
        self.assertFalse(leftover.exists())

    def test_unreachable_nas_keeps_local_workspace(self):
        self.receipt(self.store.local, overlay="0" * 64)
        with patch.object(storage, "mount_share", return_value=False):
            self.assertEqual(self.store.resolve()["mode"], "local")

    def test_free_fast_image_with_same_chromium_is_used(self):
        self.store.bundle.mkdir()
        self.receipt(self.store.image_workspace, overlay="0" * 64)
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "attach", return_value=True), \
                patch.object(self.store, "speed", return_value=250.0):
            choice = self.store.resolve()
        self.assertEqual((choice["mode"], choice["workspace"], choice["attached"]),
                         ("image", str(self.store.image_workspace), True))

    def test_slow_link_detaches_image_and_unpacks_snapshot(self):
        self.store.bundle.mkdir()
        self.receipt(self.store.image_workspace)
        self.snapshot()
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "attach", return_value=True), \
                patch.object(self.store, "speed", return_value=20.0), \
                patch.object(self.store, "detach", return_value=True) as detach, \
                patch.object(self.store, "restore", return_value=True) as restore:
            choice = self.store.resolve()
        detach.assert_called_once()
        restore.assert_called_once()
        self.assertEqual(choice["mode"], "restored")

    def test_image_behind_this_mac_is_not_used(self):
        self.store.bundle.mkdir()
        self.receipt(self.store.local, overlay="1" * 64, version=1)
        self.receipt(self.store.image_workspace, overlay="0" * 64, version=0)
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "attach", return_value=True), \
                patch.object(self.store, "speed", return_value=250.0), \
                patch.object(self.store, "detach", return_value=True) as detach:
            choice = self.store.resolve()
        detach.assert_called_once()
        self.assertEqual(choice["mode"], "local")
        self.assertTrue(any("at least as new" in line for line in self.logs))

    def test_snapshot_no_newer_than_this_mac_is_not_unpacked(self):
        self.receipt(self.store.local, overlay="1" * 64, version=1)
        self.snapshot(overlay="1" * 64, version=1)
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "restore", side_effect=AssertionError("restored")):
            self.assertEqual(self.store.resolve()["mode"], "local")

    def test_handoff_can_take_the_snapshot_at_the_same_engine_version(self):
        self.receipt(self.store.local, phase="generated")
        self.snapshot()
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "restore", return_value=True) as restore:
            self.assertEqual(self.store.resolve("snapshot")["mode"], "restored")
        restore.assert_called_once()

    def test_requested_image_that_is_busy_is_an_error(self):
        self.store.bundle.mkdir()
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "attach", return_value=False):
            with self.assertRaises(storage.StorageError):
                self.store.resolve("image")

    def test_image_held_by_another_mac_is_retried_then_treated_as_busy(self):
        self.store.bundle.mkdir()
        self.store.holder.write_text(json.dumps({"host": "other-mac"}))
        with patch.object(storage, "mounted", return_value=False), patch.object(storage, "run") as run:
            self.assertFalse(self.store.attach())
        run.assert_not_called()
        self.assertEqual(sum("held by other-mac" in line for line in self.logs), self.config["attach_attempts"])

    def test_refused_attach_retries_before_giving_up(self):
        self.store.bundle.mkdir()
        refused = storage.subprocess.CompletedProcess([], 1, "", "Resource temporarily unavailable")
        with patch.object(storage, "mounted", return_value=False), patch.object(storage, "run", return_value=refused) as run:
            self.assertFalse(self.store.attach())
        self.assertEqual(run.call_count, self.config["attach_attempts"])

    def test_snapshot_for_other_chromium_is_ignored(self):
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot()
        (self.store.current / "metadata.json").write_text(json.dumps({"lock_sha256": "1" * 64,
                                                                      "overlay_identity": "2" * 64}))
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "restore", side_effect=AssertionError("restored")):
            self.assertEqual(self.store.resolve()["mode"], "local")

    def restored(self, *args, **kwargs):
        self.receipt(self.store.local, phase="synced")
        return ""

    def test_restore_replaces_outdated_workspace_after_success(self):
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot()
        with patch.object(self.store, "engine_tool", side_effect=self.restored):
            self.assertTrue(self.store.restore(self.store.snapshot()))
        self.assertEqual(storage.describe(self.store.local)["phase"], "synced")
        self.assertEqual([p.name for p in self.store.local.parent.iterdir()], ["engine"])

    def test_failed_restore_puts_the_old_workspace_back(self):
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot()
        with patch.object(self.store, "engine_tool", side_effect=storage.StorageError("bad part")):
            with self.assertRaises(storage.StorageError):
                self.store.restore(self.store.snapshot())
        self.assertEqual(storage.describe(self.store.local)["overlay_identity"], "0" * 64)

    def test_restore_never_touches_a_folder_without_a_parc_receipt(self):
        self.store.local.mkdir(parents=True)
        (self.store.local / "keep.txt").write_text("mine")
        self.snapshot()
        with patch.object(self.store, "engine_tool", side_effect=AssertionError("restored")):
            self.assertFalse(self.store.restore(self.store.snapshot()))
        self.assertEqual((self.store.local / "keep.txt").read_text(), "mine")

    def test_publish_skips_an_unchanged_engine(self):
        self.receipt(self.store.local)
        self.snapshot()
        found = storage.describe(self.store.local)
        (self.store.current / "metadata.json").write_text(json.dumps(found))
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "engine_tool", side_effect=AssertionError("packed")):
            self.assertEqual(self.store.publish(self.store.local), {"published": False, "reason": "already current"})

    def test_publish_replaces_the_current_snapshot(self):
        self.receipt(self.store.local)
        self.snapshot(overlay="0" * 64)

        def create(*args, **kwargs):
            output = Path(args[args.index("--output") + 1])
            (output / "engine-workspace.manifest.json").write_text("{}")
            (output / "engine-workspace.inventory.jsonl").write_text('{"size": 3}\n{"size": 4}\n')
            return json.dumps({"metadata_sha256": "a" * 64})

        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "engine_tool", side_effect=create):
            self.assertEqual(self.store.publish(self.store.local), {"published": True})
        metadata = self.store.snapshot()
        self.assertEqual((metadata["overlay_identity"], metadata["workspace_bytes"]), (self.wanted["overlay_identity"], 7))
        self.assertEqual(sorted(p.name for p in self.store.snapshots.iterdir() if not p.name.startswith(".lock")),
                         ["current"])


    def test_manual_publish_defaults_to_the_last_release_workspace(self):
        run = self.repo / "build/releases/run-1"
        run.mkdir(parents=True)
        (run / "state.json").write_text(json.dumps({"workspace": str(self.store.local)}))
        (self.repo / "build/releases/latest.json").write_text(json.dumps({"run": str(run)}))
        self.assertEqual(self.store.last_release_workspace(), self.store.local)

    def test_manual_publish_opens_and_ejects_the_image_it_needs(self):
        workspace = self.store.image_workspace
        with patch.object(storage, "mounted", return_value=False), \
                patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "attach", return_value=True) as attach, \
                patch.object(self.store, "detach", return_value=True) as detach, \
                patch.object(self.store, "publish", return_value={"published": True}):
            self.assertEqual(self.store.publish_from(workspace), {"published": True})
        attach.assert_called_once()
        detach.assert_called_once()

    def test_failed_publish_writes_its_reason_for_the_release(self):
        result = self.root / "result.json"
        settings = self.root / "settings.json"
        settings.write_text(json.dumps({"schema_version": 1, "share": "nfs://nas.test/engine",
                                        "mount_point": str(self.share)}))
        with patch.dict(storage.os.environ, {"PARC_ENGINE_STORAGE": str(settings)}), \
                patch.object(storage, "mount_share", return_value=False):
            code = storage.main(["publish", "--repo", str(self.repo), "--workspace", str(self.root / "local/engine"),
                                 "--result", str(result)])
        self.assertEqual(code, 1)
        self.assertIsNone(json.loads(result.read_text())["published"])


if __name__ == "__main__":
    unittest.main()
