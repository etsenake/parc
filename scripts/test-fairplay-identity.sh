#!/bin/bash
# Pure checks for FairPlay identity: the engine's site, navigation, Widevine
# and user agent rules. No browser execution.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-fairplay-identity.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun clang++ -std=c++20 -Wall -Wextra -Werror -I "$repo_root/Engine/ParcNative" \
  "$repo_root/tests/FairPlayIdentity/policy_main.cc" -o "$output/policy"
"$output/policy"
