#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/build/tests/native-extension-install/appkit"
mkdir -p "$out"
xcrun clang++ -std=c++20 -fobjc-arc -Wall -Wextra -Werror -framework AppKit \
  -I"$root/Engine/ParcNative" "$root/tests/NativeExtensionInstall/Tests.mm" \
  "$root/Engine/ParcNative/extension_install_presenter.mm" \
  "$root/Engine/ParcNative/window_security_reservation.mm" -o "$out/tests"
"$out/tests"
