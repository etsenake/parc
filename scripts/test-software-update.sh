#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library -Onone -enforce-exclusivity=checked \
  Sources/ParcCore/SoftwareUpdateSession.swift tests/SoftwareUpdateSessionTests.swift -o "$output/check"
"$output/check"
