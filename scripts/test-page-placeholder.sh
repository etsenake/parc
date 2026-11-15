#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/PagePlaceholderView.swift" \
  "$repo_root/tests/PagePlaceholder/check.swift" \
  -o "$repo_root/build/tests/page-placeholder"
arguments=()
if [[ -n "${PARC_REFERENCE_SCREENSHOT:-}" ]]; then
  arguments+=("$PARC_REFERENCE_SCREENSHOT")
  if [[ -n "${PARC_REFERENCE_COMPARISON:-}" ]]; then arguments+=("$PARC_REFERENCE_COMPARISON"); fi
fi
exec "$repo_root/build/tests/page-placeholder" ${arguments[@]+"${arguments[@]}"}
