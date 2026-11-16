#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$root/build/tests/devtools-window"
mkdir -p "$build"
xcrun swiftc "$root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors \
  -target arm64-apple-macos13.0 -module-cache-path "$build/modules" \
  "$root/Sources/ParcApp/DevToolsWindowGeometry.swift" \
  "$root/tests/DevToolsWindow/Tests.swift" \
  -o "$build/devtools-window"
"$build/devtools-window"
