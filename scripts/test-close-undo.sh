#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -parse-as-library Sources/ParcCore/*.swift \
    Sources/ParcApp/FolderUndoManager.swift Sources/ParcApp/ParcToast.swift Sources/ParcApp/PointingHand.swift Sources/ParcApp/CloseUndo.swift \
    tests/CloseUndoTests.swift -o "$output/check"
"$output/check"
