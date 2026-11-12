#!/usr/bin/env python3
"""Choose the engine workspace for a build (this Mac, a shared NAS disk image or a NAS snapshot) and keep the NAS copy current."""
from __future__ import annotations

import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
RECEIPT = ".parc-engine-source.json"
SHIPPING = ".parc-shipping-build.json"
OPERATION_LOCK = ".parc-operation.lock"
SNAPSHOT_NAME = "engine-workspace"
TERMINAL = {"complete", "abandoned", "nothing-to-release", "handed-off"}
DEFAULTS = {
    "mount_point": "/Volumes/parc-engine-nfs",
    "image": "parc-engine.sparsebundle",
    "volume": "ParcEngine",
    "image_workspace": "ParcBuild/engine",
    "local_workspace": "~/ParcBuild/engine",
    "min_image_mb_per_second": 100,
    "attach_attempts": 3,
    "holder_stale_hours": 48,
    "lock_wait_seconds": 600,
}


class StorageError(RuntimeError):
    pass


def now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def config_path() -> Path:
    value = os.environ.get("PARC_ENGINE_STORAGE")
    return Path(value).expanduser() if value else Path.home() / ".config/parc/engine-storage.json"


def load_config(path: Path | None = None) -> dict | None:
    path = path or config_path()
    if not path.is_file():
        return None
    raw = json.loads(path.read_text())
    if raw.get("schema_version") != 1 or not isinstance(raw.get("share"), str):
        raise StorageError(f"Unsupported engine storage settings: {path}")
    config = {**DEFAULTS, **raw}
    for key in ("mount_point", "local_workspace"):
        config[key] = str(Path(config[key]).expanduser())
    return config


def sha(path: Path) -> str:
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path: Path) -> dict | None:
    try:
        value = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_name("." + path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, path)


def target(repo: Path) -> dict:
    overlay = repo / "Engine/ParcHost/overlay.json"
    return {"lock_sha256": sha(repo / "Engine/source-lock.json"), "overlay_identity": sha(overlay),
            "overlay_version": json.loads(overlay.read_text()).get("version")}


def describe(workspace: Path) -> dict | None:
    state = read_json(workspace / RECEIPT)
    if state is None:
        return None
    shipping = read_json(workspace / SHIPPING)
    identity = (state.get("overlay") or {}).get("identity")
    record = read_json(workspace / ".parc-overlays" / (str(identity) + ".json")) if identity else None
    return {"lock_sha256": state.get("lock_sha256"),
            "overlay_identity": identity,
            "overlay_version": (record or {}).get("version"),
            "source_fingerprint": state.get("source_fingerprint"),
            "phase": state.get("phase"),
            "shipping_phase": (shipping or {}).get("phase"),
            "receipt_sha256": sha(workspace / RECEIPT),
            "shipping_receipt_sha256": sha(workspace / SHIPPING) if shipping is not None else None}


def matches(found: dict | None, wanted: dict, *, overlay: bool = True) -> bool:
    if not found or found.get("lock_sha256") != wanted["lock_sha256"]:
        return False
    return not overlay or found.get("overlay_identity") == wanted["overlay_identity"]


def rank(found: dict | None, wanted: dict) -> int | None:
    if not matches(found, wanted, overlay=False):
        return None
    if found.get("overlay_identity") == wanted["overlay_identity"]:
        return int(wanted.get("overlay_version") or 0)
    version = found.get("overlay_version")
    if not isinstance(version, int) or version > int(wanted.get("overlay_version") or 0):
        return None
    return version


def newer(candidate: dict | None, local: dict | None, wanted: dict) -> bool:
    ahead, behind = rank(candidate, wanted), rank(local, wanted)
    return ahead is not None and (behind is None or ahead > behind)


def run(args: list, timeout: float, cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run([str(a) for a in args], cwd=cwd, capture_output=True, text=True, timeout=timeout)


def mounted(path: str, kind: str | None = None) -> bool:
    try:
        table = run(["/sbin/mount"], 20).stdout
    except subprocess.TimeoutExpired:
        return False
    needle = f" on {path} ("
    return any(needle in line and (kind is None or f"({kind}" in line) for line in table.splitlines())


def mount_share(config: dict, timeout: float = 90) -> bool:
    if mounted(config["mount_point"], "nfs"):
        return True
    try:
        run(["/usr/bin/osascript", "-e", f'mount volume "{config["share"]}"'], timeout)
    except subprocess.TimeoutExpired:
        return False
    return mounted(config["mount_point"], "nfs")


def relocate(value, moves: list[tuple[str, str]]):
    if isinstance(value, dict):
        return {key: relocate(item, moves) for key, item in value.items()}
    if isinstance(value, list):
        return [relocate(item, moves) for item in value]
    if isinstance(value, str):
        for old, new in moves:
            if value == old or value.startswith(old + "/"):
                return new + value[len(old):]
    return value


class Store:
    def __init__(self, config: dict, repo: Path = ROOT, log=None):
        self.config = config
        self.repo = Path(repo)
        self.log = log or (lambda message: print(f"[{now()}] engine-storage: {message}", file=sys.stderr, flush=True))
        self.share = Path(config["mount_point"])
        self.bundle = self.share / config["image"]
        self.volume = Path("/Volumes") / config["volume"]
        self.image_workspace = self.volume / config["image_workspace"]
        self.local = Path(config["local_workspace"])
        self.snapshots = self.share / "snapshots"
        self.current = self.snapshots / "current"
        self.holder = self.share / (config["image"] + ".holder.json")
        self.host = socket.gethostname()

    def snapshot(self) -> dict | None:
        metadata = read_json(self.current / "metadata.json")
        if metadata is None or not (self.current / "pin.json").is_file():
            return None
        return metadata

    def holder_blocks(self) -> str | None:
        holder = read_json(self.holder)
        if holder is None or holder.get("host") == self.host:
            return None
        try:
            age = time.time() - self.holder.stat().st_mtime
        except OSError:
            return None
        if age > self.config["holder_stale_hours"] * 3600:
            return None
        return holder.get("host") or "another Mac"

    def attach(self, take_over: bool = False) -> bool:
        if mounted(str(self.volume)):
            return True
        if not self.bundle.is_dir():
            return False
        if take_over:
            holder = read_json(self.holder)
            self.log(f"Taking the disk image over from {(holder or {}).get('host') or 'nobody'}")
            self.holder.unlink(missing_ok=True)
        attempts = max(1, int(self.config["attach_attempts"]))
        for attempt in range(attempts):
            blocker = self.holder_blocks()
            if blocker is None:
                try:
                    result = run(["/usr/bin/hdiutil", "attach", "-owners", "off", "-nobrowse", "-plist", self.bundle], 180)
                except subprocess.TimeoutExpired:
                    result = None
                if result is not None and result.returncode == 0:
                    points = [entry["mount-point"] for entry in plistlib.loads(result.stdout.encode()).get("system-entities", [])
                              if "mount-point" in entry]
                    if str(self.volume) not in points:
                        for point in points:
                            run(["/usr/bin/hdiutil", "detach", point], 120)
                        raise StorageError(f"Disk image mounted at {points}, not {self.volume}; detached")
                    write_json(self.holder, {"host": self.host, "user": os.environ.get("USER"), "pid": os.getpid(),
                                             "attached_utc": now()})
                    if take_over:
                        self.check_volume()
                    return True
                reason = (result.stderr or result.stdout).strip() if result is not None else "timed out"
                self.log(f"Disk image refused to open ({reason}); attempt {attempt + 1} of {attempts}")
            else:
                self.log(f"Disk image is held by {blocker}; attempt {attempt + 1} of {attempts}")
            if attempt + 1 < attempts:
                time.sleep(5 * 2 ** attempt)
        return False

    def check_volume(self) -> None:
        verify = run(["/usr/sbin/diskutil", "verifyVolume", self.volume], 3600)
        if verify.returncode == 0:
            self.log("The disk image's file system checked clean")
            return
        self.log("The disk image's file system needs repair; repairing")
        repair = run(["/usr/sbin/diskutil", "repairVolume", self.volume], 3600)
        if repair.returncode != 0 or not mounted(str(self.volume)):
            self.detach()
            raise StorageError("the disk image's file system could not be repaired: "
                               + (repair.stderr or repair.stdout).strip()[-400:])
        self.log("The disk image's file system was repaired")

    def detach(self) -> bool:
        if mounted(str(self.volume)):
            result = run(["/usr/bin/hdiutil", "detach", self.volume], 300)
            if result.returncode != 0:
                self.log(f"Disk image could not be ejected: {(result.stderr or result.stdout).strip()}")
                return False
        holder = read_json(self.holder)
        if holder is not None and holder.get("host") == self.host:
            self.holder.unlink(missing_ok=True)
        return True

    def speed(self, limit: int = 256 << 20, seconds: float = 8.0) -> float | None:
        bands = self.bundle / "bands"
        try:
            candidates = sorted((entry for entry in os.scandir(bands) if entry.is_file()),
                                key=lambda entry: entry.stat().st_size, reverse=True)[:8]
        except OSError:
            return None
        if not candidates:
            return None
        band = Path(candidates[len(candidates) // 2].path)
        descriptor = os.open(band, os.O_RDONLY)
        try:
            fcntl.fcntl(descriptor, getattr(fcntl, "F_NOCACHE", 48), 1)
            total, start = 0, time.perf_counter()
            while total < limit and time.perf_counter() - start < seconds:
                chunk = os.read(descriptor, 8 << 20)
                if not chunk:
                    break
                total += len(chunk)
            elapsed = time.perf_counter() - start
        finally:
            os.close(descriptor)
        return total / (1 << 20) / elapsed if total and elapsed > 0 else None

    def locked(self, exclusive: bool):
        self.snapshots.mkdir(parents=True, exist_ok=True)
        handle = (self.snapshots / ".lock").open("a+")
        deadline = time.monotonic() + float(self.config["lock_wait_seconds"])
        while True:
            try:
                fcntl.flock(handle, (fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH) | fcntl.LOCK_NB)
                return handle
            except BlockingIOError:
                if time.monotonic() > deadline:
                    handle.close()
                    raise StorageError("Another Mac is updating the NAS snapshot")
                time.sleep(10)

    def engine_tool(self, *args: str, timeout: float = 6 * 3600) -> str:
        result = run([sys.executable, self.repo / "scripts/engine-artifacts.py", *args], timeout, cwd=self.repo)
        if result.returncode != 0:
            raise StorageError((result.stderr or result.stdout).strip() or "engine artifact operation failed")
        return result.stdout

    def operation_idle(self, workspace: Path) -> bool:
        lock = workspace / OPERATION_LOCK
        if not lock.is_file():
            return True
        with lock.open("rb") as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return False
            fcntl.flock(handle, fcntl.LOCK_UN)
        return True

    def restore(self, metadata: dict) -> bool:
        need = int(metadata.get("workspace_bytes") or 0) * 1.05 + (5 << 30)
        self.local.parent.mkdir(parents=True, exist_ok=True)
        existing = describe(self.local)
        if self.local.exists() and existing is None:
            self.log(f"{self.local} exists but is not a Parc engine workspace; leaving it untouched")
            return False
        if existing is not None and not self.operation_idle(self.local):
            self.log(f"{self.local} is in use by another engine operation")
            return False
        aside = None
        if existing is not None:
            if shutil.disk_usage(self.local.parent).free >= need:
                aside = self.local.with_name(self.local.name + ".replaced-" + time.strftime("%Y%m%dT%H%M%S"))
                self.local.rename(aside)
            else:
                self.log(f"Removing the outdated engine workspace at {self.local} to make room")
                shutil.rmtree(self.local)
        if shutil.disk_usage(self.local.parent).free < need:
            if aside is not None:
                aside.rename(self.local)
            self.log(f"Not enough free space to unpack the NAS snapshot ({need / (1 << 30):.0f} GB needed)")
            return False
        handle = self.locked(exclusive=False)
        try:
            self.log(f"Unpacking the NAS snapshot into {self.local}")
            self.engine_tool("restore", "--kind", "workspace", "--lock", str(self.current / "pin.json"),
                             "--cache", str(self.current), "--destination", str(self.local))
        except (StorageError, subprocess.TimeoutExpired):
            if aside is not None and not self.local.exists():
                aside.rename(self.local)
            raise
        finally:
            handle.close()
        if aside is not None:
            shutil.rmtree(aside, ignore_errors=True)
        return True

    def pending_handoff(self, snapshot: dict | None) -> dict | None:
        handoff = (snapshot or {}).get("handoff")
        if not isinstance(handoff, dict) or handoff.get("from_host") == self.host or handoff.get("taken_by"):
            return None
        return handoff

    def mark_handoff_taken(self) -> None:
        handle = self.locked(exclusive=True)
        try:
            metadata = read_json(self.current / "metadata.json")
            if metadata and isinstance(metadata.get("handoff"), dict):
                metadata["handoff"].update(taken_by=self.host, taken_utc=now())
                write_json(self.current / "metadata.json", metadata)
        finally:
            handle.close()

    def resolve(self, prefer: str | None = None, take_over: bool = False) -> dict:
        if take_over:
            prefer = "image"
        wanted = target(self.repo)
        local = describe(self.local)
        if prefer == "local":
            return self.choice(self.local, "local", "requested")
        current = prefer is None and matches(local, wanted)
        if not mount_share(self.config, 15 if current else 90):
            if prefer is not None:
                raise StorageError("the NAS is not reachable")
            return self.choice(self.local, "local", "this Mac's workspace already matches the current engine" if current
                               else "the NAS is not reachable")
        snapshot = self.snapshot()
        handoff = self.pending_handoff(snapshot)
        if (prefer is None and handoff is not None and rank(snapshot, wanted) is not None
                and (rank(local, wanted) is None or rank(snapshot, wanted) >= rank(local, wanted))):
            self.log(f"Taking the unfinished build handed off from {handoff.get('from_host')}")
            prefer = "snapshot"
        elif current:
            return self.choice(self.local, "local", "this Mac's workspace already matches the current engine")
        if prefer in (None, "image") and self.bundle.is_dir():
            if self.attach(take_over):
                image = describe(self.image_workspace)
                rate = self.speed()
                fast = rate is not None and rate >= float(self.config["min_image_mb_per_second"])
                if prefer == "image" and rank(image, wanted) is not None:
                    return self.choice(self.image_workspace, "image", "requested", attached=True)
                if fast and newer(image, local, wanted):
                    return self.choice(self.image_workspace, "image",
                                       f"the NAS disk image is ahead of this Mac and the link reads {rate:.0f} MB/s",
                                       attached=True)
                self.detach()
                if rank(image, wanted) is None:
                    reason = "its workspace is for a different engine"
                elif not newer(image, local, wanted):
                    reason = "this Mac's workspace is at least as new"
                else:
                    reason = f"the link reads {rate or 0:.0f} MB/s"
                self.log(f"Not building inside the NAS disk image: {reason}")
            else:
                self.log("The NAS disk image is in use on another Mac")
        if prefer == "image":
            raise StorageError("the NAS disk image is unavailable or holds a different engine")
        if (prefer == "snapshot" and rank(snapshot, wanted) is not None) or (prefer is None and newer(snapshot, local, wanted)):
            try:
                if self.restore(snapshot):
                    if handoff is not None:
                        self.mark_handoff_taken()
                    return self.choice(self.local, "restored", "unpacked the NAS snapshot onto this Mac")
            except (StorageError, subprocess.TimeoutExpired) as error:
                if prefer is not None:
                    raise
                self.log(f"Unpacking the NAS snapshot failed: {error}")
        if prefer == "snapshot":
            raise StorageError("the NAS snapshot is unavailable, holds a different engine or could not be unpacked")
        return self.choice(self.local, "local", "no newer NAS copy applies")

    def choice(self, workspace: Path, mode: str, reason: str, attached: bool = False) -> dict:
        self.log(f"Engine workspace: {workspace} ({mode}: {reason})")
        return {"workspace": str(workspace), "mode": mode, "reason": reason, "attached": attached}

    def unfinished_release(self) -> dict | None:
        state = read_json(self.repo / "build/releases/current.json")
        return state if state and state.get("status") not in TERMINAL else None

    def releasable(self, workspace: Path) -> dict | None:
        release = self.unfinished_release()
        if release is None or Path(release.get("workspace", "")).resolve() != workspace.resolve():
            return None
        if "engine" in release.get("completed", []):
            raise StorageError("this release already finished its engine; finish it on this Mac")
        pid = release.get("pid")
        if release.get("status") == "running" and pid:
            try:
                os.kill(pid, 0)
                raise StorageError("stop the release first; its process is still running")
            except ProcessLookupError:
                pass
        return release

    def hand_off_release(self, release: dict) -> None:
        run_dir = Path(release["run"])
        root = self.share / "handoff"
        root.mkdir(exist_ok=True)
        staging = root / (".new-" + release["id"])
        shutil.rmtree(staging, ignore_errors=True)
        shutil.copytree(run_dir, staging / "run", symlinks=True)
        write_json(staging / "handoff.json", {"release_id": release["id"], "from_host": self.host,
                                              "from_root": str(self.repo), "from_home": str(Path.home()),
                                              "created_utc": now()})
        current = root / "current"
        if current.exists():
            shutil.rmtree(current)
        staging.rename(current)
        state = dict(release, status="handed-off", handed_off_utc=now(), updated_utc=now())
        write_json(self.repo / "build/releases/current.json", state)
        write_json(run_dir / "state.json", state)
        self.log(f"Handed release {release['id']} off; run the release script on the other Mac to continue it")

    def take_release(self) -> dict | None:
        if self.unfinished_release() is not None or not mount_share(self.config, 15):
            return None
        info_path = self.share / "handoff/current/handoff.json"
        info = read_json(info_path)
        if info is None or info.get("from_host") == self.host or info.get("taken_by"):
            return None
        source_run = self.share / "handoff/current/run"
        state = read_json(source_run / "state.json")
        if state is None or not state.get("id"):
            raise StorageError("the handed-off release is incomplete")
        run_dir = self.repo / "build/releases" / state["id"]
        if run_dir.exists():
            raise StorageError(f"{run_dir} already exists on this Mac")
        self.log(f"Taking over release {state['id']} handed off from {info.get('from_host')}")
        run(["git", "fetch", "origin", "main"], 300, cwd=self.repo)
        choice = self.resolve("snapshot")
        shutil.copytree(source_run, run_dir, symlinks=True)
        state = relocate(state, [(info["from_root"], str(self.repo)), (info["from_home"], str(Path.home()))])
        for key in ("pid", "command_pid", "command", "command_started_utc", "interrupted_process_group",
                    "interrupted_inputs_replaced", "storage_upload", "storage_result", "storage_error", "handed_off_utc"):
            state.pop(key, None)
        state.update(run=str(run_dir), workspace=choice["workspace"], storage_mode="restored", status="stopped",
                     handed_off_from=info.get("from_host"), updated_utc=now())
        write_json(run_dir / "state.json", state)
        write_json(self.repo / "build/releases/current.json", state)
        info.update(taken_by=self.host, taken_utc=now())
        write_json(info_path, info)
        return state

    def publish(self, workspace: Path, handoff: bool = False) -> dict:
        found = describe(workspace)
        if found is None:
            raise StorageError(f"{workspace} is not a Parc engine workspace")
        release = self.releasable(workspace) if handoff else None
        if not mount_share(self.config):
            raise StorageError("the NAS is not reachable")
        current = self.snapshot()
        same = ("lock_sha256", "overlay_identity", "source_fingerprint", "receipt_sha256", "shipping_receipt_sha256")
        marker = {"from_host": self.host, "created_utc": now()} if handoff else None
        if current is not None and all(current.get(key) == found.get(key) for key in same):
            if marker is not None:
                handle = self.locked(exclusive=True)
                try:
                    write_json(self.current / "metadata.json", {**current, "handoff": marker})
                finally:
                    handle.close()
                if release is not None:
                    self.hand_off_release(release)
                return {"published": False, "reason": "already current", "handoff": True}
            self.log("The NAS snapshot already holds this engine")
            return {"published": False, "reason": "already current"}
        handle = self.locked(exclusive=True)
        try:
            for leftover in [*self.snapshots.glob(".new-*"), *self.snapshots.glob(".old-*")]:
                self.log(f"Removing an interrupted upload, {leftover.name}")
                shutil.rmtree(leftover, ignore_errors=True)
            staging = self.snapshots / (".new-" + time.strftime("%Y%m%dT%H%M%S"))
            staging.mkdir()
            try:
                self.log(f"Packing {workspace} into the NAS snapshot")
                result = json.loads(self.engine_tool("create-workspace", "--workspace", str(workspace),
                                                     "--output", str(staging), "--name", SNAPSHOT_NAME))
                manifest = staging / (SNAPSHOT_NAME + ".manifest.json")
                pin = {"schema_version": 1, "target": "mac-arm64", "repository": "etsenake/parc",
                       "release": "nas-engine-snapshot", "source_revision": "",
                       "artifacts": {"workspace": {"manifest": manifest.name, "manifest_sha256": sha(manifest),
                                                   "metadata_sha256": result["metadata_sha256"]}}}
                write_json(staging / "pin.json", pin)
                total = 0
                with (staging / (SNAPSHOT_NAME + ".inventory.jsonl")).open() as inventory:
                    for line in inventory:
                        total += json.loads(line).get("size", 0)
                write_json(staging / "metadata.json", {**found, "workspace": str(workspace), "workspace_bytes": total,
                                                       "host": self.host, "created_utc": now(),
                                                       **({"handoff": marker} if marker else {})})
            except BaseException:
                shutil.rmtree(staging, ignore_errors=True)
                raise
            retired = None
            if self.current.exists():
                retired = self.snapshots / (".old-" + time.strftime("%Y%m%dT%H%M%S"))
                self.current.rename(retired)
            staging.rename(self.current)
            if retired is not None:
                shutil.rmtree(retired, ignore_errors=True)
        finally:
            handle.close()
        self.log("The NAS snapshot now holds this engine")
        if release is not None:
            self.hand_off_release(release)
        return {"published": True, **({"handoff": True} if handoff else {})}

    def last_release_workspace(self) -> Path:
        latest = read_json(self.repo / "build/releases/latest.json")
        state = read_json(Path(latest["run"]) / "state.json") if latest and latest.get("run") else None
        if not state or not state.get("workspace"):
            raise StorageError("No finished release records an engine workspace; pass --workspace")
        return Path(state["workspace"])

    def publish_from(self, workspace: Path, handoff: bool = False) -> dict:
        opened = False
        if self.volume in workspace.parents and not mounted(str(self.volume)):
            if not mount_share(self.config) or not self.attach():
                raise StorageError("the NAS disk image holding that workspace is unreachable or in use on another Mac")
            opened = True
        try:
            return self.publish(workspace, handoff)
        finally:
            if opened:
                self.detach()

    def status(self) -> dict:
        reachable = mount_share(self.config)
        return {"settings": str(config_path()), "local": describe(self.local), "share_reachable": reachable,
                "snapshot": self.snapshot() if reachable else None,
                "image_attached_here": mounted(str(self.volume)),
                "image_holder": read_json(self.holder) if reachable else None,
                "target": target(self.repo)}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("resolve", "workspace", "publish", "take-handoff", "detach", "status"))
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--result", type=Path)
    parser.add_argument("--from", dest="prefer", choices=("local", "image", "snapshot"),
                        help="Take this copy for resolve/workspace, for example when handing an unfinished build to this Mac")
    parser.add_argument("--take-over", action="store_true",
                        help="Open the disk image even though another Mac's record says it has it, then check and repair it")
    parser.add_argument("--handoff", action="store_true",
                        help="Publish an unfinished build (and its stopped release) for another Mac to continue")
    args = parser.parse_args(argv)
    try:
        config = load_config()
        if config is None:
            raise StorageError(f"No engine storage settings at {config_path()}")
        store = Store(config, args.repo.resolve())
        if args.command in ("resolve", "workspace"):
            choice = store.resolve(args.prefer, args.take_over)
            print(json.dumps(choice) if args.command == "resolve" else choice["workspace"])
        elif args.command == "take-handoff":
            taken = store.take_release()
            print(json.dumps({"release": taken["id"], "workspace": taken["workspace"]} if taken else
                             {"release": None, "reason": "no handed-off release for this Mac"}))
        elif args.command == "publish":
            pending = store.unfinished_release() if args.handoff else None
            if args.workspace:
                workspace = args.workspace.resolve()
            elif pending and pending.get("workspace"):
                workspace = Path(pending["workspace"])
            else:
                workspace = store.last_release_workspace()
            outcome = store.publish_from(workspace, args.handoff)
            if args.result:
                write_json(args.result, outcome)
            print(json.dumps(outcome))
        elif args.command == "detach":
            return 0 if store.detach() else 1
        else:
            print(json.dumps(store.status(), indent=2))
        return 0
    except (StorageError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        if args.command == "publish" and args.result:
            write_json(args.result, {"published": None, "error": str(error)})
        print(f"[{now()}] engine-storage: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
