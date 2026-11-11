#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
with tempfile.TemporaryDirectory(prefix="parc-mini-ax-") as directory:
    scratch = Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    (scratch / "ActionButton.swift").write_text(sidebar[:sidebar.index("final class MenuAction")]
        + sidebar[sidebar.index("class LayoutView: NSView {"):sidebar.index("final class FlippedStackView")]
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    fixture = (root / "tests/SidebarMiniPlayerFocus/SidebarMiniPlayerFocusTests.swift").read_text()
    fixture = fixture[fixture.index("enum PCNativeMediaAction {"):]
    fixture = fixture.replace('let identifier: String, title = "Song", sourceURL = "https://example.test/"',
                              'let identifier: String, sourceURL = "https://example.test/"\n    var title = "Song"')
    fixture = fixture.replace('let microphoneOn = false, cameraOn = false', 'var microphoneOn = false, cameraOn = false')
    (scratch / "Fixtures.swift").write_text("import AppKit\n" + fixture)
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/MiniPlayerView.swift"), str(root / "Sources/ParcApp/SidebarSpacePaging.swift"), str(root / "Sources/ParcApp/MiniPlayerMotion.swift"),
                    str(root / "Sources/ParcApp/SidebarAccessibility.swift"),
                    str(scratch / "ActionButton.swift"), str(scratch / "Fixtures.swift"), str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/ReloadControl.swift"),
                    *map(str, tooltip_sources(root, scratch, ["ReloadControl.swift"])),
                    str(Path(__file__).with_name("Checks.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
