#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -target arm64-apple-macos13.0 -framework AppKit \
  Sources/ParcApp/CommandBarEditState.swift tests/CommandBarEditTests.swift \
  -o "$TMP/command-bar-edit-tests"
"$TMP/command-bar-edit-tests"
