#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/parc-peek-dismissal.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc tests/Support/TestFailure.swift -parse-as-library -warnings-as-errors \
  Sources/ParcApp/PeekDismissalConfirmation.swift tests/PeekDismissal/main.swift \
  -o "$check_dir/peek-dismissal-checks"
"$check_dir/peek-dismissal-checks"
xcrun clang++ -std=c++20 -Wall -Wextra -Werror \
  tests/NativeKeyboard/peek_escape.cc -o "$check_dir/native-peek-escape-checks"
"$check_dir/native-peek-escape-checks"
