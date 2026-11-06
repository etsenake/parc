#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  -framework AppKit -framework AVFoundation -framework SwiftUI \
  "$repo_root/Sources/ParcApp/OnboardingArtwork.swift" \
  "$repo_root/tests/OnboardingVideoHandoffTests.swift" \
  -o "$output/check"
"$output/check"
