#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PARC_TEST_BUILD_DIR:-$root/build/tests/native-status-text}"
mkdir -p "$out"
xcrun clang++ -std=c++20 -fobjc-arc -Wall -Wextra -Werror -framework AppKit -framework QuartzCore \
  -I"$root/Engine/ParcNative" "$root/tests/NativeStatusText/Tests.mm" \
  "$root/Engine/ParcNative/status_text.mm" -o "$out/tests"
"$out/tests"
