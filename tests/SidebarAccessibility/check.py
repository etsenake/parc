#!/usr/bin/env python3
"""Sidebar accessibility attributes on production AppKit components.

Off-screen window, never made key; no browser, input or preferences.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-sidebar-ax-") as directory:
    scratch = Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    # SidebarView itself is not compiled here; its header order uses the checked helper.
    for use in ("SidebarAccessibility.headerFirst($0, header: [windowButtons] + headerControls)",
                "SidebarAccessibility.laidOut([toggle, back, forward, reload, reloadOptions])",
                "let leading: [NSView] = [keyViewGate] + headerControls + [addressButton]",
                "var keyViewEntry: NSView { keyViewGate }"):
        assert use in sidebar, f"SidebarView no longer orders its header by the checked helpers: {use}"
    # Source assertions: a hidden sidebar stays unhidden off-screen; its
    # presentation reaches the lights and the dock (behaviour checked in
    # SidebarWindowButtons and SidebarChrome), the payment entry, the list stop
    # and the bypassed Tab chain (SidebarAccessibility.link, checked below).
    for use in ("windowButtons.setPresented(isPresented); spacesHost.setPresented(isPresented)\n        retestPointerInSidebar()",
                "guard isPresented, let window = paymentAction.window else { return false }",
                "super.canBecomeKeyView && isPresented && !contentSurface.isHidden && !selectionOrder.isEmpty",
                "retestPointer(); setNeedsKeyViewLinking()",
                "if !isPresented { keyViewsNeedLinking = false; linkKeyViews() }",
                "guard isPresented, super.becomeFirstResponder() else { return false }",
                "if !isPresented, [51, 117, 125, 126].contains(event.keyCode) { super.keyDown(with: event); return }",
                "isPresented, !isHiddenOrHasHiddenAncestor, window.attachedSheet == nil,"):
        assert use in sidebar, f"SidebarView no longer follows its presentation: {use}"
    sys.path.insert(0, str(Path(__file__).parent))
    from key_view_links import assert_sidebar_links
    assert_sidebar_links(sidebar)
    # The window owner gives up focus in a sidebar that stops being presented,
    # as hiding its container did (checked below). Rename reveals a hidden
    # sidebar first, from the window's command and from a row's own actions;
    # a row's selection action focuses the list stop only while presented
    # (both helpers, presentsForEditing and focusIfPresented, run below).
    controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
    for use, count in (("let dismissed = sidebar.isPresented && !presented", 1),
                       ("if dismissed, sidebarOwnsFirstResponder { window?.makeFirstResponder(nil) }", 1),
                       ("sidebar.revealForEditing = { [weak self] in self?.revealSidebarForEditing() }", 1),
                       ("        revealSidebarForEditing()\n", 2),
                       ("private func revealSidebarForEditing() {\n        if sidebarPresentation == .hidden { setSidebarPresentation(.floating) }\n"
                        "        settleSidebarMotion(); layoutChrome(); rootView.layoutSubtreeIfNeeded()", 1)):
        assert controller.count(use) == count, f"the window owner no longer keeps focus out of the hidden sidebar: {use}"
    renames = re.findall(r"let commit = prepare\w+Rename\?\(", sidebar)
    assert len(renames) >= 2 and len(renames) == len(re.findall(
        r"let commit = prepare\w+Rename\?\(\w+\), presentsForEditing\(reveal: revealForEditing\) else \{ return false \}", sidebar)), \
        "every rename the sidebar starts (let commit = prepare…Rename?(x)) reveals a hidden sidebar first, in the same guard"
    for use, count in (("final class SidebarView: SidebarSpaceMenuSurface, NSMenuItemValidation, OffscreenPresenting {", 1),
                       ("private func focusSelectionList() { focusIfPresented(); refreshItemSelection() }", 1),
                       ("makeFirstResponder(self)", 0),
                       ("focusSelectionList()", 3)):
        assert sidebar.count(use) == count, f"SidebarView no longer keeps focus out while hidden: {use}"
    # Every saved-focus restore asks SavedFocus (checked below). A new stored
    # responder must be reviewed here: OnboardingPasswordHelp's window holds no
    # sidebar, PeekFocusReturn's responder lies inside the page or Peek, and
    # CaptureMotion's responder only detects a user's move; it restores Capture
    # Library views, which lie in the Library page or its detail panel.
    app = root / "Sources/ParcApp"
    owners = sorted(p.name for p in app.glob("*.swift")
                    if re.search(r"weak var \w*[rR]esponder: NSResponder\?", p.read_text()))
    assert owners == ["BrowserWindowController.swift", "CaptureMotion.swift", "CommandBar.swift", "EaselWebInput.swift",
                      "NavigationControls.swift", "OnboardingPasswordHelp.swift", "PeekFocusReturn.swift",
                      "SidebarPreviewController.swift"], \
        f"a new saved-focus owner must restore through SavedFocus.mayReturn: {owners}"
    for name, use in (("CommandBar.swift", "SavedFocus.mayReturn(to: view, in: parent), parent.makeFirstResponder(view)"),
                      ("BrowserWindowController.swift", "SavedFocus.mayReturn(to: responder, in: window) { window?.makeFirstResponder(responder) }"),
                      ("BrowserWindowController.swift", "(responder as? NSView).map({ SavedFocus.mayReturn(to: $0, in: sourceWindow) }) ?? true {\n                    sourceWindow.makeFirstResponder(responder)"),
                      ("NavigationControls.swift", "(oldResponder as? NSView).map({ SavedFocus.mayReturn(to: $0, in: parent) }) ?? true {\n                        parent.makeFirstResponder(oldResponder)"),
                      ("EaselWebInput.swift", "if SavedFocus.mayReturn(to: previousView, in: parentWindow) { parentWindow.makeFirstResponder(previousView) }"),
                      ("SidebarPreviewController.swift", "let responder = previousResponder as? NSView, SavedFocus.mayReturn(to: responder, in: window) {\n                    window.makeFirstResponder(responder)")):
        assert use in (app / name).read_text(), f"{name} restores saved focus without SavedFocus: {use}"
    (scratch / "ActionButton.swift").write_text(sidebar[:sidebar.index("final class MenuAction")]
        # The Favorite favicon identity above ActionButton needs SplitOrientation.
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    navigation = (root / "Sources/ParcApp/NavigationControls.swift").read_text()
    (scratch / "NavigationControlButton.swift").write_text(navigation[:navigation.index("final class NavigationHistoryController")])
    executable = scratch / "checks"
    compiled = [root / "Sources/ParcCore/SidebarResize.swift",
                root / "Sources/ParcApp/SidebarResizeRegion.swift",
                root / "Sources/ParcApp/SidebarAccessibility.swift",
                root / "Sources/ParcApp/SavedFocus.swift",
                root / "Sources/ParcApp/WindowStandardButtons.swift",
                root / "Sources/ParcApp/SidebarMotionController.swift",
                scratch / "ActionButton.swift",
                scratch / "NavigationControlButton.swift",
                root / "Sources/ParcApp/NavigationControlPress.swift",
                root / "Sources/ParcCore/SpaceTheme.swift",
                root / "Sources/ParcApp/ThemeRenderer.swift",
                root / "Sources/ParcApp/PArcMenuColors.swift",
                root / "Sources/ParcApp/ReloadControl.swift",
                root / "Sources/ParcApp/TranslucentButtonFace.swift"]
    sys.path.insert(0, str(root / "tests/Tooltip"))
    from support import tooltip_sources
    compiled += tooltip_sources(root, scratch, compiled)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *[str(path) for path in compiled],
                    str(Path(__file__).with_name("SidebarAccessibilityTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
