#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-sidebar-ax-") as directory:
    scratch = Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    (scratch / "ActionButton.swift").write_text(sidebar[:sidebar.index("final class MenuAction")]
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    navigation = (root / "Sources/ParcApp/NavigationControls.swift").read_text()
    (scratch / "NavigationControlButton.swift").write_text(navigation[:navigation.index("final class NavigationHistoryController")])
    executable = scratch / "checks"
    compiled = [root / "Sources/ParcCore/SidebarResize.swift",
                root / "Sources/ParcApp/SidebarResizeRegion.swift",
                root / "Sources/ParcApp/SidebarAccessibility.swift",
                root / "Sources/ParcApp/SavedFocus.swift",
                root / "Sources/ParcApp/WindowStandardButtons.swift",
                root / "Sources/ParcApp/SidebarMotionController.swift",
                scratch / "ActionButton.swift",
                scratch / "NavigationControlButton.swift",
                root / "Sources/ParcApp/NavigationControlPress.swift",
                root / "Sources/ParcCore/SpaceTheme.swift",
                root / "Sources/ParcApp/ThemeRenderer.swift",
                root / "Sources/ParcApp/ParcMenuColors.swift",
                root / "Sources/ParcApp/ReloadControl.swift",
                root / "Sources/ParcApp/TranslucentButtonFace.swift"]
    sys.path.insert(0, str(root / "tests/Tooltip"))
    from support import tooltip_sources
    compiled += tooltip_sources(root, scratch, compiled)
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *[str(path) for path in compiled],
                    str(Path(__file__).with_name("SidebarAccessibilityTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
