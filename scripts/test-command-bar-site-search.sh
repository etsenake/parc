#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$repo_root/build/tests/command-bar-site-search"
mkdir -p "$output"
# Exercise the production selected-row resolver with inert publication/row
# fixtures. No Chromium, browser window, profile or navigation is created.
python3 - "$repo_root" "$output" <<'PY'
from pathlib import Path
import sys
repo, output = map(Path, sys.argv[1:])
source = (repo / "Sources/ParcApp/CommandBar.swift").read_text()
start = source.index("    private var selectedScopeOffer:")
end = source.index("    private static func site(of scope: PCNativeOmniboxScope)", start)
resolver = source[start:end].replace("private var selectedScopeOffer:", "var selectedScopeOffer:", 1)
(output / "Resolver.swift").write_text("import AppKit\nextension ScopeOfferFixture {\n" + resolver + "}\n")
PY
xcrun swiftc -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/CommandBarSiteColor.swift" \
  "$repo_root/tests/CommandBar/SiteSearchOfferTests.swift" \
  "$output/Resolver.swift" -o "$output/check"
"$output/check"
