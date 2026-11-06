#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift tests/SidebarRows/OriginalSplitDropTests.swift -o "$output/check"
"$output/check"
