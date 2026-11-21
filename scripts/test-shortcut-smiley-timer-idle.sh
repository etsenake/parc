#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-shortcut-smiley-timer-idle.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/ShortcutSmileyView.swift" \
  "$repo_root/tests/Support/AppKitObservation.swift" \
  "$repo_root/tests/ShortcutSmileyTimerIdle/ShortcutSmileyTimerIdleTests.swift" \
  -o "$check_dir/shortcut-smiley-timer-idle"
cp -R "$repo_root/Resources/Shortcuts" "$check_dir/Shortcuts"
"$check_dir/shortcut-smiley-timer-idle"
