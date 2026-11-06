#!/usr/bin/env python3
"""Fresh application replacement with verified profile backup and normal startup.

No profile reset, Keychain modification, automatic downgrade or browser driving.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import signal
import stat
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def profile_inventory(root):
    result = {}
    if not root.exists():
        return result
    for parent, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = Path(parent) / name
            info = path.lstat()
            relative = str(path.relative_to(root))
            if path.is_symlink():
                result[relative] = {"link": os.readlink(path)}
            elif stat.S_ISREG(info.st_mode):
                result[relative] = {"bytes": info.st_size, "sha256": digest(path)}
            elif path.is_dir():
                result[relative] = {"directory": True}
            else:
                raise ValueError("Unexpected special file in profile: " + relative)
    return result


def app_processes(app):
    rows = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True).splitlines()
    return [int(row.strip().split(None, 1)[0]) for row in rows if str(app) + "/Contents/" in row or "/Parc.app/Contents/" in row]


def stop_app(app):
    # NSRunningApplication requests a normal quit without scripting browser UI.
    if app_processes(app):
        subprocess.run(["osascript", "-l", "JavaScript", "-e",
            'ObjC.import("AppKit"); $.NSRunningApplication.runningApplicationsWithBundleIdentifier("org.parc.Browser").js.forEach(a => a.terminate)'],
            capture_output=True, timeout=15)
    for sig, wait in [(None, 10), (signal.SIGTERM, 5), (signal.SIGKILL, 3)]:
        if sig:
            for pid in app_processes(app):
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        end = time.monotonic() + wait
        while app_processes(app) and time.monotonic() < end:
            time.sleep(.25)
    if app_processes(app):
        raise ValueError("Parc remains running; profile backup/replacement was not started")


def atomic(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    os.replace(temporary, path)


def backup_profile(receipts):
    receipts.mkdir(parents=True, exist_ok=True, mode=0o700)
    profile = Path.home() / 'Library/Application Support/Parc'
    before = profile_inventory(profile)
    atomic(receipts / 'profile-before.json', before)
    backup = receipts / 'profile-backup'
    if profile.exists():
        if not backup.exists():
            subprocess.run(['ditto', str(profile), str(backup)], check=True)
        if before != profile_inventory(backup) or before != profile_inventory(profile):
            raise ValueError('Profile backup differs; application replacement was not started')
    return profile, before, backup


def checker():
    spec = importlib.util.spec_from_file_location("parc_install_acceptance", ROOT / "scripts/record-release-acceptance.py")
    check = importlib.util.module_from_spec(spec); spec.loader.exec_module(check)
    return check



def install(package, tag, commit, receipts, app=Path("/Applications/Parc.app")):
    receipts.mkdir(parents=True, exist_ok=True, mode=0o700)
    raw = (package / "package-report.json").read_bytes()
    report = json.loads(raw)
    check = checker()
    check.publisher.dmg_tool.require_report(report, check.publisher.PRODUCTION_TEAM)
    check.publisher.verify_tag(tag, commit)
    check.verify_installed(package / "Parc.app", report, strict=True)
    receipt_path = receipts / "installation.json"
    acceptance = receipts / "acceptance.json"
    if acceptance.exists():
        value = json.loads(acceptance.read_text())
        check.publisher.verify_acceptance(value, tag, commit, report["app_version"], hashlib.sha256(raw).hexdigest())
        check.verify_installed(app, report, strict=False)
        return
    if receipt_path.exists():
        previous = json.loads(receipt_path.read_text())
        if previous['commit'] != commit or previous['report_sha256'] != hashlib.sha256(raw).hexdigest():
            raise ValueError('Installation receipt belongs to different inputs')
        # No failed startup is silently retried. Only an interrupted observation
        # without a completed result can start a fresh, explicitly recorded run.
        if previous.get('phase') in ('installed', 'launching'):
            check.verify_installed(app, report, strict=False)
            stop_app(app)
            if previous['phase'] == 'launching':
                previous['interrupted_observation_restarted_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            previous['phase'] = 'launching'
            atomic(receipt_path, previous)
            result = check.record(package, app, tag, commit, acceptance, seconds=90)
            if result['status'] != 'passed':
                raise ValueError('Startup failed; candidate and evidence preserved without automatic retry')
            return
        # A killed filesystem transaction is reconciled below using exact paths.
    stop_app(app)
    profile, before, backup = backup_profile(receipts)
    preferences = Path.home() / "Library/Preferences/org.parc.Browser.plist"
    if preferences.exists():
        subprocess.run(["ditto", str(preferences), str(receipts / "preferences-backup.plist")], check=True)
    stage_parent = app.parent / (".Parc-release-" + receipts.parent.name)
    if stage_parent.exists():
        # Retain interrupted staging rather than merging a possibly partial app.
        os.rename(stage_parent, stage_parent.with_name(stage_parent.name + '-interrupted-' + str(time.time_ns())))
    stage_parent.mkdir()
    staged = stage_parent / "Parc.app"
    subprocess.run(["ditto", str(package / "Parc.app"), str(staged)], check=True)
    check.verify_installed(staged, report, strict=True)
    subprocess.run(["xcrun", "stapler", "validate", str(staged)], check=True)
    old = receipts / "previous-Parc.app"
    intent = {'commit': commit, 'tag': tag, 'report_sha256': hashlib.sha256(raw).hexdigest(),
              'phase': 'replacing', 'previous_app': str(old), 'profile_backup': str(backup)}
    atomic(receipt_path, intent)
    if app.exists():
        if old.exists():
            # The prior rename/install may have completed before checkpointing.
            check.verify_installed(app, report, strict=True)
            shutil.rmtree(staged)
        else:
            os.rename(app, old)
    try:
        if staged.exists():
            os.rename(staged, app)
        check.verify_installed(app, report, strict=True)
    except BaseException:
        # This is a filesystem/signature transaction failure before any launch.
        if app.exists():
            os.rename(app, receipts / "failed-stage-Parc.app")
        if old.exists():
            os.rename(old, app)
        raise
    stage_parent.rmdir()
    if profile_inventory(profile) != before:
        raise ValueError("Profile changed during replacement; backup retained, no app was opened")
    receipt = {"phase": "installed", "commit": commit, "tag": tag, "report_sha256": hashlib.sha256(raw).hexdigest(),
               "version": report["app_version"], "profile_backup": str(backup),
               "profile_unchanged_before_launch": True, "previous_app": str(old),
               "installed_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    atomic(receipt_path, receipt)
    receipt["phase"] = "launching"
    atomic(receipt_path, receipt)
    result = check.record(package, app, tag, commit, acceptance, seconds=90)
    if result["status"] != "passed":
        raise ValueError("Startup observation did not pass; candidate/profile/backups retained without automatic downgrade")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--receipts", required=True, type=Path)
    args = parser.parse_args()
    install(args.package.resolve(), args.tag, args.commit, args.receipts.resolve())


if __name__ == "__main__":
    main()
