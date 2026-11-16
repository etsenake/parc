#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-shortcut-hint.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -whole-module-optimization -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcCore/SpaceTheme.swift" \
  "$repo_root/Sources/ParcApp/ParcToast.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/ShortcutPriorityHintView.swift" \
  "$repo_root/tests/KeyboardNavigation/ShortcutHintPresentationTests.swift" \
  -o "$check_dir/shortcut-hint"
"$check_dir/shortcut-hint" "$@"
