#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-split-link.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun swiftc -warnings-as-errors "$repo_root/Sources/ParcCore/SplitLinkSnapshot.swift" \
  "$repo_root/tests/SplitLinkSnapshot/main.swift" -o "$output/check"
"$output/check"
