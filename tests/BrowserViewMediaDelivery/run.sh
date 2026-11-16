#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-browser-view-media.XXXXXX")"
trap 'rm -rf "$output"' EXIT
flags=(-arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -fblocks -DOS_MAC=1
       -I "$root/Engine/ParcNative" -I "$root/Sources/ParcEngine")
xcrun clang "${flags[@]}" -Wall -Wextra -Werror -Wno-unused-parameter \
  -c "$root/Sources/ParcEngine/ParcEngine.m" -o "$output/ParcEngine.o"
xcrun clang "${flags[@]}" -Wall -Werror -Wno-incomplete-implementation -Wno-objc-property-implementation \
  -Wno-objc-protocol-property-synthesis -Wno-protocol -Wno-objc-root-class \
  -c "$root/tests/BrowserViewMediaDelivery/Tests.m" -o "$output/Tests.o"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -framework AppKit \
  "$output/ParcEngine.o" "$output/Tests.o" -o "$output/check"
"$output/check"
xcrun swiftc "$root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/NextTurnCoalescer.swift" "$root/tests/BrowserViewMediaDelivery/Coalescing.swift" \
  -o "$output/coalescing"
"$output/coalescing"
