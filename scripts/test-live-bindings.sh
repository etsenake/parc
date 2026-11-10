#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-live-bindings.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -whole-module-optimization -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$repo_root/Sources/ParcApp/KeyboardShortcuts.swift" \
  "$repo_root/Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift" \
  "$repo_root/Sources/ParcApp/SuperCopyUpsell.swift" \
  "$repo_root/Sources/ParcApp/PeekOpenCommand.swift" \
  "$repo_root/Sources/ParcCore/SpaceTheme.swift" \
  "$repo_root/Sources/ParcApp/PArcToast.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/tests/KeyboardNavigation/NativeShortcutStub.swift" \
  "$repo_root/tests/KeyboardNavigation/LiveBindingTests.swift" \
  -o "$check_dir/live-bindings"
"$check_dir/live-bindings"
