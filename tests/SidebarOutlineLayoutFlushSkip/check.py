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

# Both space-management and ordinary chrome paths lay the shown page out
# through layoutPage, which gates the outline flush.
assert body.count("layoutPage(shownPage)") == 2, \
    "space-management and ordinary layout must both lay the shown page out"
page = re.search(r"private func layoutPage\(_ page: SidebarSpacePage, flush: Bool = true\) \{(?P<body>.*?)\n    \}\n", sidebar, re.S)
assert page, "SidebarView.layoutPage not found"
page_body = page.group("body")
assert page_body.count("SidebarOutlineLayoutFlushSkip.shouldFlush(") == 1, \
    "layoutPage must gate list layoutSubtree"
assert page_body.count("page.list.layoutSubtreeIfNeeded()") == 1, \
    "layoutPage must still flush the list when shouldFlush is true"
assert re.search(
    r"list\.frame = .*\n\s+(page\.)?list\.layoutSubtreeIfNeeded\(\)", page_body) is None, \
    "layoutPage must not unconditionally layoutSubtree the list after assigning its frame"
assert "frameChanged:" in page_body and "page.list.needsLayout" in page_body, \
    "shouldFlush must observe list frame moves and needsLayout"
assert "page.list.subviews.contains(where: \\.needsLayout)" in page_body, \
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
