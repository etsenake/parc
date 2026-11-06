#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/build/tests/native-extension-uninstall/appkit"
mkdir -p "$out"
xcrun clang++ -std=c++20 -fobjc-arc -Wall -Wextra -Werror -framework AppKit \
  -I"$root/Engine/ParcNative" "$root/tests/NativeExtensionUninstall/Tests.mm" \
  "$root/Engine/ParcNative/window_security_reservation.mm" \
  "$root/Engine/ParcNative/extension_uninstall_presenter.mm" -o "$out/tests"
"$out/tests"
