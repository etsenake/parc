#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-toasts.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -warnings-as-errors -whole-module-optimization -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcCore/SpaceTheme.swift" \
  "$repo_root/Sources/ParcApp/PArcToast.swift" \
  "$repo_root/Sources/ParcApp/PointerCover.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/tests/Toasts/PArcToastTests.swift" \
  -o "$check_dir/toasts"
"$check_dir/toasts"
