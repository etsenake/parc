#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/parc-password-file.XXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun clang++ -std=c++20 -Wall -Wextra -Werror -I "$root/Engine/ParcNative" \
  "$root/tests/PasswordFileImport/FileTests.cc" -o "$build/check"
"$build/check"
