#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-import-access.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc -warnings-as-errors -target arm64-apple-macos13.0 -o "$build/check" \
  "$root"/Sources/ParcCore/*.swift \
  "$root/Sources/ParcApp/BrowserImportCoordinator.swift" \
  "$root"/tests/BrowserImportAccess/*.swift \
  "$root/tests/Fixtures/FirestoreFixture.swift"
"$build/check"
