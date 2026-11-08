#!/bin/bash
# Native HLS audio and text track proof
# (Engine/ParcNative/fairplay/fairplay_hls_media_selection.mm). Compiles the
# selection with tests/FairPlay/hls_media_selection_harness.mm using clang
# only and plays Apple's public multi-audio, multi-subtitle and CEA-608 test
# streams and a clear MP4 with two audio and two video tracks. Needs network
# access. Optional argument: one scenario (webvtt, cea608, file, teardown).
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
# The harness bounds each wait itself; this caps the whole run. The cap's
# sleep is its own process: stopping the cap must stop it too, or it would
# hold the output open. Stopping this script stops both.
"$output/hls-tracks-proof" "$@" &
proof=$!
( sleeper=; trap 'if [ -n "$sleeper" ]; then kill "$sleeper" 2>/dev/null; fi; exit 0' TERM
  sleep 290 & sleeper=$!; wait "$sleeper"; kill -TERM "$proof" 2>/dev/null ) &
cap=$!
trap 'kill "$proof" "$cap" 2>/dev/null; rm -rf "$output"' EXIT
status=0
wait "$proof" || status=$?
exit "$status"
