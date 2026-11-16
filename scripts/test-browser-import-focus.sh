#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-import-focus.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc "$root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/BrowserImportFocus.swift" \
  "$root/tests/BrowserImportFocus/main.swift" -o "$build/import-focus"
"$build/import-focus"
