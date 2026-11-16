#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -whole-module-optimization -parse-as-library "$repo_root"/Sources/ParcCore/*.swift \
    "$repo_root/tests/SpaceDeletionTests.swift" -o "$repo_root/build/tests/space-deletion"
"$repo_root/build/tests/space-deletion"
