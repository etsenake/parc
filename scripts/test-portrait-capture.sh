#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
check_root=$(mktemp -d "${TMPDIR:-/tmp}/parc-portrait-check.XXXXXX")
trap 'rm -rf "$check_root"' EXIT
app="$check_root/PortraitChecks.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources/ThemeEditor" "$app/Resources/AppIcons"
cp "$repo_root/Resources/ThemeEditor/presets.json" "$app/Resources/ThemeEditor/"
cp -R "$repo_root/Resources/AppIcons/Marks" "$app/Resources/AppIcons/"
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$check_root")
xcrun swiftc -warnings-as-errors -target arm64-apple-macos13.0 -parse-as-library "${tooltip[@]}" "$repo_root/Sources/ParcApp/PortraitCapture.swift" \
  "$repo_root/Sources/ParcApp/CaptureMotion.swift" \
  "$repo_root/Sources/ParcApp/DownloadArrivalMotion.swift" \
  "$repo_root/Sources/ParcApp/ParcBrandMark.swift" \
  "$repo_root/Sources/ParcApp/PortraitDesktopSnapshot.swift" \
  "$repo_root/Sources/ParcApp/CapturedImage.swift" \
  "$repo_root/tests/CapturePortrait/main.swift" -o "$app/MacOS/PortraitChecks"
"$app/MacOS/PortraitChecks"
