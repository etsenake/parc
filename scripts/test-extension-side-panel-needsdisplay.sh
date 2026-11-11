#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-extension-side-panel-needsdisplay.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$check_dir")
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 "${tooltip[@]}" \
  "$repo_root/Sources/ParcApp/SplitPaneControl.swift" \
  "$repo_root/Sources/ParcApp/ExtensionSidePanelView.swift" \
  "$repo_root/tests/ExtensionSidePanelNeedsDisplay/ExtensionSidePanelNeedsDisplayTests.swift" \
  -o "$check_dir/extension-side-panel-needsdisplay"
"$check_dir/extension-side-panel-needsdisplay"
