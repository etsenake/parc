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
for use in ("scroll.adoptTablistScroller()",
            "    let list = SidebarOutlineView()",
            "let geometry = PageGeometry(hiddenAddressHeight: hiddenAddressHeight, trayHeight: favoritesHeight, hasFavorites: !favorites.isEmpty,",
            "let listY = Chrome.tablistTop(trayHeight: geometry.trayHeight, spaceHeader: !page.header.isHidden, hasFavorites: geometry.hasFavorites) - geometry.hiddenAddressHeight",
            "for slot in Chrome.tablistSlots(pinnedItems: pinnedRows.count, todayItems: itemRows.count,",
            "list.reload(outline, budget:",
            "let listY = Chrome.tablistTop(trayHeight: favoritesHeight, spaceHeader: showsSpaceHeader, hasFavorites: !favorites.isEmpty) - hiddenAddressHeight",
            "page.header.frame = NSRect(x: 0, y: Chrome.SpaceHeader.top(trayHeight: geometry.trayHeight, hasFavorites: geometry.hasFavorites) - geometry.hiddenAddressHeight,",
            "width: width, height: Chrome.SpaceHeader.height)",
            "let headerContent = SidebarChromeLayout.SpaceHeader.content(",
            "spaces: state.spaces, activeSpaceID: state.activeSpaceID, privateWindow: isPrivateBrowsing,",
            "showOnSingleUnnamedSpace: state.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false)",
            "page.header.isHidden = !headerContent.isShown && !page.header.isEditing",
            "page.header.update(headerContent, symbol: space?.customIcon?.image, emoji: space?.customIcon?.emoji)",
            "header.onToggleHeader = { [weak self] in self?.toggleSpaceHeaderOnSingleUnnamedSpaces?() }",
            "header.canShowHeaderButtonsIfPossible = true",
            "page.header.applyStyle(dark: palette.isDark, tint: themed ? palette.maxContrastColor : nil)",
            "extensionToolbar, pageStrip, miniPlayers]",
            "view.addSubview(header); view.addSubview(scroll)",
            "self.onRenameSpace?(id)",
            "header.onEditTheme = { [weak self] in self?.onEditTheme?() }",
            "header.onNewFolder = { [weak self] in self?.onNewFolder?() }",
            "let end = spaceHeader.isHidden ? scroll.frame.minY : spaceHeader.frame.minY",
            "height: max(0, end - top))",
            "let dockMenu = previousSpaceMenus[spaceID] ?? SidebarDockItemMenu { [weak self] in self?.dockSpaceMenu(spaceID) }",
            "dockMenu.install(on: button)",
            "spaceMenusByID[space.id]?.install(on: button)",
            "let shown = SidebarChromeLayout.dockShowsSpaces(",
            "spacesHost.items = shown ? spaceButtons + (creating ? [creationSpaceButton] : []) : []",
            "SidebarSpaceMenu.dock(spaces: spaces, spaceID: id, activeSpaceID: activeSpaceID, creatingSpace: creationView != nil,",
            "showOnSingleUnnamedSpace: hierarchyState?.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false,",
            "rename: { [weak self] id in self?.onRenameSpace?(id) },",
            "editTheme: { [weak self] in self?.onEditTheme?() },",
            "newFolder: { [weak self] in self?.onNewFolder?() },",
            "toggleHeader: { [weak self] in self?.toggleSpaceHeaderOnSingleUnnamedSpaces?() })"):
    assert use in sidebar, f"SidebarView no longer lays its list out by the checked model: {use}"
for use in ("SidebarChromeLayout.hiddenAddressHeight(toolbar: usesContentToolbar,",
            "hasPrompt: paymentWidth > 0, keyboardSearch: keyboardSearchActive)",
            "favoritesHost.frame = NSRect(x: 0, y: Chrome.headerBottom - hiddenAddressHeight,",
            "framed.hiddenAddressHeight == pageGeometry.hiddenAddressHeight",
            "page.framed = (bounds.size, geometry.hiddenAddressHeight, geometry.trayHeight, geometry.hasFavorites, geometry.bottom)",
            "var framed: (size: NSSize, hiddenAddressHeight: CGFloat, trayHeight: CGFloat, hasFavorites: Bool, bottom: CGFloat)?"):
    assert use in sidebar, f"the collapsed URL row no longer participates in every Space page's layout: {use}"
assert "func makeMenu() -> NSMenu { spaceMenu?.makeMenu() ?? NSMenu() }" in (app / "SidebarSpaceHeader.swift").read_text(), \
    "the Space header no longer builds the shared Space menu"
for use in ("if isEditing { finishNameEditing(cancelled: false); return }",
            "guard let event = NSApp.currentEvent else { return }",
            "NSMenu.popUpContextMenu(makeMenu(), with: event, for: editButton)"):
    assert use in (app / "SidebarSpaceHeader.swift").read_text(), f"the edit button's click path changed: {use}"
assert "final class SidebarView: SidebarSpaceMenuSurface, NSMenuItemValidation, OffscreenPresenting {" in sidebar, \
    "SidebarView no longer takes the checked Space menu surface"
assert "spaceMenu = { [weak self] in self?.sidebarSpaceMenu() }" in sidebar, "SidebarView no longer supplies its Space menu"
sidebar_menu = re.search(r"private func sidebarSpaceMenu\(\) -> SidebarSpaceMenu\? \{\n(.*?)\n    \}\n", sidebar, re.S)
assert sidebar_menu, "SidebarView.sidebarSpaceMenu not found"
for use in ("SidebarSpaceMenu.sidebar(spaces: spaces, activeSpaceID: activeSpaceID, creatingSpace: creationView != nil,",
            "privateWindow: isPrivateBrowsing,",
            "showOnSingleUnnamedSpace: hierarchyState?.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false,",
            "rename: { [weak self] id in self?.onRenameSpace?(id) },",
            "editTheme: { [weak self] in self?.onEditTheme?() },",
            "newFolder: { [weak self] in self?.onNewFolder?() },",
            "toggleHeader: { [weak self] in self?.toggleSpaceHeaderOnSingleUnnamedSpaces?() })"):
    assert use in sidebar_menu.group(1), f"SidebarView's Space menu no longer follows the checked rule: {use}"
sidebar_class = sidebar[sidebar.index("final class SidebarView:"):sidebar.index("private final class SidebarKeyboardHighlightView")]
for override in ("override func menu(for", "override func rightMouseDown("):
    assert override not in sidebar_class, f"SidebarView overrides the checked surface's event handling: {override}"
assert sidebar_class.count("override func mouseDown(") == 1, \
    "SidebarView's one mouseDown: (the tablist background's) is missing, moved out of the class, or joined by another"
press_start = sidebar_class.index("override func mouseDown(")
press = " ".join(sidebar_class[press_start:sidebar_class.index("\n    }\n", press_start)].split())
for use in ("guard let window, isTablistBackground(event) else { super.mouseDown(with: event); return }",
            "switch SidebarTablistBackground.press(clickCount: event.clickCount, modifiers: event.modifierFlags)",
            "case .passThrough: super.mouseDown(with: event)"):
    assert use in press, f"a press SidebarView doesn't drag with no longer reaches the Space menu surface: {use}"
controller = (app / "BrowserWindowController.swift").read_text()
assert "sidebar.toggleSpaceHeaderOnSingleUnnamedSpaces = { [weak self] in self?.store.toggleSpaceHeaderOnSingleUnnamedSpaces() }" in controller, \
    "BrowserWindowController no longer records the Space header toggle in the store"
store = (root / "Sources/ParcCore/BrowserStore.swift").read_text()
core_sources = re.search(r"^core_sources=\((.*?)^\)", (root / "scripts/test.sh").read_text(), re.S | re.M)
assert core_sources, "scripts/test.sh no longer lists core_sources"
store_sources = [root / "Sources/ParcCore" / name for name in re.findall(r"Sources/ParcCore/(\w+\.swift)", core_sources.group(1))]
assert "BrowserStore.swift" in {path.name for path in store_sources}, "scripts/test.sh core_sources no longer compiles BrowserStore"
reference = re.search(r"^enum SidebarItemReference\b.*?^\}\n", store, re.S | re.M)
assert reference, "SidebarItemReference not found in BrowserStore.swift"
sources_by_name = {path.name: path.read_text() for path in
                   [app / "SidebarChromeLayout.swift", app / "SidebarSpaceHeader.swift", app / "SidebarSpaceMenu.swift",
                    root / "Sources/ParcCore/BrowserStore.swift"]}
negatives = [("chrome", "visibility at two Spaces", "SidebarChromeLayout.swift", "spaceCount >= 2", "spaceCount >= 3"),
             ("chrome", "header inset 0 with the header", "SidebarChromeLayout.swift",
              "trayHeight : spaceHeader ? 0 : headerBottomSpacing", "trayHeight : headerBottomSpacing"),
             ("chrome", "the setting in the visibility rule", "SidebarChromeLayout.swift",
              "(showOnSingleUnnamedSpace || spaceCount >= 2", "(spaceCount >= 2"),
             ("chrome", "the toggle's single-Space condition", "SidebarChromeLayout.swift",
              "guard spaceCount == 1, !titled", "guard spaceCount >= 1, !titled"),
             ("chrome", "the edit button's editing width", "SidebarChromeLayout.swift",
              "shown ? (editing ? max(30, ceil(titleWidth) + 4) : 24) : 0", "shown ? 24 : 0"),
             ("chrome", "the Done button's room for its title", "SidebarChromeLayout.swift",
              "shown ? (editing ? max(30, ceil(titleWidth) + 4) : 24) : 0", "shown ? (editing ? 30 : 24) : 0"),
             ("header", "double-click rename on the header", "SidebarSpaceHeader.swift",
              "            onRenameSpace?(); return\n", ""),
             ("chrome", "the header-buttons gate", "SidebarChromeLayout.swift",
              "(editing || hovered) && canShowHeaderButtons", "(editing || hovered)"),
             ("chrome", "the 0.1 s hover-in delay", "SidebarChromeLayout.swift",
              "-> Double { hovered ? 0.1 : 0 }", "-> Double { 0 }"),
             ("chrome", "one iconless Space omitted from the dock", "SidebarChromeLayout.swift",
              "creating || count > 1 || anyCustomIcon", "creating || count > 0 || anyCustomIcon"),
             ("chrome", "the divider only with Today items", "SidebarChromeLayout.swift",
              "todayItems > 0 ? [.sectionDivider] : []", "[.sectionDivider]"),
             ("header", "sidebarSpaceName identifier", "SidebarSpaceHeader.swift",
              "nameField.cell?.setAccessibilityIdentifier(Self.nameIdentifier)", ""),
             ("header", "the model's name frame", "SidebarSpaceHeader.swift", "} else { titleFrame = frames.title }",
              "} else { titleFrame = frames.title.offsetBy(dx: -2, dy: 0) }"),
             ("header", "the placeholder as AppKit's placeholder", "SidebarSpaceHeader.swift",
              'title: space.title ?? "",', "title: titled ? space.name : placeholderTitle(position: position),"),
             ("header", "the mask's editable gate", "SidebarSpaceHeader.swift",
              "if apply, isMaskingEnabled, isEditable, let cell {", "if apply, isMaskingEnabled, let cell {"),
             ("header", "the menu's header toggle", "SidebarSpaceMenu.swift",
              "+ (toggleTitle.map { [($0, toggleHeader)] } ?? [])", ""),
             ("header", "sidebarSpaceEditButton identifier", "SidebarSpaceHeader.swift",
              "editButton.cell?.setAccessibilityIdentifier(Self.editButtonIdentifier)", ""),
             ("header", "key-window-only hover tracking", "SidebarSpaceHeader.swift",
              "[.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect]",
              "[.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]"),
             ("header", "the header's hover delay", "SidebarSpaceHeader.swift",
              "let delay = SidebarChromeLayout.SpaceHeader.editButtonHoverDelay(hovered: isHovered)", "let delay = 0.0"),
             ("header", "the hover fill only while hovered", "SidebarSpaceHeader.swift",
              "(isHovered && isEnabled ? hoveredBackgroundColor : .clear).cgColor", "hoveredBackgroundColor.cgColor"),
             ("header", "hiding by alpha, never setHidden", "SidebarSpaceHeader.swift",
              "guard animated else { editButton.alphaValue = alpha; return }",
              "guard animated else { editButton.isHidden = !shown; return }"),
             ("header", "the shown button as a hit target", "SidebarSpaceHeader.swift",
              "if hit === editButton || isEditing && (hit === nameField || hit.isDescendant(of: nameField)) { return hit }",
              "_ = hit"),
             ("dockmenu", "the dock menu's header toggle", "SidebarSpaceMenu.swift",
              "+ (toggleTitle.map { [($0, toggleHeader)] } ?? [])", ""),
             ("dockmenu", "the toggle's action", "SidebarSpaceMenu.swift",
              "showOnSingleUnnamedSpace: showOnSingleUnnamedSpace),\n                                toggleHeader: toggleHeader)",
              "showOnSingleUnnamedSpace: showOnSingleUnnamedSpace),\n                                toggleHeader: nil)"),
             ("dockmenu", "no menu while a Space is created", "SidebarSpaceMenu.swift",
              "guard !creatingSpace, let position", "guard let position"),
             ("dockmenu", "the item's own Space for Rename Space…", "SidebarSpaceMenu.swift",
              "rename: { rename(spaceID) },", "rename: { rename(activeSpaceID ?? spaceID) },"),
             ("dockmenu", "the theme editor only for the active Space", "SidebarSpaceMenu.swift",
              "editTheme: active ? editTheme : nil,", "editTheme: editTheme,"),
             ("dockmenu", "the toggle from the item's own Space", "SidebarSpaceMenu.swift",
              "titled: space.title != nil,", "titled: false,"),
             ("dockmenu", "the button's menu removed while there is none", "SidebarSpaceMenu.swift",
              "button.menu = nil; menu.removeAllItems()", "menu.removeAllItems()"),
             ("dockmenu", "the menu rebuilt as it opens", "SidebarSpaceMenu.swift",
              "if let spaceMenu = provide() { spaceMenu.populate(menu) } else { menu.removeAllItems() }", "_ = menu"),
             ("listmenu", "the surface's Space menu", "SidebarSpaceMenu.swift",
              "override func menu(for event: NSEvent) -> NSMenu? { spaceMenu?()?.makeMenu() }",
              "override func menu(for event: NSEvent) -> NSMenu? { nil }"),
             ("listmenu", "the active Space's menu", "SidebarSpaceMenu.swift",
              "return dock(spaces: spaces, spaceID: activeSpaceID,", "return dock(spaces: spaces, spaceID: spaces.first?.id ?? activeSpaceID,"),
             ("listmenu", "no list menu while a Space is created", "SidebarSpaceMenu.swift",
              "guard !creatingSpace, let position", "guard let position"),
             ("listmenu", "the list menu's toggle action", "SidebarSpaceMenu.swift",
              "newFolder: newFolder, toggleHeader: toggleHeader)", "newFolder: newFolder, toggleHeader: nil)"),
             ("setting", "the store's toggle", "BrowserStore.swift",
              "$0.showSpaceHeaderOnSingleUnnamedSpaces = !($0.showSpaceHeaderOnSingleUnnamedSpaces ?? false)",
              "$0.showSpaceHeaderOnSingleUnnamedSpaces = true")]
with tempfile.TemporaryDirectory(prefix="parc-sidebar-chrome-") as directory:
    item_reference = Path(directory) / "SidebarItemReference.swift"
    item_reference.write_text("import Foundation\n" + reference.group(0))
    action_button = Path(directory) / "ActionButton.swift"
    action_button.write_text(sidebar[:sidebar.index("final class MenuAction")])
    tooltips = tooltip_sources(root, Path(directory), store_sources)
    theme_palette = next((path for path in tooltips if Path(path).name == "TooltipThemePalette.swift"), None)
    assert theme_palette, "tests/Tooltip/support.py no longer cuts the ThemeRenderer palette slice"
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
        subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
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
    for index, (suite, rule, file, original, mutated) in enumerate(negatives):
        source = sources_by_name[file]
        assert source.count(original) == 1, f"negative control target not found once: {original}"
        copy = Path(directory) / f"mutant-{index}" / file
        copy.parent.mkdir()
        copy.write_text(source.replace(original, mutated))
        sources = [copy if path.name == file else path for path in suites[suite]]
        try:
            failed = subprocess.run([str(build(f"negative-{index}", sources))], capture_output=True, text=True,
                                    timeout=60).returncode != 0
        except subprocess.TimeoutExpired:
            failed = True
        assert failed, f"negative control passed: reverting {rule} left the {suite} suite green"
        print(f"negative control: reverting {rule} fails the {suite} suite as expected")
