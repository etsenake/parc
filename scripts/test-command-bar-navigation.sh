#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$repo_root/build/tests/command-bar-navigation"
mkdir -p "$output"
# Compile the actual command-bar pipeline against inert native publications.
# Only access modifiers change; ranking, filtering, request identity, the
# publication fingerprint, zero-query rows, scope resolution and Return selection
# stay intact. Native request dispatch and AppKit table presentation are omitted.
python3 - "$repo_root" "$output" <<'PY'
from pathlib import Path
import sys
repo, output = map(Path, sys.argv[1:])
source = (repo / "Sources/ParcApp/CommandBar.swift").read_text()
markers = [
    ("    private struct Result {", "    var onNavigate:"),
    ("    private func tabResult(", "    /// Every source ranked"),
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
# Keep the actual query selection, skip decision and complete row construction.
# The fixture supplies only the native hold and table/window shell; it must not
# reproduce the compact editor's pristine/cleared logic independently.
query_start = source.index("        let showsCurrentAddress =", source.index("    private func refreshResults("))
query_end = source.index("        if sidebarAnchor != nil {", query_start)
rows_start = source.index("        let fingerprint = openResultsFingerprint(query: query)", query_end)
rows_end = source.index("        emptyLabel.stringValue =", rows_start)
blocks.append("    func refreshResults(requestNative: Bool = false) {\n"
    "        guard !dismissed, !nativeHold.isHolding else { return }\n"
    + source[query_start:query_end] + source[rows_start:rows_end]
    + "        rebuilds += 1\n        table.selectedRow = results.isEmpty ? -1 : 0\n    }\n")
(output / "Pipeline.swift").write_text("import AppKit\nextension NavigationFixture {\n" + "\n".join(blocks) + "}\n")
window = (repo / "Sources/ParcApp/BrowserWindowController.swift").read_text()
# Integration guard: an explicit URL click supplies the compact anchor, while
# Cmd-L's default call retains the full palette. Ordinary address submission
# must resolve against the captured tab rather than opening/switching a tab.
delegate = (repo / "Sources/ParcApp/AppDelegate.swift").read_text()
assert 'front?.focusAddress()' in delegate
for use in ("func focusAddress(anchor: NSView? = nil)",
            "presentCommandBar(newTab: false, addressAnchor: anchor)",
            "self.focusAddress(anchor: self.sidebar.addressEditorAnchor)",
            "addressOnly: addressAnchor != nil,",
            "let commandTab = currentTabID",
            "else { self.resolveInput(input, replacing: commandTab) }"):
    assert use in window, f"current-tab compact editor wiring changed: {use}"
start = window.index("    private func commandBarTabs(")
end = window.index("    private func commandBarTabCaption(", start)
(output / "TabCandidates.swift").write_text("import Foundation\nextension TabCandidatesFixture {\n" +
    window[start:end].replace("private func commandBarTabs", "func commandBarTabs", 1) + "}\n")
PY
xcrun swiftc -warnings-as-errors -whole-module-optimization -parse-as-library \
  "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/Sources/ParcApp/CommandBarRanking.swift" \
  "$repo_root/Sources/ParcApp/CommandBarCommandCandidate.swift" \
  "$repo_root/Sources/ParcApp/CommandBarRowDiff.swift" \
  "$repo_root/Sources/ParcApp/CommandBarNativeHold.swift" \
  "$repo_root/Sources/ParcApp/CommandBarEditState.swift" \
  "$repo_root/Sources/ParcApp/CommandBarSubmission.swift" \
  "$repo_root/Sources/ParcApp/CommandBarSiteColor.swift" \
  "$repo_root/tests/CommandBar/NavigationPipelineTests.swift" \
  "$output/Pipeline.swift" "$output/TabCandidates.swift" -o "$output/check"
"$output/check"
