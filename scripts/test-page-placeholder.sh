#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/PagePlaceholderView.swift" \
  "$repo_root/tests/PagePlaceholder/check.swift" \
  -o "$repo_root/build/tests/page-placeholder"
arguments=()
if [[ -n "${PARC_ARC_FROZEN_SCREENSHOT:-}" ]]; then
  arguments+=("$PARC_ARC_FROZEN_SCREENSHOT")
  if [[ -n "${PARC_ARC_FROZEN_COMPARISON:-}" ]]; then arguments+=("$PARC_ARC_FROZEN_COMPARISON"); fi
fi
exec "$repo_root/build/tests/page-placeholder" ${arguments[@]+"${arguments[@]}"}
