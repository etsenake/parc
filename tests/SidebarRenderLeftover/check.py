#!/usr/bin/env python3
"""P1-AE leftover behavior lock: full SidebarView.render skips outline rebuild
when membership/selection/folder expansion already match by preferring
applyLivePageMetadata gated on preservesSidebarOutline (not the stricter
preservesChromeLayout). Membership moves still reconstruct. Favorite favicon
re-arm skip and live metadata path stay intact.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
core = (root / "Sources/ParcCore/BrowserStore.swift").read_text()

assert "func preservesSidebarOutline(relativeTo previous: BrowserState) -> Bool" in core, \
    "missing preservesSidebarOutline predicate"
assert "preservesSidebarOutline(relativeTo: previous)" in core, \
    "preservesChromeLayout must compose preservesSidebarOutline"

live = re.search(
    r"func applyLivePageMetadata\(state: BrowserState,.*?\) -> Bool \{(?P<body>.*?)\n"
    r"    func reloadFavicon\(for id: UUID\)",
    sidebar, re.S)
assert live, "applyLivePageMetadata not found"
live_body = live.group("body")
assert "preservesSidebarOutline(relativeTo: previous)" in live_body, \
    "live path must gate on outline membership, not only chrome layout"
assert "preservesChromeLayout(relativeTo: previous)" not in live_body, \
    "live path must not refuse download/customTitle ticks via preservesChromeLayout"

render = re.search(
    r"func render\(state: BrowserState, focusedTabID: UUID\?, loading: Set<UUID>, canBack: Bool, "
    r"canForward: Bool, captures: \[UUID: CaptureIndicatorPresentation\] = \[:\],\n"
    r"                shareable: Set<UUID> = \[\], audio: \[UUID: SidebarTabAudio\] = \[\:\]\) \{(?P<body>.*?)\n"
    r"    func updateSpaceAvailability\(\)",
    sidebar, re.S)
assert render, "SidebarView.render not found"
render_body = render.group("body")
assert "if hierarchyState != nil," in render_body, \
    "render must prefer live patch when hierarchy already exists"
assert "applyLivePageMetadata(state: state, focusedTabID: focusedTabID, loading: loading," in render_body, \
    "render must call applyLivePageMetadata before outline rebuild"
assert render_body.index("if hierarchyState != nil,") < render_body.index("tabRows.removeAll()"), \
    "live no-op skip must precede row teardown"
assert "favoriteFaviconArms[tab.id] == arm" in render_body, \
    "Favorite favicon re-arm skip on full render must remain"
assert "button.hasSettledPageFavicons(count: pages.count)" in render_body, \
    "Favorite settled-art gate must remain"
assert "needsLayout = true; layoutSubtreeIfNeeded()" in render_body, \
    "membership rebuilds must still force layoutSubtreeIfNeeded"

print("SidebarRenderLeftover checks passed")
