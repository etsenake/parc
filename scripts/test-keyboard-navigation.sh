#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -parse-as-library "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/KeyboardNavigation/SelectionTests.swift" -o "$repo_root/build/tests/tab-selection"
"$repo_root/build/tests/tab-selection"
xcrun swiftc -parse-as-library "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
"$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/MigrationTests.swift" -o "$repo_root/build/tests/shortcut-migration"
"$repo_root/build/tests/shortcut-migration"
xcrun swiftc -warnings-as-errors -parse-as-library "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/KeyLabelTests.swift" -o "$repo_root/build/tests/shortcut-key-labels"
"$repo_root/build/tests/shortcut-key-labels"
xcrun swiftc -parse-as-library "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/KeyboardNavigation/SidebarHierarchyTests.swift" -o "$repo_root/build/tests/sidebar-keyboard-hierarchy"
"$repo_root/build/tests/sidebar-keyboard-hierarchy"
xcrun swiftc -warnings-as-errors -parse-as-library "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcApp/TextFormatMenu.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/FormatCommandTests.swift" -o "$repo_root/build/tests/format-commands"
"$repo_root/build/tests/format-commands"
