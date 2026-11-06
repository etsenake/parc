#!/bin/bash
# Inert layout/resource checks only. Does not load a browser or user profile.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
check_root=$(mktemp -d "${TMPDIR:-/tmp}/parc-capture-presentation.XXXXXX")
trap 'rm -rf "$check_root"' EXIT
xcrun swiftc -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/CapturePresentation.swift" \
  "$repo_root/tests/CapturePresentation/main.swift" -o "$check_root/CapturePresentationChecks"
# An unbundled executable's Bundle.main.resourceURL is its own directory.
cp -R "$repo_root/Resources/Capture" "$check_root/Capture"
"$check_root/CapturePresentationChecks"
