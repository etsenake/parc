#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library -Onone -enforce-exclusivity=checked \
  Sources/ParcCore/SoftwareUpdateSession.swift tests/SoftwareUpdateSessionTests.swift -o "$output/check"
"$output/check"
xcrun swiftc -warnings-as-errors -parse-as-library -Onone -enforce-exclusivity=checked \
  Sources/ParcCore/AutomaticUpdate.swift tests/AutomaticUpdateTests.swift -o "$output/automatic"
"$output/automatic"
bash scripts/test-software-update-progress.sh
# The optional inert mode avoids the release-notes WKWebView in the window test.
if [[ "${1:-}" == "--inert" ]]; then exit 0; fi
xcrun swiftc -warnings-as-errors -parse-as-library \
  Sources/ParcApp/SoftwareUpdateWindow.swift Sources/ParcApp/PointingHand.swift tests/SoftwareUpdateWindowTests.swift -o "$output/window"
"$output/window"
