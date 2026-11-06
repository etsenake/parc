#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output_dir="$repo_root/build/tests/native-autofill-save"
mkdir -p "$output_dir"
for test_source in Tests presentation_tests; do
  xcrun clang++ -arch arm64 -std=c++20 -mmacosx-version-min=13.0 \
    -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -I "$repo_root/Engine/ParcNative" \
    "$repo_root/Engine/ParcNative/autofill_save_presenter.mm" \
    "$repo_root/tests/NativeAutofillSave/$test_source.mm" \
    -framework Cocoa -o "$output_dir/$test_source"
  "$output_dir/$test_source"
done
