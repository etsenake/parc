#!/bin/bash
# Model and inert native Space management checks; never opens a browser/window.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
check_dir="$repo_root/build/tests/space-management-check"
mkdir -p "$check_dir"
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$check_dir" SpaceTheme.swift)
xcrun swiftc -warnings-as-errors -whole-module-optimization -parse-as-library "${tooltip[@]}" \
  "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/Sources/ParcApp/SidebarChromeLayout.swift" \
  "$repo_root/Sources/ParcApp/SidebarAccessibility.swift" \
  "$repo_root/Sources/ParcApp/SidebarSpaceHeader.swift" \
  "$repo_root/Sources/ParcApp/SidebarSpaceMenu.swift" \
  "$repo_root/Sources/ParcApp/SidebarRowAppearance.swift" \
  "$repo_root/tests/SpaceManagementTests.swift" \
  -o "$check_dir/space-management"
"$check_dir/space-management"
