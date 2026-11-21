#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
here = Path(__file__).parent
app = root / "Sources/ParcApp"
core = root / "Sources/ParcCore"
sidebar = (app / "SidebarView.swift").read_text()
store = (root / "Sources/ParcCore/BrowserStore.swift").read_text()
core_sources = re.search(r"^core_sources=\((.*?)^\)", (root / "scripts/test.sh").read_text(), re.S | re.M)
store_sources = [root / "Sources/ParcCore" / name for name in re.findall(r"Sources/ParcCore/(\w+\.swift)", core_sources.group(1))]
reference = re.search(r"^enum SidebarItemReference\b.*?^\}\n", store, re.S | re.M)
with tempfile.TemporaryDirectory(prefix="parc-sidebar-chrome-") as directory:
    item_reference = Path(directory) / "SidebarItemReference.swift"
    item_reference.write_text("import Foundation\n" + reference.group(0))
    action_button = Path(directory) / "ActionButton.swift"
    action_button.write_text(sidebar[:sidebar.index("final class MenuAction")])
    tooltips = tooltip_sources(root, Path(directory), store_sources)
    theme_palette = next((path for path in tooltips if Path(path).name == "TooltipThemePalette.swift"), None)
    suites = {"chrome": [app / "SidebarChromeLayout.swift", here / "SidebarChromeLayoutTests.swift"],
              "header": [*store_sources, app / "SidebarChromeLayout.swift", app / "SidebarSpaceMenu.swift", app / "SidebarSpaceHeader.swift",
                         app / "SidebarRowAppearance.swift", here / "SidebarSpaceHeaderTests.swift", *tooltips],
              "dockmenu": [*store_sources, app / "SidebarChromeLayout.swift", app / "SidebarSpaceMenu.swift", app / "SidebarDockStrip.swift",
                           app / "SidebarRowAppearance.swift", theme_palette, app / "SidebarAccessibility.swift", here / "SidebarDockMenuTests.swift"],
              "listmenu": [*store_sources, core / "SidebarOutlineConfigureSkip.swift",
                           app / "SidebarChromeLayout.swift", app / "SidebarSpaceMenu.swift", app / "SidebarOutline.swift",
                           app / "SidebarTablist.swift", action_button, app / "PointingHand.swift", app / "TranslucentButtonFace.swift", app / "PointerCover.swift",
                           app / "ReloadControl.swift", here / "SidebarListMenuTests.swift"],
              "setting": [*store_sources, here / "SpaceHeaderSettingTests.swift"]}
    def build(name, sources):
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        return executable
    for name, sources, runs in [("chrome", suites["chrome"], [[]]),
                                ("header", suites["header"], [[]]),
                                ("dockmenu", suites["dockmenu"], [[]]),
                                ("listmenu", suites["listmenu"], [[]]),
                                ("setting", suites["setting"], [[]]),
                                ("tablist", [core / "SidebarOutlineConfigureSkip.swift",
                                             app / "SidebarChromeLayout.swift", app / "SidebarTablist.swift", app / "SidebarOutline.swift",
                                             item_reference, here / "SidebarTablistTests.swift"], [[], ["-AppleShowScrollBars", "Always"]]),
                                ("strip", [app / "SidebarChromeLayout.swift", app / "SidebarDockStrip.swift", app / "SidebarRowAppearance.swift",
                                           theme_palette, core / "SpaceTheme.swift",
                                           app / "SidebarAccessibility.swift", here / "SidebarDockStripTests.swift"], [[]])]:
        executable = build(name, sources)
        for arguments in runs:
            subprocess.run([str(executable), *arguments], check=True)
