#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
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
  Sources/ParcApp/OnboardingReadyContent.swift Sources/ParcApp/TranslucentButtonFace.swift Sources/ParcApp/PointerCover.swift Sources/ParcApp/ReloadControl.swift Sources/ParcApp/PointingHand.swift "$output/NativeBases.swift" \
  tests/OnboardingSetupCardTests.swift -o "$output/check"
cp -R Resources/ThemeTextures "$output/ThemeTextures"
"$output/check"
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  Sources/ParcCore/SpaceTheme.swift \
  Sources/ParcCore/OnboardingStepMotion.swift \
  Sources/ParcCore/WindowFrame.swift \
  Sources/ParcApp/WindowFramePreferences.swift \
  Sources/ParcApp/OnboardingWindowFrameLayout.swift \
  Sources/ParcApp/OnboardingSetupCard.swift \
  Sources/ParcApp/BrowserImportBackdrop.swift \
  Sources/ParcApp/SidebarSpacePaging.swift \
  tests/OnboardingWindowFrameTests.swift -o "$output/frame"
"$output/frame"
