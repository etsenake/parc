#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -parse-as-library Sources/ParcApp/SidebarFaviconView.swift tests/SidebarRows/SidebarFaviconTests.swift -o "$output/check"
"$output/check"
