#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
check_root=$(mktemp -d "${TMPDIR:-/tmp}/parc-capture-presentation.XXXXXX")
trap 'rm -rf "$check_root"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/CapturePresentation.swift" \
  "$repo_root/tests/CapturePresentation/main.swift" -o "$check_root/CapturePresentationChecks"
cp -R "$repo_root/Resources/Capture" "$check_root/Capture"
"$check_root/CapturePresentationChecks"
