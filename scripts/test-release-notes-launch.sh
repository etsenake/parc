#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
python3 tests/Support/app_sources.py xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library \
  Sources/ParcCore/*.swift Sources/ParcApp/SoftwareUpdateBanner.swift \
  tests/SoftwareUpdateBannerTests.swift -o "$output/banner"
"$output/banner"
