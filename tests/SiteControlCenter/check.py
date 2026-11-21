#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
app = root / "Sources/ParcApp"
with tempfile.TemporaryDirectory(prefix="parc-site-control-center-") as directory:
    scratch = Path(directory)
    executable = scratch / "checks"
    compiled = [*sorted((root / "Sources/ParcCore").glob("*.swift")),
                *[app / name for name in ("ThemeRenderer.swift", "ParcMenuColors.swift", "SidebarPlusMenu.swift",
                                          "LibraryRailTile.swift", "LibraryRailIcon.swift", "DownloadActivityBadge.swift",
                                          "DownloadLibrarySelection.swift", "WindowStandardButtons.swift",
                                          "ExtensionControls.swift", "SiteControlCenter.swift", "ParcContextMenu.swift",
                                          "BlockedPageContent.swift", "SiteControlCenterBlockedView.swift")]]
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
        "-import-objc-header", str(root / "Engine/ParcNative/native_appkit_bridge.h"),
        *map(str, compiled), *map(str, tooltip_sources(root, scratch, compiled)),
        str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    shutil.copytree(root / "Resources/SiteControlCenter", scratch / "SiteControlCenter")
    shutil.copytree(root / "Resources/SidebarPlusMenu", scratch / "SidebarPlusMenu")
    subprocess.run([str(executable), *sys.argv[1:2]], check=True)
