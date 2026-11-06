#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -parse-as-library Sources/ParcCore/*.swift \
    Sources/ParcApp/FolderUndoManager.swift Sources/ParcApp/SidebarSplitTitleUndo.swift \
    tests/SidebarRows/SplitTitleUndoTests.swift -o "$output/check"
"$output/check"
