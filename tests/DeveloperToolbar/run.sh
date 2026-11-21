#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$root/build/tests/developer-toolbar"
mkdir -p "$build"
xcrun swiftc "$root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors \
  -target arm64-apple-macos13.0 -module-cache-path "$build/modules" \
  "$root/Sources/ParcApp/DeveloperToolbarLayout.swift" \
  "$root/tests/DeveloperToolbar/Tests.swift" \
  -o "$build/developer-toolbar"
"$build/developer-toolbar"
