#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-owner-sequence.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/WindowOwnerSequence.swift" \
  "$root/tests/WindowOwnerSequence/main.swift" -o "$build/owner-sequence"
"$build/owner-sequence"
