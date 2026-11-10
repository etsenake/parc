#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
# A busy dialog button shows the onboarding button's spinner.
spinner=$(python3 -B tests/Support/declarations.py "$output/PArcButtonSpinner.swift" PArcButtonSpinner)
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift \
    Sources/ParcApp/PArcDialog.swift Sources/ParcApp/PointingHand.swift "$spinner" Sources/ParcApp/InterProfileMoveDialog.swift \
    tests/PArcDialog/PArcDialogTests.swift -o "$output/check"
"$output/check"
