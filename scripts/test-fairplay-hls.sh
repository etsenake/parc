#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-fairplay-hls.XXXXXX")"
trap 'rm -rf "$output"' EXIT
core="$repo_root/Engine/ParcNative/fairplay"
tests="$repo_root/tests/FairPlay"
cxx_flags=(-std=c++20 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -I "$core")
flags=("${cxx_flags[@]}" -fobjc-arc)
xcrun clang++ "${cxx_flags[@]}" -c "$core/fairplay_hls_timeline.cc" -o "$output/fairplay_hls_timeline.o"
for name in fairplay_hls_frame_stats fairplay_hls_player fairplay_hls_player_layer fairplay_hls_keys fairplay_key_session fairplay_init_data; do
  xcrun clang++ "${flags[@]}" -c "$core/$name.mm" -o "$output/$name.o"
done
xcrun clang++ "${flags[@]}" -c "$tests/hls_player_harness.mm" -o "$output/hls_player_harness.o"
xcrun clang++ "$output"/*.o -framework AVFoundation -framework CoreAudio -framework CoreGraphics -framework CoreMedia \
  -framework Foundation -framework QuartzCore -o "$output/hls-player-proof"
"$output/hls-player-proof" "$@" &
proof=$!
( sleeper=; trap 'if [ -n "$sleeper" ]; then kill "$sleeper" 2>/dev/null; fi; exit 0' TERM
  sleep 300 & sleeper=$!; wait "$sleeper"; kill -TERM "$proof" 2>/dev/null ) &
cap=$!
trap 'kill "$proof" "$cap" 2>/dev/null; rm -rf "$output"' EXIT
status=0
wait "$proof" || status=$?
exit "$status"
