#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PARC_TEST_BUILD_DIR:-$root/build/tests/renderer-crash-presentation}"
mkdir -p "$out"
# PageFailureView pins its text through SidebarMotionController, which needs
# the sidebar geometry and theme types it is compiled with elsewhere.
xcrun swiftc -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/PageFailureView.swift" \
  "$root/Sources/ParcApp/SadTabContent.swift" \
  "$root/Sources/ParcApp/SidebarMotionController.swift" \
  "$root/Sources/ParcApp/SidebarChromeLayout.swift" \
  "$root/Sources/ParcApp/WindowStandardButtons.swift" \
  "$root/Sources/ParcApp/ThemeRenderer.swift" \
  "$root/Sources/ParcCore/SpaceTheme.swift" \
  "$root/tests/RendererCrashPresentation/Tests.swift" \
  -framework AppKit -o "$out/tests"
# An unbundled executable's Bundle.main.resourceURL is its own directory.
rm -rf "$out/SadTab"
cp -R "$root/Resources/SadTab" "$out/SadTab"
"$out/tests"
