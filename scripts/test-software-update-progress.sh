#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library -Onone -enforce-exclusivity=checked \
  Sources/ParcCore/SoftwareUpdateDownloadProgress.swift Sources/ParcApp/SoftwareUpdateWindow.swift Sources/ParcApp/PointingHand.swift \
  tests/SoftwareUpdateDownloadProgressTests.swift -o "$output/progress"
"$output/progress"
