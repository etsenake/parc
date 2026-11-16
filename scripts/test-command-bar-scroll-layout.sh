#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-command-scroll.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc "$root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/CommandResultsTable.swift" \
  "$root/tests/CommandBar/ResultScrollLayoutTests.swift" -o "$build/test"
"$build/test"
