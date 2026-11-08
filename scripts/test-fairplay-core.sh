#!/bin/bash
# FairPlay M0 proof. Compiles the engine-independent FairPlay core
# (Engine/ParcNative/fairplay) with the harness in tests/FairPlay using clang
# only, then plays Axinom's public CMAF H264 SingleKey (cbcs) vector with a
# real FairPlay license exchange in a visible window. Needs network access.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-fairplay.XXXXXX")"
trap 'rm -rf "$output"' EXIT
core="$repo_root/Engine/ParcNative/fairplay"
tests="$repo_root/tests/FairPlay"
flags=(-std=c++20 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -I "$core" -I "$tests")
# Exercise the pre-14.4 preroll callback on a newer development Mac too.
if [ "${PARC_FAIRPLAY_FORCE_LEGACY_PREROLL:-0}" = 1 ]; then
  flags+=(-DPARC_FAIRPLAY_FORCE_LEGACY_PREROLL)
fi
xcrun clang++ "${flags[@]}" -c "$core/fairplay_bitstream.cc" -o "$output/fairplay_bitstream.o"
for name in fairplay_init_data fairplay_key_session fairplay_renderer; do
  xcrun clang++ "${flags[@]}" -fobjc-arc -c "$core/$name.mm" -o "$output/$name.o"
done
xcrun clang++ "${flags[@]}" -c "$tests/fmp4_parser.cc" -o "$output/fmp4_parser.o"
xcrun clang++ "${flags[@]}" -c "$tests/ts_parser.cc" -o "$output/ts_parser.o"
xcrun clang++ "${flags[@]}" -c "$tests/webm_parser.cc" -o "$output/webm_parser.o"
xcrun clang++ "${flags[@]}" -fobjc-arc -c "$tests/harness.mm" -o "$output/harness.o"
xcrun clang++ "$output"/*.o -framework AppKit -framework AVFoundation -framework AudioToolbox \
  -framework CoreAudio -framework CoreMedia -framework CoreVideo -framework QuartzCore -framework VideoToolbox -o "$output/fairplay-proof"
cache="${PARC_FAIRPLAY_CACHE:-${TMPDIR:-/tmp}/parc-fairplay-cache}"
# Runs the proof with a hard cap of $1 seconds. The harness exits by itself on
# a stalled main thread (sampling its stack) or after --time-limit seconds
# (default 480); the cap backs that up. The cap's sleep is its own process:
# stopping the cap must stop it too.
run_capped() {
  local limit=$1
  shift
  "$@" &
  local proof=$!
  ( trap 'kill "$sleeper" 2>/dev/null; exit 0' TERM; sleep "$limit" & sleeper=$!; wait "$sleeper"
    kill -TERM "$proof" 2>/dev/null ) &
  local cap=$!
  local result=0
  wait "$proof" || result=$?
  kill "$cap" 2>/dev/null || true
  return "$result"
}
status=0
run_capped 600 "$output/fairplay-proof" --cache "$cache" "$@" || status=$?
# Core Audio's services out of reach (as a sandbox can leave them): the
# renderer must fail Initialize, not throw out of it.
if [ "$status" -eq 0 ] && [ "$#" -eq 0 ]; then
  run_capped 120 /usr/bin/sandbox-exec -p '(version 1)(allow default)(deny mach-lookup
      (global-name "com.apple.audio.audiohald") (global-name "com.apple.audio.AudioSession")
      (global-name "com.apple.coremedia.routingcontext.xpc"))' \
    "$output/fairplay-proof" --cache "$cache" --only AudioUnavailable --audio-unavailable 1 --time-limit 90 ||
    status=$?
fi
exit "$status"
