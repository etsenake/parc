#!/usr/bin/env python3
"""Production feedback components with isolated preferences and injected outputs.

Does not launch a browser, send Apple Events, play sound, or invoke haptic hardware.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-feedback-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run([
        "xcrun", "swiftc", "-target", "arm64-apple-macos13.0",
        str(root / "Sources/ParcApp/InterfaceFeedback.swift"),
        str(Path(__file__).with_name("main.swift")), "-o", str(executable)
    ], check=True)
    subprocess.run([str(executable)], check=True)
