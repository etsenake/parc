#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
  "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/ArcSidebarImportTests.swift" \
  -o "$repo_root/build/tests/arc-sidebar-import"
"$repo_root/build/tests/arc-sidebar-import"
