#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-shortcut-search.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -whole-module-optimization -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/Sources/ParcApp/ShortcutRecorderView.swift" \
  "$repo_root/Sources/ParcApp/ShortcutsSettingsView.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcCore/NumberedTarget.swift" \
  "$repo_root/Sources/ParcApp/ShortcutKeycapView.swift" \
  "$repo_root/Sources/ParcApp/ShortcutSmileyView.swift" \
  "$repo_root/Sources/ParcApp/ThemeRenderer.swift" \
  "$repo_root/Sources/ParcCore/SpaceTheme.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/SearchPresentationTests.swift" \
  -o "$check_dir/shortcut-search"
"$check_dir/shortcut-search"
