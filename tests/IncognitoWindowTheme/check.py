#!/usr/bin/env python3
"""the static incognito WindowTheme: the private window's opaque surface,
brand palette and URL bar fill on the production ThemeRendererView and
SidebarAddressPillView, plus the controller and sidebar wiring that gives
them to a private window. An off-screen window that is never ordered in or
made key; no browser, input or preferences."""
from pathlib import Path
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
controller = (app / "BrowserWindowController.swift").read_text()
#
# Space's theme.
for use in ("        let incognitoTheme = store.isEphemeral && !popup\n"
            "        rootView.incognito = incognitoTheme; sidebarContainer.incognito = incognitoTheme\n",
            "TooltipController.controller(for: window).palette = TooltipColorPalette(theme: self.rootView.paletteTheme)",
            "        rootView.incognito = incognitoTheme; sidebarContainer.incognito = incognitoTheme\n"
            "        toasts.basicBackground = windowBasicBackground\n",
            "private var windowBasicBackground: NSColor? { rootView.incognito ? IncognitoWindowTheme.background : nil }",
            "theme: rootView.theme, basicBackground: windowBasicBackground) : nil",
            "self.shortcutHint?.update(theme: self.rootView.theme, basicBackground: self.windowBasicBackground)",
            "canEdit: commandID != nil, theme: rootView.theme, basicBackground: windowBasicBackground)",
            "private var windowPaletteTheme: SpaceTheme { rootView.incognito ? IncognitoWindowTheme.paletteTheme : activeSpace.theme }",
            "NavigationHistoryController(page: page, snapshot: snapshot, window: window,\n                    theme: self.windowPaletteTheme)",
            "RecentTabSwitcher(items: items, currentTabIDs: sourceIDs, parent: window, theme: windowPaletteTheme,",
            "completion(.closed(self.recentSwitcherItems(available, in: window), theme: self.windowPaletteTheme))",
            "DownloadReviewController(review: snapshot, theme: activeSpace.theme, incognito: rootView.incognito)"):
    assert use in controller, f"a private window no longer takes the incognito theme: {use}"
assert controller.count(".incognito = ") == 2, "only the window's own two surfaces are incognito"
review = (app / "DownloadReviewController.swift").read_text()
assert ("        if incognito { panel.appearance = NSAppearance(named: .darkAqua) }\n"
        "        super.init(window: panel)\n"
        "        root.incognito = incognito\n"
        "        root.theme = theme\n") in review, "a private window's download review no longer draws the incognito theme"
assert "        if store.isEphemeral { window.appearance = NSAppearance(named: .darkAqua);" in controller, \
    "the incognito theme's window appearance is .single(.dark)"
sidebar = (app / "SidebarView.swift").read_text()
assert "    var isPrivateBrowsing = false { didSet { addressBackground.incognito = isPrivateBrowsing } }\n" in sidebar, \
    "the private sidebar's URL bar no longer takes the incognito fill"
with tempfile.TemporaryDirectory(prefix="parc-incognito-window-theme-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/SpaceTheme.swift"), str(app / "ThemeRenderer.swift"),
                    str(app / "SidebarAddressPill.swift"), str(Path(__file__).with_name("main.swift")),
                    "-o", str(executable)], check=True)
    shutil.copytree(root / "Resources/FloatingSidebar", Path(directory) / "FloatingSidebar")
    shutil.copytree(root / "Resources/ThemeTextures", Path(directory) / "ThemeTextures")
    subprocess.run([str(executable)], check=True, timeout=120)
print("IncognitoWindowTheme check passed")
