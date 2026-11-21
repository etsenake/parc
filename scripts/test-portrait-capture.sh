#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
check_root=$(mktemp -d "${TMPDIR:-/tmp}/parc-portrait-check.XXXXXX")
trap 'rm -rf "$check_root"' EXIT
app="$check_root/PortraitChecks.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources/ThemeEditor" "$app/Resources/AppIcons"
cp "$repo_root/Resources/ThemeEditor/presets.json" "$app/Resources/ThemeEditor/"
cp -R "$repo_root/Resources/AppIcons/Marks" "$app/Resources/AppIcons/"
source_dir="$repo_root/Sources/ParcApp"
sources=("$repo_root/Sources/ParcCore/"*.swift "$source_dir/CapturePresentation.swift" "$source_dir/NoteTheme.swift"
  "$source_dir/NoteAnimation.swift" "$source_dir/NoteFloatingPanel.swift" "$source_dir/NoteControls.swift"
  "$source_dir/NoteCustomEmojiImages.swift" "$source_dir/DocumentDefaultIcon.swift" "$source_dir/LibraryArtwork.swift"
  "$source_dir/ParcDialog.swift")
python3 -c 'import sys; t = open(sys.argv[1]).read(); open(sys.argv[2], "w").write("import SwiftUI\n" + t[t.index("struct ParcButtonSpinner"):t.index("extension NSColor")])' \
  "$source_dir/OnboardingProgressionButton.swift" "$check_root/ParcButtonSpinner.swift"
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$check_root" "${sources[@]}")
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -target arm64-apple-macos13.0 -parse-as-library "${tooltip[@]}" "${sources[@]}" \
  "$check_root/ParcButtonSpinner.swift" "$repo_root/Sources/ParcApp/PortraitCapture.swift" \
  "$repo_root/Sources/ParcApp/CaptureMotion.swift" \
  "$repo_root/Sources/ParcApp/DownloadArrivalMotion.swift" \
  "$repo_root/Sources/ParcApp/ParcBrandMark.swift" \
  "$repo_root/Sources/ParcApp/PortraitDesktopSnapshot.swift" \
  "$repo_root/Sources/ParcApp/CapturedImage.swift" \
  "$repo_root/tests/CapturePortrait/main.swift" -o "$app/MacOS/PortraitChecks"
"$app/MacOS/PortraitChecks"
