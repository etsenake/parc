#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/AppIconController.swift" \
  "$repo_root/Sources/ParcApp/IconSettingsView.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/tests/IconSettingsTests.swift" -o "$output/icon-settings-tests"
"$output/icon-settings-tests" "$repo_root" "$@"
