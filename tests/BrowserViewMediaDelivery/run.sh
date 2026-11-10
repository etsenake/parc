#!/bin/bash
# The facade's media change delivery over stand-in engine classes, and the
# window's once-per-turn refresh of it. run.sh <chromium src> [source lock].
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
chromium="${1:?usage: run.sh <chromium src>}"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-browser-view-media.XXXXXX")"
trap 'rm -rf "$output"' EXIT
flags=(-arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -fblocks -DOS_MAC=1
       -I "$root/Engine/ParcNative" -I "$root/Sources/ParcEngine")
lock="${2:-$root/Engine/source-lock.json}"
schema="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["schema_version"])' "$lock")"
case "$schema" in
  1) flags+=(-I "$chromium/cef/include") ;;
  2)
    if rg -q 'cef_application_mac.h' "$root/Sources/ParcEngine/ParcEngine.h"; then
      echo "Direct facade check blocked: the public facade still imports the CEF application protocol; migrate that header first." >&2
      exit 1
    fi
    ;;
  *) echo "Unsupported source lock schema: $schema" >&2; exit 1 ;;
esac
xcrun clang "${flags[@]}" -Wall -Wextra -Werror -Wno-unused-parameter \
  -c "$root/Sources/ParcEngine/ParcEngine.m" -o "$output/ParcEngine.o"
# The stand-in page implements only what the change path reads.
xcrun clang "${flags[@]}" -Wall -Werror -Wno-incomplete-implementation -Wno-objc-property-implementation \
  -Wno-objc-protocol-property-synthesis -Wno-protocol -Wno-objc-root-class \
  -c "$root/tests/BrowserViewMediaDelivery/Tests.m" -o "$output/Tests.o"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -framework AppKit \
  "$output/ParcEngine.o" "$output/Tests.o" -o "$output/check"
"$output/check"
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/NextTurnCoalescer.swift" "$root/tests/BrowserViewMediaDelivery/Coalescing.swift" \
  -o "$output/coalescing"
"$output/coalescing"
