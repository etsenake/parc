#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-page-shell-notify.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -I "$repo_root/Engine/ParcNative" \
  "$repo_root/tests/PageShellNotify/main.cc" -o "$output/check"
"$output/check"
