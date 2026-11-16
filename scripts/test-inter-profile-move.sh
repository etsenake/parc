#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift tests/SidebarRows/InterProfileMoveTests.swift -o "$output/check"
"$output/check"
python3 tests/SidebarRows/document_move_block_check.py
