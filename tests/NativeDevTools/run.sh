#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-devtools"
mkdir -p "$output_dir"
xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
  -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -I "$repo_root/Engine/ParcNative" \
  "$repo_root/Engine/ParcNative/devtools_pane_view.mm" \
  "$repo_root/tests/NativeDevTools/Tests.mm" \
  -framework Cocoa -o "$output_dir/NativeDevToolsTests"
"$output_dir/NativeDevToolsTests"
