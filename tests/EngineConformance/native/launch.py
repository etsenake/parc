#!/usr/bin/env python3
"""Launch the compiled native host using an explicitly owned disposable profile."""
import argparse
import os
from pathlib import Path
import stat
import subprocess

MARKER = ".parc-native-host-profile"
MARKER_TEXT = "Parc native host fixture profile v1\n"


def profile_directory(path: Path, reuse: bool) -> Path:
    if not path.is_absolute() or path != path.resolve(strict=False):
        raise ValueError("Profile must be an absolute canonical path without symlinks")
    if reuse:
        info = path.lstat()
        marker = path / MARKER
        marker_info = marker.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                or stat.S_IMODE(info.st_mode) != 0o700
                or not stat.S_ISREG(marker_info.st_mode)
                or marker_info.st_uid != os.getuid()
                or marker.read_text() != MARKER_TEXT):
            raise ValueError("Profile is not an owned native-host fixture directory")
    else:
        # mkdir(exist_ok=False) deliberately refuses all existing directories.
        path.mkdir(mode=0o700, parents=False, exist_ok=False)
        marker = path / MARKER
        descriptor = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            stream.write(MARKER_TEXT)
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--reuse-profile", action="store_true")
    parser.add_argument("--url", default="about:blank")
    options = parser.parse_args()
    app = options.app.resolve(strict=True)
    binary = app / "Contents/MacOS/parc_host_harness"
    if not binary.is_file() or not os.access(binary, os.X_OK):
        parser.error("--app must be the compiled parc_host_harness.app")
    # Preserve the component build's location. Do not copy its bundle away from
    # the pinned output directory or create an alternate/hidden host window.
    try:
        profile = profile_directory(options.profile, options.reuse_profile)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    command = [str(binary), f"--parc-profile={profile}", f"--url={options.url}"]
    print(f"Native host: {app}\nDisposable profile: {profile}", flush=True)
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
