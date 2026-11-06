#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-return-modifiers.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/CommandBarSubmission.swift" \
  "$root/tests/CommandBar/ReturnModifierTests.swift" -o "$build/keys"
"$build/keys"
xcrun swiftc -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root"/Sources/ParcCore/*.swift \
  "$root/Sources/ParcApp/CommandBarSubmission.swift" \
  "$root/tests/CommandBar/BackgroundOpenTests.swift" -o "$build/model"
"$build/model"
