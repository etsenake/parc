#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/SpaceTheme.swift" \
  "$repo_root/Sources/ParcCore/SpaceThemeEditor.swift" \
  "$repo_root/tests/SpaceThemeEditorTests.swift" \
  -o "$repo_root/build/tests/space-theme-editor"
"$repo_root/build/tests/space-theme-editor"
