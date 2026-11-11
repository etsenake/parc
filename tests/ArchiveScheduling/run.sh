#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
output="${ARCHIVE_SCHEDULING_CHECK_OUTPUT:-$repo_root/build/tests/archive-scheduling}"
mkdir -p "$(dirname -- "$output")"
xcrun swiftc -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/ArchiveScheduling.swift" \
  "$repo_root/tests/ArchiveSchedulingTests.swift" -o "$output"
"$output"
