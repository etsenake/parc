#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/ShortcutPersistSkipTests.swift" \
  -o "$repo_root/build/tests/shortcut-persist-skip"
"$repo_root/build/tests/shortcut-persist-skip"
