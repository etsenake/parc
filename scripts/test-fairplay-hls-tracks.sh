#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-fairplay-hls-tracks.XXXXXX")"
trap 'rm -rf "$output"' EXIT
core="$repo_root/Engine/ParcNative/fairplay"
tests="$repo_root/tests/FairPlay"
flags=(-std=c++20 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -fobjc-arc -I "$core")
xcrun clang++ "${flags[@]}" -c "$core/fairplay_hls_media_selection.mm" -o "$output/fairplay_hls_media_selection.o"
xcrun clang++ "${flags[@]}" -c "$tests/hls_media_selection_harness.mm" -o "$output/hls_media_selection_harness.o"
xcrun clang++ "$output"/*.o -framework AVFoundation -framework CoreMedia -framework Foundation \
  -framework MediaAccessibility -o "$output/hls-tracks-proof"
"$output/hls-tracks-proof" "$@" &
proof=$!
( sleeper=; trap 'if [ -n "$sleeper" ]; then kill "$sleeper" 2>/dev/null; fi; exit 0' TERM
  sleep 290 & sleeper=$!; wait "$sleeper"; kill -TERM "$proof" 2>/dev/null ) &
cap=$!
trap 'kill "$proof" "$cap" 2>/dev/null; rm -rf "$output"' EXIT
status=0
wait "$proof" || status=$?
exit "$status"
