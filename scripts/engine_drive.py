#!/usr/bin/env python3
"""Keep Parc's engine on an external drive mounted at the engine's usual folder on every Mac."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shlex
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


def engine_spot(repo: Path, override: Path | None) -> Path:
    if override is not None:
        return override.resolve() if override.exists() else override.absolute()
    link = repo / "work/engine"
    if not link.is_symlink():
        raise DriveError(f"{link} does not point at an engine folder; pass --engine")
    return Path(os.path.realpath(link))


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


def privileged(script: str) -> bool:
    attempts = [["/usr/bin/sudo", "-n", "/bin/sh", "-c", script]]
    if sys.stdin.isatty():
        attempts.append(["/usr/bin/sudo", "/bin/sh", "-c", script])
    attempts.append(["/usr/bin/osascript", "-e", f'do shell script "{script}" with administrator privileges'])
    for command in attempts:
        try:
            if run(command, 600).returncode == 0:
                return True
        except subprocess.TimeoutExpired:
            pass
    return False


def fstab_line(uuid: str, spot: Path) -> str:
    return f"UUID={uuid} {spot} apfs rw"


def fstab_has(uuid: str, spot: Path) -> bool:
    try:
        lines = Path("/etc/fstab").read_text().splitlines()
    except OSError:
        return False
    return fstab_line(uuid, spot) in (line.strip() for line in lines)


def write_fstab(uuid: str, spot: Path) -> None:
    if fstab_has(uuid, spot):
        return
    line = fstab_line(uuid, spot)
    script = f"/usr/bin/printf '%s\\n' {shlex.quote(line)} >> /etc/fstab"
    log("Adding the drive to this Mac's mount settings; this needs administrator rights once")
    if not privileged(script) or not fstab_has(uuid, spot):
        raise DriveError(f"could not add the mount setting; run once: sudo sh -c \"echo '{line}' >> /etc/fstab\"")


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


def mounted_at(spot: Path, device: str) -> bool:
    info = run(["/usr/sbin/diskutil", "info", "-plist", device])
    return info.returncode == 0 and plistlib.loads(info.stdout.encode()).get("MountPoint") == str(spot)


def prepare(volume: str, repo: Path, override: Path | None, use_fstab: bool = True) -> dict:
    spot = engine_spot(repo, override)
    info = volume_info(volume if volume.startswith("/") else f"/Volumes/{volume}")
    device, uuid, mount = info["DeviceIdentifier"], info["VolumeUUID"], Path(info.get("MountPoint") or "")
    if mount == spot:
        if use_fstab:
            write_fstab(uuid, spot)
        return {"engine": str(spot), "drive": device, "state": "already in place"}
    if not mount.is_dir():
        raise DriveError(f"mount the drive first so its contents can be checked ({device})")
    if spot.exists() and not idle(spot):
        raise DriveError(f"an engine operation is using {spot}; let it finish first")
    if holds_engine(mount):
        log("The drive already holds an engine; using it as is")
    elif empty(mount):
        if not holds_engine(spot):
            raise DriveError(f"{spot} has no engine to copy and the drive is empty")
        copy_engine(spot, mount)
    else:
        raise DriveError(f"{mount} holds other files and no Parc engine; use an empty drive")
    (mount / ".metadata_never_index").touch()
    aside = None
    if spot.is_symlink():
        spot.unlink()
    elif spot.exists():
        aside = spot.with_name(spot.name + ".local-" + time.strftime("%Y%m%dT%H%M%S"))
        spot.rename(aside)
        log(f"Moved this Mac's own engine aside to {aside}; delete it once the drive works")
    spot.mkdir(parents=True)
    if use_fstab:
        write_fstab(uuid, spot)
    if run(["/usr/sbin/diskutil", "unmount", device]).returncode != 0:
        raise DriveError(f"could not unmount the drive from {mount}; close anything using it and run again")
    remount = run(["/usr/sbin/diskutil", "mount", "-mountPoint", spot, device])
    if remount.returncode != 0 or not mounted_at(spot, device):
        raise DriveError("could not mount the drive at the engine folder: " + (remount.stderr or remount.stdout).strip())
    if not holds_engine(spot):
        raise DriveError(f"the drive mounted at {spot} but holds no engine")
    log(f"The engine now lives on the drive, mounted at {spot}")
    return {"engine": str(spot), "drive": device, "state": "mounted", "moved_aside": str(aside) if aside else None}


def status(repo: Path, override: Path | None) -> dict:
    spot = engine_spot(repo, override)
    info = run(["/usr/sbin/diskutil", "info", "-plist", spot]) if spot.exists() else None
    details = plistlib.loads(info.stdout.encode()) if info is not None and info.returncode == 0 else {}
    on_drive = os.path.ismount(spot)
    return {"engine": str(spot), "on_drive": on_drive, "drive": details.get("VolumeName") if on_drive else None,
            "mount_setting": bool(on_drive and details.get("VolumeUUID") and fstab_has(details["VolumeUUID"], spot)),
            "engine_present": holds_engine(spot), "idle": idle(spot) if spot.exists() else True}


def eject(repo: Path, override: Path | None) -> None:
    spot = engine_spot(repo, override)
    if not os.path.ismount(spot):
        raise DriveError(f"{spot} is not on a drive")
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
    parser.add_argument("--engine", type=Path, help="Engine folder, when the checkout's work/engine link is absent")
    args = parser.parse_args(argv)
    try:
        if args.command == "prepare":
            if not args.volume:
                parser.error("prepare needs --volume")
            print(json.dumps(prepare(args.volume, args.repo.resolve(), args.engine)))
        elif args.command == "status":
            print(json.dumps(status(args.repo.resolve(), args.engine), indent=2))
        else:
            eject(args.repo.resolve(), args.engine)
        return 0
    except (DriveError, OSError, subprocess.TimeoutExpired, KeyError, ValueError) as error:
        log(str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
