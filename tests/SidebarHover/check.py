#!/usr/bin/env python3
"""Sidebar hover regions: the pure model and the production AppKit tracker.

The tracker runs in an off-screen window that is never made key; the pointer
and the listening condition are injected. No browser or input.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
model = root / "Sources/ParcCore/SidebarHover.swift"
with tempfile.TemporaryDirectory(prefix="parc-sidebar-hover-") as directory:
    for name, sources in [("model", [model, here / "SidebarHoverModelTests.swift"]),
                          ("tracker", [model, root / "Sources/ParcApp/SidebarHoverTracker.swift",
                                       here / "SidebarHoverTrackerTests.swift"])]:
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
