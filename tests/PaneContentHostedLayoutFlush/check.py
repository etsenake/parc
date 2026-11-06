#!/usr/bin/env python3
"""P0-K behavior lock: BrowserPane skips content.layoutSubtreeIfNeeded when
hosted chrome is current. content.layout / place still run on moved or dirty
content; only dirty direct children get layoutSubtree. PageContentResizer still
flushes on a new page size / shallow hosted-chrome mismatch."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
resizer = (root / "Sources/ParcApp/PageContentResizer.swift").read_text()
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()

assert "enum PaneContentHostedLayoutFlush" in resizer, \
    "PaneContentHostedLayoutFlush helper missing from PageContentResizer.swift"
assert "static func shouldLayoutContent(frameChanged: Bool, needsLayout: Bool)" in resizer, \
    "shouldLayoutContent predicate missing"
assert "frameChanged || needsLayout" in resizer, \
    "shouldLayoutContent must require a moved frame or dirty content"
assert "static func shouldLayoutChild(needsLayout: Bool)" in resizer, \
    "shouldLayoutChild predicate missing"
assert "hostedChromeNeedsFlush" in resizer, \
    "apply must use shallow hostedChromeNeedsFlush (not deep recursive verify)"
assert "hostedSubtreeNeedsFlush" not in resizer, \
    "deep hostedSubtreeNeedsFlush verify walk must stay gone on the no-op path"
assert "lastFlushedFrame != page.frame || Self.hostedChromeNeedsFlush(page)" in resizer, \
    "place must still flush when page frame is new or shallow chrome needs it"
assert "static func flushHostedLayout(_ view: NSView)" in resizer, \
    "flushHostedLayout must remain for real size / dirty chrome changes"

pane = re.search(
    r"private final class BrowserPane: NSView \{(?P<body>.*?)\n\}\n\nextension BrowserPane:",
    controller, re.S)
assert pane, "BrowserPane class not found"
body = pane.group("body")
layout = re.search(r"override func layout\(\) \{(?P<body>.*?)\n    \}", body, re.S)
assert layout, "BrowserPane.layout not found"
lb = layout.group("body")

assert "let contentMoved = content.frame != nextContent" in lb, \
    "contentMoved gate must remain"
assert "if contentMoved { content.needsLayout = true }" in lb, \
    "moved content must still be marked dirty before layout"
assert "PaneContentHostedLayoutFlush.shouldLayoutContent(" in lb, \
    "BrowserPane.layout must gate content.layout on shouldLayoutContent"
assert "content.layout()" in lb, \
    "BrowserPane must still run content.layout (place) when gated true"
assert "content.layoutSubtreeIfNeeded()" not in lb, \
    "unconditional content.layoutSubtreeIfNeeded must stay gone (always walks Chromium)"
assert "PaneContentHostedLayoutFlush.shouldLayoutChild(needsLayout: child.needsLayout)" in lb, \
    "dirty direct children must still layoutSubtree via shouldLayoutChild"
assert "child.layoutSubtreeIfNeeded()" in lb, \
    "dirty direct children must still flush their subtrees"

print("PaneContentHostedLayoutFlush: content.layout gated; no content.layoutSubtree; "
      "shallow hosted chrome flush intact")
