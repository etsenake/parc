#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
spinner=$(python3 -B tests/Support/declarations.py "$output/PArcButtonSpinner.swift" PArcButtonSpinner)
xcrun swiftc -parse-as-library Sources/ParcCore/*.swift \
    Sources/ParcApp/FolderUndoManager.swift Sources/ParcApp/SidebarTabTitleUndo.swift \
    Sources/ParcApp/FavoriteRenameDialog.swift Sources/ParcApp/PArcDialog.swift Sources/ParcApp/PointingHand.swift "$spinner" tests/SidebarRows/FavoriteRenameTests.swift -o "$output/check"
"$output/check"
