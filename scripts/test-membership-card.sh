#!/bin/bash
# File-backed model + inert AppKit components only. Never creates/drives a browser.
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
mkdir -p "$output/CardChecks.app/Contents/MacOS" "$output/CardChecks.app/Contents/Resources"
mkdir -p "$output/CardChecks.app/Contents/Resources/Onboarding"
cp Resources/Onboarding/grain-1.png "$output/CardChecks.app/Contents/Resources/Onboarding/"
cp -R Resources/MembershipCard "$output/CardChecks.app/Contents/Resources/"
# Compile the real shared base classes without Sidebar's unrelated browser owners.
python3 - "$output/NativeBases.swift" <<'PY'
import pathlib,sys
s=pathlib.Path('Sources/ParcApp/SidebarView.swift').read_text()
a=s[s.index('final class ActionButton:'):s.index('final class MenuAction:')]
b=s[s.index('class LayoutView:'):s.index('final class FlippedStackView:')]
pathlib.Path(sys.argv[1]).write_text('import AppKit\nextension NSColor { static let parcInk = NSColor.labelColor }\n'+a+b)
PY
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/MembershipCard.swift \
  Sources/ParcApp/MembershipCardView.swift Sources/ParcApp/MembershipCardSettingsView.swift \
  Sources/ParcApp/SettingsHoverButton.swift Sources/ParcApp/SettingsFocus.swift Sources/ParcApp/SettingsPresentation.swift \
  Sources/ParcApp/TranslucentButtonFace.swift Sources/ParcApp/ReloadControl.swift \
  "$output/NativeBases.swift" tests/MembershipCardTests.swift -o "$output/CardChecks.app/Contents/MacOS/CardChecks"
"$output/CardChecks.app/Contents/MacOS/CardChecks" "${1:-$output}"
