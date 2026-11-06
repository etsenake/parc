#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-javascript-dialogs"
mkdir -p "$output_dir"
xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
  -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -I "$repo_root/Engine/ParcNative" \
  "$repo_root/Engine/ParcNative/javascript_dialog_presenter.mm" \
  "$repo_root/tests/NativeJavaScriptDialogs/Tests.mm" \
  -framework Cocoa -o "$output_dir/NativeJavaScriptDialogTests"
"$output_dir/NativeJavaScriptDialogTests"
