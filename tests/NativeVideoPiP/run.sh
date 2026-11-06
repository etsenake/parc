#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-video-pip"
mkdir -p "$output_dir"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
  -Wall -Wextra -Werror -Wno-unused-parameter \
  -I "$repo_root/Engine/ParcNative" -I "$repo_root/Sources/ParcEngine" \
  "$repo_root/Sources/ParcEngine/VideoPiPWindow.m" \
  "$repo_root/tests/NativeVideoPiP/Tests.m" -framework Cocoa -framework QuartzCore \
  -o "$output_dir/NativeVideoPiPTests"
"$output_dir/NativeVideoPiPTests"
