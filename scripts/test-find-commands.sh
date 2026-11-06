#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/parc-find-commands.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library -framework AppKit -framework Carbon \
  Sources/ParcApp/BrowserFindCommand.swift Sources/ParcApp/KeyboardShortcuts.swift \
  Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift \
  tests/KeyboardNavigation/NativeShortcutStub.swift tests/KeyboardNavigation/FindCommandTests.swift \
  -o "$test_dir/find-commands"
"$test_dir/find-commands"
