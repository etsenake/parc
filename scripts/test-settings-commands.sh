#!/bin/bash
# File-backed model and destination checks only; no browser/engine or user data.
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library Sources/ParcCore/*.swift \
  tests/ProfileSettingsTests.swift -o "$output/check"
"$output/check"
