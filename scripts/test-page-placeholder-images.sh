#!/bin/bash
set -euo pipefail

# The frozen frame each tab keeps for its placeholders in other windows: one
# image per tab shared by every window, and the order a window copies its
# arrived panes in. Model only; no browser runs.
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -warnings-as-errors -parse-as-library "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/PagePlaceholderImagesTests.swift" -o "$repo_root/build/tests/page-placeholder-images"
exec "$repo_root/build/tests/page-placeholder-images"
