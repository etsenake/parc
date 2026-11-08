#!/usr/bin/env python3
"""P2-AR behavior lock: MiniPlayerDeck.resize and MiniPlayerRow.failure skip
forced layoutSubtreeIfNeeded when frames/subtree are already clean after the
sidebar height/content flush. Real dirty trees still flush. Do not touch
cross-window mini-player sweep admission."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
view = (root / "Sources/ParcApp/MiniPlayerView.swift").read_text()
unit = (root / "tests/MiniPlayerLayoutFlushSkipTests.swift").read_text()

assert "enum MiniPlayerLayoutFlushSkip" in view, "MiniPlayerLayoutFlushSkip helper missing"
assert "static func shouldFlush(" in view, "shouldFlush predicate missing"
assert "frameChanged || needsLayout || subtreeNeedsLayout" in view, \
    "shouldFlush must require a moved frame or dirty tree"
# Freestanding unit test must keep the same true no-op formula.
assert "frameChanged || needsLayout || subtreeNeedsLayout" in unit, \
    "MiniPlayerLayoutFlushSkipTests must mirror the production shouldFlush formula"

resize = re.search(
    r"private func resize\(\) \{(?P<body>.*?)\n    \}\n    private func resetExpansion",
    view, re.S)
assert resize, "MiniPlayerDeck.resize not found"
rb = resize.group("body")
assert "needsLayout = true" in rb and "onHeightChanged?()" in rb, \
    "resize must still dirty and notify height changes"
assert "MiniPlayerLayoutFlushSkip.shouldFlush(" in rb, \
    "resize must gate layoutSubtree on shouldFlush"
assert "layoutSubtreeIfNeeded()" in rb, \
    "resize must still flush when shouldFlush is true"
assert "onKeyViewsChanged?()" in rb, \
    "resize must still notify key-view changes"
assert re.search(
    r"onHeightChanged\?\(\)\n\s+layoutSubtreeIfNeeded\(\)", rb) is None, \
    "resize must not unconditionally layoutSubtree after onHeightChanged"

failure = re.search(
    r"private func showUnavailable\(\) \{(?P<body>.*?)\n    \}\n    override func mouseDown",
    view, re.S)
assert failure, "MiniPlayerRow.showUnavailable not found"
fb = failure.group("body")
assert 'unavailable.stringValue = "This media is no longer available."' in fb, \
    "failure must still set the unavailable message"
assert "onFocus?()" in fb, "failure must still expand for the clipped error"
assert "needsLayout = true; onHeightChanged?()" in fb, \
    "failure must still dirty and notify height before the layout gate"
assert "MiniPlayerLayoutFlushSkip.shouldFlush(" in fb, \
    "failure must gate contentView layoutSubtree on shouldFlush"
assert "window?.contentView?.layoutSubtreeIfNeeded()" in fb, \
    "failure must still flush contentView when shouldFlush is true"
assert "NSAccessibility.post(element: unavailable, notification: .valueChanged)" in fb, \
    "failure must still announce the unavailable message when visible"
assert re.search(
    r"onHeightChanged\?\(\)\n\s+window\?\.contentView\?\.layoutSubtreeIfNeeded\(\)",
    fb) is None, \
    "failure must not unconditionally layoutSubtree contentView after onHeightChanged"

# Cross-window sweep admission must stay untouched (1e9231a1).
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
assert "miniPlayerSourceSignature" in controller, \
    "mini-player multi-window sweep signature must remain"

print("MiniPlayerLayoutFlushSkip: resize/failure gate layoutSubtree; "
      "dirty trees still flush; admission sweep untouched")
