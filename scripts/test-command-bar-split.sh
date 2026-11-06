#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
# The whole model module: a fixed file list goes stale as ParcCore grows.
xcrun swiftc -parse-as-library \
  "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/CommandBar/SplitSubmissionTests.swift" \
  -o "$repo_root/build/tests/command-bar-split"
"$repo_root/build/tests/command-bar-split"
