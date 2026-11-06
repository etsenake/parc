#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  Sources/ParcCore/SpaceTheme.swift \
  Sources/ParcApp/OnboardingSetupCard.swift \
  Sources/ParcApp/OnboardingProgressionButton.swift \
  Sources/ParcApp/OnboardingConfettiView.swift \
  tests/OnboardingSetupCardTests.swift -o "$output/check"
# An unbundled executable's Bundle.main.resourceURL is its own directory.
cp -R Resources/ThemeTextures "$output/ThemeTextures"
"$output/check"
