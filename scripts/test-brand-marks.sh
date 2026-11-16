#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
check_root=$(mktemp -d "${TMPDIR:-/tmp}/parc-brand-mark-check.XXXXXX")
trap 'rm -rf "$check_root"' EXIT
app="$check_root/BrandMarkChecks.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources/AppIcons"
cp -R "$repo_root/Resources/AppIcons/Marks" "$app/Resources/AppIcons/"
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/ParcBrandMark.swift" \
  "$repo_root/tests/BrandMarks/main.swift" -o "$app/MacOS/BrandMarkChecks"
"$app/MacOS/BrandMarkChecks" "$@"
