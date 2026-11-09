#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 tests/Tooltip/support.py "$output" SpaceTheme.swift)
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 "${tooltip[@]}" \
  Sources/ParcCore/SpaceTheme.swift \
  Sources/ParcCore/SpaceThemeEditor.swift \
  Sources/ParcApp/AppAppearance.swift \
  Sources/ParcApp/ThemeHapticFeedback.swift \
  Sources/ParcApp/SpaceThemeEditorView.swift \
  Sources/ParcApp/OnboardingCloseCommand.swift \
  tests/OnboardingKeyboardTests.swift \
  -o "$output/check"
# An unbundled executable's Bundle.main.resourceURL is its own directory.
cp -R Resources/ThemeTextures "$output/ThemeTextures"
"$output/check"
