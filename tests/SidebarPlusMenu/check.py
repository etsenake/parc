#!/usr/bin/env python3
"""Dock plus HUD: the New Space / Folder / Easel / Note / Split / Tab menu.

Off-screen AppKit windows, including a key child HUD. No browser, input or preferences.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
plus = (root / "Sources/ParcApp/SidebarPlusMenu.swift").read_text()
for use in (
    'private let footerMore = ActionButton("New Tab, Folder, or Space")\n',
    "private let plusMenu = SidebarPlusMenuController()",
    "footerMore.actionBlock = { [weak self] in self?.showPlusMenu() }",
    "private func showPlusMenu()",
    "SidebarPlusMenuModel.rows(",
    "case .space: self.onNewSpace?()",
    "case .folder: self.onNewFolder?()",
    "case .easel: self.onNewEasel?()",
    "case .note: self.onNewNote?()",
    "case .split: self.onNewSplit?()",
    "case .tab: self.onNewTab?()",
):
    assert use in sidebar, f"SidebarView no longer presents the plus HUD: {use}"
for gone in ("func showFooterMenu()", 'ActionButton("Space actions"', "Tab previews"):
    assert gone not in sidebar, f"SidebarView still presents the Space context menu from plus: {gone}"
for use in (
    "sidebar.onNewEasel = { [weak self] in self?.createEaselFromPlusMenu() }",
    "sidebar.onNewSplit = { [weak self] in self?.toggleSplit() }",
    "sidebar.plusMenuCanCreateEasel = { [weak self] in self?.canCreateNote ?? false }",
    "sidebar.onNewNote = { [weak self] in self?.createNote() }",
    "sidebar.plusMenuCanCreateNote = { [weak self] in self?.canCreateNote ?? false }",
    "func createEaselFromPlusMenu()",
):
    assert use in controller, f"the window no longer wires the plus HUD: {use}"
assert 'row(.note, "New Note", "doc.text", "createNote:", canCreateNote' in plus
#
for use in (
    "static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)",
    "static let shortcutFont = NSFont.systemFont(ofSize: 13, weight: .regular)",
    "private static let shortcutKern: CGFloat = 2",
    "NSAttributedString(string: row.shortcut, attributes: [\n            .font: Self.shortcutFont, .kern: Self.shortcutKern,",
    ".font: Self.titleFont, .foregroundColor: titleColor",
):
    assert use in plus, f"the plus HUD rows no longer use PArcMenu's fonts: {use}"
assert "NSAppearance(named:" not in plus and ".appearance = " not in plus, "the HUD forces no appearance of its own"
assert "appearanceSource" not in plus, "like the PArcMenu, the HUD keeps AppKit's default appearance source, the app"
#
navigation = (root / "Sources/ParcApp/NavigationControls.swift").read_text()
history = navigation[navigation.index("private final class NavigationHistoryFill"):]
for use in (
    "init(page: PCNativePage, snapshot: PCNativeNavigationHistory, window: NSWindow, theme: SpaceTheme) {",
    "colors = PArcMenuColors(theme: theme)",
    "base = NavigationHistoryFill(color: colors.base)",
    "tint = NavigationHistoryFill(color: colors.background)",
    "override func updateLayer() { layer?.backgroundColor = color.cgColor }",
    "view.hoverColor = colors.hover",
    "let primary = colors.title",
):
    assert use in history, f"the history chooser no longer resolves PArcMenu colours like the plus HUD: {use}"
for gone in ("palette.isDark", ".appearance = ", "NSAppearance(named:", "appearanceSource", "ThemeChromePalette"):
    assert gone not in history, f"the history chooser still picks its own light/dark half: {gone}"
assert ("NavigationHistoryController(page: page, snapshot: snapshot, window: window,\n"
        "                    theme: self.windowPaletteTheme)") in controller \
    and "private var windowPaletteTheme: SpaceTheme { rootView.incognito ? IncognitoWindowTheme.paletteTheme : activeSpace.theme }" in controller, \
    "the window hands the history chooser its Space theme, or the incognito theme in a private window"
# The window's live theme reaches the HUD, including while it is open. A
#
assert "sidebar.plusMenuTheme = rootView.paletteTheme" in controller.split("private func applyChromeTheme(", 1)[1].split("\n    }\n", 1)[0], \
    "the window hands its chrome theme to the plus HUD"
assert "var paletteTheme: SpaceTheme { incognito ? IncognitoWindowTheme.paletteTheme : theme }" in (root / "Sources/ParcApp/ThemeRenderer.swift").read_text(), \
    "the surface's palette theme is the incognito theme only for a private window"
assert "set { plusMenu.theme = newValue }" in sidebar, "the sidebar forwards the window theme to the plus HUD"
assert "SidebarPlusMenuView(rows: rows, colors: PArcMenuColors(theme: theme)" in plus, "the HUD opens in the window theme"
assert "Boost" not in plus.split("enum SidebarPlusAction", 1)[1], "Boost is excluded from the plus menu"
#
for use in (
    "private let plusButton = SidebarPlusButtonState()",
    'footerMore.title = ""\n',
    "plusButton.install(in: footerMore)",
    "footerMore.onHover = { [weak self] hovered in self?.plusButton.hovered = hovered }",
    "footerMore.onHighlight = { [weak self] pressed in self?.plusButton.pressed = pressed }",
    "plusMenu.onVisibilityChange = { [weak self] shown in",
    "self.plusButton.open = shown",
    "if !shown { self.footerMore.refreshHover() }",
    "let plusColors = TranslucentButtonColors.standard(dark: palette.isDark)",
    "if plusButton.colors != plusColors { plusButton.colors = plusColors }",
    "hovered = isEnabled && NSApp.isActive && !isHiddenOrHasHiddenAncestor",
    # A press dragged off or back on the + changes its highlight; each edge re-reads the hover.
    "if tracksHover { refreshHover() }\n        onHighlight?(flag)",
):
    assert use in sidebar, f"SidebarView no longer drives the + button face: {use}"
tinted = sidebar.split("button.contentTintColor = palette.title", 1)[0].rsplit("for button in", 1)[1]
assert "footerMore" not in tinted, "the + glyph is GrayA11, not the theme title colour"
image_only = sidebar.split("button.imagePosition = .imageOnly", 1)[0].rsplit("for button in", 1)[1]
assert "footerMore" not in image_only, "the + button draws no AppKit image"
face = (root / "Sources/ParcApp/SidebarPlusButtonFace.swift").read_text()
for use in (
    "CGRect(x: rect.midX - 7, y: rect.midY - 1, width: 14, height: 2), cornerSize: corner, style: .continuous",
    "CGRect(x: rect.midX - 1, y: rect.midY - 7, width: 2, height: 14), cornerSize: corner, style: .continuous",
    ".rotationEffect(.radians(state.open ? .pi / 4 : 0))",
    ".animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.5, blendDuration: 0), value: state.open)",
    ".frame(width: 32, height: 32, alignment: .center)",
    ".clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))",
    ".scaleEffect(state.pressed ? 0.95 : 1, anchor: .center)",
    ".animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: state.pressed)",
    ".animation(.easeIn(duration: 0.1), value: state.hovered)",
):
    assert use in face, f"the + face no longer matches the PlusMenuIcon / PArcButtonStyle: {use}"
with tempfile.TemporaryDirectory(prefix="parc-plus-menu-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(
        [
            "xcrun",
            "swiftc",
            "-warnings-as-errors",
            "-parse-as-library",
            "-target",
            "arm64-apple-macos13.0",
            *map(str, sorted((root / "Sources/ParcCore").glob("*.swift"))),
            str(root / "Sources/ParcApp/ThemeRenderer.swift"),
            str(root / "Sources/ParcApp/PArcMenuColors.swift"),
            str(root / "Sources/ParcApp/SidebarPlusMenu.swift"),
            str(Path(__file__).with_name("PlusMenuTests.swift")),
            "-o",
            str(executable),
        ],
        check=True,
    )
    # An unbundled executable's Bundle.main.resourceURL is its own directory.
    shutil.copytree(root / "Resources/SidebarPlusMenu", Path(directory) / "SidebarPlusMenu")
    subprocess.run([str(executable)], check=True)
    # The face over the real ActionButton (SidebarView.swift's head) and the
    # Library entry's TranslucentButtonColors / rendering host.
    controls = Path(directory) / "ActionButton.swift"
    controls.write_text(sidebar[:sidebar.index("final class MenuAction")])
    button_checks = Path(directory) / "button-checks"
    subprocess.run(
        [
            "xcrun",
            "swiftc",
            "-warnings-as-errors",
            "-parse-as-library",
            "-target",
            "arm64-apple-macos13.0",
            *map(str, sorted((root / "Sources/ParcCore").glob("*.swift"))),
            str(root / "Sources/ParcApp/ThemeRenderer.swift"),
            str(root / "Sources/ParcApp/LibraryArtwork.swift"),
            str(root / "Sources/ParcApp/BoxOfThingsIcon.swift"),
            str(root / "Sources/ParcApp/SidebarPlusButtonFace.swift"),
            str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/PointerCover.swift"),
            str(root / "Sources/ParcApp/ReloadControl.swift"),
            str(controls),
            str(Path(__file__).with_name("PlusButtonTests.swift")),
            "-o",
            str(button_checks),
        ],
        check=True,
    )
    subprocess.run([str(button_checks)], check=True)
