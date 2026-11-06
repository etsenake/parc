#!/bin/bash
# Inert native Settings hover/ownership checks; no visible window or browser.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/SettingsHoverButton.swift" \
  "$repo_root/tests/SettingsHoverTests.swift" -o "$output/settings-hover-tests"
"$output/settings-hover-tests"
