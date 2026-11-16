#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-link-routing-fallback.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors "$repo_root/Sources/ParcCore/LinkRouting.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/tests/LinkRoutingFallback/main.swift" -o "$output/check"
"$output/check"
