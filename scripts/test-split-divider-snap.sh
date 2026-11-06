#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -whole-module-optimization -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/ParcSplitView.swift Sources/ParcApp/PageCardShadow.swift Sources/ParcApp/SplitMarginHandle.swift Sources/ParcApp/SplitDropGeometry.swift tests/SidebarRows/SplitDividerSnapTests.swift -o "$output/check"
"$output/check"
