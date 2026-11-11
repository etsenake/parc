#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
motion = (root / "Sources/ParcApp/SidebarMotionController.swift").read_text()

assert "struct LayoutChromeGeometryFingerprint: Equatable" in motion, \
    "LayoutChromeGeometryFingerprint missing beside SidebarChromeFrames"
assert "enum LayoutChromeGeometrySkip" in motion, \
    "LayoutChromeGeometrySkip helper missing"
assert "static func shouldReturnEarly(" in motion, \
    "shouldReturnEarly predicate missing"
assert "previous == next && !dirtyHostedLayout" in motion, \
    "early return must require identical fingerprint and clean hosted tree"
assert "var currentTabID: UUID?" in motion and "var activePeekID: UUID?" in motion, \
    "fingerprint must cover selection / Peek eligibility inputs"
assert "var commandBarOpen: Bool" in motion and "var transferringTabIDs: [UUID]" in motion, \
    "fingerprint must cover command-bar and transfer eligibility inputs"
assert "var libraryContentWidth: CGFloat\n" in motion, \
    "fingerprint must cover the Library page's content width"

assert "private var lastAppliedChromeGeometryFingerprint: LayoutChromeGeometryFingerprint?" in controller, \
    "missing last-applied chrome geometry fingerprint"
assert "private func chromeGeometryFingerprint() -> LayoutChromeGeometryFingerprint" in controller, \
    "chromeGeometryFingerprint builder missing"
assert "currentTabID: currentTabID" in controller and "activePeekID: activePeek?.identity" in controller, \
    "chromeGeometryFingerprint must read live selection / Peek identity"
assert "commandBarOpen: commandBar != nil" in controller, \
    "chromeGeometryFingerprint must read command-bar presence"
assert "library: libraryView != nil,\n            libraryContentWidth: libraryContentWidth," in controller, \
    "chromeGeometryFingerprint must read the Library page's content width"

layout = re.search(
    r"private func layoutChrome\(\) \{(?P<body>.*?)\n    \}\n\n    /// Cheap chrome-geometry \+ full-pass eligibility inputs",
    controller, re.S)
assert layout, "layoutChrome not found (or fingerprint helper comment moved)"
body = layout.group("body")

assert "let fingerprint = chromeGeometryFingerprint()" in body, \
    "layoutChrome must build the geometry fingerprint before work"
assert "LayoutChromeGeometrySkip.shouldReturnEarly(" in body, \
    "layoutChrome must gate on LayoutChromeGeometrySkip.shouldReturnEarly"
assert "dirtyHostedLayout:" in body, \
    "early return must consider dirty hosted layout"
assert body.index("chromeGeometryFingerprint()") < body.index("refreshSidebarHoverZones()"), \
    "fingerprint skip must precede hover-zone refresh"
assert body.index("shouldReturnEarly(") < body.index("refreshSidebarHoverZones()"), \
    "true no-op must skip hover-zone refresh"
assert "lastAppliedChromeGeometryFingerprint = fingerprint" in body, \
    "successful passes must record the applied fingerprint"

assert "var flushedHostedLayout = false" in body, \
    "layoutChrome must still track hosted layout flushes (P1-S)"
assert "let pageHostMoved = pageHost.frame != frames.pageHost" in body, \
    "pageHostMoved gate (P1-W) must remain"
assert "let sidePanelMoved = extensionSidePanel.isHidden != sidePanelHidden" in body, \
    "sidePanelMoved gate (P1-W) must remain"
assert (
    "if flushedHostedLayout {\n"
    "            synchronizeNativeLayout()\n"
    "        }"
) in body, "synchronizeNativeLayout must stay gated (P1-S)"
assert "windowKeyViews.relink()" in body, \
    "full pass must still request key-view relink"

geometry = re.search(
    r"private func layoutChromeGeometry\(\) \{(?P<body>.*?)\n    \}\n\n    func newTab",
    controller, re.S)
assert geometry, "layoutChromeGeometry not found"
geo = geometry.group("body")
assert "pageHost.needsLayout = true" in geo and "pageHost.layoutSubtreeIfNeeded()" in geo, \
    "layoutChromeGeometry must still flush pageHost during sidebar motion"

theme = (root / "Sources/ParcApp/ThemeRenderer.swift").read_text()
assert "if surfacesMoved { onLayout?() }" in theme, \
    "ThemeRenderer onLayout frame skip (15de84db) must remain untouched"

print("LayoutChromeGeometrySkip: identical chrome geometry returns early; "
      "Cmd-S changes and P1-W/P1-S flushes still run")
