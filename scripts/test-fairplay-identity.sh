#!/bin/bash
# Pure checks for FairPlay identity: the engine's site, navigation, Widevine
# and user agent rules, and the shell's site lists. No browser execution.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-fairplay-identity.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun clang++ -std=c++20 -Wall -Wextra -Werror -I "$repo_root/Engine/ParcNative" \
  "$repo_root/tests/FairPlayIdentity/policy_main.cc" -o "$output/policy"
"$output/policy"
# The shell's per-Profile site lists, private overlays and file format.
xcrun swiftc -parse-as-library -warnings-as-errors \
  "$repo_root/Sources/ParcCore/FairPlayIdentity.swift" \
  "$repo_root/tests/FairPlayIdentitySitesTests.swift" -o "$output/sites"
"$output/sites"
# The ManagedMediaSource script Safari-identity pages get, against a model of
# Chromium's media APIs.
if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/FairPlayIdentity/managed_media_source.mjs"
else
  echo "managed media source: skipped (node not installed)"
fi
