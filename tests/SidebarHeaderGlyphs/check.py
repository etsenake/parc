#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
app = root / "Sources/ParcApp"
with tempfile.TemporaryDirectory(prefix="parc-sidebar-header-glyphs-") as directory:
    scratch = Path(directory)
    slices = {
        "ActionButton.swift": ("SidebarView.swift", "final class MenuAction"),
        "NavigationControlButton.swift": ("NavigationControls.swift", "final class NavigationHistoryController"),
        "ThemePalette.swift": ("ThemeRenderer.swift", "@MainActor\nenum NativeInputDiagnostics"),
    }
    for target, (source, marker) in slices.items():
        text = (app / source).read_text()
        (scratch / target).write_text(text[:text.index(marker)])
    (scratch / "SplitOrientation.swift").write_text(
        "enum SplitOrientation: String, Codable, CaseIterable { case horizontal, vertical }\n")
    text = (root / "Sources/ParcApp/SiteControlCenter.swift").read_text()
    (scratch / "SiteControlCenterArtwork.swift").write_text(text[:text.index("enum SiteControlCenterMetrics")])
    store = (root / "Sources/ParcCore/BrowserStore.swift").read_text()
    page = store[store.index("enum InternalPage: Equatable {"):]
    (scratch / "InternalPage.swift").write_text("import Foundation\n" + page[:page.index("\n}\n") + 3])
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/SpaceTheme.swift"), str(scratch / "SplitOrientation.swift"),
                    str(scratch / "InternalPage.swift"), str(root / "Sources/ParcCore/NoteFileKind.swift"),
                    str(root / "Sources/ParcCore/NoteFilePaths.swift"),
                    *[str(scratch / name) for name in slices],
                    str(app / "ExtensionControls.swift"), str(scratch / "SiteControlCenterArtwork.swift"),
                    str(app / "NavigationControlPress.swift"), str(app / "ReloadControl.swift"),
                    str(app / "TranslucentButtonFace.swift"), str(app / "SidebarAddressPill.swift"), str(app / "SidebarAddressText.swift"),
                    str(app / "SidebarChromeLayout.swift"), str(app / "ParcMenuColors.swift"),
                    *map(str, tooltip_sources(root, scratch, ["SpaceTheme.swift", "ThemeRenderer.swift", "ReloadControl.swift"])),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=120)
