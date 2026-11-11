#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
app = root / "Sources/ParcApp"
sidebar = (app / "SidebarView.swift").read_text()
for use in ("private let addressBackground = SidebarAddressPillView()",
            "addressBackground.dark = palette.isDark",
            "toggle.translucentFace = TranslucentButtonFace(view: toggle)",
            "glyphPointSize: SidebarChromeLayout.navigationGlyphPointSize)",
            "let glyph = Chrome.navigationGlyphPointSize(buttonSide: (bar.back ?? bar.toggle)?.height ?? Chrome.dockButtonSide)",
            "let revealed = SidebarAddressButtonsReveal.revealed(sidebarHovered: pointerInSidebar || addressControlFocused,",
            "showingMenu: showingAddressMenu || !addressPopovers.isEmpty,",
            "SidebarAddressButtonsReveal.showsSiteControlCenter(revealed: revealed, copyQuoteLink: showsSharedQuote)",
            "SidebarAddressButtonsReveal.apply(revealed, to: extensionToolbar, animated: animated)",
            "if sidebarFloating != floating { sidebarFloating = floating; updateAddressButtonsReveal() }",
            "return responder === addressButton || responder === pageActions || responder.isDescendant(of: extensionToolbar)",
            "firstResponderObservation = window?.observe(\\.firstResponder, options: [.new])",
            "        observeFirstResponder()\n",
            "pageActions.hitTestsWhenTransparent = false",
            "extensionToolbar.hitTestsWhenTransparent = false",
            "reloadOptions.windowControlStyle = true",
            "addressBackground.style = .urlBar",
            "shareQuote.contentTintColor = palette?.maxContrastColor ?? .labelColor",
            "copyQuote.contentTintColor = palette?.maxContrastColor ?? .labelColor",
            ".font: NSFont.systemFont(ofSize: SidebarChromeLayout.addressFontSize), .foregroundColor: color, .paragraphStyle: paragraph,",
            "paragraph.firstLineHeadIndent = empty ? SidebarAddressSearchIcon.textIndent : SidebarChromeLayout.addressTextIndent",
            "let empty = address == SidebarAddressSearchIcon.placeholder",
            "addressSearchIcon.isHidden = !empty; addressSearchIcon.contentTintColor = color",
            "addressSearchIcon.isHidden = true; addressButton.addSubview(addressSearchIcon)",
            "(palette?.isDark == true ? NSColor.white : NSColor.black).withAlphaComponent(0.6)",
            "addressButton.focusRingCornerRadius = SidebarAddressPillView.cornerRadius"):
    assert use in sidebar, f"SidebarView no longer wires the header through the checked types: {use}"
quote_layout = sidebar[sidebar.index("        addressBackground.frame = field"):sidebar.index("        let iconSide = SidebarAddressSearchIcon.side")]
assert quote_layout.count("addressBackground.frame") == 1, "quote mode must not shrink or reposition the full URL pill"
assert "height: Chrome.fieldHeight)" in sidebar and "static let fieldHeight: CGFloat = 36" in (app / "SidebarChromeLayout.swift").read_text()
for use in ("addressButton.frame.size.height = 18",
            "shareQuote.frame = NSRect(x: field.minX + 13.5, y: field.minY + 18,",
            "shareQuote.alignment = .left; shareQuote.font = .systemFont(ofSize: 13, weight: .semibold)",
            "shareQuote.refusesFirstResponder = true; copyQuote.refusesFirstResponder = true",
            "shareQuote.actionBlock = action; copyQuote.actionBlock = action"):
    assert use in sidebar, f"the full-height quote pill lost its two-line presentation or original selection: {use}"
for kind in ("Entered", "Exited"):
    assert (f"guard let revealTracking, event.trackingArea === revealTracking else {{ super.mouse{kind}(with: event); return }}"
            in sidebar), f"the sidebar's mouse{kind} must not match a nil tracking area"
assert "addressBackground.layer?.backgroundColor" not in sidebar, "the palette must not overwrite the pill's own fill"
controller = (app / "BrowserWindowController.swift").read_text()
assert "for view in [addressBackground, addressButton, pageActions, extensionToolbar] as [NSView] {\n                view.isHidden = usesContentToolbar" \
    in sidebar, "the Toolbar no longer hides exactly the URL bar group"
assert "showsNavigation: !usesContentToolbar && !navigationInContentToolbar," in sidebar, \
    "a pane bar no longer takes the header's Back/Forward/Reload"
assert controller.count("applySidebarToolbarOwnership()") == 3 and \
    "sidebar.usesContentToolbar = !sidebarShowsAddressBar\n        sidebar.navigationInContentToolbar = selectedBrowserToolbar != nil" \
    in controller, "the window no longer derives the URL bar and navigation owners separately"
assert "PaneTopBarAdmission.sidebarAddressBarShown(focusedHasTopBar: selectedBrowserToolbar != nil,\n" \
       "                                                   toolbarVisible: BrowserToolbarPreferences.shared.state.isVisible)" \
    in controller, "the URL bar's visibility no longer follows the Toolbar preference"
assert sidebar.count("Self.address(of: state.tabs.first { $0.id == (focusedTabID ?? state.selectedTabIDs.first) })") == 2 \
    and "SidebarAddressSearchIcon.host(of: url) ?? SidebarAddressSearchIcon.placeholder" in sidebar, \
    "both address paths no longer show the www-less host or its empty URL bar text"
pill = (app / "SidebarAddressPill.swift").read_text()
assert 'static let placeholder = "Search or Enter URL…"' in pill and '"magnifyingglass"' in pill \
    and "override func hitTest(_ point: NSPoint) -> NSView? { nil }" in pill[pill.index("class SidebarAddressSearchIcon"):], \
    "the empty URL bar's glyph no longer matches the or lets clicks through to the URL bar"
assert "if sidebar.isPresented && sidebarShowsAddressBar {\n            return .sidebar(" in controller, \
    "extension popups no longer anchor at the visible sidebar URL bar"
assert controller.count("if anchor === sidebar.pageControlsAnchor { sidebar.setAddressPopover(controller, open: true) }") == 1, \
    "the pill popover no longer holds its buttons revealed"
assert controller.count("self.sidebar.setAddressPopover(controller, open: false)") == 2, "close and detach must release the reveal hold"
anchor_body = controller[controller.index("func sitePermissionAnchor(forPage page: NSView) -> NSDictionary? {"):]
anchor_body = anchor_body[:anchor_body.index("\n    }\n")]
assert "if anchor === sidebar.pageControlsAnchor { holdAddressButtonsForPermissionPrompt() }" in anchor_body, \
    "a permission prompt from the pill no longer holds its buttons revealed"
for use in ("let hold = AddressPopoverRevealHold { [weak self] in",
            "self.sidebar.setAddressPopover(owner, open: false)",
            "sidebar.setAddressPopover(owner, open: true)",
            "addressPromptHolds.values.forEach { $0.end() }"):
    assert use in controller, f"the permission-prompt reveal hold is no longer wired: {use}"
reload = (app / "ReloadControl.swift").read_text()
assert "rasterized ? NavigationControlArtwork.symbol(name, pointSize: pointSize)" in reload, "the toolbar reload must stay a vector symbol"
navigation = (app / "NavigationControls.swift").read_text()
for use in ("if glyphPointSize != nil { translucentFace = TranslucentButtonFace(view: self) }",
            "face.setPressed(isHighlighted && isEnabled)",
            "reloadGlyph.draw(in: bounds, tint: tint, press: face.pressProgress, in: self)",
            "face.drawGlyph(image, tint: tint, in: bounds, shiftX: pressedArrowShift * face.pressProgress, view: self)",
            'symbol == "arrow.left" ? -3 : symbol == "arrow.right" ? 3 : 0',
            "rasterized: glyphPointSize != nil)",
            "if window !== newWindow { press?.cancel(); hovering = false }"):
    assert use in navigation, f"NavigationControlButton no longer draws its TranslucentButton face: {use}"
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
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/SpaceTheme.swift"), str(scratch / "SplitOrientation.swift"),
                    *[str(scratch / name) for name in slices],
                    str(app / "ExtensionControls.swift"), str(scratch / "SiteControlCenterArtwork.swift"),
                    str(app / "NavigationControlPress.swift"), str(app / "ReloadControl.swift"),
                    str(app / "TranslucentButtonFace.swift"), str(app / "SidebarAddressPill.swift"),
                    str(app / "SidebarChromeLayout.swift"), str(app / "PArcMenuColors.swift"),
                    *map(str, tooltip_sources(root, scratch, ["SpaceTheme.swift", "ThemeRenderer.swift", "ReloadControl.swift"])),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=120)
