#!/bin/bash
# Compile actual picker/controller source into an inert AppKit component runner.
# No browser or system identity mutation; all apply effects are injected recorders.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/AppIconController.swift" \
  "$repo_root/Sources/ParcApp/IconSettingsView.swift" \
  "$repo_root/tests/IconSettingsTests.swift" -o "$output/icon-settings-tests"
"$output/icon-settings-tests" "$repo_root" "$@"
