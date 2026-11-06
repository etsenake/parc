#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -parse-as-library Sources/ParcCore/TabHistoryArchive.swift tests/TabHistoryArchiveTests.swift -o "$output/check"
"$output/check"
