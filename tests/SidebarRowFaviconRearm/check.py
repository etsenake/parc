#!/usr/bin/env python3
"""Queue 20 leftover behavior lock: SidebarView.makeRow skips loadFavicon /
loadResetIcon only when tab page URL + reset destination match the last arm
and settled art can be adopted onto the replacement row. URL/art changes and
reloadFavicon still load. Favorite favicon skip and outline live-path skip
must remain.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
favicon = (root / "Sources/ParcApp/SidebarFaviconView.swift").read_text()

assert "private struct TabRowFaviconIdentity: Equatable" in sidebar, \
    "missing TabRowFaviconIdentity"
assert "var pageURL: String" in sidebar and "var resetDestination: URL?" in sidebar, \
    "tab row favicon identity must cover page URL and reset destination"
assert "private struct TabRowSettledFaviconArt" in sidebar, \
    "missing settled-art carrier for row rebuild adopt"
assert "private var tabFaviconArms: [UUID: TabRowFaviconIdentity] = [:]" in sidebar, \
    "missing last-armed tab row favicon map"
assert "var hasSettledFavicon: Bool { hasFavicon }" in favicon, \
    "SidebarFaviconView must expose settled-art gate"
assert "func adoptSettled(_ image: NSImage)" in favicon, \
    "SidebarFaviconView must adopt settled art without a new load"
assert "func settledFaviconArt() -> TabRowSettledFaviconArt?" in sidebar, \
    "SidebarTabRow must expose settled page (+ reset) art"
assert "func adoptSettledFaviconArt(_ art: TabRowSettledFaviconArt)" in sidebar, \
    "SidebarTabRow must adopt settled art onto a replacement row"

render = re.search(
    r"func render\(state: BrowserState, focusedTabID: UUID\?, loading: Set<UUID>, canBack: Bool, "
    r"canForward: Bool, captures: \[UUID: CaptureIndicatorPresentation\] = \[:\],\n"
    r"                shareable: Set<UUID> = \[\], audio: \[UUID: SidebarTabAudio\] = \[\:\]\) \{(?P<body>.*?)\n"
    r"    func updateSpaceAvailability\(\)",
    sidebar, re.S)
assert render, "SidebarView.render not found"
render_body = render.group("body")

assert "var priorTabFaviconArt: [UUID: TabRowSettledFaviconArt] = [:]" in render_body, \
    "a page build must snapshot settled row art before its rows are let go"
assert render_body.index("priorTabFaviconArt") < render_body.index("page.beginBuild()"), \
    "settled-art snapshot must precede the page's row teardown"
assert "let arm = TabRowFaviconIdentity(pageURL: tab.url, resetDestination: tab.resetDestination)" in render_body, \
    "makeRow must build TabRowFaviconIdentity from page URL + reset destination"
assert "let skipArm = (tabFaviconArms[tab.id] == arm || releasedArt != nil)" in render_body, \
    "makeRow skip must require last-arm identity match, or art let go at the same identity"
assert "let releasedArt = released?.arm == arm ? released?.art : nil" in render_body, \
    "art kept from a row the list let go must match the row's identity"
assert "let priorArt = releasedArt ?? build.priorFavicons[tab.id] ?? reused?.settledFaviconArt()" in render_body \
    and "releasedArt != nil) && priorArt != nil" in render_body, \
    "makeRow skip must require prior settled art (the replaced, reused or let-go row's)"
assert "row.adoptSettledFaviconArt(art)" in render_body, \
    "skip path must adopt settled art onto the replacement row"
assert "tabFaviconArms[tab.id] = arm" in render_body, \
    "non-skip makeRow must record the armed identity"
assert render_body.count("row.loadFavicon") >= 1, \
    "makeRow must still loadFavicon when skip does not apply"
assert render_body.count("row.loadResetIcon") >= 1, \
    "makeRow must still loadResetIcon when skip does not apply"

# reloadFavicon remains an unconditional force load for tab rows.
reload = re.search(
    r"func reloadFavicon\(for id: UUID\) \{(?P<body>.*?)\n    func render\(state: BrowserState",
    sidebar, re.S)
assert reload, "reloadFavicon not found"
reload_body = reload.group("body")
assert "row.loadFavicon" in reload_body, \
    "reloadFavicon must still force loadFavicon on tab rows"
assert "skipArm" not in reload_body, \
    "reloadFavicon must not share makeRow's skipArm gate"

# Live URL changes still re-arm and record identity.
live = re.search(
    r"func applyLivePageMetadata\(state: BrowserState,.*?\) -> Bool \{(?P<body>.*?)\n"
    r"    func reloadFavicon\(for id: UUID\)",
    sidebar, re.S)
assert live, "applyLivePageMetadata not found"
live_body = live.group("body")
assert "if urlChanged {" in live_body, \
    "live path must still gate favicon loads on URL change"
assert "tabFaviconArms[tab.id] = TabRowFaviconIdentity(" in live_body, \
    "live URL change must record tabFaviconArms"
assert "preservesSidebarOutline(relativeTo: previous)" in live_body, \
    "outline membership skip must remain"
assert "favoriteFaviconArms[id] == arm" in live_body, \
    "Favorite favicon re-arm skip on live path must remain"
assert "button.hasSettledPageFavicons(count: pages.count)" in live_body, \
    "Favorite settled-art gate on live path must remain"

# Favorite skip on full render must remain.
assert "favoriteFaviconArms[tab.id] == arm" in render_body, \
    "Favorite favicon re-arm skip on full render must remain"
assert "button.hasSettledPageFavicons(count: pages.count)" in render_body, \
    "Favorite settled-art gate on full render must remain"
assert "if hierarchyState != nil," in render_body, \
    "render must prefer live outline patch when hierarchy already exists"
assert "applyLivePageMetadata(state: state, focusedTabID: focusedTabID, loading: loading," in render_body, \
    "render must call applyLivePageMetadata before outline rebuild"

print("SidebarRowFaviconRearm checks passed")
