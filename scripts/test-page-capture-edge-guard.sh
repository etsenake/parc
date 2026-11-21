#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-capture-edge-guard.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/PageCaptureEdgeGuard.swift" \
  "$repo_root/tests/PageCaptureEdgeGuard/main.swift" -o "$check_dir/checks"
"$check_dir/checks"
