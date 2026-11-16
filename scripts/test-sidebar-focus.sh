#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library "$repo_root/Sources/ParcCore/SidebarKeyboardCursor.swift" \
  "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/SidebarFocusTests.swift" -o "$repo_root/build/tests/sidebar-focus"
"$repo_root/build/tests/sidebar-focus"
