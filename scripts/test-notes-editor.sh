#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
out="$repo_root/build/tests/notes-editor"
mkdir -p "$out"
shopt -s nullglob
filter="${1:-}"
for test in "$repo_root"/tests/NotesEditor/*Tests.swift; do
  name="$(basename "$test" .swift)"
  if [ -n "$filter" ] && [[ "$name" != *"$filter"* ]]; then continue; fi
  sidecar="${test%.swift}.files"
  sources=()
  if [ -f "$sidecar" ]; then
    lines=()
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      lines+=("$line")
      if [ "$line" = "Sources/ParcCore/NoteModel.swift" ] && [ -f "$repo_root/tests/NotesEditor/NoteModel.deps" ]; then
        while IFS= read -r dep; do [ -n "$dep" ] && lines+=("$dep"); done < "$repo_root/tests/NotesEditor/NoteModel.deps"
      fi
    done < "$sidecar"
    seen=" "
    for line in "${lines[@]}"; do
      for path in "$repo_root"/$line; do
        case "$seen" in *" $path "*) ;; *) sources+=("$path"); seen="$seen$path ";; esac
      done
    done
  else
    sources=("$repo_root"/Sources/ParcCore/*.swift)
  fi
  echo "== $name"
  xcrun swiftc -parse-as-library -warnings-as-errors "$repo_root/tests/Support/TestFailure.swift" "${sources[@]}" "$test" -o "$out/$name"
  "$out/$name" "$repo_root"
done
