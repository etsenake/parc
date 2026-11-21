#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from support import tooltip_sources
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"

def source(name):
    return (app / name).read_text()

sidebar = source("SidebarView.swift")
assert "if isSuppressed && !isExempt(view) { return false }" in source("TooltipController.swift") \
    and "TooltipController.controller(for: window).isSuppressed = card != nil" in source("SidebarPreviewController.swift") \
    and "TooltipController.controller(for: window).exemptView = card" in source("SidebarPreviewController.swift"), \
    "a shown sidebar preview card no longer holds back the window's other tooltips"
assert 'LiveShortcutToolTip.set(toggle, label, commandID: "toggleSidebar:")' in sidebar, \
    "the sidebar toggle no longer shows its tooltip with the live binding and help"
assert 'LiveShortcutToolTip.set(closeButton, tooltip, commandID: "closeTab:")' in sidebar \
    and sidebar.count("bindCloseButton(tooltip: Self.closeTooltip(tab)") == 2 \
    and '"Archive this tab" : "Close and Keep Pinned"' in sidebar, "the row Close lost its Archive / Close and Keep Pinned tooltips"
assert "parcTooltip = compactSplitChild ? nil : Self.rowTooltip(tooltipTab, renameable: beginRename != nil)" in sidebar \
    and "style: .label(subtitle: hint), anchor: .cursor" in sidebar \
    and "behavior: .onMouseIdle(delay: 1.5)" in sidebar and 'static let renameHint = "Double-click to rename"' in sidebar \
    and "renameable && tab.customTitle == nil" in sidebar, \
    "the tab row lost its title / rename-hint tooltip at the pointer, or a split child gained one"
assert "if Self.isRenameClick(originalEvent), beginRename?() == true { return }" in sidebar \
    and "row.beginRename = inGroup || isSpaceManagement || !SidebarTabTitle.isRenameable(tab) ? nil" in sidebar, \
    "the rename hint no longer matches the row's double-click rename"
assert 'LiveShortcutToolTip.set(parts.region, "Reset Tab", commandID: "resetTab:", requiresBinding: true)' in sidebar
assert "footerMore.toolTip" not in sidebar and "LiveShortcutToolTip.set(footerMore" not in sidebar \
    and "footerMore.parcTooltip" not in sidebar, "the dock + has no tooltip"
assert 'LiveShortcutToolTip.help(row.button, "New tab", commandID: "newTab:")' in sidebar \
    and "LiveShortcutToolTip.set(row.button" not in sidebar and "newTabRow.button.parcTooltip" not in sidebar, \
    "the New Tab row has no tooltip; its help keeps the binding"
assert 'LiveShortcutToolTip.help(addressButton, "Search or enter a URL", commandID: "focusAddress:")' in sidebar \
    and "LiveShortcutToolTip.set(addressButton" not in sidebar, "the URL pill has no tooltip"
assert 'button.parcTooltip = TooltipConfiguration(space.name.isEmpty ? "Untitled Space" : space.name,' in sidebar \
    and "style: .dockItem" not in sidebar \
    and "shortcut: .command(NumberedTarget.spaceBindingID(offset + 1)), anchor: .top)" in sidebar \
    and "let profileName = state.profiles.count > 1 ? state.profiles.first(where: { $0.id == space.profileID })?.name : nil" not in sidebar, \
    "a dock Space item's tooltip sits above it with the Space's numbered binding and no profile name"
assert sidebar.count('"Copy Quote as URL", commandID: "copyCurrentURLAsQuote:")') == 2 \
    and "Copy a link to the selected text" not in sidebar, "quote mode's buttons show the Copy Quote as URL label"
center = source("SiteControlCenter.swift")
center_tooltips = (
    "TooltipConfiguration(button.title, shortcut: button.commandID.map { .command($0) })",
    "TooltipConfiguration(tooltip)",
    "TooltipConfiguration(item.tooltip.isEmpty ? item.name : item.tooltip)",
    'TooltipConfiguration("Add Extension")',
    'TooltipConfiguration(isPinned ? "Unpin" : "Pin")',
    "TooltipConfiguration(accessory.help)",
    "TooltipConfiguration(setting.title)",
    'TooltipConfiguration(isSecure ? "Secure" : "Insecure")',
    'TooltipConfiguration("More")',
)
missing_center_tooltips = [tooltip for tooltip in center_tooltips if f".parcTooltip({tooltip})" not in center]
assert not re.search(r"^\s*\.help\(", center, re.M) and not missing_center_tooltips \
    and center.count(".parcTooltip(TooltipConfiguration(") == len(center_tooltips), \
    "Site Control Center's SwiftUI controls (the action buttons, section headers, extension rows, Add Extension, Pin, " \
    "permission rows and their Settings button, the security badge and More) show the Parc tooltip through the bridge; " \
    f"missing {missing_center_tooltips}, found {center.count('.parcTooltip(TooltipConfiguration(')} of {len(center_tooltips)}"
for name in ("SidebarView.swift", "SidebarRowActionButton.swift", "SplitPaneControl.swift", "SplitDragView.swift",
             "SidebarSplitTitleView.swift", "SidebarSpaceHeader.swift", "SidebarMoveAttentionView.swift", "SpaceManagerView.swift",
             "SpaceCreationView.swift", "SpaceThemeEditorView.swift", "MiniPlayerView.swift", "PageFindView.swift",
             "PortraitCapture.swift", "ExtensionControls.swift", "ExtensionSidePanelView.swift", "DocumentsLibraryView.swift",
             "SidebarLibraryEntry.swift", "LibraryRailTile.swift"):
    assert not re.search(r"\btoolTip\s*=", source(name)), f"{name} sets an AppKit help tag beside the Parc tooltip"
entry = source("SidebarLibraryEntry.swift")
assert "NSPanel" not in entry and ".toolTipsFont" not in entry and "TooltipConfiguration(text, shortcut: shortcut, anchorRect: rect)" in entry, \
    "the Library entry draws its own tooltip panel again"
assert "parcTooltip = showsLabel ? nil : TooltipConfiguration(title)" in source("LibraryRailTile.swift"), \
    "a compact rail tile no longer carries its title"
assert 'LiveShortcutToolTip.set(back, "Exit Library")' in source("LibraryView.swift")
assert "Remove" not in source("DownloadLibraryView.swift") or "Filter" not in source("DownloadLibraryView.swift"), "Downloads regained a Remove Filter chip"
assert 'anchor: .bottom' in source("PopupChromeView.swift"), "popup window tooltips sit below their buttons"

sources = {name: (app / name).read_text() for name in ("Tooltip.swift", "TooltipView.swift", "TooltipController.swift")}
for use in ("override var canBecomeKey: Bool { false }", "override var canBecomeMain: Bool { false }",
            "window.ignoresMouseEvents = true", "override func isAccessibilityElement() -> Bool { false }"):
    assert use in sources["TooltipController.swift"], f"the tooltip window lost a safety guarantee: {use}"
for name, text in sources.items():
    for call in (r"\bmakeKey", r"\bmakeMain", r"\borderFront", r"\bactivate\(", r"NSApp\.activate", r"becomeKey\("):
        assert not re.search(call, text), f"{name} must not take focus: {call}"
assert "event.trackingArea" not in sources["TooltipController.swift"], "tracking areas are only valid on entered/exited events"
controller = browser_window_controller_source(app)
assert "TooltipController.controller(for: window).palette = TooltipColorPalette(theme: self.rootView.paletteTheme)" in controller, \
    "the browser window no longer gives its tooltips the window theme's palette (the Space's, or the incognito theme's)"
delegate = (app / "AppDelegate.swift").read_text()
assert "TooltipController.commandShortcut = { KeyboardShortcuts.shared.activeShortcut(for: $0) }" in delegate, \
    "the app no longer resolves tooltip shortcuts through the live registry"
assert "TooltipController.eventChord = { KeyboardShortcuts.shared.chord(for: $0) }" in delegate \
    and "TooltipController.symbolicChord = { KeyboardShortcuts.shared.symbolicChord(for: $0) }" in delegate, \
    "tooltip keycaps no longer identify keys through command dispatch's own chord and symbolic fallback"
assert "KeyboardShortcuts.shared.bindHelp(view, title: title, commandID: id, requiresBinding: requiresBinding)" in delegate, \
    "the app no longer keeps tooltipped controls' accessibility help on the live binding"
shortcuts = source("KeyboardShortcuts.swift")
assert "guard let symbolic = symbolicChord(for: event, physical: shortcut) else { return nil }" in shortcuts \
    and "guard let physical = chord(for: event), firstValidNativeCommand(from: nativeChords[physical] ?? []) == nil else { return nil }" in shortcuts \
    and "return symbolicChord(for: event, physical: physical)" in shortcuts, \
    "command dispatch and tooltip keycaps no longer share one symbolic-shortcut fallback"
assert "view.toolTip" not in shortcuts and "(view as? NSControl)?.cell?.setAccessibilityHelp(help)" in shortcuts, \
    "the registry must bind accessibility help, not help tags"

with tempfile.TemporaryDirectory(prefix="parc-tooltip-") as directory:
    scratch = Path(directory)
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *[str(path) for path in tooltip_sources(root, scratch, [])],
                    str(root / "tests/Support/AppKitObservation.swift"),
                    str(Path(__file__).with_name("TooltipTests.swift")), "-o", str(executable)], check=True)
    run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=120)
    print(run.stdout, end="")
    assert run.returncode == 0, run.stderr
    assert "Invalid message sent to event" not in run.stdout + run.stderr, run.stderr
