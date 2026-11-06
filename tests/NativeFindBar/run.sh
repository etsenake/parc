#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-find-bar"
mkdir -p "$output_dir"
xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
  -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -I "$repo_root/Engine/ParcNative" \
  "$repo_root/Engine/ParcNative/focus_manager.mm" \
  "$repo_root/Engine/ParcNative/find_bar_view.mm" \
  "$repo_root/tests/NativeFindBar/Tests.mm" \
  -framework Cocoa -framework QuartzCore -o "$output_dir/NativeFindBarTests"
"$output_dir/NativeFindBarTests"
