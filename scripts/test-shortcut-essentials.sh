#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-essentials.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -whole-module-optimization -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/Sources/ParcApp/ShortcutEssentialsWindow.swift" "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/ShortcutKeycapView.swift" \
  "$repo_root/Sources/ParcApp/ShortcutSmileyView.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/EssentialsTests.swift" \
  -o "$check_dir/essentials"
"$check_dir/essentials" "$repo_root/Resources/NoteFonts/Nunito-ExtraBold.ttf"
