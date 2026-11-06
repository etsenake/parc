#!/bin/bash
#
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift tests/SidebarRows/SplitSeparateAllTests.swift -o "$output/model"
"$output/model"
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/ParcSplitView.swift Sources/ParcApp/PageCardShadow.swift \
    Sources/ParcApp/SplitMarginHandle.swift Sources/ParcApp/SplitDropGeometry.swift Sources/ParcApp/SidebarSplitCellMenu.swift \
    tests/SidebarRows/SplitCellMenuTests.swift -o "$output/native"
"$output/native"
