#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -parse-as-library Sources/ParcApp/QuitWarningPreferences.swift \
    Sources/ParcApp/ApplicationQuitWarning.swift Sources/ParcApp/PArcDialog.swift tests/QuitWarningTests.swift -o "$output/check"
"$output/check"
