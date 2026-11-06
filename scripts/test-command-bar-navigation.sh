#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$repo_root/build/tests/command-bar-navigation"
mkdir -p "$output"
# Compile the actual command-bar pipeline against inert native publications.
# Only access modifiers change; ranking, filtering, request identity, the
# publication fingerprint, scope resolution and Return selection stay intact.
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
    ("    private var selectedScopeOffer:", "    /// The engine's template,"),
    ("    private func openResultsFingerprint(", "    private func commandResults("),
    ("    private func endNativeHold()", "    /// An edit keeps a native error"),
    ("    private func clearNativeResults(", "    /// Present this query's own rows"),
    ("    private func releaseNativeHold()", "    private func refreshResults("),
    ("    private func submitSelection(", "    private func submitResult("),
]
blocks = []
for start, end in markers:
    offset = source.index(start)
    blocks.append(source[offset:source.index(end, offset)].replace("    private ", "    "))
(output / "Pipeline.swift").write_text("import AppKit\nextension NavigationFixture {\n" + "\n".join(blocks) + "}\n")
window = (repo / "Sources/ParcApp/BrowserWindowController.swift").read_text()
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
