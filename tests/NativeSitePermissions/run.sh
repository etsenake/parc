#!/bin/bash
set -euo pipefail
source_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="${PARC_TEST_BUILD_DIR:-$source_root/build/tests/native-site-permissions}"
mkdir -p "$output_dir"
xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
  -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -I "$source_root/Engine/ParcNative" \
  "$source_root/Engine/ParcNative/site_permission_presenter.mm" \
  "$source_root/tests/NativeSitePermissions/Tests.mm" \
  -framework Cocoa -o "$output_dir/site-permission-presenter"
"$output_dir/site-permission-presenter"
