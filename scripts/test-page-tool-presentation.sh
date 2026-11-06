#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-page-tool-presentation.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/DeveloperToolbarLayout.swift" \
  "$repo_root/Sources/ParcApp/DeveloperToolbarControls.swift" \
  "$repo_root/tests/PageToolPresentation/PageToolPresentationTests.swift" \
  -o "$check_dir/page-tool-presentation"
"$check_dir/page-tool-presentation"
