#!/usr/bin/env python3
"""797f2a55 leftover behavior lock: SidebarView.layout skips forced outline/list
layoutSubtreeIfNeeded when the list frame already matches and the outline
subtree is clean. Membership rebuilds still force layoutSubtree at the end of
render; size/disclosure/dirty-tree cases still flush the list.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
skip = (root / "Sources/ParcCore/SidebarOutlineLayoutFlushSkip.swift").read_text()

assert "enum SidebarOutlineLayoutFlushSkip" in skip, \
    "SidebarOutlineLayoutFlushSkip helper missing"
assert "static func shouldFlush(" in skip, "shouldFlush predicate missing"
assert "frameChanged || needsLayout || subtreeNeedsLayout" in skip, \
    "shouldFlush must require a moved frame or dirty tree"

layout = re.search(
    r"override func layout\(\) \{(?P<body>.*?)\n    \}\n\n    /// The selected Space",
    sidebar, re.S)
assert layout, "SidebarView.layout not found"
body = layout.group("body")

# Both space-management and ordinary chrome paths must gate the outline flush.
assert body.count("SidebarOutlineLayoutFlushSkip.shouldFlush(") == 2, \
    "space-management and ordinary layout must both gate list layoutSubtree"
assert body.count("list.layoutSubtreeIfNeeded()") == 2, \
    "both layout paths must still flush the list when shouldFlush is true"
assert re.search(
    r"list\.frame = .*\n\s+list\.layoutSubtreeIfNeeded\(\)", body) is None, \
    "layout must not unconditionally layoutSubtree the list after assigning its frame"
assert "frameChanged:" in body and "list.needsLayout" in body, \
    "shouldFlush must observe list frame moves and needsLayout"
assert "list.subviews.contains(where: \\.needsLayout)" in body, \
    "shouldFlush must observe dirty outline children"

# Membership rebuilds must still force a sidebar layoutSubtree walk.
render = re.search(
    r"func render\(state: BrowserState, focusedTabID: UUID\?, loading: Set<UUID>, canBack: Bool, "
    r"canForward: Bool, captures: \[UUID: CaptureIndicatorPresentation\] = \[:\],\n"
    r"                shareable: Set<UUID> = \[\], audio: \[UUID: SidebarTabAudio\] = \[\:\]\) \{(?P<body>.*?)\n"
    r"    func updateSpaceAvailability\(\)",
    sidebar, re.S)
assert render, "SidebarView.render not found"
render_body = render.group("body")
assert "needsLayout = true; layoutSubtreeIfNeeded()" in render_body, \
    "membership rebuilds must still force layoutSubtreeIfNeeded"
assert "if hierarchyState != nil," in render_body, \
    "matching-membership live early-return must remain"

print("SidebarOutlineLayoutFlushSkip: layout gates list layoutSubtree; "
      "dirty/moved outline still flushes; membership render force kept")
