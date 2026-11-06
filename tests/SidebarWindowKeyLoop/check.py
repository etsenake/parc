#!/usr/bin/env python3
"""The window owner's key-view loop between the page side and the sidebar:
WindowKeyViewLoop and the production sidebar linker over a stand-in page side.

Off-screen window, never made key; no browser, input or preferences.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
# BrowserWindowController is not compiled here: its wiring is asserted in source.
for use, count in (("private lazy var windowKeyViews = WindowKeyViewLoop(", 1),
                   ("excluded: { [sidebarContainer, parkedPages, pageHost, weak self] in\n"
                    "            EaselBrowserObjects.excludesFromKeyboardNavigation($0) ||\n"
                    "            WindowKeyViewLoop.windowExcludes($0, sidebarContainer: sidebarContainer, parkedPages: parkedPages,\n"
                    "                                             pageHost: pageHost, activePeek: { self?.activePeek?.view })", 1),
                   ("isPage: { [extensionSidePanel] in $0 is PCBrowserView || $0 === extensionSidePanel.content },", 1),
                   ("passesThrough: { $0 is PeekHostView })", 1),
                   ("windowKeyViews.attach(to: window)", 1),
                   # layoutChrome plus easel keyboard-structure and selection-change paths
                   ("windowKeyViews.relink()", 3),
                   ("extension SidebarView: SidebarKeyViewEnds {}", 1),
                   ("recalculateKeyViewLoop", 0),
                   ("autorecalculatesKeyViewLoop", 0)):
    assert controller.count(use) == count, f"the window owner's key-view loop wiring changed: {use}"
layout = controller[controller.index("    private func layoutChrome() {"):controller.index("    private func chromeFrames(sidebarWidth: CGFloat, in bounds: NSRect) -> SidebarChromeFrames {")]
assert layout.index("guard fullPass else { return }") < layout.index("windowKeyViews.relink()"), \
    "the window loop must relink at the end of every full chrome layout"
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
for use in ("var keyViewEntry: NSView { keyViewGate }",
            "weak var keyViewExit: NSView? { didSet { if keyViewExit !== oldValue { setNeedsKeyViewLinking() } } }",
            "SidebarAccessibility.link(chain, within: self, exit: keyViewExit, bypassed: !isPresented)"):
    assert use in sidebar, f"SidebarView's ends changed: {use}"
# The preview card's own surface, the root subview the window leaves out
# (and PeekController's host, hosted over the page host, as asserted above).
peek = (root / "Sources/ParcApp/PeekController.swift").read_text()
assert "final class PeekHostView: NSView {" in peek and "override var acceptsFirstResponder: Bool { true }" in peek
assert controller.count("pageHost.addSubview(peek.view, positioned: .above, relativeTo: nil)") == 1
preview = (root / "Sources/ParcApp/SidebarPreviewController.swift").read_text()
assert "host.addSubview(card, positioned: .above, relativeTo: nil)" in preview and "host: rootView" in controller
with tempfile.TemporaryDirectory(prefix="parc-window-key-loop-") as directory:
    executable = Path(directory) / "checks"
    presentation = (root / "Sources/ParcApp/SidebarPreviewPresentation.swift").read_text()
    surface = Path(directory) / "SidebarPreviewSurface.swift"
    surface.write_text(presentation[:presentation.index("final class SidebarPreviewItemView")])
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/SidebarAccessibility.swift"),
                    str(root / "Sources/ParcApp/WindowKeyViewLoop.swift"), str(surface),
                    str(Path(__file__).with_name("SidebarWindowKeyLoopTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
