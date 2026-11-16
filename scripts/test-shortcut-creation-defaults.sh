#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-creation-defaults.XXXXXX")"
trap 'rm -rf "$build"' EXIT
for check in CreationDefaultTests MigrationTests CopyCommandTests; do
  xcrun swiftc "$root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
    "$root/Sources/ParcApp/KeyboardShortcuts.swift" \
    "$root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
    "$root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
    "$root/tests/KeyboardNavigation/$check.swift" -o "$build/$check"
  "$build/$check"
done
