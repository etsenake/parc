#!/usr/bin/env python3
"""Isolated original-press ownership and cancellation checks; no browser/events posted."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-navigation-press-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/NavigationControlPress.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
