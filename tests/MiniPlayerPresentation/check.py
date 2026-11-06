#!/usr/bin/env python3
"""Compile and inspect the production deck in an off-screen inert window.
No browser, input events, profiles, or playback are used.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
with tempfile.TemporaryDirectory(prefix="parc-mini-presentation-") as directory:
    scratch = Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    (scratch / "ActionButton.swift").write_text(sidebar[:sidebar.index("final class MenuAction")]
        + sidebar[sidebar.index("class LayoutView: NSView {"):sidebar.index("final class FlippedStackView")]
        # The Favorite favicon identity above ActionButton needs SplitOrientation.
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    fixture = (root / "tests/SidebarMiniPlayerFocus/SidebarMiniPlayerFocusTests.swift").read_text()
    fixture = fixture[fixture.index("// Stand-ins for the engine's media types"):]
    fixture = fixture.replace('title = "Song"', 'title = "A long track title that must overflow the mini player available width"')
    fixture = fixture.replace('let volume = 1.0, canSetVolume = true, canToggleMicrophone = false, canToggleCamera = false',
                              'let volume = 1.0, canToggleMicrophone = false, canToggleCamera = false; var canSetVolume = true')
    (scratch / "Fixtures.swift").write_text("import AppKit\n" + fixture)
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/MiniPlayerView.swift"), str(root / "Sources/ParcApp/MiniPlayerMotion.swift"), str(root / "Sources/ParcApp/SidebarAccessibility.swift"),
                    str(scratch / "ActionButton.swift"), str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/ReloadControl.swift"),
                    str(scratch / "Fixtures.swift"), str(Path(__file__).with_name("PresentationTests.swift")),
                    *map(str, tooltip_sources(root, scratch, ["ReloadControl.swift"])),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable), "-ParcMiniPlayerMarqueeTitleEnabled", "YES"], check=True)
