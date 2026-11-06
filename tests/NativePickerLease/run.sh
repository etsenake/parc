#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
out="$(mktemp -d "${TMPDIR:-/tmp}/parc-native-picker-lease.XXXXXX")"
trap 'rm -rf "$out"' EXIT
xcrun clang++ -std=c++20 -Wall -Wextra -Werror -I "$root/Engine/ParcHost/native" \
  "$root/tests/NativePickerLease/Tests.cc" -o "$out/check"
"$out/check"
