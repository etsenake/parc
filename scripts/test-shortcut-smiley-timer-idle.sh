#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-shortcut-smiley-timer-idle.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
# Inert AppKit cue timer only. No browser, page, engine or shortcut binding edits.
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/ShortcutSmileyView.swift" \
  "$repo_root/tests/Support/AppKitObservation.swift" \
  "$repo_root/tests/ShortcutSmileyTimerIdle/ShortcutSmileyTimerIdleTests.swift" \
  -o "$check_dir/shortcut-smiley-timer-idle"
# An unbundled executable's Bundle.main.resourceURL is its own directory.
cp -R "$repo_root/Resources/Shortcuts" "$check_dir/Shortcuts"
"$check_dir/shortcut-smiley-timer-idle"
python3 "$repo_root/tests/ShortcutSmileyTimerIdle/check.py"
