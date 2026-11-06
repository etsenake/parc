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
xcrun clang++ "${flags[@]}" -c "$core/fairplay_bitstream.cc" -o "$output/fairplay_bitstream.o"
for name in fairplay_init_data fairplay_key_session fairplay_renderer; do
  xcrun clang++ "${flags[@]}" -fobjc-arc -c "$core/$name.mm" -o "$output/$name.o"
done
xcrun clang++ "${flags[@]}" -c "$tests/fmp4_parser.cc" -o "$output/fmp4_parser.o"
xcrun clang++ "${flags[@]}" -fobjc-arc -c "$tests/harness.mm" -o "$output/harness.o"
xcrun clang++ "$output"/*.o -framework AppKit -framework AVFoundation -framework AudioToolbox \
  -framework CoreMedia -framework QuartzCore -o "$output/fairplay-proof"
"$output/fairplay-proof" --cache "${PARC_FAIRPLAY_CACHE:-${TMPDIR:-/tmp}/parc-fairplay-cache}" "$@"
