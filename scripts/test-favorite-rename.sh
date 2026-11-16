#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
spinner=$(python3 -B tests/Support/declarations.py "$output/ParcButtonSpinner.swift" ParcButtonSpinner)
xcrun swiftc tests/Support/TestFailure.swift -parse-as-library Sources/ParcCore/*.swift \
    Sources/ParcApp/FolderUndoManager.swift Sources/ParcApp/SidebarTabTitleUndo.swift \
    Sources/ParcApp/FavoriteRenameDialog.swift Sources/ParcApp/ParcDialog.swift Sources/ParcApp/PointingHand.swift "$spinner" tests/SidebarRows/FavoriteRenameTests.swift -o "$output/check"
"$output/check"
