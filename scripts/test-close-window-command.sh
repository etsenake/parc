#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-close-window.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/BrowserWindowCloseCommand.swift" \
  "$root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$root/tests/KeyboardNavigation/CloseWindowCommandTests.swift" -o "$build/close-window"
"$build/close-window"
