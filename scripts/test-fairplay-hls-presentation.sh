#!/bin/bash
# Native HLS presentation proofs (tests/FairPlay/hls_presentation). Compiles
# the harness with clang only and runs it against Apple's public HLS examples
# in visible windows. Needs network access. Pass --only <Section> to run one
# section.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-fairplay-hls-presentation.XXXXXX")"
trap 'rm -rf "$output"' EXIT
tests="$repo_root/tests/FairPlay/hls_presentation"
core="$repo_root/Engine/ParcNative/fairplay"
flags=(-std=c++20 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -fobjc-arc -I "$core" -I "$tests")
xcrun clang++ "${flags[@]}" -c "$core/fairplay_hls_frame_stats.mm" -o "$output/fairplay_hls_frame_stats.o"
xcrun clang++ "${flags[@]}" -c "$tests/harness.mm" -o "$output/harness.o"
xcrun clang++ "$output"/*.o -framework AppKit -framework AVFoundation \
  -framework CoreMedia -framework QuartzCore -o "$output/fairplay-hls-presentation-proof"
# The harness exits by itself; a 300 s cap backs that up. The cap's sleep is
# its own process: stopping the cap must stop it too.
"$output/fairplay-hls-presentation-proof" "$@" &
proof=$!
( trap 'kill "$sleeper" 2>/dev/null; exit 0' TERM; sleep 300 >/dev/null 2>&1 & sleeper=$!
  wait "$sleeper"; kill -TERM "$proof" 2>/dev/null ) &
cap=$!
status=0
wait "$proof" || status=$?
kill "$cap" 2>/dev/null || true
exit "$status"
