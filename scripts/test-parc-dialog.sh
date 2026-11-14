#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
spinner=$(python3 -B tests/Support/declarations.py "$output/ParcButtonSpinner.swift" ParcButtonSpinner)
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift \
    Sources/ParcApp/ParcDialog.swift Sources/ParcApp/PointingHand.swift "$spinner" Sources/ParcApp/InterProfileMoveDialog.swift \
    tests/ParcDialog/ParcDialogTests.swift -o "$output/check"
"$output/check"
