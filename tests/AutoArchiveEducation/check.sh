#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
out="$(mktemp -d "${TMPDIR:-/tmp}/parc-auto-archive-education.XXXXXX")"
trap 'rm -rf "$out"' EXIT
xcrun swiftc "$root/tests/Support/TestFailure.swift" -warnings-as-errors -o "$out/auto-archive-education" \
  "$root/Sources/ParcApp/SidebarBannerHost.swift" \
  "$root/tests/AutoArchiveEducation/main.swift"
"$out/auto-archive-education"
