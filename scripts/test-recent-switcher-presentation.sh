#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-recent-switcher.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -whole-module-optimization -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/RecentTabSwitcherView.swift" \
  "$repo_root/tests/KeyboardNavigation/RecentSwitcherPresentationTests.swift" \
  -o "$check_dir/recent-switcher"
# An unbundled executable's Bundle.main.resourceURL is its own directory.
cp -R "$repo_root/Resources/RecentSwitcher" "$check_dir/RecentSwitcher"
"$check_dir/recent-switcher"
