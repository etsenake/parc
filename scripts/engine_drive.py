#!/usr/bin/env python3
"""Keep Parc's engine on an external drive and build it in place at the drive's /Volumes path."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
RECEIPT = ".parc-engine-source.json"
SYSTEM_ENTRIES = {".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems", ".DocumentRevisions-V100",
                  ".metadata_never_index", ".DS_Store", ".com.apple.timemachine.donotpresent"}


class DriveError(RuntimeError):
    pass


def log(message: str) -> None:
    print(f"engine-drive: {message}", file=sys.stderr, flush=True)


def run(args: list, timeout: float = 120) -> subprocess.CompletedProcess:
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)


def workspace_tools(repo: Path):
    spec = importlib.util.spec_from_file_location("engine_workspace", repo / "scripts/engine_workspace.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def linked_engine(repo: Path) -> Path | None:
    link = repo / "work/engine"
    if link.is_symlink():
        return Path(os.path.realpath(link))
    return link.resolve() if link.is_dir() else None


def volume_info(target: str) -> dict:
    result = run(["/usr/sbin/diskutil", "info", "-plist", target])
    if result.returncode != 0:
        raise DriveError(f"no disk named {target}: {(result.stderr or result.stdout).strip()}")
    info = plistlib.loads(result.stdout.encode())
    if info.get("FilesystemType") != "apfs":
        raise DriveError(f"{target} is {info.get('FilesystemType') or 'not formatted'}; erase it as APFS first")
    if info.get("Internal"):
        raise DriveError(f"{target} is an internal disk")
    return info


def idle(spot: Path) -> bool:
    guard = spot / ".parc-operation.lock"
    if not guard.exists():
        return True
    with guard.open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except BlockingIOError:
            return False


def holds_engine(root: Path) -> bool:
    return (root / RECEIPT).is_file()


def registered_at(root: Path) -> str | None:
    try:
        return json.loads((root / RECEIPT).read_text()).get("workspace")
    except (OSError, ValueError):
        return None


def empty(root: Path) -> bool:
    return all(entry.name in SYSTEM_ENTRIES for entry in root.iterdir())


def copy_engine(source: Path, mount: Path) -> None:
    total = int(run(["/usr/bin/du", "-sk", source], 3600).stdout.split()[0]) * 1024
    began, done = time.monotonic(), threading.Event()

    def report():
        while not done.wait(30):
            used = shutil.disk_usage(mount).used
            log(f"Copied about {used / 2**30:.1f} of {total / 2**30:.1f} GB "
                f"({(time.monotonic() - began) / 60:.0f} min)")

    threading.Thread(target=report, daemon=True).start()
    log(f"Copying the engine from {source} onto the drive, keeping every file date")
    try:
        result = run(["/usr/bin/ditto", source, mount], 6 * 3600)
    finally:
        done.set()
    if result.returncode != 0:
        raise DriveError("copying the engine onto the drive failed: " + (result.stderr or result.stdout).strip()[-400:])


def point_link(repo: Path, mount: Path) -> None:
    link = repo / "work/engine"
    if link.is_symlink():
        if Path(os.path.realpath(link)) == mount:
            return
        link.unlink()
    elif link.exists():
        raise DriveError(f"{link} is a real folder; move it away so the link can name the drive")
    link.parent.mkdir(parents=True, exist_ok=True)
    link.symlink_to(mount)
    log(f"The checkout's engine link now names {mount}")


def register(source: Path, mount: Path, repo: Path, lock: Path) -> None:
    if not holds_engine(source) or registered_at(source) != str(source):
        raise DriveError(f"the drive's engine was registered at {source}, which no longer holds that engine")
    if not idle(source) or not idle(mount):
        raise DriveError("an engine operation is running; let it finish first")
    tools = workspace_tools(repo)
    log(f"Registering the drive's engine at {mount}; its next build regenerates and recompiles")
    try:
        tools.adopt_local_clone(source, mount, repo, lock, moved=True)
    except tools.Refusal as error:
        raise DriveError(f"the drive's engine could not be registered: {error}") from error


def prepare(volume: str, repo: Path, source: Path | None, lock: Path) -> dict:
    info = volume_info(volume if volume.startswith("/") else f"/Volumes/{volume}")
    mount = Path(info.get("MountPoint") or "")
    if not mount.is_dir():
        raise DriveError(f"mount the drive first so its contents can be checked ({info['DeviceIdentifier']})")
    source = source or linked_engine(repo)
    if holds_engine(mount):
        recorded = registered_at(mount)
        if recorded == str(mount):
            state = "already in place"
        else:
            source = Path(recorded or "")
            register(source, mount, repo, lock)
            state = "registered"
    elif empty(mount):
        if source is None or not holds_engine(source):
            raise DriveError(f"{source or 'this checkout'} has no engine to copy and the drive is empty")
        if not idle(source):
            raise DriveError(f"an engine operation is using {source}; let it finish first")
        copy_engine(source, mount)
        register(source, mount, repo, lock)
        state = "copied"
    else:
        raise DriveError(f"{mount} holds other files and no Parc engine; use an empty drive")
    (mount / ".metadata_never_index").touch()
    point_link(repo, mount)
    return {"engine": str(mount), "drive": info["DeviceIdentifier"], "state": state,
            "previous_engine": str(source) if source and source != mount else None}


def status(repo: Path, override: Path | None) -> dict:
    spot = override or linked_engine(repo)
    if spot is None:
        raise DriveError(f"{repo / 'work/engine'} does not name an engine folder; pass --engine")
    info = run(["/usr/sbin/diskutil", "info", "-plist", spot]) if spot.exists() else None
    details = plistlib.loads(info.stdout.encode()) if info is not None and info.returncode == 0 else {}
    on_drive = details.get("Internal") is False
    return {"engine": str(spot), "on_drive": on_drive, "drive": details.get("VolumeName") if on_drive else None,
            "engine_present": holds_engine(spot), "registered": registered_at(spot) == str(spot),
            "idle": idle(spot) if spot.exists() else True}


def eject(repo: Path, override: Path | None) -> None:
    spot = override or linked_engine(repo)
    if spot is None or not status(repo, spot)["on_drive"]:
        raise DriveError(f"{spot} is not on an external drive")
    if not idle(spot):
        raise DriveError("an engine operation is using the drive; let it finish before unplugging")
    result = run(["/usr/sbin/diskutil", "eject", spot], 300)
    if result.returncode != 0:
        raise DriveError("the drive could not be ejected: " + (result.stderr or result.stdout).strip())
    log("Ejected; the drive can be unplugged")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "status", "eject"))
    parser.add_argument("--volume", help="The drive's name in Finder, for prepare")
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--engine", type=Path, help="Engine folder to copy or inspect, instead of the work/engine link")
    parser.add_argument("--lock", type=Path, help="Source lock the engine was built with (default: the checkout's)")
    args = parser.parse_args(argv)
    try:
        repo = args.repo.resolve()
        if args.command == "prepare":
            if not args.volume:
                parser.error("prepare needs --volume")
            lock = (args.lock or repo / "Engine/source-lock.json").absolute()
            print(json.dumps(prepare(args.volume, repo, args.engine, lock)))
        elif args.command == "status":
            print(json.dumps(status(repo, args.engine), indent=2))
        else:
            eject(repo, args.engine)
        return 0
    except (DriveError, OSError, subprocess.TimeoutExpired, KeyError, ValueError) as error:
        log(str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
