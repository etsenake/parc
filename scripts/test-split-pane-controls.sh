#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift tests/SidebarRows/SplitPaneControlsTests.swift -o "$output/model"
"$output/model"
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/SplitPaneMenu.swift Sources/ParcApp/LinkPasteboard.swift Sources/ParcApp/MenuItemImage.swift Sources/ParcApp/SplitPaneHighlight.swift tests/SidebarRows/SplitPaneMenuTests.swift -o "$output/native"
cp -R Resources/SplitPaneMenu "$output/SplitPaneMenu"
"$output/native"
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 tests/Tooltip/support.py "$output")
xcrun swiftc -warnings-as-errors -parse-as-library "${tooltip[@]}" Sources/ParcApp/SplitPaneControl.swift tests/Support/AppKitObservation.swift tests/SidebarRows/SplitPaneControlPresentationTests.swift -o "$output/presentation"
"$output/presentation"
