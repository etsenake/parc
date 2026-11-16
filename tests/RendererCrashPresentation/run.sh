#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PARC_TEST_BUILD_DIR:-$root/build/tests/renderer-crash-presentation}"
mkdir -p "$out"
xcrun swiftc "$root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/PageFailureView.swift" \
  "$root/Sources/ParcApp/SadTabContent.swift" \
  "$root/Sources/ParcApp/SidebarMotionController.swift" \
  "$root/Sources/ParcApp/SidebarChromeLayout.swift" \
  "$root/Sources/ParcApp/WindowStandardButtons.swift" \
  "$root/Sources/ParcApp/ThemeRenderer.swift" \
  "$root/Sources/ParcCore/SpaceTheme.swift" \
  "$root/tests/RendererCrashPresentation/Tests.swift" \
  -framework AppKit -o "$out/tests"
rm -rf "$out/SadTab" "$out/PageFailure"
cp -R "$root/Resources/SadTab" "$out/SadTab"
cp -R "$root/Resources/PageFailure" "$out/PageFailure"
"$out/tests"
