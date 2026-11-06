#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-extension-popup"
mkdir -p "$output_dir"
xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
  -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
  -I "$repo_root/Engine/ParcNative" \
  "$repo_root/Engine/ParcNative/page_host.mm" \
  "$repo_root/Engine/ParcNative/pane_compositor_view.mm" \
  "$repo_root/Engine/ParcNative/extension_popup_presenter.mm" \
  "$repo_root/tests/NativeExtensionPopup/Tests.mm" \
  -framework Cocoa -o "$output_dir/NativeExtensionPopupTests"
"$output_dir/NativeExtensionPopupTests"
