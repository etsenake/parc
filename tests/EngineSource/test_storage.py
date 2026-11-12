import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
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
        self.developer = self.root / "Xcode.app/Contents/Developer"
        headers = self.developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include"
        headers.mkdir(parents=True)
        (self.developer / "usr/bin").mkdir(parents=True)
        (self.developer.parent / "version.plist").write_bytes(storage.plistlib.dumps(
            {"CFBundleShortVersionString": "27.2", "ProductBuildVersion": "27B52"}))
        for path, text in ((headers / "stdio.h", "int printf();"), (headers / "stdlib.h", "void exit(int);"),
                           (self.developer / "usr/bin/actool", "tool")):
            path.write_text(text)
            storage.os.utime(path, ns=(1_700_000_000_000_000_000, 1_700_000_000_000_000_000))
        (headers / "alias.h").symlink_to("stdio.h")
        patcher = patch.object(storage, "developer_dir", return_value=self.developer)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.privileged = []

    def run_privileged(self, script, ran=None):
        self.privileged.append(script)
        return subprocess.run(script, shell=True).returncode == 0

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

    def run_setup(self, metal=(True,), mounted=True, local_engine=False, environment=None):
        settings = self.root / "settings/engine-storage.json"
        settings.parent.mkdir()
        settings.write_text(json.dumps({"schema_version": 1, "share": "nfs://old.local/engine",
                                        "mount_point": str(self.share), "min_image_mb_per_second": 50}))
        if local_engine:
            self.receipt(self.repo / "work/engine")
        home = self.root / "home"
        home.mkdir(exist_ok=True)
        with patch.dict(storage.os.environ, {"PARC_ENGINE_STORAGE": str(settings), **(environment or {})}), \
                patch.object(storage.Path, "home", return_value=home), \
                patch.object(storage, "metal_toolchain_ready", side_effect=list(metal)), \
                patch.object(storage.subprocess, "run") as download, \
                patch.object(storage, "mount_share", return_value=mounted), \
                patch.object(storage.Store, "make_folder") as make_folder, \
                patch.object(storage.Store, "align_current") as align:
            problems = storage.setup("nfs://Tardis.local/volume1/parc-engine-nfs", self.repo, self.logs.append)
        return problems, json.loads(settings.read_text()), download, make_folder, align

    def test_setup_prepares_a_new_mac_for_the_shared_engine(self):
        built = self.root / "elsewhere/ParcBuild/engine-cx"
        self.snapshot()
        metadata = json.loads((self.store.current / "metadata.json").read_text())
        (self.store.current / "metadata.json").write_text(json.dumps({**metadata, "workspace": str(built)}))
        problems, settings, download, make_folder, align = self.run_setup(metal=(False, True))
        self.assertEqual(problems, [])
        self.assertEqual(settings["share"], "nfs://Tardis.local/volume1/parc-engine-nfs")
        self.assertEqual(settings["min_image_mb_per_second"], 50)
        self.assertEqual(download.call_args.args[0], ["xcodebuild", "-downloadComponent", "MetalToolchain"])
        make_folder.assert_called_once_with(built.parent)
        align.assert_called_once()

    def test_setup_leaves_xcode_alone_on_a_mac_with_its_own_engine(self):
        self.snapshot()
        problems, _, download, _, align = self.run_setup(local_engine=True)
        self.assertEqual(problems, [])
        download.assert_not_called()
        align.assert_not_called()

    def test_setup_finds_an_engine_anywhere_a_release_would_look(self):
        self.snapshot()
        self.receipt(self.root / "home/ParcBuild/engine")
        _, _, _, _, align = self.run_setup()
        align.assert_not_called()
        storage.shutil.rmtree(self.root / "home/ParcBuild")
        self.receipt(self.root / "chosen/engine")
        (self.root / "settings/engine-storage.json").unlink()
        (self.root / "settings").rmdir()
        _, _, _, _, align = self.run_setup(environment={"PARC_ENGINE_WORKSPACE": str(self.root / "chosen/engine")})
        align.assert_not_called()

    def test_setup_says_what_is_still_needed(self):
        problems, _, _, make_folder, _ = self.run_setup(metal=(False, False), mounted=False)
        self.assertEqual(len(problems), 2)
        self.assertIn("downloadComponent MetalToolchain", problems[0])
        self.assertIn("Network Volumes", problems[1])
        make_folder.assert_not_called()

    def test_a_release_finds_the_engine_through_the_checkout_and_matches_its_frozen_source(self):
        frozen = self.root / "build/releases/run-1/source"
        (frozen / "Engine/ParcHost").mkdir(parents=True)
        (frozen / "Engine/source-lock.json").write_text((self.repo / "Engine/source-lock.json").read_text())
        (frozen / "Engine/ParcHost/overlay.json").write_text((self.repo / "Engine/ParcHost/overlay.json").read_text())
        workspace = self.root / "elsewhere/ParcBuild/engine-cx"
        self.receipt(workspace)
        (self.repo / "work").mkdir()
        (self.repo / "work/engine").symlink_to(workspace)
        (self.repo / "Engine/ParcHost/overlay.json").write_text('{"version": 3}\n')
        config = {key: value for key, value in self.config.items() if key != "local_workspace"}
        store = storage.Store(config, self.repo, log=self.logs.append, source=frozen)
        with patch.object(storage, "mount_share", return_value=False), \
                patch.object(store, "restore", side_effect=AssertionError("unpacked over this Mac's engine")):
            choice = store.resolve()
        self.assertEqual((choice["mode"], choice["workspace"]), ("local", str(workspace.resolve())))

    def test_missing_settings_leave_scripts_unchanged(self):
        self.assertIsNone(storage.load_config(self.root / "absent.json"))

    def test_local_workspace_defaults_to_the_checkouts_ignored_work_folder(self):
        settings = self.root / "settings.json"
        settings.write_text(json.dumps({"schema_version": 1, "share": "nfs://nas.test/engine"}))
        store = storage.Store(storage.load_config(settings), self.repo)
        self.assertEqual(store.local, self.repo / "work/engine")

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
                                                          "from_root": other_root, "from_home": other_home,
                                                          "snapshot_created_utc": "T1"}))
        self.handed_off_snapshot("T1")
        with patch.object(storage, "mount_share", return_value=True), patch.object(storage, "run"), \
                patch.object(self.store, "restore", return_value=True) as restore:
            taken = self.store.take_release()
        restore.assert_called_once()
        self.assertEqual(self.store.snapshot()["handoff"]["taken_by"], self.store.host)
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

    def handed_off_snapshot(self, created):
        self.snapshot()
        metadata = json.loads((self.store.current / "metadata.json").read_text())
        (self.store.current / "metadata.json").write_text(json.dumps(
            {**metadata, "handoff": {"from_host": "other-mac", "created_utc": created}}))

    def handoff_waiting(self, **extra):
        handoff = self.share / "handoff/current"
        (handoff / "run").mkdir(parents=True)
        (handoff / "run/state.json").write_text(json.dumps({"id": "20261112T000000Z-abcd1234", "completed": []}))
        (handoff / "handoff.json").write_text(json.dumps({"release_id": "20261112T000000Z-abcd1234",
                                                          "from_host": "other-mac", "from_root": "/a", "from_home": "/b",
                                                          "snapshot_created_utc": "T1", **extra}))
        return handoff / "handoff.json"

    def test_a_release_another_mac_already_claimed_is_left_alone(self):
        self.handoff_waiting(taken_by="third-mac")
        self.handed_off_snapshot("T1")
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "restore", side_effect=AssertionError("restored")):
            self.assertIsNone(self.store.take_release())

    def test_failed_takeover_gives_the_claim_back(self):
        info = self.handoff_waiting()
        self.handed_off_snapshot("T1")
        with patch.object(storage, "mount_share", return_value=True), patch.object(storage, "run"), \
                patch.object(self.store, "restore", return_value=False), \
                self.assertRaises(storage.StorageError):
            self.store.take_release()
        self.assertNotIn("taken_by", json.loads(info.read_text()))
        self.assertFalse((self.repo / "build/releases/20261112T000000Z-abcd1234").exists())

    def test_takeover_refuses_a_snapshot_replaced_since_the_handoff(self):
        info = self.handoff_waiting()
        self.handed_off_snapshot("T2")
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "restore", side_effect=AssertionError("restored")), \
                self.assertRaisesRegex(storage.StorageError, "no longer holds"):
            self.store.take_release()
        self.assertNotIn("taken_by", json.loads(info.read_text()))

    def test_handoff_packs_even_when_the_snapshot_holds_the_same_engine(self):
        self.receipt(self.store.local)
        self.snapshot()
        (self.store.current / "metadata.json").write_text(json.dumps(storage.describe(self.store.local)))

        def create(*args, **kwargs):
            output = Path(args[args.index("--output") + 1])
            (output / "engine-workspace.manifest.json").write_text("{}")
            (output / "engine-workspace.inventory.jsonl").write_text('{"size": 5}\n')
            return json.dumps({"metadata_sha256": "a" * 64})

        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "engine_tool", side_effect=create) as tool:
            self.assertTrue(self.store.publish(self.store.local, handoff=True)["published"])
        tool.assert_called_once()
        self.assertEqual(self.store.snapshot()["handoff"]["from_host"], self.store.host)

    def test_restore_refuses_a_snapshot_replaced_after_it_was_chosen(self):
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot()
        chosen = {**self.store.snapshot(), "created_utc": "earlier"}
        with patch.object(self.store, "engine_tool", side_effect=AssertionError("unpacked")), \
                self.assertRaisesRegex(storage.StorageError, "changed"):
            self.store.restore(chosen)
        self.assertEqual(storage.describe(self.store.local)["overlay_identity"], "0" * 64)

    def test_short_space_checks_the_snapshot_before_deleting_the_old_copy(self):
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot(size=1 << 50)
        calls = []

        def tool(*args, **kwargs):
            calls.append(args[0])
            raise storage.StorageError("part 3 is damaged")

        with patch.object(self.store, "engine_tool", side_effect=tool), \
                patch.object(storage, "available_bytes", return_value=10 << 30), \
                patch.object(storage, "reclaimable_bytes", return_value=1 << 51), \
                self.assertRaisesRegex(storage.StorageError, "damaged"):
            self.store.restore(self.store.snapshot())
        self.assertEqual(calls, ["verify"])
        self.assertEqual(storage.describe(self.store.local)["overlay_identity"], "0" * 64)

    def test_too_little_room_even_after_deleting_keeps_the_old_copy(self):
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot(size=1 << 50)
        with patch.object(self.store, "engine_tool", side_effect=AssertionError("touched the snapshot")), \
                patch.object(storage, "available_bytes", return_value=10 << 30):
            self.assertFalse(self.store.restore(self.store.snapshot()))
        self.assertEqual(storage.describe(self.store.local)["overlay_identity"], "0" * 64)
        self.assertTrue(any("nothing was removed" in line for line in self.logs))

    def test_only_storage_a_file_owns_counts_as_freed(self):
        folder, outside = self.root / "old-engine", self.root / "elsewhere"
        folder.mkdir()
        outside.mkdir()
        (folder / "own.bin").write_bytes(storage.os.urandom(1 << 20))
        (outside / "shared.bin").write_bytes(storage.os.urandom(1 << 20))
        storage.os.link(outside / "shared.bin", folder / "second-name.bin")
        (outside / "original.bin").write_bytes(storage.os.urandom(1 << 20))
        subprocess.run(["/bin/cp", "-c", str(outside / "original.bin"), str(folder / "copy.bin")], check=True)
        (folder / "link").symlink_to(outside / "original.bin")
        freed = storage.reclaimable_bytes(folder)
        self.assertGreaterEqual(freed, 1 << 20)
        self.assertLess(freed, (1 << 20) + (1 << 18))

    def test_a_disk_that_cannot_report_ownership_never_authorizes_deleting(self):
        self.receipt(self.store.local, overlay="0" * 64)
        (self.store.local / "objects.bin").write_bytes(storage.os.urandom(1 << 20))
        self.snapshot(size=1 << 30)
        need = int((1 << 30) * 1.05 + (5 << 30))
        with patch.object(storage, "LIBC", SimpleNamespace(getattrlist=lambda *args: 0)), \
                patch.object(storage, "available_bytes", return_value=need - (1 << 19)), \
                patch.object(self.store, "engine_tool", side_effect=AssertionError("touched the snapshot")):
            self.assertFalse(self.store.restore(self.store.snapshot()))
        self.assertTrue((self.store.local / "objects.bin").is_file())
        self.assertTrue(any("nothing was removed" in line for line in self.logs))

    def test_free_space_counts_what_macos_reclaims_on_demand(self):
        self.assertGreaterEqual(storage.available_bytes(self.root), storage.shutil.disk_usage(self.root).free)

    def test_room_made_by_deleting_the_old_copy_unpacks_after_checking(self):
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot(size=50 << 30)
        calls = []

        def tool(*args, **kwargs):
            calls.append(args[0])
            return self.restored(*args, **kwargs) if args[0] == "restore" else ""

        with patch.object(self.store, "engine_tool", side_effect=tool), \
                patch.object(storage, "reclaimable_bytes", return_value=100 << 30), \
                patch.object(storage, "available_bytes",
                             side_effect=lambda path: (10 << 30) if self.store.local.exists() else (200 << 30)):
            self.assertTrue(self.store.restore(self.store.snapshot()))
        self.assertEqual(calls, ["verify", "restore"])
        self.assertEqual(storage.describe(self.store.local)["phase"], "synced")

    def assert_takeover_left_no_trace(self, info):
        self.assertNotIn("taken_by", json.loads(info.read_text()))
        self.assertNotIn("taken_by", self.store.snapshot()["handoff"])
        releases = self.repo / "build/releases"
        self.assertEqual(sorted(p.name for p in releases.iterdir()) if releases.exists() else [], [])

    def test_takeover_failing_while_copying_the_release_rolls_everything_back(self):
        info = self.handoff_waiting()
        self.handed_off_snapshot("T1")
        with patch.object(storage, "mount_share", return_value=True), patch.object(storage, "run"), \
                patch.object(self.store, "restore", return_value=True), \
                patch.object(storage.shutil, "copytree", side_effect=OSError("disk full")), \
                self.assertRaises(OSError):
            self.store.take_release()
        self.assert_takeover_left_no_trace(info)

    def test_claim_failing_halfway_leaves_the_release_free_for_any_mac(self):
        info = self.handoff_waiting()
        self.handed_off_snapshot("T1")
        original = storage.write_json

        def write(path, value):
            if path.name == "metadata.json":
                raise OSError("NAS went away")
            original(path, value)

        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(storage, "write_json", side_effect=write), \
                self.assertRaises(OSError):
            self.store.take_release()
        self.assertNotIn("taken_by", json.loads(info.read_text()))

    def test_takeover_failing_to_record_the_release_rolls_everything_back(self):
        info = self.handoff_waiting()
        self.handed_off_snapshot("T1")
        original = storage.write_json

        def write(path, value):
            if path.name == "current.json":
                raise OSError("disk full")
            original(path, value)

        with patch.object(storage, "mount_share", return_value=True), patch.object(storage, "run"), \
                patch.object(self.store, "restore", return_value=True), \
                patch.object(storage, "write_json", side_effect=write), \
                self.assertRaises(OSError):
            self.store.take_release()
        self.assert_takeover_left_no_trace(info)

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

    def test_restore_goes_where_the_engine_was_last_built_and_links_the_repo(self):
        built = self.root / "elsewhere/ParcBuild/engine-cx"
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot()
        metadata = json.loads((self.store.current / "metadata.json").read_text())
        (self.store.current / "metadata.json").write_text(json.dumps({**metadata, "workspace": str(built)}))

        def restored(*args, **kwargs):
            destination = Path(args[args.index("--destination") + 1])
            self.receipt(destination, phase="synced")
            return ""

        with patch.object(self.store, "engine_tool", side_effect=restored):
            self.assertTrue(self.store.restore(self.store.snapshot()))
        self.assertEqual(self.store.local, built)
        self.assertEqual(storage.describe(built)["phase"], "synced")
        self.assertFalse(self.config["local_workspace"] and Path(self.config["local_workspace"]).exists())
        self.assertTrue(self.store.link.is_symlink())
        self.assertEqual(Path(storage.os.readlink(self.store.link)), built)

    def test_local_workspace_follows_the_repo_link(self):
        target = self.root / "elsewhere/engine"
        target.mkdir(parents=True)
        (self.repo / "work").mkdir()
        (self.repo / "work/engine").symlink_to(target)
        config = {key: value for key, value in self.config.items() if key != "local_workspace"}
        self.assertEqual(storage.Store(config, self.repo).local, target.resolve())

    def test_unwritable_build_path_is_created_with_administrator_rights(self):
        folder = self.root / "protected/ParcBuild"

        def privileged(command, timeout, cwd=None):
            storage.os.makedirs(folder)
            return storage.subprocess.CompletedProcess(command, 0, "", "")

        with patch.object(storage.Path, "mkdir", side_effect=PermissionError("denied")), \
                patch.object(storage, "run", side_effect=privileged) as run:
            self.store.make_folder(folder)
        self.assertEqual(run.call_args.args[0][:3], ["/usr/bin/sudo", "-n", "/bin/sh"])
        self.assertIn("chown", run.call_args.args[0][-1])

    def tool(self, body):
        scripts = self.repo / "scripts"
        scripts.mkdir(exist_ok=True)
        (scripts / "engine-artifacts.py").write_text("import sys, time\n" + body)
        self.store.progress_seconds = 0.05

    def test_engine_tool_reports_progress_and_shows_tool_messages_as_they_happen(self):
        self.tool("print('working', file=sys.stderr, flush=True)\ntime.sleep(0.4)\nprint('{\"ok\": 1}')\n")
        ticks = []
        self.assertEqual(self.store.engine_tool("restore", progress=lambda: ticks.append(1)).strip(), '{"ok": 1}')
        self.assertGreater(len(ticks), 1)
        self.assertIn("working", self.logs)

    def test_engine_tool_failure_carries_the_tools_error(self):
        self.tool("print('bad archive part', file=sys.stderr)\nsys.exit(1)\n")
        with self.assertRaisesRegex(storage.StorageError, "bad archive part"):
            self.store.engine_tool("restore")

    def test_unpack_progress_reports_gigabytes_and_then_verification(self):
        used = iter([0, 30 << 30, 60 << 30, 60 << 30])
        with patch.object(storage.shutil, "disk_usage", side_effect=lambda path: SimpleNamespace(used=next(used))):
            report = self.store.unpack_progress(self.root, 60 << 30)
            report()
            report()
            report()
        self.assertIn("Unpacked 30.0 of 60.0 GB (50%", self.logs[0])
        self.assertTrue(self.logs[1].startswith("Unpacked; verifying"))
        self.assertTrue(self.logs[2].startswith("Still verifying"))

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
        for path in (self.store.current / storage.XCODE_RECORD, self.share / storage.XCODE_RECORD):
            record = storage.read_record(path)
            self.assertEqual(record["xcode"], {"version": "27.2", "build": "27B52"})
            self.assertEqual(sorted(entry[0].rsplit("/", 1)[-1] for entry in record["files"]),
                             ["actool", "stdio.h", "stdlib.h"])

    def test_restore_matches_this_macs_xcode_timestamps_to_the_build_mac(self):
        record = storage.xcode_record(self.developer)
        headers = self.developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include"
        storage.os.utime(headers / "stdio.h", ns=(1, 1_800_000_000_000_000_000))
        (headers / "stdlib.h").write_text("void quit(int);")
        storage.os.utime(headers / "stdlib.h", ns=(1, 1_800_000_000_000_000_000))
        (self.developer / "usr/bin/actool").unlink()
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot()
        storage.write_record(self.store.current / storage.XCODE_RECORD, record)
        with patch.object(self.store, "engine_tool", side_effect=self.restored), \
                patch.object(self.store, "privileged", side_effect=self.run_privileged):
            self.assertTrue(self.store.restore(self.store.snapshot()))
        self.assertEqual((headers / "stdio.h").stat().st_mtime_ns, 1_700_000_000_000_000_000)
        self.assertEqual((headers / "stdlib.h").stat().st_mtime_ns, 1_800_000_000_000_000_000)
        self.assertEqual(len(self.privileged), 1)
        self.assertIn("Xcode timestamps: 1 match the engine's build Mac, 1 differ in content, 1 missing", self.logs)

    def test_xcode_is_aligned_before_the_long_unpack_starts(self):
        record = storage.xcode_record(self.developer)
        header = self.developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/stdio.h"
        storage.os.utime(header, ns=(1, 1_800_000_000_000_000_000))
        self.snapshot()
        storage.write_record(self.store.current / storage.XCODE_RECORD, record)
        seen = []

        def restored(*args, **kwargs):
            seen.append(header.stat().st_mtime_ns)
            return self.restored(*args, **kwargs)

        with patch.object(self.store, "engine_tool", side_effect=restored), \
                patch.object(self.store, "privileged", side_effect=self.run_privileged):
            self.assertTrue(self.store.restore(self.store.snapshot()))
        self.assertEqual(seen, [1_700_000_000_000_000_000])

    def test_macos_refusing_xcode_changes_names_the_missing_permission(self):
        record = storage.xcode_record(self.developer)
        header = self.developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/stdio.h"
        storage.os.utime(header, ns=(1, 1_800_000_000_000_000_000))
        subprocess.run(["/usr/bin/chflags", "uchg", str(header)], check=True)
        self.addCleanup(subprocess.run, ["/usr/bin/chflags", "nouchg", str(header)])
        with patch.object(self.store, "privileged", side_effect=self.run_privileged), \
                self.assertRaisesRegex(storage.StorageError, "App Management"):
            self.store.align_xcode(record)

    def test_a_refusal_does_not_ask_for_the_password_again(self):
        with patch.object(storage, "run", return_value=SimpleNamespace(returncode=3, stdout="", stderr="")) as run:
            self.assertFalse(self.store.privileged("true", ran=lambda: True))
        self.assertEqual(run.call_count, 1)

    def test_aligned_xcode_needs_no_administrator_rights(self):
        record = storage.xcode_record(self.developer)
        with patch.object(self.store, "privileged", side_effect=AssertionError("asked for rights")):
            counts = self.store.align_xcode(record)
        self.assertEqual(counts, {"aligned": 3, "changed": 0, "missing": 0})

    def test_other_xcode_build_still_aligns_identical_files(self):
        record = storage.xcode_record(self.developer)
        record["xcode"] = {"version": "27.2.1", "build": "27C10"}
        headers = self.developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include"
        storage.os.utime(headers / "stdio.h", ns=(1, 1_800_000_000_000_000_000))
        with patch.object(self.store, "privileged", side_effect=self.run_privileged):
            counts = self.store.align_xcode(record)
        self.assertEqual(counts["aligned"], 3)
        self.assertEqual((headers / "stdio.h").stat().st_mtime_ns, 1_700_000_000_000_000_000)

    def test_refused_rights_leave_the_restore_in_place_and_say_why(self):
        record = storage.xcode_record(self.developer)
        headers = self.developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include"
        storage.os.utime(headers / "stdio.h", ns=(1, 1_800_000_000_000_000_000))
        self.receipt(self.store.local, overlay="0" * 64)
        self.snapshot()
        storage.write_record(self.store.current / storage.XCODE_RECORD, record)
        with patch.object(self.store, "engine_tool", side_effect=self.restored), \
                patch.object(self.store, "privileged", return_value=False):
            self.assertTrue(self.store.restore(self.store.snapshot()))
        self.assertTrue(any("Xcode timestamps were not aligned" in line for line in self.logs))

    def test_building_in_the_image_matches_xcode_to_the_shared_record(self):
        self.store.bundle.mkdir()
        self.receipt(self.store.image_workspace, overlay="0" * 64)
        storage.write_record(self.share / storage.XCODE_RECORD, storage.xcode_record(self.developer))
        with patch.object(storage, "mount_share", return_value=True), \
                patch.object(self.store, "attach", return_value=True), \
                patch.object(self.store, "speed", return_value=250.0), \
                patch.object(self.store, "align_xcode") as align:
            self.assertEqual(self.store.resolve()["mode"], "image")
        self.assertEqual(align.call_args.args[0]["xcode"], {"version": "27.2", "build": "27B52"})

    def test_record_command_writes_the_current_snapshot_and_shared_record(self):
        self.snapshot()
        with patch.object(storage, "mount_share", return_value=True):
            record = self.store.record_current()
        self.assertEqual(len(record["files"]), 3)
        self.assertTrue((self.store.current / storage.XCODE_RECORD).is_file())
        self.assertTrue((self.share / storage.XCODE_RECORD).is_file())


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
