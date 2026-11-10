#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-page-host"
mkdir -p "$output_dir"
xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
  -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -I "$repo_root/Engine/ParcNative" \
  "$repo_root/Engine/ParcNative/page_host.mm" \
  "$repo_root/Engine/ParcNative/pane_compositor_view.mm" \
  "$repo_root/Engine/ParcNative/devtools_pane_view.mm" \
  "$repo_root/tests/NativePageHost/Tests.mm" \
  -framework Cocoa -framework QuartzCore -o "$output_dir/NativePageHostTests"
"$output_dir/NativePageHostTests"
