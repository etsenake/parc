#!/bin/bash
# Pure checks for FairPlay identity: the engine's site, navigation, Widevine
# and user agent rules, the renderer's Safari scripts and their gate, and the
# shell's site lists. No browser execution.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-fairplay-identity.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun clang++ -std=c++20 -Wall -Wextra -Werror -I "$repo_root/Engine/ParcNative" \
  "$repo_root/tests/FairPlayIdentity/policy_main.cc" -o "$output/policy"
"$output/policy"
# The renderer's gate: only a Safari-identity document gets the Safari scripts.
xcrun clang++ -std=c++20 -Wall -Wextra -Werror -I "$repo_root/Engine/ParcNative" \
  -I "$repo_root/Engine/ParcRenderer" -I "$repo_root/tests/FairPlayIdentity/blink_stub" \
  "$repo_root/tests/FairPlayIdentity/renderer_gate_main.cc" -o "$output/gate"
"$output/gate"
# The shell's per-Profile site lists, private overlays and file format.
xcrun swiftc -parse-as-library -warnings-as-errors \
  "$repo_root/Sources/ParcCore/FairPlayIdentity.swift" \
  "$repo_root/tests/FairPlayIdentitySitesTests.swift" -o "$output/sites"
"$output/sites"
# The ManagedMediaSource, WebKitMediaKeys, MediaKeys and video presentation
# scripts Safari-identity pages get, against models of Chromium's media APIs.
if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/FairPlayIdentity/managed_media_source.mjs"
  node "$repo_root/tests/FairPlayIdentity/webkit_media_keys.mjs"
  node "$repo_root/tests/FairPlayIdentity/safari_media_keys.mjs"
  node "$repo_root/tests/FairPlayIdentity/webkit_presentation.mjs"
else
  echo "managed media source, webkit media keys, safari media keys, webkit presentation: skipped (node not installed)"
fi
