#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-shortcut-alternates.XXXXXX")"
trap 'rm -rf "$build"' EXIT
for check in AlternateBindingTests CreationDefaultTests MigrationTests CopyCommandTests InventoryCommandTests ChordIndexTests; do
  xcrun swiftc -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
    "$root/Sources/ParcApp/KeyboardShortcuts.swift" \
    "$root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
    "$root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
    "$root/tests/KeyboardNavigation/$check.swift" -o "$build/$check"
  "$build/$check"
done
