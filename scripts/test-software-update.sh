#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
bash scripts/test-software-update-progress.sh
if [[ "${1:-}" == "--inert" ]]; then exit 0; fi
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library \
  Sources/ParcApp/SoftwareUpdateWindow.swift Sources/ParcApp/PointingHand.swift tests/SoftwareUpdateWindowTests.swift -o "$output/window"
"$output/window"
