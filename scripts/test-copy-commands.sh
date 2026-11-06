#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -parse-as-library "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
"$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/CopyCommandTests.swift" -o "$repo_root/build/tests/copy-commands"
"$repo_root/build/tests/copy-commands"
