#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-capture-gesture.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -whole-module-optimization -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/Sources/ParcApp/PageCaptureGesture.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/PageCaptureGesture/main.swift" -o "$check_dir/checks"
"$check_dir/checks"
