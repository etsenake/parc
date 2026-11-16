#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -whole-module-optimization -parse-as-library Sources/ParcCore/*.swift Sources/ParcApp/SplitDropGeometry.swift tests/NativeContentDrop/GeometryTests.swift -o "$output/check"
"$output/check"
