#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-browser-view-media.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun swiftc "$root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$root/Sources/ParcApp/NextTurnCoalescer.swift" "$root/tests/BrowserViewMediaDelivery/Coalescing.swift" \
  -o "$output/coalescing"
"$output/coalescing"
