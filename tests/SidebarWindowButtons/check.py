#!/usr/bin/env python3
"""the sidebar traffic lights (WindowStandardButtons) on production AppKit components.

Off-screen titled windows, never made key; no browser, input or preferences.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-sidebar-window-buttons-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/WindowStandardButtons.swift"),
                    str(root / "Sources/ParcApp/SidebarChromeLayout.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
