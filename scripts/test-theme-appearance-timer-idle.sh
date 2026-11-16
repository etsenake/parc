#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-theme-appearance-timer-idle.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$check_dir" SpaceTheme.swift)
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 "${tooltip[@]}" \
  "$repo_root/Sources/ParcCore/SpaceTheme.swift" \
  "$repo_root/Sources/ParcCore/SpaceThemeEditor.swift" \
  "$repo_root/Sources/ParcApp/AppAppearance.swift" \
  "$repo_root/Sources/ParcApp/ThemeHapticFeedback.swift" \
  "$repo_root/Sources/ParcApp/SpaceThemeEditorView.swift" \
  "$repo_root/tests/Support/AppKitObservation.swift" \
  "$repo_root/tests/ThemeAppearanceTimerIdle/ThemeAppearanceTimerIdleTests.swift" \
  -o "$check_dir/theme-appearance-timer-idle"
cp -R "$repo_root/Resources/ThemeEditor" "$check_dir/ThemeEditor"
"$check_dir/theme-appearance-timer-idle"
python3 "$repo_root/tests/ThemeAppearanceTimerIdle/check.py"
