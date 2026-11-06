#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
  "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/BrowserImportTests.swift" \
  -o "$repo_root/build/tests/browser-import"
"$repo_root/build/tests/browser-import"
xcrun swiftc -parse-as-library -warnings-as-errors \
  "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/BrowserImportRestartTests.swift" \
  -o "$repo_root/build/tests/browser-import-restart"
"$repo_root/build/tests/browser-import-restart"
