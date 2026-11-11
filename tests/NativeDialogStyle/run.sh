#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/build/tests/native-dialog-style"
mkdir -p "$out"
xcrun clang++ -std=c++20 -mmacosx-version-min=13.0 -fobjc-arc -Wall -Wextra -Werror \
  -framework AppKit -I"$root/Engine/ParcNative" \
  "$root/tests/NativeDialogStyle/Tests.mm" \
  "$root/Engine/ParcNative/dialog_style.mm" -o "$out/tests"
"$out/tests"
