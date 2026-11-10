#!/usr/bin/env python3
"""Site Control Center (WEB14) production components: model, layout and artwork.

Off-screen hosting only; no browser, page, popover presentation, input or preferences.
Pass a directory to also write light/dark renders for appearance review.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[2]
# The window owner is not compiled here; these are its recovered routes.
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
for use in ('sidebar.onPageMenu = { [weak self] in self?.showSiteControlCenter() }',
            'case .siteInfo, .siteInsecure: self.showSiteControlCenter(from: anchor)',
            'popupChrome.prepareExtensions = { [weak self] in self?.preparePopupSiteControls(requireExtensions: true) }',
            'popupChrome.prepareSiteControls = { [weak self] in self?.preparePopupSiteControls(requireExtensions: false) }',
            'let openControls = preparePopupSiteControls(requireExtensions: false)',
            'self.showSiteControlCenter(from: self.popupChrome.pageControlsAnchor)',
            'if browser.hasPageInfo, page.responds(to: #selector(PCNativePage.openSiteControls(handler:)))',
            'page.responds(to: #selector(PCNativePage.toggleSiteControlsPermission(_:revision:)))',
            'let internalPage = ["chrome", "parc"].contains(page.url?.scheme?.lowercased() ?? "parc")',
            'model.isSecure = internalPage ? nil : page.developerModeSecure',
            'if page.responds(to: #selector(PCNativePage.showCertificate)) {',
            'guard page.canShowCertificate else { return }',
            'let host = page.developerModeSiteHost',
            'let secure = page.developerModeHost != nil && page.developerModeSecure',
            'after: pill ? .milliseconds(anchor.isHiddenOrHasHiddenAncestor ? 100 : 10) : nil,',
            'self.siteControlCenterItems[id]?.showContextMenuInControlCenter()'):
    assert use in controller, f"the window owner no longer routes the Site Control Center: {use}"
assert controller.count(".developerModeHost") == 1, \
    "only the permission rows' web-host gate reads developerModeHost; Developer Mode reads share developerModeSiteHost"
assert "return developerModeExtensionHost?.lowercased()" in controller, \
    "Parc keys Developer Mode by the committed page's host, an extension page's ID included"
# Chromium's desktop PageInfo aborts on extension and internal pages.
facade = (root / "Sources/ParcEngine/ParcEngine.m").read_text()
assert "return !_disposed && self.hasPageInfo && _nativePage.canShowSiteInfo;" in facade, \
    "the facade must refuse site info on pages without PageInfo, whatever the engine"
page_info = (root / "Engine/ParcNative/native_page_info.mm").read_text()
begin = page_info[page_info.index("  bool Begin(SiteControlsHandler handler) {"):]
begin = begin[:begin.index("\n  }\n")]
assert begin.index("if (!HasPageInfo(contents)) return true;") < begin.index("std::make_shared<PageInfo>"), \
    "Site Controls must open without constructing PageInfo where Chromium refuses it"
center = (root / "Sources/ParcApp/SiteControlCenter.swift").read_text()
assert "icon: $0.pinnedArtwork?.image ?? $0.image," in controller \
    and "badge: $0.pinnedArtwork?.badge, badgeText: $0.badgeText)" in controller, \
    "the tiles show the unbadged canvas with the strips' badge, or the baked canvas on older engines"
assert ".accessibilityValue(item.badgeText)" in center, "VoiceOver reads an extension tile's badge, as the strips do"
assert "static let button = CGSize(width: 48, height: 32)" in center, "SCC extension tiles must stay the 48×32"
assert center.count(".fixedSize()") >= 4, "SCC extension tiles must not compress below 48×32"
downloads = (root / "Engine/ParcNative/downloads.cc").read_text()
assert "IsExtensionInstallTransfer" in downloads and "application/x-chrome-extension" in downloads, \
    "CRX/webstore installs must not publish as Library downloads"
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
app = root / "Sources/ParcApp"
with tempfile.TemporaryDirectory(prefix="parc-site-control-center-") as directory:
    scratch = Path(directory)
    executable = scratch / "checks"
    compiled = [*sorted((root / "Sources/ParcCore").glob("*.swift")),
                *[app / name for name in ("ThemeRenderer.swift", "PArcMenuColors.swift", "SidebarPlusMenu.swift",
                                          "LibraryRailTile.swift", "LibraryRailIcon.swift", "DownloadActivityBadge.swift",
                                          "DownloadLibrarySelection.swift", "WindowStandardButtons.swift",
                                          "ExtensionControls.swift", "SiteControlCenter.swift")]]
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
        *map(str, compiled), *map(str, tooltip_sources(root, scratch, compiled)),
        str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    # An unbundled executable's Bundle.main.resourceURL is its own directory.
    shutil.copytree(root / "Resources/SiteControlCenter", scratch / "SiteControlCenter")
    shutil.copytree(root / "Resources/SidebarPlusMenu", scratch / "SidebarPlusMenu")
    subprocess.run([str(executable), *sys.argv[1:2]], check=True)
