#!/bin/bash
# FairPlay protected-codec proof. Compiles the engine-independent FairPlay
# core (Engine/ParcNative/fairplay) with tests/FairPlay/codecs using clang
# only, then encrypts clear Dolby Vision, AV1, HE-AAC, xHE-AAC, AC-3 and E-AC-3
# samples with a key Axinom's FairPlay service licenses and plays them in a
# visible window. Needs network access.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/parc-fairplay-codecs.XXXXXX")"
trap 'rm -rf "$output"' EXIT
core="$repo_root/Engine/ParcNative/fairplay"
tests="$repo_root/tests/FairPlay"
flags=(-std=c++20 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -I "$core" -I "$tests" -I "$tests/codecs")
xcrun clang++ "${flags[@]}" -c "$core/fairplay_bitstream.cc" -o "$output/fairplay_bitstream.o"
for name in fairplay_init_data fairplay_key_session fairplay_renderer; do
  xcrun clang++ "${flags[@]}" -fobjc-arc -c "$core/$name.mm" -o "$output/$name.o"
done
xcrun clang++ "${flags[@]}" -c "$tests/fmp4_parser.cc" -o "$output/fmp4_parser.o"
xcrun clang++ "${flags[@]}" -c "$tests/codecs/sample_encryptor.cc" -o "$output/sample_encryptor.o"
xcrun clang++ "${flags[@]}" -fobjc-arc -c "$tests/codecs/codecs.mm" -o "$output/codecs.o"
xcrun clang++ "$output"/*.o -framework AppKit -framework AVFoundation -framework AudioToolbox -framework CoreAudio \
  -framework CoreMedia -framework OSLog -framework QuartzCore -o "$output/fairplay-codecs"
# The program exits by itself on a stalled main thread (sampling its stack)
# or after --time-limit seconds (default 600); this cap backs that up.
"$output/fairplay-codecs" --cache "${PARC_FAIRPLAY_CACHE:-${TMPDIR:-/tmp}/parc-fairplay-cache}" "$@" &
proof=$!
( sleep 660; kill -TERM "$proof" 2>/dev/null ) &
cap=$!
status=0
wait "$proof" || status=$?
kill "$cap" 2>/dev/null || true
exit "$status"
