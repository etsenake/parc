#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 tests/Tooltip/support.py "$TMP" SpaceTheme.swift)
xcrun swiftc tests/Support/TestFailure.swift -target arm64-apple-macos13.0 -framework AppKit "${tooltip[@]}" \
  Sources/ParcCore/*.swift \
  Sources/ParcApp/CommandResultCell.swift Sources/ParcApp/CommandBarAppearance.swift tests/CommandBar/SuggestionDeletionTests.swift \
  -o "$TMP/command-bar-deletion-tests"
"$TMP/command-bar-deletion-tests"
