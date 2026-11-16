#!/usr/bin/env python3
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
        subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
