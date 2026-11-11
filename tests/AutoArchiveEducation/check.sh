#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
out=${1:?Usage: check.sh outside-repository-output-directory}
mkdir -p "$out"
xcrun swiftc -warnings-as-errors -o "$out/auto-archive-education" \
  "$root/Sources/ParcApp/SidebarBannerHost.swift" \
  "$root/tests/AutoArchiveEducation/main.swift"
"$out/auto-archive-education"
