#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/ParcSplitView.swift Sources/ParcApp/PageCardShadow.swift Sources/ParcApp/SplitMarginHandle.swift Sources/ParcApp/PointerCover.swift Sources/ParcApp/SplitDropGeometry.swift tests/SidebarRows/SplitDividerTests.swift -o "$output/check"
"$output/check"
