#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-exit-command.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/BrowserExitCommand.swift" \
  "$root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$root/tests/KeyboardNavigation/ExitCommandTests.swift" -o "$build/exit-command"
"$build/exit-command"
