#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
mkdir -p "$root/build/tests/native-media-episode-store"
xcrun clang++ -std=c++20 -Wall -Wextra -Werror \
  -I "$root/Engine/ParcNative" "$root/tests/NativeMediaEpisodeStore/Tests.cc" \
  -o "$root/build/tests/native-media-episode-store/check"
"$root/build/tests/native-media-episode-store/check"
