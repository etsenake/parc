#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
check_root=$(mktemp -d "${TMPDIR:-/tmp}/parc-capture-palette.XXXXXX")
trap 'rm -rf "$check_root"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcCore/"*.swift "$repo_root/tests/CapturePaletteTests.swift" -o "$check_root/CapturePaletteChecks"
"$check_root/CapturePaletteChecks"
