#!/usr/bin/env python3
"""Isolated preference checks; no browser, engine process or real defaults."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
with tempfile.TemporaryDirectory(prefix="parc-developer-mode-") as directory:
    scratch = Path(directory)
    # Compile the actual shared native button declaration without pulling in
    # Sidebar's browser model. This is an exact source slice, not a test double.
    source = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    support = scratch / "ActionButton.swift"
    support.write_text(source[:source.index("final class MenuAction")]
        # The Favorite favicon identity above ActionButton needs SplitOrientation.
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/DeveloperToolbarLayout.swift"),
                    str(root / "Sources/ParcApp/DeveloperMode.swift"),
                    str(root / "Sources/ParcApp/DeveloperToolbarControls.swift"),
                    str(support), str(root / "Sources/ParcApp/TranslucentButtonFace.swift"),
                    str(root / "Sources/ParcApp/ReloadControl.swift"), str(Path(__file__).with_name("main.swift")),
                    *map(str, tooltip_sources(root, scratch, ["ReloadControl.swift"])),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
