"""The pinned Sparkle release Parc embeds for software updates, fetched on first use."""
from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import tempfile

VERSION = "2.10.1"
URL = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz"
SHA256 = "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
RELEASES = "https://github.com/etsenake/parc-releases/releases"
FEED_URL = RELEASES + "/latest/download/appcast.xml"
# The private key lives in the release Mac's login Keychain under Sparkle's
# service, this account (generate_keys/sign_update --account parc).
SERVICE = "https://sparkle-project.org"
ACCOUNT = "parc"
PUBLIC_ED_KEY = "1hic4mo2AXODWtTea711Nwof69H++DEETfSXVUzCqKI="
#
INFO = {"SUFeedURL": FEED_URL, "SUPublicEDKey": PUBLIC_ED_KEY, "SUEnableAutomaticChecks": True,
        "SUAutomaticallyUpdate": True, "SUScheduledCheckInterval": 28800}


def has_key() -> bool:
    """Whether the login Keychain holds the signing key; its secret is not read."""
    return subprocess.run(["security", "find-generic-password", "-s", SERVICE, "-a", ACCOUNT],
                          capture_output=True).returncode == 0


def directory(cache: Path) -> Path:
    return cache / f"Sparkle-{VERSION}-{SHA256[:12]}"


def fetch(cache: Path) -> Path:
    """The verified release (Sparkle.framework and bin/), downloaded once into cache."""
    target = directory(cache)
    if target.is_dir():
        return target
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".sparkle-", dir=cache) as temporary:
        archive = Path(temporary) / "Sparkle.tar.xz"
        subprocess.run(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location", "--retry", "3",
                        "--connect-timeout", "30", "--max-time", "600", "--output", str(archive), URL], check=True)
        with archive.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != SHA256:
                raise ValueError(f"Downloaded Sparkle {VERSION} does not match its pinned SHA-256")
        extracted = Path(temporary) / "extracted"
        extracted.mkdir()
        subprocess.run(["/usr/bin/tar", "-xJf", str(archive), "-C", str(extracted),
                        "./Sparkle.framework", "./bin"], check=True)
        try:
            extracted.rename(target)
        except OSError:
            # A concurrent build published the same verified release first.
            if not target.is_dir():
                raise
    return target
