#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-theme-rendering.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
# Pure renderer configuration, inert native views/windows and CA animation
# ownership only. No visible window, browser, page or engine is opened.
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$check_dir" SpaceTheme.swift ThemeRenderer.swift)
xcrun swiftc -warnings-as-errors -whole-module-optimization -parse-as-library -target arm64-apple-macos13.0 "${tooltip[@]}" \
  "$repo_root/Sources/ParcCore/SpaceTheme.swift" \
  "$repo_root/Sources/ParcCore/SpaceThemeEditor.swift" \
  "$repo_root/Sources/ParcApp/AppAppearance.swift" \
  "$repo_root/Sources/ParcApp/ThemeHapticFeedback.swift" \
  "$repo_root/Sources/ParcApp/ThemeRenderer.swift" \
  "$repo_root/Sources/ParcApp/SpaceThemeEditorView.swift" \
  "$repo_root/tests/SpaceThemeRenderingTests.swift" \
  -o "$check_dir/theme-rendering"
cp -R "$repo_root/Resources/ThemeTextures" "$repo_root/Resources/ThemeEditor" "$check_dir/"
"$check_dir/theme-rendering"
