#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
layout = (app / "DeveloperToolbarLayout.swift").read_text()
controller = (app / "BrowserWindowController.swift").read_text()

assert "enum DeveloperChromeGeometry" in layout, "DeveloperChromeGeometry helper missing"
assert "static func paneIsCurrent(" in layout, "paneIsCurrent missing"
assert "static func peekIsCurrent(" in layout, "peekIsCurrent missing"

def method(signature):
    match = re.search(rf"^    private func {signature} \{{(?P<body>.*?)\n    \}}\n", controller, re.S | re.M)
    return match and match.group("body")


refresh = method(r"refreshDeveloperToolbars\(\)")
assert refresh, "refreshDeveloperToolbars not found"
body = refresh

assert "var flushedChromeLayout = false" in body, \
    "refreshDeveloperToolbars must track whether a chrome layout flush ran"
assert "if pane.controlsObstructed != obstructed { pane.controlsObstructed = obstructed }" in body, \
    "identical controlsObstructed must not restamp needsLayout"
assert "if pane.controlsFocused != focused { pane.controlsFocused = focused }" in body, \
    "identical controlsFocused must not restamp needsLayout"
assert "DeveloperChromeGeometry.paneIsCurrent(" in body, \
    "pane flush must gate on DeveloperChromeGeometry.paneIsCurrent"
assert "DeveloperChromeGeometry.peekIsCurrent(" in body, \
    "peek flush must gate on DeveloperChromeGeometry.peekIsCurrent"
assert "if pane.needsLayout\n                || !DeveloperChromeGeometry.paneIsCurrent(" in body, \
    "pane must flush when needsLayout or geometry is stale"
assert "if peek.view.needsLayout\n                || !DeveloperChromeGeometry.peekIsCurrent(" in body, \
    "peek must flush when needsLayout or geometry is stale"
assert body.count("pane.needsLayout = true") == 1, \
    "pane needsLayout=true must appear only inside the flush gate"
assert body.count("peek.view.needsLayout = true") == 1, \
    "peek needsLayout=true must appear only inside the flush gate"
assert "pane.layoutSubtreeIfNeeded()" in body and "peek.view.layoutSubtreeIfNeeded()" in body, \
    "real flush paths must still call layoutSubtreeIfNeeded"
assert (
    "if flushedChromeLayout {\n"
    "            synchronizeNativeLayout()\n"
    "        }"
) in body, "synchronizeNativeLayout must run only after a real chrome layout flush"
assert "pane.needsLayout = true; pane.layoutSubtreeIfNeeded()" not in body, \
    "blanket pane needsLayout+layoutSubtree must be gone"
assert "peek.view.needsLayout = true; peek.view.layoutSubtreeIfNeeded()" not in body, \
    "blanket peek needsLayout+layoutSubtree must be gone"

live_body = method(r"refreshLivePageChrome\(\) -> Bool")
assert live_body, "refreshLivePageChrome not found"
assert "configurePaneDeveloperToolbar(pane," in live_body and "configureDeveloperToolbar(peek.view.developerToolbar," in live_body, \
    "live path must still configure pane and peek developer toolbars"
pane_toolbar = method(r"configurePaneDeveloperToolbar\(_ pane: BrowserPane, visible: Bool\)")
assert pane_toolbar and "configureDeveloperToolbar(toolbar," in pane_toolbar, "configurePaneDeveloperToolbar not found"
toolbar = method(r"configureDeveloperToolbar\(_ toolbar: DeveloperToolbarView, browser: PCBrowserView\?, visible: Bool\)")
assert toolbar, "configureDeveloperToolbar not found"
for path, text in (("live path", live_body), ("pane developer toolbar", pane_toolbar), ("developer toolbar", toolbar)):
    assert not re.search(r"layoutSubtreeIfNeeded\(|needsLayout\s*=\s*true|\blayout\(\)|layoutChrome\(", text), \
        f"{path} must not force layout"

print("DeveloperToolbarSkip: geometry+needsLayout gate; sync only after flush; live path stays no-force")
