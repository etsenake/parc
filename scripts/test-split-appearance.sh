#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 tests/Tooltip/support.py "$output" SpaceTheme.swift)
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift "${tooltip[@]}" \
    Sources/ParcApp/SidebarTitleField.swift Sources/ParcApp/SidebarSplitTitleView.swift Sources/ParcApp/SidebarSplitCellLayout.swift \
    Sources/ParcApp/FolderUndoManager.swift Sources/ParcApp/SidebarSplitTitleUndo.swift \
    Sources/ParcApp/SidebarGroupIconPicker.swift \
    Sources/ParcApp/SidebarEmojiPicker.swift Sources/ParcApp/SidebarIconCatalog.swift Sources/ParcApp/SidebarRowAppearance.swift tests/SidebarRows/SplitAppearanceTests.swift -o "$output/check"
# An unbundled executable's Bundle.main.resourceURL is its own directory.
cp -R Resources/CustomInfoPicker "$output/CustomInfoPicker"
"$output/check"
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcApp/SidebarRowAppearance.swift \
    Sources/ParcApp/SidebarSplitCellLayout.swift tests/SidebarRows/SplitCellLayoutTests.swift -o "$output/layout"
"$output/layout"
python3 tests/SidebarRows/split_close_gate_check.py
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/SidebarItemDrag.swift \
    tests/SidebarRows/SidebarMoveCopyTests.swift -o "$output/copy"
"$output/copy"
python3 tests/SidebarRows/split_copy_drag_check.py
