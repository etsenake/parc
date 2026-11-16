#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-theme-appearance.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$check_dir" SpaceTheme.swift)
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -whole-module-optimization -parse-as-library -target arm64-apple-macos13.0 "${tooltip[@]}" \
  "$repo_root/Sources/ParcCore/SpaceTheme.swift" \
  "$repo_root/Sources/ParcCore/SpaceThemeEditor.swift" \
  "$repo_root/Sources/ParcApp/AppAppearance.swift" \
  "$repo_root/Sources/ParcApp/ThemeHapticFeedback.swift" \
  "$repo_root/Sources/ParcApp/SpaceThemeEditorView.swift" \
  "$repo_root/tests/SpaceThemeAppearanceTests.swift" \
  -o "$check_dir/theme-appearance"
"$check_dir/theme-appearance"
