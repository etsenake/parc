#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-safari-export.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 -o "$build/check" \
  "$root"/Sources/ParcCore/*.swift \
  "$root/tests/SafariBrowsingExport/SafariBrowsingExportTests.swift"
"$build/check"
