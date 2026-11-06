#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -parse-as-library Sources/ParcCore/*.swift \
    Sources/ParcApp/FolderUndoManager.swift Sources/ParcApp/PArcToast.swift Sources/ParcApp/CloseUndo.swift \
    tests/CloseUndoTests.swift -o "$output/check"
"$output/check"
