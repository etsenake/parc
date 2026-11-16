#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
window = browser_window_controller_source(root / "Sources/ParcApp")
peek = (root / "Sources/ParcApp/PeekController.swift").read_text()
drop = (root / "Sources/ParcApp/ExternalSplitDropView.swift").read_text()


def body(text, start, end="\n    }\n"):
    assert text.count(start) == 1, f"expected one {start!r}"
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


order = ["rootView.addSubview(pageHost)", "rootView.addSubview(splitMarginHandle)", "rootView.addSubview(extensionSidePanel)",
         "rootView.addSubview(loadingIndicator)", "rootView.addSubview(peekLayer)", "rootView.addSubview(findHost)",
         "rootView.addSubview(sidebarContainer)"]
positions = [window.index(line) for line in order]
assert positions == sorted(positions), "the Peek layer sits above the page, grip and side panel, below Find and the sidebar"
assert "pageHost.addSubview(peek.view" not in window and "pageHost.addSubview(controller.view" not in window, \
    "no Peek lives inside the page card any more"
assert window.count("peekLayer.addSubview(controller.view, positioned: .above, relativeTo: nil)") == 1, \
    "a tab-backed Peek lands in the window's Peek layer too"
assert window.count("peekLayer.addSubview(peek.view, positioned: .above, relativeTo: nil)") == 2, \
    "adoption and window transfer both land a Peek in the window's Peek layer"
assert "rootView.subviews =" not in window, "the Peek layer keeps its place instead of being re-stacked under a focused page"
assert "func contains(_ event: NSEvent) -> Bool {\n        !view.isHidden && event.window === view.window && view.claims(" in peek, \
    "clicks and three-finger swipes count as the Peek's only where they reach it"
menu = body(window, "    func windowFrameContextMenu(rootHit hit: NSView?) -> NSMenu? {")
assert "splitMarginHandle, peekLayer]" in menu, "right-clicking the Peek or its faded page doesn't offer Adjust Window Frame"
shudder = body(window, "    private func shudderWindowFrame() {")
assert "peekLayer" not in shudder and "pageHost, pageShadow" in shudder, "the crank shudders the page, never the Peek"
step = body(window, "    func syncPeekStepBack(animated: Bool = false) {")
for token in ("loadingIndicator.alphaValue = (shown?.view.stepProgress ?? 0) > 0 ? 0 : 1", "steppingPeek.flatMap",
              "peek.view.stepsBack", "pageHost.peekStepScale = scale",
              "peekStepBack.animateIn(scale: scale)", "peekStepBack.reset()"):
    assert token in step, f"the step-back sync lost {token!r}"
stepping = body(window, "    private var steppingPeek: PeekController? {")
assert "tabPeeks.leaving" in stepping, "a tab-backed Peek that is fading out still eases the page forward"
laid = body(window, "    func layoutPeeks() {")
assert laid.index("reconcileTabPeek()") < laid.index("for card in leavingTabPeekCards { placePeek(card); card.view.layoutSubtreeIfNeeded() }") \
    < laid.index("syncPeekStepBack()"), "a tab-backed Peek fading out after its tab opens follows the window's new layout"
assert "var leavingTabPeekCards: [PeekController] { tabPeeks.leaving.compactMap(\\.controller) }" in window, \
    "the fading tab-backed cards are the ones still leaving"
geometry = body(window, "    private func layoutChromeGeometry() {")
assert "for peek in presentedPeeks + leavingTabPeekCards { placePeek(peek); peek.view.layoutSubtreeIfNeeded() }" in geometry, \
    "the geometry-only layout pass moves fading tab-backed cards too"
place = body(window, "    func placePeek(_ peek: PeekController) {")
assert "peek.view.pageFrame = pageHost.frame" in place and "accessibilityDisplayShouldReduceMotion" in place, \
    "a Peek measures its card from the window and skips the step-back under Reduce Motion"
assert "lazy var peekStepBack = PeekStepBack([pageHost, pageShadow])" in window, "the page card and its shadow step back together"
assert "final class PeekHostView: PeekHitView {" in peek, "the Peek host routes clicks through the shared layout"
layout = body(peek, "    override func layout() {")
for token in ("PeekWindowLayout(bounds: bounds, page: pageFrame, stepsBack: stepsBack)", "backdrop.frame = pageFrame",
              "hitLayout = geometry; hitControls = controls.frame"):
    assert token in layout, f"the Peek host layout lost {token!r}"
assert "swipe.onWash = { [weak self] wash in self?.reportStep(CGFloat(wash)) }" in peek, \
    "the swipe and closing fade drive the page's step-back"
assert "PeekWindowLayout.pageAcceptsHit(at: convert(point, from: superview), in: bounds," in drop, \
    "the stepped-back page leaves the band it reveals to the window frame"

sources = [root / "tests/Support/TestFailure.swift",
           root / "Sources/ParcApp/PeekWindowLayout.swift",
           root / "Sources/ParcApp/PeekStepBack.swift",
           Path(__file__).with_name("main.swift")]
with tempfile.TemporaryDirectory(prefix="parc-peek-window-host-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                    "-module-cache-path", str(Path(directory) / "modules"), *map(str, sources), "-o", str(executable)],
                   check=True)
    subprocess.run([str(executable)], check=True)
