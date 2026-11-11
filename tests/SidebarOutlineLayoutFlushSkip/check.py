#!/usr/bin/env python3
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
    r"override func layout\(\) \{(?P<body>.*?)\n    \}\n\n    private func updateDockItems\(\) \{",
    sidebar, re.S)
assert layout, "SidebarView.layout not found"
body = layout.group("body")

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
