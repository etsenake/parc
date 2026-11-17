#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
mkdir -p "$root/build/tests/native-background-pip-hold"
xcrun clang++ -std=c++20 -Wall -Wextra -Werror \
  -I "$root/Engine/ParcNative" "$root/tests/NativeBackgroundPipHold/Tests.cc" \
  -o "$root/build/tests/native-background-pip-hold/check"
"$root/build/tests/native-background-pip-hold/check"
