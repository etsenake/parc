#!/bin/bash
# Native HLS player proof (Engine/ParcNative/fairplay/fairplay_hls_player.mm
# and fairplay_hls_timeline.cc, with the key loader and key session for
# FairPlay keys). Compiles the player with
# tests/FairPlay/hls_player_harness.mm using clang only and plays public HLS
# streams through a loader the harness controls. Needs network access, except
# for the timeline scenario (WebKit's live and DVR timing rules). Optional
# argument: one scenario (timeline, ts, fmp4, live, missing, http, bad-url,
# data-url, data-url-video, skd, skd-handler, teardown, keys-first, keys-loader,
# keys-attach-at-request, keys-multikey,
# keys-await, keys-early, keys-close, keys-legacy, metadata-first,
# keys-legacy-order, airplay, file). The keys
# scenarios license Axinom's FairPlay HLS vectors from its public test
# license service.
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
xcrun clang++ "$output"/*.o -framework AVFoundation -framework CoreGraphics -framework CoreMedia \
  -framework Foundation -framework QuartzCore -o "$output/hls-player-proof"
# The harness bounds each wait itself; this caps the whole run. The cap's
# sleep is its own process: stopping the cap must stop it too, or it would
# hold the output open. Stopping this script stops both.
"$output/hls-player-proof" "$@" &
proof=$!
( sleeper=; trap 'if [ -n "$sleeper" ]; then kill "$sleeper" 2>/dev/null; fi; exit 0' TERM
  sleep 300 & sleeper=$!; wait "$sleeper"; kill -TERM "$proof" 2>/dev/null ) &
cap=$!
trap 'kill "$proof" "$cap" 2>/dev/null; rm -rf "$output"' EXIT
status=0
wait "$proof" || status=$?
exit "$status"
