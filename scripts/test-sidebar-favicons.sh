#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -parse-as-library Sources/ParcApp/SidebarFaviconView.swift tests/SidebarRows/SidebarFaviconTests.swift -o "$output/check"
"$output/check"
python3 - <<'PY'
from pathlib import Path
sidebar = Path("Sources/ParcApp/SidebarView.swift").read_text()
assert "icon.fallbackTintColor = title" in sidebar, "tab fallbacks must tint with SemanticColorPalette.title"
assert "resetParts?.icon.fallbackTintColor = title" in sidebar, "reset fallbacks must tint with the same title color"
assert "InternalPage.sidebarFallbackSymbol(urlString: tab.url)" in sidebar
assert "paintpalette" not in sidebar, "Easel and Note rows must not share a paintpalette glyph"
import sys
sys.path.insert(0, str(Path(".") / "tests/Support"))
from window_sources import browser_window_controller_source
controller = browser_window_controller_source(Path(".") / "Sources/ParcApp")
assert "InternalPage.sidebarFallbackSymbol(urlString: tab.url)" in controller
assert 'systemSymbolName: "paintpalette"' not in controller
print("sidebar document glyphs use title tint and distinct symbols")
PY
python3 tests/SidebarRowFaviconRearm/check.py
python3 tests/SidebarRenderLeftover/check.py
