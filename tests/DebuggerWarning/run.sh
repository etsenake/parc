#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$root/build/tests/debugger-warning"
mkdir -p "$build"
xcrun swiftc "$root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors \
  -target arm64-apple-macos13.0 -module-cache-path "$build/modules" \
  "$root/Sources/ParcApp/DeveloperToolbarLayout.swift" \
  "$root/Sources/ParcApp/DebuggerWarningLayout.swift" \
  "$root/tests/DebuggerWarning/Tests.swift" \
  -o "$build/debugger-warning"
"$build/debugger-warning"
