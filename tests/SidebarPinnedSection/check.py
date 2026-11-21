#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
app = root / "Sources/ParcApp"
core = root / "Sources/ParcCore"
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources

sidebar = (app / "SidebarView.swift").read_text()

store = (core / "BrowserStore.swift").read_text()
core_sources = re.search(r"^core_sources=\((.*?)^\)", (root / "scripts/test.sh").read_text(), re.S | re.M)
store_sources = [core / name for name in re.findall(r"Sources/ParcCore/(\w+\.swift)", core_sources.group(1))]
reference = re.search(r"^enum SidebarItemReference\b.*?^\}\n", store, re.S | re.M)

with tempfile.TemporaryDirectory(prefix="parc-pinned-section-") as directory:
    scratch = Path(directory)
    (scratch / "SidebarItemReference.swift").write_text("import Foundation\n" + reference.group(0))
    (scratch / "ActionButton.swift").write_text(
        "import AppKit\nenum SplitOrientation: Equatable { case horizontal, vertical }\n"
        + sidebar[:sidebar.index("final class MenuAction")])
    (scratch / "SidebarRows.swift").write_text("import AppKit\n" + sidebar[:sidebar.index("final class SidebarTabRow")])
    plate = [*store_sources, app / "SidebarChromeLayout.swift", app / "SidebarRowAppearance.swift",
             app / "SidebarPinnedHeader.swift", app / "DocumentDefaultIcon.swift", app / "LibraryArtwork.swift",
             app / "SidebarOutline.swift", scratch / "SidebarRows.swift",
             app / "TranslucentButtonFace.swift", app / "PointerCover.swift", app / "ReloadControl.swift", app / "PointingHand.swift"]
    if core / "SidebarOutlineConfigureSkip.swift" not in plate:
        plate.append(core / "SidebarOutlineConfigureSkip.swift")
    suites = {
        "model": [*sorted(core.glob("*.swift")), here / "ModelTests.swift"],
        "header": [*store_sources, app / "SidebarChromeLayout.swift", app / "SidebarRowAppearance.swift",
                   app / "SidebarPinnedHeader.swift", app / "DocumentDefaultIcon.swift", app / "LibraryArtwork.swift",
                   app / "PinnedSectionPreferences.swift",
                   *tooltip_sources(root, scratch, store_sources), here / "HeaderTests.swift"],
        "outline": [core / "SidebarOutlineConfigureSkip.swift", app / "SidebarOutline.swift", app / "SidebarChromeLayout.swift",
                    scratch / "SidebarItemReference.swift", scratch / "ActionButton.swift",
                    app / "TranslucentButtonFace.swift", app / "PointerCover.swift", app / "ReloadControl.swift",
                    app / "PointingHand.swift", here / "OutlineHeaderTests.swift"],
        "plate": [*plate, *tooltip_sources(root, scratch, plate), here / "PlateGeometryTests.swift"],
    }
    for name, sources in suites.items():
        executable = scratch / name
        subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
print("Pinned section checks passed")
