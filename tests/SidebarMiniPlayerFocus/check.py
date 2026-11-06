#!/usr/bin/env python3
"""The sidebar mini player's keyboard stops and rings (every stop in the
sidebar's chain draws one), on the production MiniPlayerDeck with stand-in
engine media types.

Off-screen window, never made key; no browser, input or preferences.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
with tempfile.TemporaryDirectory(prefix="parc-mini-player-focus-") as directory:
    scratch = Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    # ActionButton (with its ring) and LayoutView, without the rest of SidebarView.
    (scratch / "ActionButton.swift").write_text(sidebar[:sidebar.index("final class MenuAction")]
        + sidebar[sidebar.index("class LayoutView: NSView {"):sidebar.index("final class FlippedStackView")]
        # The Favorite favicon identity above ActionButton needs SplitOrientation.
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/SidebarAccessibility.swift"),
                    str(root / "Sources/ParcApp/MiniPlayerView.swift"), str(root / "Sources/ParcApp/MiniPlayerMotion.swift"),
                    str(scratch / "ActionButton.swift"), str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/ReloadControl.swift"),
                    *map(str, tooltip_sources(root, scratch, ["ReloadControl.swift"])),
                    str(Path(__file__).with_name("SidebarMiniPlayerFocusTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
