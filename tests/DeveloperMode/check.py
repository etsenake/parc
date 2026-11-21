#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
with tempfile.TemporaryDirectory(prefix="parc-developer-mode-") as directory:
    scratch = Path(directory)
    source = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    support = scratch / "ActionButton.swift"
    support.write_text(source[:source.index("final class MenuAction")]
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    artwork_source = (root / "Sources/ParcApp/SiteControlCenter.swift").read_text()
    artwork = scratch / "SiteControlCenterArtwork.swift"
    artwork.write_text("import AppKit\n" + artwork_source[artwork_source.index("@MainActor enum SiteControlCenterArtwork")
                                                          :artwork_source.index("enum SiteControlCenterMetrics")])
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/DeveloperToolbarLayout.swift"),
                    str(root / "Sources/ParcApp/DeveloperMode.swift"),
                    str(root / "Sources/ParcApp/DeveloperToolbarControls.swift"),
                    str(support), str(artwork), str(root / "Sources/ParcApp/TranslucentButtonFace.swift"),
                    str(root / "Sources/ParcApp/BlockedPageContent.swift"),
                    str(root / "Sources/ParcApp/BlockedContentSign.swift"),
                    str(root / "Sources/ParcApp/ReloadControl.swift"), str(Path(__file__).with_name("main.swift")),
                    *map(str, tooltip_sources(root, scratch, ["ReloadControl.swift"])),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
