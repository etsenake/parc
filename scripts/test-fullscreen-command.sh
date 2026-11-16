#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-fullscreen-command.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc "$root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/BrowserWindowFullscreenCommand.swift" \
  "$root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$root/tests/KeyboardNavigation/FullscreenCommandTests.swift" -o "$build/fullscreen-command"
"$build/fullscreen-command"
