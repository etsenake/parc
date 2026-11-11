#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
spinner=$(python3 -B tests/Support/declarations.py "$output/PArcButtonSpinner.swift" PArcButtonSpinner)
xcrun swiftc -parse-as-library Sources/ParcApp/QuitWarningPreferences.swift \
    Sources/ParcApp/ApplicationQuitWarning.swift Sources/ParcApp/PArcDialog.swift Sources/ParcApp/PointingHand.swift "$spinner" tests/QuitWarningTests.swift -o "$output/check"
"$output/check"
