from __future__ import annotations

import json
from pathlib import Path
import plistlib
import subprocess
from typing import NamedTuple

VERSION = "2.10.1"
PACKAGE = "https://github.com/sparkle-project/Sparkle"
REVISION = "ab7d71291238df6e0492143b120c9b696a35f603"
CHECKSUM = "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
RELEASES = "https://github.com/etsenake/parc-releases/releases"
FEED_URL = RELEASES + "/latest/download/appcast.xml"
SERVICE = "https://sparkle-project.org"
ACCOUNT = "parc"
PUBLIC_ED_KEY = "1hic4mo2AXODWtTea711Nwof69H++DEETfSXVUzCqKI="
INFO = {"SUFeedURL": FEED_URL, "SUPublicEDKey": PUBLIC_ED_KEY, "SUEnableAutomaticChecks": True,
        "SUAutomaticallyUpdate": True, "SUScheduledCheckInterval": 14400}


class Release(NamedTuple):
    frameworks: Path
    tools: Path


def has_key() -> bool:
    found = subprocess.run(["security", "find-generic-password", "-s", SERVICE, "-a", ACCOUNT],
                           capture_output=True, timeout=30).returncode
    if found not in (0, 44):
        raise RuntimeError("The login Keychain could not be searched for Sparkle's signing key; unlock it first")
    return found == 0


def artifact(repo: Path, scratch: Path) -> Release:
    pins = json.loads((repo / "Package.resolved").read_text())["pins"]
    pin = next((item for item in pins if item.get("identity") == "sparkle"), None)
    if pin is None or pin.get("location") != PACKAGE or pin.get("state") != {"revision": REVISION, "version": VERSION}:
        raise ValueError(f"Package.resolved must pin Sparkle {VERSION} at {REVISION}")
    manifest = scratch / "checkouts/Sparkle/Package.swift"
    if f'let checksum = "{CHECKSUM}"' not in manifest.read_text():
        raise ValueError(f"The resolved Sparkle package does not declare the pinned binary checksum: {manifest}")
    directory = scratch / "artifacts/sparkle/Sparkle"
    frameworks = directory / "Sparkle.xcframework/macos-arm64_x86_64"
    info = plistlib.loads((frameworks / "Sparkle.framework/Resources/Info.plist").read_bytes())
    if info.get("CFBundleShortVersionString") != VERSION:
        raise ValueError(f"The resolved Sparkle framework is not version {VERSION}: {frameworks}")
    if not (directory / "bin/sign_update").is_file() or not (directory / "bin/generate_keys").is_file():
        raise ValueError(f"The resolved Sparkle package lacks its signing tools: {directory / 'bin'}")
    return Release(frameworks, directory / "bin")


def resolve(repo: Path, scratch: Path | None = None) -> Release:
    location = repo / ".build" if scratch is None else scratch
    subprocess.run(["xcrun", "swift", "package", "--package-path", str(repo), "--scratch-path", str(location),
                    "--disable-keychain", "resolve"], check=True)
    return artifact(repo, location)
