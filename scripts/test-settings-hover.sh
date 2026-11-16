#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/SettingsHoverButton.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/tests/SettingsHoverTests.swift" -o "$output/settings-hover-tests"
"$output/settings-hover-tests"
