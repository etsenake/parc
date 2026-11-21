#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
root = Path(__file__).resolve().parents[2]
controller = browser_window_controller_source(root / "Sources/ParcApp")
for use, count in (("lazy var windowKeyViews = WindowKeyViewLoop(", 1),
                   ("excluded: { [sidebarContainer, parkedPages, pageHost, peekLayer, weak self] in\n"
                    "            EmbeddedPagePool.excludesFromKeyboardNavigation($0) ||\n"
                    "            WindowKeyViewLoop.windowExcludes($0, sidebarContainer: sidebarContainer, parkedPages: parkedPages,\n"
                    "                                             pageHost: pageHost, peekLayer: peekLayer, activePeek: { self?.activePeek?.view })", 1),
                   ("isPage: { [extensionSidePanel] in $0 is PCBrowserView || $0 === extensionSidePanel.content },", 1),
                   ("passesThrough: { $0 is PeekHostView })", 1),
                   ("windowKeyViews.attach(to: window)", 1),
                   ("windowKeyViews.relink()", 6),
                   ("keyLoopChanged: { [weak self] in self?.windowKeyViews.relink() })", 1),
                   ("if relinksKeyViews { windowKeyViews.relink() }", 1),
                   ("extension SidebarView: SidebarKeyViewEnds {}", 1),
                   ("recalculateKeyViewLoop", 0),
                   ("autorecalculatesKeyViewLoop", 0)):
    assert controller.count(use) == count, f"the window owner's key-view loop wiring changed: {use}"
layout = controller[controller.index("    func layoutChrome() {"):controller.index("    private func chromeFrames(sidebarWidth: CGFloat, in bounds: NSRect) -> SidebarChromeFrames {")]
assert layout.index("guard fullPass else { return }") < layout.index("windowKeyViews.relink()"), \
    "the window loop must relink at the end of every full chrome layout"
toolbars = controller[controller.index("    func refreshDeveloperToolbars() {"):controller.index("    func configurePaneDeveloperToolbar(")]
assert toolbars.count("relinksKeyViews = true") == 2 and \
    toolbars.rindex("relinksKeyViews = true") < toolbars.index("if relinksKeyViews { windowKeyViews.relink() }"), \
    "a debugger warning row that appears or goes away relinks the window loop after its pane or Peek strip is laid out"
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
for use in ("var keyViewEntry: NSView { keyViewGate }",
            "weak var keyViewExit: NSView? { didSet { if keyViewExit !== oldValue { setNeedsKeyViewLinking() } } }"):
    assert use in sidebar, f"SidebarView's ends changed: {use}"
sys.path.insert(0, str(root / "tests/SidebarAccessibility"))
from key_view_links import assert_sidebar_links
assert_sidebar_links(sidebar)
peek = (root / "Sources/ParcApp/PeekController.swift").read_text()
assert "final class PeekHostView: PeekHitView {" in peek and "override var acceptsFirstResponder: Bool { true }" in peek
hosted = controller.count("addSubview(peek.view")
assert controller.count("peekLayer.addSubview(peek.view, positioned: .above, relativeTo: nil)") == hosted, \
    "every Peek is hosted in a window's Peek layer"
assert re.search(r"^\s+peekLayer\.addSubview\(peek\.view, positioned: \.above, relativeTo: nil\)", controller, re.M), \
    "this window's own Peek is hosted in its Peek layer"
preview = (root / "Sources/ParcApp/SidebarPreviewController.swift").read_text()
assert "host.addSubview(card, positioned: .above, relativeTo: nil)" in preview and "host: rootView" in controller
with tempfile.TemporaryDirectory(prefix="parc-window-key-loop-") as directory:
    executable = Path(directory) / "checks"
    presentation = (root / "Sources/ParcApp/SidebarPreviewPresentation.swift").read_text()
    surface = Path(directory) / "SidebarPreviewSurface.swift"
    surface.write_text(presentation[:presentation.index("final class SidebarPreviewItemView")])
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/SidebarAccessibility.swift"),
                    str(root / "Sources/ParcApp/WindowKeyViewLoop.swift"), str(surface),
                    str(root / "Sources/ParcApp/PopoverBackgroundView.swift"),
                    str(Path(__file__).with_name("SidebarWindowKeyLoopTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
