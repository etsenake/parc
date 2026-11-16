#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-find-presentation.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
tooltip=()
while IFS= read -r path; do tooltip+=("$path"); done < <(python3 "$repo_root/tests/Tooltip/support.py" "$check_dir")
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 "${tooltip[@]}" \
  "$repo_root/Sources/ParcApp/PageFindView.swift" \
  "$repo_root/tests/KeyboardNavigation/FindPresentationTests.swift" \
  -o "$check_dir/find-presentation"
"$check_dir/find-presentation"
