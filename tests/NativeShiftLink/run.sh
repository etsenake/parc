#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-shift-link"
mkdir -p "$output_dir"
xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
  -fobjc-arc -Wall -Wextra -Werror \
  -I "$repo_root/Engine/ParcNative" \
  "$repo_root/tests/NativeShiftLink/main.mm" \
  -framework AppKit -o "$output_dir/NativeShiftLinkTests"
"$output_dir/NativeShiftLinkTests"
