#!/usr/bin/env python3
"""Preference and token-lifetime checks without native pages, browser input or clipboard writes."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-shared-quotes-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/SharedQuotePreferences.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
