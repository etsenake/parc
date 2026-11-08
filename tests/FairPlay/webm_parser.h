// Minimal WebM parser for the FairPlay proofs: the first track of one of
// Chromium's WebM test files as its WebM parser hands it to a renderer.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "fmp4_parser.h"

namespace parc::fairplay::test {

// A VP9 ('vp09') or Vorbis ('vorb') first track: CodecPrivate as the codec
// config, frames as stored (unlaced SimpleBlocks or Blocks), times in the
// segment's timecode units with each frame lasting until the next.
bool ParseWebmFile(const std::vector<uint8_t>& file, TrackInfo* track, std::vector<Sample>* samples,
                   std::string* error);

}  // namespace parc::fairplay::test
