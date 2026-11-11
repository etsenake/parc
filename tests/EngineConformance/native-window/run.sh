#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../../.." && pwd)"
output_dir="$repo_root/build/tests/native-window"
mkdir -p "$output_dir"
xcrun clang -x objective-c -arch arm64 -mmacosx-version-min=13.0 \
  -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -I "$repo_root/Engine/ParcNative" \
  "$repo_root/Engine/ParcNative/browser_window.mm" \
  "$repo_root/tests/EngineConformance/native-window/AssociationTests.m" \
  -framework AppKit -o "$output_dir/NativeWindowAssociationTests"
"$output_dir/NativeWindowAssociationTests"
