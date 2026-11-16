#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-sidebar-ax-") as directory:
    scratch = Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    for use in ("SidebarAccessibility.headerFirst($0, header: [windowButtons] + headerControls)",
                "SidebarAccessibility.laidOut([toggle, back, forward, reload, reloadOptions])",
                "let leading: [NSView] = [keyViewGate] + headerControls + [addressButton]",
                "var keyViewEntry: NSView { keyViewGate }"):
        assert use in sidebar, f"SidebarView no longer orders its header by the checked helpers: {use}"
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
    controller = browser_window_controller_source(root / "Sources/ParcApp")
    for use, count in (("let dismissed = sidebar.isPresented && !presented", 1),
                       ("if dismissed, sidebarOwnsFirstResponder { window?.makeFirstResponder(nil) }", 1),
                       ("sidebar.revealForEditing = { [weak self] in self?.revealSidebarForEditing() }", 1),
                       ("        revealSidebarForEditing()\n", 2),
                       ("func revealSidebarForEditing() {\n        if sidebarPresentation == .hidden { setSidebarPresentation(.floating) }\n"
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
    app = root / "Sources/ParcApp"
    owners = sorted(p.name for p in app.glob("*.swift")
                    if re.search(r"weak var \w*[rR]esponder: NSResponder\?", p.read_text()))
    assert owners == ["BrowserWindowController.swift", "CaptureMotion.swift", "CommandBar.swift", "EaselWebInput.swift",
                      "NavigationControls.swift", "OnboardingPasswordHelp.swift", "PeekFocusReturn.swift",
                      "SidebarPreviewController.swift", "WindowFrameCrankView.swift"], \
        f"a new saved-focus owner must restore through SavedFocus.mayReturn: {owners}"
    for name, use in (("CommandBar.swift", "SavedFocus.mayReturn(to: view, in: parent), parent.makeFirstResponder(view)"),
                      ("BrowserWindowController.swift", "SavedFocus.mayReturn(to: responder, in: window) { window?.makeFirstResponder(responder) }"),
                      ("BrowserWindowController.swift", "(responder as? NSView).map({ SavedFocus.mayReturn(to: $0, in: sourceWindow) }) ?? true {\n                    sourceWindow.makeFirstResponder(responder)"),
                      ("NavigationControls.swift", "(oldResponder as? NSView).map({ SavedFocus.mayReturn(to: $0, in: parent) }) ?? true {\n                        parent.makeFirstResponder(oldResponder)"),
                      ("EaselWebInput.swift", "if SavedFocus.mayReturn(to: previousView, in: parentWindow) { parentWindow.makeFirstResponder(previousView) }"),
                      ("SidebarPreviewController.swift", "let responder = previousResponder as? NSView, SavedFocus.mayReturn(to: responder, in: window) {\n                    window.makeFirstResponder(responder)"),
                      ("WindowFrameCrankView.swift", "guard let view, SavedFocus.mayReturn(to: view, in: window), view.acceptsFirstResponder else { return nil }")):
        text = browser_window_controller_source(app) if name == "BrowserWindowController.swift" else (app / name).read_text()
        assert use in text, f"{name} restores saved focus without SavedFocus: {use}"
    (scratch / "ActionButton.swift").write_text(sidebar[:sidebar.index("final class MenuAction")]
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
                root / "Sources/ParcApp/ParcMenuColors.swift",
                root / "Sources/ParcApp/ReloadControl.swift",
                root / "Sources/ParcApp/TranslucentButtonFace.swift"]
    sys.path.insert(0, str(root / "tests/Tooltip"))
    from support import tooltip_sources
    compiled += tooltip_sources(root, scratch, compiled)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *[str(path) for path in compiled],
                    str(Path(__file__).with_name("SidebarAccessibilityTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
