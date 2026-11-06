#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 tests/Tooltip/support.py "$output" SpaceTheme.swift)
xcrun swiftc -parse-as-library Sources/ParcCore/*.swift "${tooltip[@]}" \
    Sources/ParcApp/SidebarTitleField.swift Sources/ParcApp/SidebarSplitTitleView.swift Sources/ParcApp/SidebarSplitCellLayout.swift Sources/ParcApp/SidebarGroupIconPicker.swift \
    Sources/ParcApp/SidebarEmojiPicker.swift Sources/ParcApp/SidebarIconCatalog.swift Sources/ParcApp/SidebarRowAppearance.swift \
    tests/SidebarRows/SplitTitleTests.swift -o "$output/check"
"$output/check"
