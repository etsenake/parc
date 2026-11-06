#!/usr/bin/env python3
"""P1-AA behavior lock: refreshDeveloperToolbars skips forced needsLayout /
layoutSubtreeIfNeeded when pane/peek developer chrome geometry is already
current and the host does not need layout; real geometry/needsLayout still
flushes and synchronizeNativeLayout runs only after a flush."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
layout = (app / "DeveloperToolbarLayout.swift").read_text()
controller = (app / "BrowserWindowController.swift").read_text()

assert "enum DeveloperChromeGeometry" in layout, "DeveloperChromeGeometry helper missing"
assert "static func paneIsCurrent(" in layout, "paneIsCurrent missing"
assert "static func peekIsCurrent(" in layout, "peekIsCurrent missing"

refresh = re.search(
    r"private func refreshDeveloperToolbars\(\) \{(?P<body>.*?)\n    \}\n    private func configureDeveloperToolbar",
    controller, re.S)
assert refresh, "refreshDeveloperToolbars not found"
body = refresh.group("body")

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

# Live path must still configure without forcing pane layout.
live = re.search(
    r"private func refreshLivePageChrome\(\) -> Bool \{(?P<body>.*?)\n    \}\n\n    private func showInternalPage",
    controller, re.S)
assert live, "refreshLivePageChrome not found"
live_body = live.group("body")
assert "configureDeveloperToolbar" in live_body, "live path must still configure developer toolbars"
assert "layoutSubtreeIfNeeded()" not in live_body, \
    "live path must not force layoutSubtreeIfNeeded"

print("DeveloperToolbarSkip: geometry+needsLayout gate; sync only after flush; live path stays no-force")
