#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/parc-sidebar-rows.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$root/tests/Tooltip/support.py" "$tmp")
xcrun swiftc -parse-as-library "${tooltip[@]}" "$root/Sources/ParcApp/SidebarRowActionButton.swift" \
    "$root/Sources/ParcApp/SidebarRowAppearance.swift" \
    "$root/tests/SidebarRows/SidebarRowActionButtonTests.swift" -o "$tmp/sidebar-rows"
"$tmp/sidebar-rows"
# The appearance-resolved layer colour helper, without the rest of the theme renderer.
sed -n '/^extension NSColor {/,/^}/p' "$root/Sources/ParcApp/ThemeRenderer.swift" | { echo "import AppKit"; cat; } > "$tmp/ColorInAppearance.swift"
xcrun swiftc -parse-as-library "$root/Sources/ParcApp/SidebarRowAppearance.swift" "$tmp/ColorInAppearance.swift" \
    "$root/tests/SidebarRows/SidebarRowAppearanceTests.swift" -o "$tmp/sidebar-row-appearance"
"$tmp/sidebar-row-appearance"
