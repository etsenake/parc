#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$root/build/tests/settings-focus"
mkdir -p "$build"
xcrun swiftc -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/SettingsFocus.swift" "$root/tests/SettingsFocus/Tests.swift" \
  -o "$build/settings-focus"
"$build/settings-focus"
