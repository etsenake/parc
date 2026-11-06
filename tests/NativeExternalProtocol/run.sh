#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PARC_TEST_BUILD_DIR:-$root/build/tests/native-external-protocol}"
mkdir -p "$out"
xcrun clang++ -std=c++20 -fobjc-arc -Wall -Wextra -Werror -framework AppKit \
  -I"$root/Engine/ParcNative" "$root/tests/NativeExternalProtocol/Tests.mm" \
  "$root/Engine/ParcNative/external_protocol_presenter.mm" -o "$out/tests"
"$out/tests"
