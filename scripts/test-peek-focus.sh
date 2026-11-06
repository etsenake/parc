#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output_dir="$repo_root/build/tests/peek-focus"
mkdir -p "$output_dir"
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/PeekFocusReturn.swift" \
  "$repo_root/tests/PeekFocus/main.swift" \
  -o "$output_dir/PeekFocusTests"
"$output_dir/PeekFocusTests"
