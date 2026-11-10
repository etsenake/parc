#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -whole-module-optimization -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/Sources/ParcApp/ShortcutRecorderView.swift" \
  "$repo_root/Sources/ParcApp/ThemeRenderer.swift" \
  "$repo_root/Sources/ParcApp/ShortcutsSettingsView.swift" \
  "$repo_root/Sources/ParcApp/ShortcutKeycapView.swift" \
  "$repo_root/Sources/ParcApp/ShortcutSmileyView.swift" \
  "$repo_root/Sources/ParcCore/SpaceTheme.swift" \
  "$repo_root/Sources/ParcCore/NumberedTarget.swift" \
  "$repo_root/Sources/ParcApp/PArcToast.swift" \
  "$repo_root/Sources/ParcApp/ShortcutPriorityHintView.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/ShortcutCueTests.swift" \
  -o "$repo_root/build/tests/shortcut-cue"
"$repo_root/build/tests/shortcut-cue"
