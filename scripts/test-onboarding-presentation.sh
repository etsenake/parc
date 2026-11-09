#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
# The real shared ActionButton/LayoutView without Sidebar's browser owners.
python3 - "$output/NativeBases.swift" <<'PY'
import pathlib,sys
s=pathlib.Path('Sources/ParcApp/SidebarView.swift').read_text()
a=s[s.index('final class ActionButton:'):s.index('final class MenuAction:')]
b=s[s.index('class LayoutView:'):s.index('final class FlippedStackView:')]
pathlib.Path(sys.argv[1]).write_text('import AppKit\nextension NSColor { static let parcInk = NSColor.labelColor }\n'+a+b)
PY
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  Sources/ParcCore/SpaceTheme.swift \
  Sources/ParcCore/OnboardingStepMotion.swift \
  Sources/ParcApp/OnboardingSetupCard.swift \
  Sources/ParcApp/BrowserImportBackdrop.swift \
  Sources/ParcApp/SidebarSpacePaging.swift \
  Sources/ParcApp/OnboardingProgressionButton.swift \
  Sources/ParcApp/OnboardingConfettiView.swift \
  Sources/ParcCore/MembershipCard.swift Sources/ParcApp/MembershipCardView.swift \
  Sources/ParcApp/OnboardingReadyContent.swift Sources/ParcApp/TranslucentButtonFace.swift Sources/ParcApp/ReloadControl.swift "$output/NativeBases.swift" \
  tests/OnboardingSetupCardTests.swift -o "$output/check"
# An unbundled executable's Bundle.main.resourceURL is its own directory.
cp -R Resources/ThemeTextures "$output/ThemeTextures"
"$output/check"
