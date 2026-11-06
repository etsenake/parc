#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -parse-as-library \
  "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/PrivateBrowsingTests.swift" \
  -o "$repo_root/build/tests/private-browsing"
"$repo_root/build/tests/private-browsing"
