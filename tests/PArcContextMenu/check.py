#!/usr/bin/env python3
"""Parc's extension context menu (PArcContextMenu): placement, rows, keys, pointer and dispatch.

Off-screen windows under a prohibited activation policy; no browser, engine or input devices.
Pass a directory to also write light/dark renders of the Site Control Center with the menu open.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
app = root / "Sources/ParcApp"
with tempfile.TemporaryDirectory(prefix="parc-arc-context-menu-") as directory:
    scratch = Path(directory)
    executable = scratch / "checks"
    compiled = [*sorted((root / "Sources/ParcCore").glob("*.swift")),
                *[app / name for name in ("ThemeRenderer.swift", "PArcMenuColors.swift", "SidebarPlusMenu.swift",
                                          "LibraryRailTile.swift", "LibraryRailIcon.swift", "DownloadActivityBadge.swift",
                                          "DownloadLibrarySelection.swift", "WindowStandardButtons.swift",
                                          "ExtensionControls.swift", "SiteControlCenter.swift", "PArcContextMenu.swift")]]
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
        "-import-objc-header", str(root / "Engine/ParcNative/native_appkit_bridge.h"),
        *map(str, compiled), *map(str, tooltip_sources(root, scratch, compiled)),
        str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    shutil.copytree(root / "Resources/SiteControlCenter", scratch / "SiteControlCenter")
    shutil.copytree(root / "Resources/SidebarPlusMenu", scratch / "SidebarPlusMenu")
    subprocess.run([str(executable), *sys.argv[1:2]], check=True)
