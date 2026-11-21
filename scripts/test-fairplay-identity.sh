#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-fairplay-identity.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library -warnings-as-errors \
  "$repo_root/Sources/ParcCore/FairPlayIdentity.swift" \
  "$repo_root/tests/FairPlayIdentitySitesTests.swift" -o "$output/sites"
"$output/sites"
if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/FairPlayIdentity/managed_media_source.mjs"
  node "$repo_root/tests/FairPlayIdentity/webkit_media_keys.mjs"
  node "$repo_root/tests/FairPlayIdentity/safari_media_keys.mjs"
  node "$repo_root/tests/FairPlayIdentity/webkit_presentation.mjs"
  node "$repo_root/tests/FairPlayIdentity/webkit_playback_target.mjs"
else
  echo "managed media source, webkit media keys, safari media keys, webkit presentation, webkit playback target: skipped (node not installed)"
fi
