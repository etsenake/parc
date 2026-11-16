#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library Sources/ParcCore/ReleaseNotesLaunch.swift tests/ReleaseNotesLaunchTests.swift -o "$output/launch"
"$output/launch"
python3 tests/Support/app_sources.py xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library \
  Sources/ParcCore/*.swift Sources/ParcApp/SoftwareUpdateBanner.swift \
  tests/SoftwareUpdateBannerTests.swift -o "$output/banner"
"$output/banner"
