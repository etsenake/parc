#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -parse-as-library Sources/ParcCore/*.swift \
    Sources/ParcApp/KeyboardShortcuts.swift \
    tests/KeyboardNavigation/NativeShortcutStub.swift \
    tests/KeyboardNavigation/RenameCommandTests.swift -o "$output/check"
"$output/check"
