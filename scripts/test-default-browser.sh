#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library \
  Sources/ParcApp/DefaultBrowserController.swift tests/DefaultBrowserTests.swift -o "$output/check"
"$output/check"
