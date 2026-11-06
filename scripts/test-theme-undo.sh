#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 tests/Tooltip/support.py "$check_dir" SpaceTheme.swift)
xcrun swiftc -warnings-as-errors -whole-module-optimization -parse-as-library -target arm64-apple-macos13.0 "${tooltip[@]}" \
    Sources/ParcCore/*.swift Sources/ParcApp/AppAppearance.swift \
    Sources/ParcApp/FolderUndoManager.swift Sources/ParcApp/SpaceThemeUndo.swift \
    Sources/ParcApp/ThemeHapticFeedback.swift Sources/ParcApp/SpaceThemeEditorView.swift tests/SpaceThemeUndoTests.swift -o "$check_dir/check"
"$check_dir/check"
