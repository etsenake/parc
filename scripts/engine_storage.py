#!/usr/bin/env python3
"""Choose the engine workspace for a build (this Mac, a shared NAS disk image or a NAS snapshot) and keep the NAS copy current."""
from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import datetime
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
RECEIPT = ".parc-engine-source.json"
SHIPPING = ".parc-shipping-build.json"
OPERATION_LOCK = ".parc-operation.lock"
SNAPSHOT_NAME = "engine-workspace"
TERMINAL = {"complete", "abandoned", "nothing-to-release", "handed-off"}
XCODE_ROOTS = ("Platforms/MacOSX.platform", "Toolchains/XcodeDefault.xctoolchain", "usr")
XCODE_RECORD = "xcode-files.json.gz"
SNAPSHOT_IDENTITY = ("created_utc", "host", "workspace", "lock_sha256", "overlay_identity")
ALIGN_HELPER = """import json, os, sys
for path, mtime in json.load(open(sys.argv[1])):
    info = os.stat(path)
    try:
        os.utime(path, ns=(info.st_atime_ns, mtime))
    except PermissionError as error:
        open(sys.argv[2], "w").write(str(error))
        sys.exit(3)
"""
DEFAULTS = {
    "mount_point": "/Volumes/parc-engine-nfs",
    "image": "parc-engine.sparsebundle",
    "volume": "ParcEngine",
    "image_workspace": "ParcBuild/engine",
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
        if config.get(key):
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


class AttributeRequest(ctypes.Structure):
    _fields_ = [("bitmapcount", ctypes.c_ushort), ("reserved", ctypes.c_uint16), ("commonattr", ctypes.c_uint32),
                ("volattr", ctypes.c_uint32), ("dirattr", ctypes.c_uint32), ("fileattr", ctypes.c_uint32),
                ("forkattr", ctypes.c_uint32)]


LIBC = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
RETURNED_ATTRIBUTES = 0x80000000
PRIVATE_SIZE = 0x00000008
NO_FOLLOW_EXTENDED = 0x00000001 | 0x00000020


def private_bytes(path: str, allocated: int) -> int:
    request = AttributeRequest(5, 0, RETURNED_ATTRIBUTES, 0, 0, 0, PRIVATE_SIZE)
    answer = ctypes.create_string_buffer(64)
    if LIBC.getattrlist(os.fsencode(path), ctypes.byref(request), answer, len(answer), NO_FOLLOW_EXTENDED) != 0:
        return 0
    if not struct.unpack_from("5I", answer, 4)[4] & PRIVATE_SIZE:
        return 0
    return min(allocated, struct.unpack_from("q", answer, 24)[0])


def reclaimable_bytes(folder: Path) -> int:
    total = 0
    for base, _, names in os.walk(folder):
        for name in names:
            path = os.path.join(base, name)
            try:
                info = os.lstat(path)
            except OSError:
                continue
            if info.st_nlink == 1 and stat.S_ISREG(info.st_mode):
                total += private_bytes(path, info.st_blocks * 512)
    return total


def available_bytes(folder: Path) -> int:
    key = "NSURLVolumeAvailableCapacityForImportantUsageKey"
    script = (f'ObjC.import("Foundation"); const u = $.NSURL.fileURLWithPath({json.dumps(str(folder))}); '
              f'const v = u.resourceValuesForKeysError($([{json.dumps(key)}]), null); v.objectForKey({json.dumps(key)}).js')
    try:
        result = run(["/usr/bin/osascript", "-l", "JavaScript", "-e", script], 30)
        if result.returncode == 0 and result.stdout.strip().isdigit():
            return max(int(result.stdout.strip()), shutil.disk_usage(folder).free)
    except subprocess.TimeoutExpired:
        pass
    return shutil.disk_usage(folder).free


def developer_dir() -> Path | None:
    try:
        result = run(["/usr/bin/xcode-select", "-p"], 30)
    except subprocess.TimeoutExpired:
        return None
    path = Path(result.stdout.strip())
    return path if result.returncode == 0 and path.is_dir() else None


def xcode_identity(developer: Path) -> dict:
    info = plistlib.loads((developer.parent / "version.plist").read_bytes())
    return {"version": info.get("CFBundleShortVersionString"), "build": info.get("ProductBuildVersion")}


def xcode_record(developer: Path) -> dict:
    files = []
    for root in XCODE_ROOTS:
        for base, _, names in os.walk(developer / root):
            for name in names:
                path = Path(base) / name
                info = os.lstat(path)
                if stat.S_ISREG(info.st_mode):
                    files.append([str(path.relative_to(developer)), info.st_size, info.st_mtime_ns, sha(path)])
    return {"schema_version": 1, "xcode": xcode_identity(developer), "files": files}


def write_record(path: Path, record: dict) -> None:
    temporary = path.with_name("." + path.name + ".tmp")
    with gzip.open(temporary, "wt") as stream:
        json.dump(record, stream)
    os.replace(temporary, path)


def read_record(path: Path) -> dict | None:
    try:
        with gzip.open(path, "rt") as stream:
            value = json.load(stream)
    except (OSError, ValueError, EOFError):
        return None
    return value if isinstance(value, dict) and value.get("schema_version") == 1 else None


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
        self.link = self.repo / "work/engine"
        if config.get("local_workspace"):
            self.local = Path(config["local_workspace"])
        elif self.link.is_symlink():
            self.local = (self.link.parent / os.readlink(self.link)).resolve()
        else:
            self.local = self.link
        self.snapshots = self.share / "snapshots"
        self.current = self.snapshots / "current"
        self.holder = self.share / (config["image"] + ".holder.json")
        self.host = socket.gethostname()
        self.progress_seconds = 30

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

    def engine_tool(self, *args: str, timeout: float = 6 * 3600, progress=None) -> str:
        command = [sys.executable, str(self.repo / "scripts/engine-artifacts.py"), *args]
        child = subprocess.Popen(command, cwd=self.repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        output, errors = [], []

        def pump(stream, sink, echo):
            for line in stream:
                sink.append(line)
                if echo and line.strip():
                    self.log(line.rstrip())

        pumps = [threading.Thread(target=pump, args=(child.stdout, output, False), daemon=True),
                 threading.Thread(target=pump, args=(child.stderr, errors, True), daemon=True)]
        for thread in pumps:
            thread.start()
        deadline = time.monotonic() + timeout
        while True:
            try:
                child.wait(timeout=self.progress_seconds)
                break
            except subprocess.TimeoutExpired:
                if time.monotonic() > deadline:
                    child.kill()
                    child.wait()
                    raise
                if progress is not None:
                    progress()
        for thread in pumps:
            thread.join()
        child.stdout.close()
        child.stderr.close()
        if child.returncode != 0:
            raise StorageError(("".join(errors) or "".join(output)).strip()[-2000:] or "engine artifact operation failed")
        return "".join(output)

    def unpack_progress(self, folder: Path, total: int):
        start, began, phase = shutil.disk_usage(folder).used, time.monotonic(), {"verifying": False}

        def report():
            done = max(0, shutil.disk_usage(folder).used - start)
            minutes = (time.monotonic() - began) / 60
            if phase["verifying"]:
                self.log(f"Still verifying the unpacked workspace ({minutes:.0f} min elapsed)")
            elif total and done >= total * 0.99:
                phase["verifying"] = True
                self.log("Unpacked; verifying every file and adopting the workspace at this path")
            elif total:
                self.log(f"Unpacked {done / 2**30:.1f} of {total / 2**30:.1f} GB ({done / total:.0%}, {minutes:.0f} min)")
            else:
                self.log(f"Unpacked {done / 2**30:.1f} GB ({minutes:.0f} min)")

        return report

    def pack_progress(self, staging: Path, estimate: int):
        reader = {"path": None, "offset": 0, "bytes": 0, "began": time.monotonic(), "checking": False}

        def report():
            if reader["path"] is None:
                found = sorted(staging.glob(f".{SNAPSHOT_NAME}-*/{SNAPSHOT_NAME}.inventory.jsonl"))
                reader["path"] = found[0] if found else None
            minutes = (time.monotonic() - reader["began"]) / 60
            if reader["path"] is None or not reader["path"].exists():
                if reader["bytes"] and not reader["checking"]:
                    reader["checking"] = True
                    self.log("Packed; confirming the workspace did not change while it was read")
                elif not reader["bytes"]:
                    self.log(f"Checking the workspace before packing ({minutes:.0f} min)")
                return
            with reader["path"].open("rb") as stream:
                stream.seek(reader["offset"])
                for line in stream:
                    if not line.endswith(b"\n"):
                        break
                    reader["offset"] += len(line)
                    reader["bytes"] += json.loads(line).get("size", 0)
            share = f", about {reader['bytes'] / estimate:.0%}" if estimate else ""
            self.log(f"Packed {reader['bytes'] / 2**30:.1f} GB of the workspace into the NAS snapshot ({minutes:.0f} min{share})")

        return report

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

    def make_folder(self, folder: Path) -> None:
        if folder.is_dir():
            return
        missing = [part for part in [folder, *folder.parents] if not part.exists()]
        try:
            folder.mkdir(parents=True)
            return
        except PermissionError:
            pass
        user = os.environ.get("USER") or str(os.getuid())
        script = (f"/bin/mkdir -p {shlex.quote(str(folder))} && /usr/sbin/chown {shlex.quote(user)}:staff "
                  + " ".join(shlex.quote(str(part)) for part in missing))
        self.log(f"Creating {folder} needs administrator rights once on this Mac")
        if not (self.privileged(script) and folder.is_dir()):
            raise StorageError(f"could not create {folder}; run once on this Mac: sudo /bin/sh -c '{script}'")

    def privileged(self, script: str, ran=lambda: False) -> bool:
        attempts = [["/usr/bin/sudo", "-n", "/bin/sh", "-c", script]]
        if sys.stdin.isatty():
            attempts.append(["/usr/bin/sudo", "/bin/sh", "-c", script])
        attempts.append(["/usr/bin/osascript", "-e", f'do shell script "{script}" with administrator privileges'])
        for command in attempts:
            try:
                if run(command, 1800).returncode == 0:
                    return True
            except subprocess.TimeoutExpired:
                pass
            if ran():
                return False
        return False

    def xcode_plan(self, record: dict) -> tuple[list, dict] | None:
        developer = developer_dir()
        if developer is None:
            self.log("No Xcode is selected on this Mac; Xcode timestamps were not aligned")
            return None
        if xcode_identity(developer) != record.get("xcode"):
            self.log(f"This Mac's Xcode {xcode_identity(developer)} differs from the engine's {record.get('xcode')}; "
                     "only files with identical contents are aligned and steps that use the rest will rebuild")
        plan, counts = [], {"aligned": 0, "changed": 0, "missing": 0}
        for relative, size, mtime, digest in record.get("files", []):
            path = developer / relative
            try:
                info = os.lstat(path)
            except OSError:
                counts["missing"] += 1
                continue
            if not stat.S_ISREG(info.st_mode) or info.st_size != size:
                counts["changed"] += 1
            elif info.st_mtime_ns == mtime:
                counts["aligned"] += 1
            elif sha(path) == digest:
                plan.append([str(path), mtime])
            else:
                counts["changed"] += 1
        return plan, counts

    def align_xcode(self, record: dict | None) -> dict | None:
        if not record:
            return None
        result = self.xcode_plan(record)
        if result is None:
            return None
        plan, counts = result
        if plan:
            self.log(f"Matching {len(plan)} Xcode file timestamps to the engine's build Mac; "
                     "this needs administrator rights")
            with tempfile.TemporaryDirectory(prefix="parc-xcode-align-") as folder:
                helper, listing, refusal = (Path(folder) / name for name in ("align.py", "plan.json", "refusal.txt"))
                helper.write_text(ALIGN_HELPER)
                listing.write_text(json.dumps(plan))
                os.chmod(folder, 0o755)
                granted = self.privileged(f"{shlex.quote(sys.executable)} {shlex.quote(str(helper))} "
                                          f"{shlex.quote(str(listing))} {shlex.quote(str(refusal))}",
                                          ran=refusal.is_file)
                if refusal.is_file():
                    raise StorageError(f"macOS refused to change Xcode's files ({refusal.read_text()}); turn on "
                                       "System Settings > Privacy & Security > App Management for the app running "
                                       "this script, such as Terminal or T3 Code")
                if not granted:
                    raise StorageError("could not align Xcode file timestamps; administrator rights were not granted")
            moved = sum(1 for path, mtime in plan if os.lstat(path).st_mtime_ns == mtime)
            counts["aligned"] += moved
            counts["unmoved"] = len(plan) - moved
        self.log(f"Xcode timestamps: {counts['aligned']} match the engine's build Mac, "
                 f"{counts['changed']} differ in content, {counts['missing']} missing")
        return counts

    def record_xcode(self, *targets: Path) -> dict | None:
        developer = developer_dir()
        if developer is None:
            self.log("No Xcode is selected on this Mac; Xcode timestamps were not recorded")
            return None
        try:
            record = xcode_record(developer)
        except (OSError, ValueError) as error:
            self.log(f"Xcode timestamps were not recorded ({error})")
            return None
        for target in targets:
            write_record(target, record)
        self.log(f"Recorded {len(record['files'])} Xcode file timestamps for Xcode {record['xcode']}")
        return record

    def link_repo(self, destination: Path) -> None:
        if destination == self.link:
            return
        if self.link.exists() and not self.link.is_symlink():
            self.log(f"{self.link} is a real folder, so it was not replaced with a link to {destination}")
            return
        self.link.parent.mkdir(parents=True, exist_ok=True)
        if self.link.is_symlink():
            self.link.unlink()
        self.link.symlink_to(destination)
        self.log(f"{self.link} now points at {destination}")

    def restore(self, metadata: dict) -> bool:
        handle = self.locked(exclusive=False)
        try:
            current = self.snapshot()
            if current is None or any(current.get(key) != metadata.get(key) for key in SNAPSHOT_IDENTITY):
                raise StorageError("the NAS snapshot changed while this Mac was choosing it; run again")
            return self.restore_locked(current)
        finally:
            handle.close()

    def verify_snapshot(self) -> None:
        began = time.monotonic()
        self.log("Checking every byte of the NAS snapshot before removing an engine copy to make room")
        self.engine_tool("verify", "--kind", "workspace", "--lock", str(self.current / "pin.json"),
                         "--cache", str(self.current),
                         progress=lambda: self.log(f"Still checking the NAS snapshot "
                                                   f"({(time.monotonic() - began) / 60:.0f} min elapsed)"))

    def restore_locked(self, metadata: dict) -> bool:
        destination = Path(metadata.get("workspace") or self.local)
        need = int(metadata.get("workspace_bytes") or 0) * 1.05 + (5 << 30)
        self.make_folder(destination.parent)
        existing = describe(destination)
        if destination.exists() and existing is None:
            self.log(f"{destination} exists but is not a Parc engine workspace; leaving it untouched")
            return False
        if existing is not None and not self.operation_idle(destination):
            self.log(f"{destination} is in use by another engine operation")
            return False
        previous = self.local if self.local != destination and describe(self.local) is not None else None
        if previous is not None and not self.operation_idle(previous):
            previous = None
        free = available_bytes(destination.parent)
        if free < need:
            device = os.stat(destination.parent).st_dev
            removable = [path for path in (destination if existing is not None else None, previous)
                         if path is not None and os.stat(path).st_dev == device]
            reclaimable = sum(reclaimable_bytes(path) for path in removable)
            if free + reclaimable < need:
                self.log(f"Not enough free space to unpack the NAS snapshot ({need / (1 << 30):.0f} GB needed, "
                         f"{free / (1 << 30):.0f} GB available, {reclaimable / (1 << 30):.0f} GB that removing older "
                         "engine copies would free); nothing was removed")
                return False
            self.verify_snapshot()
        aside = None
        if existing is not None:
            if free >= need:
                aside = destination.with_name(destination.name + ".replaced-" + time.strftime("%Y%m%dT%H%M%S"))
                destination.rename(aside)
            else:
                self.log(f"Removing the outdated engine workspace at {destination} to make room")
                shutil.rmtree(destination)
        if previous is not None and available_bytes(destination.parent) < need:
            self.log(f"Removing the outdated engine workspace at {previous} to make room")
            shutil.rmtree(previous)
            previous = None
        if available_bytes(destination.parent) < need:
            if aside is not None:
                aside.rename(destination)
            self.log(f"Not enough free space to unpack the NAS snapshot ({need / (1 << 30):.0f} GB needed)")
            return False
        self.align_quietly(read_record(self.current / XCODE_RECORD))
        try:
            self.log(f"Unpacking the NAS snapshot into {destination}, where its engine was last built")
            self.engine_tool("restore", "--kind", "workspace", "--lock", str(self.current / "pin.json"),
                             "--cache", str(self.current), "--destination", str(destination),
                             progress=self.unpack_progress(destination.parent, int(metadata.get("workspace_bytes") or 0)))
        except (StorageError, subprocess.TimeoutExpired):
            if aside is not None and not destination.exists():
                aside.rename(destination)
            raise
        if aside is not None:
            shutil.rmtree(aside, ignore_errors=True)
        if previous is not None and previous.exists():
            self.log(f"Removing the outdated engine workspace at {previous}")
            shutil.rmtree(previous, ignore_errors=True)
        self.link_repo(destination)
        self.local = destination
        return True

    def align_quietly(self, record: dict | None) -> None:
        if record is None:
            self.log("The NAS copy has no Xcode timestamp record; a build may redo work that depends on Xcode")
            return
        try:
            self.align_xcode(record)
        except (StorageError, OSError, subprocess.TimeoutExpired) as error:
            self.log(f"Xcode timestamps were not aligned ({error}); a build may redo work that depends on Xcode")

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
                    self.align_quietly(read_record(self.share / XCODE_RECORD))
                    return self.choice(self.image_workspace, "image", "requested", attached=True)
                if fast and newer(image, local, wanted):
                    self.align_quietly(read_record(self.share / XCODE_RECORD))
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

    def hand_off_release(self, release: dict, marker: dict) -> None:
        run_dir = Path(release["run"])
        root = self.share / "handoff"
        handle = self.locked(exclusive=True)
        try:
            root.mkdir(exist_ok=True)
            staging = root / (".new-" + release["id"])
            shutil.rmtree(staging, ignore_errors=True)
            shutil.copytree(run_dir, staging / "run", symlinks=True)
            write_json(staging / "handoff.json", {"release_id": release["id"], "from_host": self.host,
                                                  "from_root": str(self.repo), "from_home": str(Path.home()),
                                                  "snapshot_created_utc": marker["created_utc"], "created_utc": now()})
            current = root / "current"
            if current.exists():
                shutil.rmtree(current)
            staging.rename(current)
        finally:
            handle.close()
        state = dict(release, status="handed-off", handed_off_utc=now(), updated_utc=now())
        write_json(self.repo / "build/releases/current.json", state)
        write_json(run_dir / "state.json", state)
        self.log(f"Handed release {release['id']} off; run the release script on the other Mac to continue it")

    def take_release(self) -> dict | None:
        if self.unfinished_release() is not None or not mount_share(self.config, 15):
            return None
        info_path = self.share / "handoff/current/handoff.json"
        handle = self.locked(exclusive=True)
        try:
            info = read_json(info_path)
            if info is None or info.get("from_host") == self.host or info.get("taken_by") not in (None, self.host):
                return None
            snapshot = self.snapshot()
            marker = (snapshot or {}).get("handoff") or {}
            if (marker.get("from_host"), marker.get("created_utc")) != (info.get("from_host"),
                                                                       info.get("snapshot_created_utc")):
                raise StorageError("the NAS snapshot no longer holds the handed-off build; hand it off again")
            claim = {"taken_by": self.host, "taken_utc": now()}
            info.update(claim)
            try:
                write_json(info_path, info)
                write_json(self.current / "metadata.json", {**snapshot, "handoff": {**marker, **claim}})
            except BaseException:
                try:
                    self.clear_claim(info)
                except OSError:
                    pass
                raise
        finally:
            handle.close()
        try:
            return self.continue_release(info, snapshot)
        except BaseException:
            self.release_claim(info)
            raise

    def release_claim(self, info: dict) -> None:
        handle = self.locked(exclusive=True)
        try:
            self.clear_claim(info)
        finally:
            handle.close()

    def clear_claim(self, info: dict) -> None:
        identity = (info.get("from_host"), info.get("snapshot_created_utc"), self.host)
        path = self.share / "handoff/current/handoff.json"
        claimed = read_json(path)
        if claimed and (claimed.get("from_host"), claimed.get("snapshot_created_utc"),
                        claimed.get("taken_by")) == identity:
            claimed.pop("taken_by", None)
            claimed.pop("taken_utc", None)
            write_json(path, claimed)
        metadata = read_json(self.current / "metadata.json")
        marker = (metadata or {}).get("handoff")
        if isinstance(marker, dict) and (marker.get("from_host"), marker.get("created_utc"),
                                         marker.get("taken_by")) == identity:
            marker.pop("taken_by", None)
            marker.pop("taken_utc", None)
            write_json(self.current / "metadata.json", metadata)

    def continue_release(self, info: dict, snapshot: dict) -> dict:
        source_run = self.share / "handoff/current/run"
        state = read_json(source_run / "state.json")
        if state is None or not state.get("id"):
            raise StorageError("the handed-off release is incomplete")
        run_dir = self.repo / "build/releases" / state["id"]
        if run_dir.exists():
            raise StorageError(f"{run_dir} already exists on this Mac")
        self.log(f"Taking over release {state['id']} handed off from {info.get('from_host')}")
        run(["git", "fetch", "origin", "main"], 300, cwd=self.repo)
        if rank(snapshot, target(self.repo)) is None:
            raise StorageError("the handed-off build is for a different engine than this checkout")
        if not self.restore(snapshot):
            raise StorageError("the handed-off build could not be unpacked on this Mac")
        staging = run_dir.with_name(".taking-" + run_dir.name)
        shutil.rmtree(staging, ignore_errors=True)
        try:
            shutil.copytree(source_run, staging, symlinks=True)
            state = relocate(state, [(info["from_root"], str(self.repo)), (info["from_home"], str(Path.home()))])
            for key in ("pid", "command_pid", "command", "command_started_utc", "interrupted_process_group",
                        "interrupted_inputs_replaced", "storage_upload", "storage_result", "storage_error",
                        "handed_off_utc"):
                state.pop(key, None)
            state.update(run=str(run_dir), workspace=str(self.local), storage_mode="restored", status="stopped",
                         handed_off_from=info.get("from_host"), updated_utc=now())
            write_json(staging / "state.json", state)
            staging.rename(run_dir)
        except BaseException:
            shutil.rmtree(staging, ignore_errors=True)
            raise
        try:
            write_json(self.repo / "build/releases/current.json", state)
        except BaseException:
            shutil.rmtree(run_dir, ignore_errors=True)
            raise
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
        if marker is None and current is not None and all(current.get(key) == found.get(key) for key in same):
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
                estimate = int((current or {}).get("workspace_bytes") or 0)
                result = json.loads(self.engine_tool("create-workspace", "--workspace", str(workspace),
                                                     "--output", str(staging), "--name", SNAPSHOT_NAME,
                                                     progress=self.pack_progress(staging, estimate)))
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
                xcode = self.record_xcode(staging / XCODE_RECORD)
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
            if xcode is not None:
                write_record(self.share / XCODE_RECORD, xcode)
        finally:
            handle.close()
        self.log("The NAS snapshot now holds this engine")
        if release is not None:
            self.hand_off_release(release, marker)
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

    def record_current(self) -> dict | None:
        if not mount_share(self.config):
            raise StorageError("the NAS is not reachable")
        handle = self.locked(exclusive=True)
        try:
            targets = [self.share / XCODE_RECORD]
            if self.snapshot() is not None:
                targets.append(self.current / XCODE_RECORD)
            return self.record_xcode(*targets)
        finally:
            handle.close()

    def align_current(self) -> dict | None:
        if not mount_share(self.config):
            raise StorageError("the NAS is not reachable")
        record = read_record(self.current / XCODE_RECORD) or read_record(self.share / XCODE_RECORD)
        if record is None:
            raise StorageError("the NAS holds no Xcode timestamp record")
        return self.align_xcode(record)

    def status(self) -> dict:
        reachable = mount_share(self.config)
        return {"settings": str(config_path()), "local": describe(self.local), "share_reachable": reachable,
                "snapshot": self.snapshot() if reachable else None,
                "xcode_record": reachable and (self.current / XCODE_RECORD).is_file(),
                "image_attached_here": mounted(str(self.volume)),
                "image_holder": read_json(self.holder) if reachable else None,
                "target": target(self.repo)}


def metal_toolchain_ready() -> bool:
    try:
        return run(["xcrun", "metal", "--version"], 120).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def setup(share: str, repo: Path, log) -> list[str]:
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    current = read_json(path) or {}
    if current.get("share") not in (None, share):
        log(f"Replacing the NAS address {current['share']} with {share}")
    write_json(path, {**current, "schema_version": 1, "share": share})
    log(f"Saved the NAS settings at {path}")
    store = Store(load_config(path), repo, log=log)
    problems = []
    if not metal_toolchain_ready():
        log("Downloading Apple's Metal toolchain, which the engine build needs")
        subprocess.run(["xcodebuild", "-downloadComponent", "MetalToolchain"])
        if not metal_toolchain_ready():
            problems.append("Apple's Metal toolchain is still missing; run: xcodebuild -downloadComponent MetalToolchain")
    if not mount_share(store.config):
        problems.append(f"The NAS at {share} did not mount; join the network it is on and allow this app's "
                        "Network Volumes prompt, then run setup again")
        return problems
    log(f"The NAS is mounted at {store.share}")
    snapshot = store.snapshot()
    if snapshot is None:
        log("The NAS holds no engine snapshot yet; the first release on any Mac will upload one")
        return problems
    try:
        store.make_folder(Path(snapshot.get("workspace") or store.local).parent)
        if describe(store.local) is None:
            store.align_current()
        else:
            log("This Mac already has an engine workspace, so its Xcode dates were left alone")
    except StorageError as error:
        problems.append(str(error))
    return problems


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("setup", "resolve", "workspace", "publish", "take-handoff", "detach",
                                            "status", "record-xcode", "align-xcode"))
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--share", help="NAS address for setup, for example nfs://nas.local/volume1/parc-engine-nfs")
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--result", type=Path)
    parser.add_argument("--from", dest="prefer", choices=("local", "image", "snapshot"),
                        help="Take this copy for resolve/workspace, for example when handing an unfinished build to this Mac")
    parser.add_argument("--take-over", action="store_true",
                        help="Open the disk image even though another Mac's record says it has it, then check and repair it")
    parser.add_argument("--handoff", action="store_true",
                        help="Publish an unfinished build (and its stopped release) for another Mac to continue")
    args = parser.parse_args(argv)
    if args.command == "setup":
        if not args.share:
            parser.error("setup needs --share")
        problems = setup(args.share, args.repo.resolve(),
                         lambda message: print(f"[{now()}] engine-storage: {message}", file=sys.stderr, flush=True))
        for problem in problems:
            print(f"[{now()}] engine-storage: Still needed: {problem}", file=sys.stderr)
        print(json.dumps({"ready": not problems, "problems": problems}))
        return 0 if not problems else 1
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
        elif args.command == "record-xcode":
            record = store.record_current()
            print(json.dumps({"files": len(record["files"]), "xcode": record["xcode"]} if record else {"files": 0}))
        elif args.command == "align-xcode":
            print(json.dumps(store.align_current()))
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
