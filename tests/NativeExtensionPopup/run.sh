#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-extension-popup"
mkdir -p "$output_dir"
compile() {
  local output="$1"
  shift
  xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
    -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
    -I "$repo_root/Engine/ParcNative" \
    "$repo_root/Engine/ParcNative/page_host.mm" \
    "$repo_root/Engine/ParcNative/pane_compositor_view.mm" \
    "$repo_root/Engine/ParcNative/extension_popup_presenter.mm" \
    "$@" -framework Cocoa -framework QuartzCore -o "$output_dir/$output"
}
compile NativeExtensionPopupMotionTests \
  "$repo_root/tests/NativeExtensionPopup/MotionTests.mm"
"$output_dir/NativeExtensionPopupMotionTests"
compile NativeExtensionPopupTests "$repo_root/tests/NativeExtensionPopup/Tests.mm"
"$output_dir/NativeExtensionPopupTests"
