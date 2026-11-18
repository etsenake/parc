#!/usr/bin/env python3
"""Create, sign, notarize and verify Parc's drag-to-Applications disk image."""
import argparse
import contextlib
import datetime
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import tempfile
import time

spec = importlib.util.spec_from_file_location("parc_dmg_notary", Path(__file__).with_name("notarize-app.py"))
notary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notary)
Refusal = notary.Refusal
spec = importlib.util.spec_from_file_location("parc_dmg_layout", Path(__file__).with_name("dmg_layout.py"))
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)
ASSET = "Parc-arm64.dmg"


def require_report(report, team):
    approval = report.get("notarization", {})
    if (report.get("purpose") != "distribution" or report.get("configuration") != "release"
            or report.get("layout") != "standalone-app" or report.get("distribution_eligible") is not True
            or report.get("notarized") is not True or report.get("signing_team") != team
            or approval.get("team") != team or approval.get("status") != "Accepted"
            or approval.get("stapled") is not True or approval.get("gatekeeper_verified") is not True
            or not re.fullmatch(r"[A-Z0-9]{10}", team or "")
            or not report.get("signed_images") or not report.get("app_version")):
        raise Refusal("DMG packaging requires a verified notarized standalone app with its version and Team ID")


def verify_app(app, report, folder):
    require_report(report, report.get("signing_team"))
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = report["app_version"]
    if (info.get("CFBundleIdentifier") != "org.parc.Browser"
            or info.get("CFBundleShortVersionString") != version["version"]
            or info.get("CFBundleVersion") != str(version["build"])):
        raise Refusal("DMG app identity/version differs from the notarized package")
    for relative, expected in report["signed_images"].items():
        image = app.parent / relative
        if not image.resolve().is_relative_to(app.resolve()) or notary.digest(image) != expected:
            raise Refusal("DMG signed image differs from the notarized package: " + relative)
    notary.command(["codesign", "--verify", "--deep", "--strict", app], folder / "app-codesign.log")
    details = notary.command(["codesign", "-dv", "--verbose=4", app], folder / "app-identity.log")
    details += (folder / "app-identity.log").read_text()
    if (f'TeamIdentifier={report["signing_team"]}\n' not in details
            or "Authority=Developer ID Application: " not in details or "Timestamp=" not in details):
        raise Refusal("DMG app does not retain timestamped Developer ID signing")
    notary.command(["xcrun", "stapler", "validate", app], folder / "app-staple.log")
    notary.command(["spctl", "--assess", "--type", "execute", "--verbose=4", app], folder / "app-gatekeeper.log")


def detach(mount, log, attempts=5, pause=2):
    output = []
    for attempt in range(attempts):
        if attempt:
            time.sleep(pause)
            if not os.path.ismount(mount):
                log.write_text("".join(output))
                return
        result = subprocess.run(["hdiutil", "detach", str(mount)], capture_output=True, text=True)
        output.append(result.stdout + result.stderr)
        if not result.returncode:
            log.write_text("".join(output))
            return
    log.write_text("".join(output))
    if os.path.ismount(mount):
        notary.command(["hdiutil", "detach", "-force", mount], log.with_name(log.stem + "-force.log"))


def verify_layout(volume, folder):
    result = subprocess.run(["xattr", "-px", "com.apple.FinderInfo", str(volume)], capture_output=True, text=True)
    (folder / "volume-info.log").write_text(result.stdout + result.stderr)
    try:
        finder_info = b"" if result.returncode else bytes.fromhex("".join(result.stdout.split()))
        layout.verify(volume, finder_info, (volume / "Parc.app/Contents/Resources/Parc.icns").read_bytes())
    except (OSError, ValueError) as error:
        raise Refusal("DMG install window is missing or wrong: " + str(error)) from error


def release_images(work, folder):
    result = subprocess.run(["hdiutil", "info", "-plist"], capture_output=True)
    for image in plistlib.loads(result.stdout).get("images", []):
        if Path(image.get("image-path", "/")).resolve().is_relative_to(work.resolve()):
            for entity in image.get("system-entities", []):
                if entity.get("mount-point"):
                    with contextlib.suppress(Exception):
                        detach(Path(entity["mount-point"]), folder / "leftover-detach.log", attempts=1)


def build_image(app, output, folder):
    work = Path(tempfile.mkdtemp(prefix=".parc-dmg-", dir=output.parent))
    try:
        image = work / output.name
        try:
            layout.build(app, image, folder / "dmgbuild.log")
        except Exception as error:
            raise Refusal("dmgbuild could not build the install window: " + str(error)) from error
        os.link(image, output)
    finally:
        with contextlib.suppress(Exception):
            release_images(work, folder)
        shutil.rmtree(work, ignore_errors=True)


def verify_dmg(dmg, report, folder, *, notarized=True, layout_expected=True):
    notary.command(["hdiutil", "verify", dmg], folder / "image-verify.log")
    notary.command(["codesign", "--verify", "--strict", dmg], folder / "image-codesign.log")
    notary.command(["codesign", "-dv", "--verbose=4", dmg], folder / "image-identity.log")
    identity = (folder / "image-identity.log").read_text()
    if (f'TeamIdentifier={report["signing_team"]}\n' not in identity
            or "Authority=Developer ID Application: " not in identity or "Timestamp=" not in identity):
        raise Refusal("DMG lacks matching timestamped Developer ID signing")
    with tempfile.TemporaryDirectory(prefix="parc-dmg-mount-") as temporary:
        mount = Path(temporary) / "volume"
        mount.mkdir()
        notary.command(["hdiutil", "attach", dmg, "-nobrowse", "-readonly", "-mountpoint", mount],
                       folder / "image-attach.log")
        try:
            if not (mount / "Applications").is_symlink() or os.readlink(mount / "Applications") != "/Applications":
                raise Refusal("DMG lacks the Applications shortcut")
            verify_app(mount / "Parc.app", report, folder)
            if layout_expected:
                verify_layout(mount, folder)
        finally:
            detach(mount, folder / "image-detach.log")
    if notarized:
        notary.command(["xcrun", "stapler", "validate", dmg], folder / "image-staple.log")
        notary.command(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature",
                        "--verbose=4", dmg], folder / "image-gatekeeper.log")
    match = re.search(r"^CDHash=([0-9a-f]+)$", identity, re.M)
    if not match:
        raise Refusal("DMG signature lacks a code-directory hash")
    return match[1]


def package_dmg(package, output, identity, profile, team, poll_seconds=20):
    package, output = package.resolve(), output.resolve()
    report = json.loads((package / "package-report.json").read_text())
    require_report(report, team)
    if output.parent != package.parent or output.name != ASSET:
        raise Refusal("DMG destination must be " + ASSET + " beside the package directory")
    folder = package.parent / "dmg-notarization"
    folder.mkdir(exist_ok=True)
    with (folder / "operation.lock").open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refusal("This DMG already has an active operation") from error
        receipt_path = folder / "submission.json"
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
        if receipt and (receipt["app_report_sha256"] != notary.digest(package / "package-report.json")
                        or receipt["team"] != team):
            raise Refusal("The app changed since DMG creation; preserve the original inputs")
        verify_app(package / "Parc.app", report, folder)
        if not output.exists():
            if receipt:
                raise Refusal("The submitted DMG is missing; do not create a second notarization input")
            build_image(package / "Parc.app", output, folder)
            notary.command(["codesign", "--sign", identity, "--timestamp", "--identifier",
                            "org.parc.Browser.diskimage", output], folder / "sign.log")
            code_hash = verify_dmg(output, report, folder, notarized=False)
            receipt = {"team": team, "app_version": report["app_version"], "phase": "prepared",
                       "app_report_sha256": notary.digest(package / "package-report.json"),
                       "archive_sha256": notary.digest(output),
                       "cdhash": code_hash, "install_window": True,
                       "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
            notary.save(receipt_path, receipt)
        elif receipt is None:
            raise Refusal("DMG destination already exists without its receipt; refusing to overwrite it")
        window = receipt.get("install_window") is True
        if verify_dmg(output, report, folder, notarized=False, layout_expected=window) != receipt["cdhash"]:
            raise Refusal("DMG payload signature changed since notarization submission")
        if receipt["phase"] == "complete":
            if notary.digest(output) != receipt["stapled_sha256"]:
                raise Refusal("Completed DMG differs from its receipt")
            verify_dmg(output, report, folder, layout_expected=window)
            return receipt
        if receipt["phase"] != "stapling" and notary.digest(output) != receipt["archive_sha256"]:
            raise Refusal("DMG changed since its notarization input was recorded")
        if not receipt.get("submission_id"):
            if receipt["phase"] != "prepared" and not receipt.get("submit_failure"):
                raise Refusal("An earlier DMG upload has no confirmed ID; reconcile notarytool history before retrying")
            notary.service.submit(output, profile, folder / "submit.log", receipt,
                                  lambda value: notary.save(receipt_path, value),
                                  "DMG upload has no confirmed success; reconcile notarytool history before retrying")
        submission = receipt["submission_id"]
        while True:
            info = json.loads(notary.notarytool(["xcrun", "notarytool", "info", submission, "--keychain-profile",
                                                 profile, "--output-format", "json"], folder / "status.json"))
            status = info.get("status")
            if status in ("Accepted", "Invalid", "Rejected"):
                break
            if status != "In Progress":
                raise Refusal("Unexpected DMG notarization status: " + repr(status))
            print("Apple DMG notarization pending: " + submission, flush=True)
            time.sleep(poll_seconds)
        notary.notarytool(["xcrun", "notarytool", "log", submission, "--keychain-profile", profile,
                           folder / "apple-log.json"], folder / "download-log.log")
        apple_log = json.loads((folder / "apple-log.json").read_text())
        if (status != "Accepted" or apple_log.get("status") != "Accepted"
                or apple_log.get("jobId") != submission or apple_log.get("sha256") != receipt["archive_sha256"]):
            raise Refusal("Apple did not approve this exact DMG; inspect its notarization log")
        receipt.update(phase="stapling", status="Accepted")
        notary.save(receipt_path, receipt)
        notary.command(["xcrun", "stapler", "staple", output], folder / "staple.log")
        verify_dmg(output, report, folder, layout_expected=window)
        receipt.update(phase="complete", stapled=True, gatekeeper_verified=True,
                       stapled_sha256=notary.digest(output), apple_log_issues=apple_log.get("issues") or [],
                       completed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
        notary.save(receipt_path, receipt)
        print("DMG notarized, stapled and verified: " + str(output), flush=True)
        return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sign-identity", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--team", required=True)
    args = parser.parse_args()

    def interrupted(signum, frame):
        raise KeyboardInterrupt("DMG packaging interrupted by signal " + str(signum))

    signal.signal(signal.SIGTERM, interrupted)
    try:
        package_dmg(args.package, args.output, args.sign_identity, args.profile, args.team)
    except (Refusal, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(notary.service.EXIT_DOWN if isinstance(error, notary.service.Unavailable) else 1,
                    "DMG packaging refused: " + str(error) + "\n")


if __name__ == "__main__":
    main()
