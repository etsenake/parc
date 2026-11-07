#!/bin/bash
# Plays an x265 clip with Netflix's frame reordering (P then three
# hierarchical B-frames, decode times four frames ahead) through the FairPlay
# core, silent and video only, with and without decode timestamps. Needs x265
# (Homebrew). Extra arguments go to every --play run. PARC_DECODE_TIMES_SIZE,
# _KBPS and _BFRAMES change the clip (default 1920x1080, 12000, 3).
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/../../.." && pwd)"
core="$repo_root/Engine/ParcNative/fairplay"
here="$repo_root/tests/FairPlay/decode_times"
out="${PARC_DECODE_TIMES_DIR:-${TMPDIR:-/tmp}/parc-decode-times}"
mkdir -p "$out"
codecs="$repo_root/tests/FairPlay/codecs"
flags=(-std=c++20 -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -I "$core" -I "$codecs")
xcrun clang++ "${flags[@]}" -c "$core/fairplay_bitstream.cc" -o "$out/fairplay_bitstream.o"
for name in fairplay_init_data fairplay_key_session fairplay_renderer; do
  xcrun clang++ "${flags[@]}" -fobjc-arc -c "$core/$name.mm" -o "$out/$name.o"
done
xcrun clang++ "${flags[@]}" -c "$codecs/sample_encryptor.cc" -o "$out/sample_encryptor.o"
xcrun clang++ "${flags[@]}" -fobjc-arc -c "$here/decode_time_harness.mm" -o "$out/harness.o"
xcrun clang++ "$out"/fairplay_*.o "$out/sample_encryptor.o" "$out/harness.o" -framework AppKit -framework AVFoundation \
  -framework AudioToolbox -framework CoreAudio -framework CoreMedia -framework CoreVideo \
  -framework QuartzCore -framework VideoToolbox -o "$out/decode-time-harness"

bitrate="${PARC_DECODE_TIMES_KBPS:-12000}"
size="${PARC_DECODE_TIMES_SIZE:-1920x1080}"
bframes="${PARC_DECODE_TIMES_BFRAMES:-3}"
clip="$out/pyramid-${size}-24fps-${bitrate}k-b${bframes}"
if [ ! -s "$clip.hevc" ]; then
  "$out/decode-time-harness" --write-yuv 480 "${size%x*}" "${size#*x}" |
    x265 --input - --input-res "$size" --fps 24 --preset ultrafast \
      --bframes "$bframes" --rc-lookahead $((bframes + 2)) --b-adapt 0 --b-pyramid --keyint 48 --min-keyint 48 --no-scenecut --no-open-gop \
      --repeat-headers --aud --bitrate "$bitrate" --vbv-maxrate $((bitrate * 4 / 3)) \
      --vbv-bufsize $((bitrate * 2)) --csv "$clip.csv" --csv-log-level 1 -o "$clip.hevc" 2>&1 | tail -1
fi
for dts in invalid real; do
  "$out/decode-time-harness" --play "$clip.hevc" "$clip.csv" --dts "$dts" --size "$size" "$@"
  echo
done
