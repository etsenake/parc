#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 tests/Tooltip/support.py "$output" SpaceTheme.swift)
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift "${tooltip[@]}" \
    Sources/ParcApp/SidebarTitleField.swift Sources/ParcApp/SidebarSplitTitleView.swift Sources/ParcApp/SidebarSplitCellLayout.swift \
    Sources/ParcApp/FolderUndoManager.swift Sources/ParcApp/SidebarSplitTitleUndo.swift \
    Sources/ParcApp/SidebarGroupIconPicker.swift \
    Sources/ParcApp/SidebarEmojiPicker.swift Sources/ParcApp/SidebarIconCatalog.swift Sources/ParcApp/SidebarRowAppearance.swift tests/SidebarRows/SplitAppearanceTests.swift -o "$output/check"
cp -R Resources/CustomInfoPicker "$output/CustomInfoPicker"
"$output/check"
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library Sources/ParcApp/SidebarRowAppearance.swift \
    Sources/ParcApp/SidebarSplitCellLayout.swift "$output/TooltipThemePalette.swift" Sources/ParcCore/SpaceTheme.swift \
    tests/SidebarRows/SplitCellLayoutTests.swift -o "$output/layout"
"$output/layout"
python3 tests/SidebarRows/split_close_gate_check.py
mkdir "$output/drag"
drag_list=$(python3 -B tests/Support/sidebar_item_drag.py "$output/drag" Sources/ParcCore/*.swift)
drag=()
while IFS= read -r path; do drag+=("$path"); done <<< "$drag_list"
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift "${drag[@]}" \
    tests/SidebarRows/SidebarMoveCopyTests.swift -o "$output/copy"
"$output/copy"
python3 tests/SidebarRows/split_copy_drag_check.py
