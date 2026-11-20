#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
xcrun swiftc -warnings-as-errors "$repo_root/tests/Support/TestFailure.swift" -parse-as-library "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/NoteTabTests.swift" -o "$repo_root/build/tests/note-tabs"
"$repo_root/build/tests/note-tabs"
bash "$repo_root/scripts/test-notes-editor.sh" "$@"
