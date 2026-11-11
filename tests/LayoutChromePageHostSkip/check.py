#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()

layout = re.search(
    r"private func layoutChrome\(\) \{(?P<body>.*?)\n    \}\n\n    /// Cheap chrome-geometry \+ full-pass eligibility inputs",
    controller, re.S)
assert layout, "layoutChrome not found"
body = layout.group("body")

assert "var flushedHostedLayout = false" in body, \
    "layoutChrome must track whether a hosted layout flush ran"
assert "let pageHostMoved = pageHost.frame != frames.pageHost" in body, \
    "pageHostMoved gate (P1-W) must remain"
assert "let sidePanelMoved = extensionSidePanel.isHidden != sidePanelHidden" in body, \
    "sidePanelMoved gate (P1-W) must remain"
assert "if sidePanelMoved || extensionSidePanel.needsLayout" in body, \
    "side panel must flush only when moved or dirty"
assert "flushedHostedLayout = true" in body, \
    "hosted flushes must mark flushedHostedLayout"
assert body.count("flushedHostedLayout = true") >= 2, \
    "both side-panel and pageHost flush paths must mark flushedHostedLayout"
assert "if pageHostMoved {" in body and "pageHost.needsLayout = true" in body, \
    "moved pageHost must still force needsLayout"
assert "pageHost.layoutSubtreeIfNeeded()" in body, \
    "real pageHost flush paths must still layoutSubtreeIfNeeded"
assert "pageHost.needsLayout = true\n        pageHost.layoutSubtreeIfNeeded()" not in body, \
    "blanket pageHost needsLayout+layoutSubtree before the gate must stay gone"
assert (
    "if flushedHostedLayout {\n"
    "            synchronizeNativeLayout()\n"
    "        }"
) in body, "synchronizeNativeLayout must run only after a real hosted layout flush"
full = body[body.index("guard fullPass else { return }"):]
assert full.count("synchronizeNativeLayout()") == 1, \
    "full pass must call synchronizeNativeLayout exactly once (gated)"
assert "windowKeyViews.relink()" in full, \
    "full pass must still request key-view relink (skip lives inside WindowKeyViewLoop)"

geometry = re.search(
    r"private func layoutChromeGeometry\(\) \{(?P<body>.*?)\n    \}\n\n    func newTab",
    controller, re.S)
assert geometry, "layoutChromeGeometry not found"
geo = geometry.group("body")
assert "pageHost.needsLayout = true" in geo and "pageHost.layoutSubtreeIfNeeded()" in geo, \
    "layoutChromeGeometry must still flush pageHost during sidebar motion"
assert "synchronizeNativeLayout()" not in geo, \
    "geometry-only pass must not gain synchronizeNativeLayout"

keyloop = (root / "Sources/ParcApp/WindowKeyViewLoop.swift").read_text()
assert "static func isInstalled(_ chain: [NSView], entry: NSView, exit: NSView?) -> Bool" in keyloop, \
    "WindowKeyViewLoop.isInstalled skip (0f652a99) must remain"
assert "if Self.isInstalled(chain, entry: entry, exit: sidebar.keyViewExit)" in keyloop, \
    "relink must still skip rewrite when the page-side chain is installed"

print("LayoutChromePageHostSkip: sync only after hosted flush; P1-W + relink skips intact")
