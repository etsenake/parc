#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$root/build/tests/native-extension-controls"
mkdir -p "$build"
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$root/tests/Tooltip/support.py" "$build")
xcrun swiftc "$root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors \
  -target arm64-apple-macos13.0 -module-cache-path "$build/modules" "${tooltip[@]}" \
  "$root/Sources/ParcApp/ExtensionControls.swift" \
  "$root/tests/NativeExtensionControls/Tests.swift" \
  -o "$build/extension-controls"
"$build/extension-controls"
