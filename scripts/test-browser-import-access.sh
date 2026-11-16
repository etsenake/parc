#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-import-access.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc "$root/tests/Support/TestFailure.swift" -warnings-as-errors -target arm64-apple-macos13.0 -o "$build/check" \
  "$root"/Sources/ParcCore/*.swift \
  "$root/Sources/ParcApp/BrowserImportCoordinator.swift" \
  "$root/Sources/ParcApp/SetupExtensionChanges.swift" \
  "$root/Sources/ParcApp/ImportedExtensionRetries.swift" \
  "$root"/tests/BrowserImportAccess/*.swift
"$build/check"
