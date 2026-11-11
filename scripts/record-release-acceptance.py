#!/usr/bin/env python3
"""Verify a fresh installed candidate, open it normally, and record bounded startup acceptance.

Run only after the user authorizes the ready candidate. Never kills an app, changes
profiles, inspects protected authorization, or reads Keychain items.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import time

spec = importlib.util.spec_from_file_location("parc_acceptance_publisher", Path(__file__).with_name("publish-homebrew.py"))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
EXPECTED_DR = publisher.PRODUCTION_DESIGNATED_REQUIREMENT


def processes(app):
    output = subprocess.check_output(["ps", "-axo", "pid=,stat=,comm="], text=True)
    rows = [line.strip().split(None, 2) for line in output.splitlines()]
    return [{"pid": int(row[0]), "state": row[1], "executable": row[2]} for row in rows
            if len(row) == 3 and row[2].startswith(str(app) + "/Contents/")]


def crash_reports():
    return {str(path): path.stat().st_mtime_ns
            for folder in (Path.home() / "Library/Logs/DiagnosticReports", Path("/Library/Logs/DiagnosticReports"))
            if folder.is_dir() for path in folder.glob("Parc*") if path.is_file()}


def verify_installed(app, report, *, strict):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = report["app_version"]
    if (info.get("CFBundleIdentifier") != "org.parc.Browser"
            or info.get("CFBundleShortVersionString") != version["version"]
            or info.get("CFBundleVersion") != str(version["build"])):
        raise ValueError("Installed version/identity differs from the release package")
    for relative, expected in report["signed_images"].items():
        image = app.parent / relative
        if not image.resolve().is_relative_to(app.resolve()):
            raise ValueError("Signed-image path escapes the installed app")
        with image.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != expected:
                raise ValueError("Installed code differs from the release package: " + relative)
        signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(image)],
                                   text=True, capture_output=True, check=True).stderr
        if (f"TeamIdentifier={publisher.PRODUCTION_TEAM}\n" not in signature
                or "Authority=Developer ID Application: " not in signature or "Timestamp=" not in signature):
            raise ValueError("Installed code lacks timestamped production Developer ID signing")
    subprocess.run(["codesign", "--verify", "--deep", *(["--strict"] if strict else []), str(app)], check=True)
    requirement = subprocess.run(["codesign", "-dr", "-", str(app)], text=True,
                                 capture_output=True, check=True).stdout.strip()
    if requirement != EXPECTED_DR:
        raise ValueError("The stable production designated requirement changed")
    return requirement


def record(package, app, tag, commit, output, seconds=90):
    if type(seconds) is not int or not 60 <= seconds <= 300 or output.exists() or not output.parent.is_dir():
        raise ValueError("Use 60 to 300 seconds and a new acceptance receipt path in an existing directory")
    raw = (package / "package-report.json").read_bytes()
    report = json.loads(raw)
    publisher.dmg_tool.require_report(report, publisher.PRODUCTION_TEAM)
    if tag != "v" + report["app_version"]["version"]:
        raise ValueError("Release tag and package version differ")
    publisher.verify_tag(tag, commit)
    observation = {"application": str(app), "main_pid": 0, "observed_seconds": 0,
                   "passed": False, "new_crash_reports": [], "failure": None}
    receipt = {"schema_version": 1, "status": "failed", "acceptance_kind": "automatic",
               "release_tag": tag, "source_commit": commit,
               "app_version": report["app_version"], "package_report_sha256": hashlib.sha256(raw).hexdigest(),
               "signing_team": publisher.PRODUCTION_TEAM, "installed_app": str(app),
               "installed_code_hashes_verified": False, "prelaunch_strict_verified": False,
               "launch_observation": observation}
    baseline = None
    try:
        if processes(app):
            raise ValueError("Quit the installed app before recording a fresh candidate launch")
        verify_installed(app, report, strict=True)
        subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
        subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=4", str(app)], check=True)
        receipt["prelaunch_strict_verified"] = True
        baseline = crash_reports()
        subprocess.run(["open", str(app)], check=True, timeout=15)
        deadline = time.monotonic() + 15
        executable = str(app / "Contents/MacOS/Parc")
        main = []
        while time.monotonic() < deadline:
            main = [row for row in processes(app) if row["executable"] == executable and not row["state"].startswith("Z")]
            if main:
                break
            time.sleep(.5)
        if len(main) != 1:
            raise ValueError("Expected one installed candidate process after normal open")
        observation["main_pid"] = main[0]["pid"]
        started = time.monotonic()
        while True:
            elapsed = time.monotonic() - started
            live = [row for row in processes(app) if row["pid"] == observation["main_pid"]
                    and row["executable"] == executable and not row["state"].startswith("Z")]
            observation["observed_seconds"] = round(elapsed, 2)
            if len(live) != 1:
                raise ValueError("Candidate exited or restarted during startup observation")
            if elapsed >= seconds:
                break
            time.sleep(min(5, seconds - elapsed))
        observation["new_crash_reports"] = [path for path, stamp in crash_reports().items() if baseline.get(path) != stamp]
        if observation["new_crash_reports"]:
            raise ValueError("New Parc crash reports appeared during startup observation")
        receipt["designated_requirement"] = verify_installed(app, report, strict=False)
        if not any(row["pid"] == observation["main_pid"] and row["executable"] == executable
                   and not row["state"].startswith("Z") for row in processes(app)):
            raise ValueError("Candidate exited before post-launch verification completed")
        observation["new_crash_reports"] = [path for path, stamp in crash_reports().items() if baseline.get(path) != stamp]
        if observation["new_crash_reports"]:
            raise ValueError("New Parc crash reports appeared during post-launch verification")
        receipt["installed_code_hashes_verified"] = True
        receipt["code_image_count"] = len(report["signed_images"])
        observation["passed"] = True
        receipt["status"] = "passed"
    except (ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        observation["failure"] = str(error)
        if baseline is not None:
            observation["new_crash_reports"] = [path for path, stamp in crash_reports().items() if baseline.get(path) != stamp]
    receipt["recorded_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with output.open("x") as stream:
        stream.write(json.dumps(receipt, indent=2) + "\n")
    return receipt


def record_user_confirmation(package, tag, commit, output, statement, confirmed_at, raw_observation=None):
    if output.exists() or not output.parent.is_dir():
        raise ValueError("Use a new receipt path in an existing directory")
    raw = (package / "package-report.json").read_bytes()
    report = json.loads(raw)
    publisher.dmg_tool.require_report(report, publisher.PRODUCTION_TEAM)
    if tag != "v" + report["app_version"]["version"]:
        raise ValueError("Release tag and package version differ")
    receipt = {"schema_version": 1, "status": "user-confirmed", "acceptance_kind": "user-confirmed",
        "release_tag": tag, "source_commit": commit, "app_version": report["app_version"],
        "package_report_sha256": hashlib.sha256(raw).hexdigest(), "signing_team": publisher.PRODUCTION_TEAM,
        "automatic_startup_acceptance_claimed": False,
        "user_confirmation": {"confirmed_by": "Josh", "confirmed_at": confirmed_at,
                              "scope": "normal-startup", "statement": statement}}
    publisher.require_evidence(receipt)
    publisher.verify_tag(tag, commit)
    artifact = package / "Parc.app"
    receipt["designated_requirement"] = verify_installed(artifact, report, strict=True)
    subprocess.run(["xcrun", "stapler", "validate", str(artifact)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=4", str(artifact)], check=True)
    receipt.update(artifact_code_hashes_verified=True, artifact_strict_verified=True,
                   code_image_count=len(report["signed_images"]), verified_artifact=str(artifact))
    if raw_observation is not None:
        observation_bytes = raw_observation.read_bytes()
        receipt.update(launch_observation=json.loads(observation_bytes),
                       raw_observation=str(raw_observation),
                       raw_observation_sha256=hashlib.sha256(observation_bytes).hexdigest(),
                       observation_classification="User testing invalidated the uncontrolled observation; this is explicit user acceptance")
    publisher.verify_acceptance(receipt, tag, commit, report["app_version"], receipt["package_report_sha256"])
    receipt["recorded_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with output.open("x") as stream:
        stream.write(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--app", type=Path, default=Path("/Applications/Parc.app"))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", type=int, default=90)
    parser.add_argument("--user-confirmed", action="store_true",
                        help="record the user's existing explicit approval; verify the preserved artifact without any app launch")
    parser.add_argument("--statement-file", type=Path)
    parser.add_argument("--confirmed-at", help="ISO 8601 timestamp with timezone of the recorded user confirmation")
    parser.add_argument("--raw-observation", type=Path, help="retain an interrupted observation unchanged as separate evidence")
    args = parser.parse_args()
    try:
        if args.user_confirmed:
            if args.statement_file is None or args.confirmed_at is None:
                raise ValueError("--user-confirmed requires --statement-file and --confirmed-at")
            receipt = record_user_confirmation(args.package.resolve(), args.tag, args.commit, args.output,
                                               args.statement_file.read_text(), args.confirmed_at, args.raw_observation)
        else:
            if any((args.statement_file, args.confirmed_at, args.raw_observation)):
                raise ValueError("User confirmation arguments require the explicit --user-confirmed flag")
            receipt = record(args.package.resolve(), args.app.resolve(), args.tag, args.commit, args.output, args.seconds)
        if receipt["status"] == "failed":
            raise ValueError(receipt["launch_observation"]["failure"])
    except (ValueError, OSError, KeyError, publisher.dmg_tool.Refusal, subprocess.CalledProcessError) as error:
        parser.exit(1, "Acceptance refused: " + str(error) + "\n")
    print("Startup acceptance recorded: " + str(args.output))


if __name__ == "__main__":
    main()
