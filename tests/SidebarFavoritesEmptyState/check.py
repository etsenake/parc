#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
app = root / "Sources/ParcApp"
store = sorted((root / "Sources/ParcCore").glob("*.swift"))
with tempfile.TemporaryDirectory(prefix="parc-sidebar-empty-state-") as directory:
    for name, sources in [("view", [*store, app / "SidebarChromeLayout.swift", app / "SidebarFavoritesEmptyState.swift", app / "PointerCover.swift", app / "PointingHand.swift",
                                    app / "SidebarAccessibility.swift", here / "EmptyStateViewTests.swift"]),
                          ("dismissal", [*store, here / "EmptyStateDismissalTests.swift"])]:
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
