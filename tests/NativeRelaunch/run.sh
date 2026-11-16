#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mktemp -d "${TMPDIR:-/tmp}/parc-relaunch-tests.XXXXXX")"
trap 'rm -rf "$out"' EXIT
xcrun swiftc "$repo/tests/Support/TestFailure.swift" -warnings-as-errors "$repo/Sources/ParcCore/NativeRelaunch.swift" "$repo/tests/NativeRelaunch/Tests.swift" -o "$out/tests"
"$out/tests"
