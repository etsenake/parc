#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mktemp -d "${TMPDIR:-/tmp}/parc-test-instance-tests.XXXXXX")"
trap 'rm -rf "$out"' EXIT
xcrun swiftc -warnings-as-errors "$repo/Sources/ParcCore/TestInstance.swift" "$repo/Sources/ParcCore/PerfMarks.swift" \
  "$repo/tests/TestInstance/Tests.swift" -o "$out/tests"
"$out/tests"
