#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$root/build/tests/native-extension-side-panel-chrome"
mkdir -p "$build"
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$root/tests/Tooltip/support.py" "$build")
xcrun swiftc -parse-as-library -warnings-as-errors \
  -target arm64-apple-macos13.0 -module-cache-path "$build/modules" "${tooltip[@]}" \
  "$root/Sources/ParcApp/SplitPaneControl.swift" \
  "$root/Sources/ParcApp/ExtensionSidePanelView.swift" \
  "$root/tests/NativeExtensionSidePanelChrome/Tests.swift" \
  -o "$build/extension-side-panel-chrome"
"$build/extension-side-panel-chrome"
