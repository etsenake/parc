#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$repo_root/build/tests/command-bar-navigation"
mkdir -p "$output"
python3 - "$repo_root" "$output" <<'PY'
from pathlib import Path
import re
import sys
repo, output = map(Path, sys.argv[1:])
source = (repo / "Sources/ParcApp/CommandBar.swift").read_text()
markers = [
    ("    private struct Result {", "    var onNavigate:"),
    ("    private func tabResult(", "    private func rankedResults("),
    ("    private func rankedResults(", "    func updateTopDomains("),
    ("    private func nativeResultRows(", "    private func nativeRow("),
    ("    private func nativeRow(", "    private func caption("),
    ("    private var selectedScopeOffer:", "    private static func site(of scope: PCNativeOmniboxScope)"),
    ("    private func openResultsFingerprint(", "    private func tabResult("),
    ("    private func adoptCommands(", "    private var results:"),
    ("    private static func title(for command:", "    private func nativeResultRows("),
    ("    func updateRecentPages(", "    private static func iconImage(_ name: String)"),
    ("    private func endNativeHold()", "    private func clearNativeResults(keepingError: Bool = false)"),
    ("    private func clearNativeResults(", "    private func releaseNativeHold()"),
    ("    private func releaseNativeHold()", "    private func refreshResults("),
    ("    private func submitSelection(", "    private func submitResult("),
]
blocks = []
for start, end in markers:
    offset = source.index(start)
    blocks.append(source[offset:source.index(end, offset)].replace("    private ", "    "))
query_start = source.index("        let showsCurrentAddress =", source.index("    private func refreshResults("))
query_end = source.index("        if sidebarAnchor != nil {", query_start)
rows_start = source.index("        let fingerprint = openResultsFingerprint(query: query)", query_end)
rows_end = source.index("        emptyLabel.stringValue =", rows_start)
blocks.append("    func refreshResults(requestNative: Bool = false) {\n"
    "        guard !dismissed, !nativeHold.isHolding else { return }\n"
    + source[query_start:query_end] + source[rows_start:rows_end]
    + "        rebuilds += 1\n        table.selectedRow = results.isEmpty ? -1 : 0\n    }\n")
(output / "Pipeline.swift").write_text("import AppKit\nextension NavigationFixture {\n" + "\n".join(blocks) + "}\n")
import sys
sys.path.insert(0, str(repo / "tests/Support"))
from window_sources import browser_window_controller_source
window = browser_window_controller_source(repo / "Sources/ParcApp")
delegate = (repo / "Sources/ParcApp/AppDelegate.swift").read_text()
assert 'front?.focusAddress()' in delegate
for use in ("func focusAddress(anchor: NSView? = nil)",
            "presentCommandBar(newTab: false, addressAnchor: anchor)",
            "self.focusAddress(anchor: self.sidebar.addressEditorAnchor)",
            "self.focusAddress(anchor: self.popupChrome.addressAnchor)",
            "addressOnly: addressAnchor != nil, popup: isPopupWindow,",
            "let commandTab = currentTabID",
            "let commandPeek = newTab ? nil : sourcePeek",
            "else { self.resolveInput(input, typedText: typed, replacing: commandTab) }"):
    assert use in window, f"current-tab compact editor wiring changed: {use}"
assert window.count("focusAddress(anchor:") - window.count("func focusAddress(anchor:") == 2, \
    "only the sidebar address and popup chrome may open the compact editor"
def toolbar_actions(name, admit):
    match = re.search(rf"^    func {name}\(.*?^    }}\n", window, re.S | re.M)
    assert match, f"{name} is missing"
    body = match.group(0)
    assert "toolbar.onAction = {" in body and admit in body, f"{name} lost its click targeting"
    actions = body[body.index("toolbar.onAction = {"):]
    opens = "case .address: self.focusAddress()\n"
    assert admit in actions and opens in actions, f"{name} no longer opens the full command bar"
    assert "focusAddress" not in actions[:actions.index(admit)] and actions.index(admit) < actions.index(opens), \
        f"{name} opens the command bar before targeting the clicked pane"
    return body
browser_toolbar = toolbar_actions("configureBrowserToolbar", "guard original(), let browser, let page else { return }")
assert "return self.activateDeveloperPage(browser, page: page, revision: revision)" in browser_toolbar, \
    "a page toolbar click no longer targets its pane or Peek"
document_toolbar = toolbar_actions("configureDocumentToolbar", "guard admit() else { return }")
assert "if self.focusedTabID != tabID { self.focusedTabID = tabID; self.requestNativeSelection(); self.updateNavigation() }" \
    in document_toolbar, "a Note or Easel toolbar click no longer targets its pane"
position = source[source.index("    private func position()"):source.index("    private func setSurfaceFrame(")]
assert position.count("CommandBarCompactLayout.width(popup: popup, window: parent.frame, screen: available)") == 2, \
    "the compact editor is no longer capped to its window"
for use in ("CommandBarCompactLayout.originX(anchor: anchorRect.minX, width: width, window: parent.frame, screen: available)",
            "CommandBarCompactLayout.restingFrame(anchor: anchorRect, sidebar: anchor.superview?.bounds.width ?? anchorRect.width,",
            "let lift = CommandBarCompactLayout.lift(anchorHeight: anchorRect.height)",
            "CommandBarCompactLayout.originY(anchor: anchorRect, height: height, lift: lift, screen: available)"):
    assert use in position, f"the compact editors no longer keep their row on the address's line: {use}"
contents = source[source.index("    private func layoutContents()"):source.index("    func reconcile(tabs:")]
for use in ("let centre = sidebarBrowsing ? container.bounds.height / 2 : Compact.headerCentre",
            "inputIcon.frame = Compact.iconFrame(centre: centre)",
            "input.frame = Compact.inputFrame(width: width, centre: centre)",
            "scroll.frame = NSRect(x: Compact.listInset, y: 50, width: max(0, width - 2 * Compact.listInset),"):
    assert use in contents, f"the compact address row no longer lines up with its results: {use}"
header = source[source.index("    private func layoutScopeHeader()"):source.index("    private func setScopeInput(")]
assert "let baseX = large ? 49 : CommandBarCompactLayout.textX" in header, \
    "the compact scope label no longer starts at the result title column"
fit = header.index("table.fit(in: scroll, rowCount: results.count)\n        headerScrollerReserve = scroll.scrollerReserve\n")
assert fit < header.index("let right = (large ? 22 : CommandBarCompactLayout.trailing) + headerScrollerReserve"), \
    "the address row no longer ends where the fitted list's columns end"
for use in ("private let scroll = CommandResultsScrollView()",
            "scroll.onTile = { [weak self] in self?.scrollDidTile() }",
            "observe(NSScroller.preferredScrollerStyleDidChangeNotification, object: nil) { $0.adoptScrollerStyle() }",
            "guard !dismissed, !layingOutContents, scroll.scrollerReserve != headerScrollerReserve else { return }"):
    assert use in source, f"the header no longer follows scroll bar changes live: {use}"
present = source[source.index("    func present()"):source.index("    func presentResident(in slot: NSView)")]
assert "        observeLifetime(of: parent)\n        glideFromPill()\n    }\n    private func glideFromPill()" in present, \
    "opening from the pill no longer glides its icon and text into place"
glide = present[present.index("    private func glideFromPill()"):]
for use in ("!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion",
            "let pillIcon = anchor.subviews.first(where: { $0 is SidebarAddressSearchIcon && !$0.isHidden })",
            "input.stringValue.isEmpty",
            "pillTextX: container.convert(NSPoint(x: SidebarAddressSearchIcon.textIndent, y: 0), from: anchor).x",
            "animation.duration = CommandBarCompactLayout.glideDuration",
            "CABasicAnimation(keyPath: \"transform.translation.x\")"):
    assert use in glide, f"the pill glide lost a guard or its sideways-only motion: {use}"
assert "inputIcon.image = sidebarAnchor != nil || addressOnly ? SidebarAddressSearchIcon.glyph" in source, \
    "the compact editor no longer draws the pill's own magnifying glass"
start = window.index("    private func commandBarTabs(")
end = window.index("    func commandBarTabCaption(", start)
(output / "TabCandidates.swift").write_text("import Foundation\nextension TabCandidatesFixture {\n" +
    window[start:end].replace("private func commandBarTabs", "func commandBarTabs", 1) + "}\n")
PY
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -whole-module-optimization -parse-as-library \
  "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/Sources/ParcApp/CommandBarRanking.swift" \
  "$repo_root/Sources/ParcApp/CommandBarCommandCandidate.swift" \
  "$repo_root/Sources/ParcApp/CommandBarRowDiff.swift" \
  "$repo_root/Sources/ParcApp/CommandBarNativeHold.swift" \
  "$repo_root/Sources/ParcApp/CommandBarEditState.swift" \
  "$repo_root/Sources/ParcApp/CommandBarSubmission.swift" \
  "$repo_root/Sources/ParcApp/CommandBarResidentLifetime.swift" \
  "$repo_root/Sources/ParcApp/CommandBarSiteColor.swift" \
  "$repo_root/tests/CommandBar/NavigationPipelineTests.swift" \
  "$output/Pipeline.swift" "$output/TabCandidates.swift" -o "$output/check"
"$output/check"
