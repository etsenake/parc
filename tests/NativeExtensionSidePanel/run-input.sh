#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-extension-side-panel-input"
mkdir -p "$output_dir"
xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
  -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -I "$repo_root/Engine/ParcNative" \
  "$repo_root/tests/NativeExtensionSidePanel/input_tests.mm" \
  -framework AppKit -o "$output_dir/SidePanelInputTests"
"$output_dir/SidePanelInputTests"
