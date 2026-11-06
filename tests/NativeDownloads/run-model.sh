#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mktemp -d "${TMPDIR:-/tmp}/parc-download-model.XXXXXX")"
trap 'rm -rf "$out"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors \
  "$repo"/Sources/ParcCore/*.swift \
  "$repo/tests/NativeDownloads/ModelTests.swift" -o "$out/tests"
"$out/tests"
