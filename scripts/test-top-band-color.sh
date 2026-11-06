#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-top-band-color.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun clang++ -std=c++20 -Wall -Wextra -Werror -I "$repo_root/Engine/ParcRenderer" \
  "$repo_root/tests/TopBandColor/sampling_test.cc" -o "$output/check"
"$output/check"
