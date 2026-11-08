// Minimal MPEG-2 TS demuxer yielding what Chromium's Mp2tStreamParser hands
// a renderer for one elementary stream (the harness's stand-in for it, as
// fmp4_parser is for MP4StreamParser).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "fmp4_parser.h"

namespace parc::fairplay::test {

struct TsElementaryStream {
  uint8_t stream_type = 0;
  std::vector<uint8_t> descriptors;  // The PMT's ES_info bytes.
  // H.264: access units from AUD to AUD, Annex B as carried (EsParserH264).
  // ADTS: one frame per sample, header included, its PES PTS for the first
  // frame of a PES and 1024 samples per frame after it (EsParserAdts). Times
  // in 90 kHz; |dts| is the PES DTS (PTS when absent).
  std::vector<Sample> samples;
};

// The first video (H.264, 0x1b or SAMPLE-AES 0xdb) or audio (ADTS AAC, 0x0f
// or 0xcf) stream of |data|.
bool ParseTransportStream(const std::vector<uint8_t>& data, bool video, TsElementaryStream* stream,
                          std::string* error);

// The AudioSpecificConfig in a SAMPLE-AES stream's audio setup information
// (the 'apad' registration descriptor), empty if there is none.
uint32_t TsAudioSetupType(const std::vector<uint8_t>& descriptors);
std::vector<uint8_t> TsAudioSetupConfig(const std::vector<uint8_t>& descriptors);

}  // namespace parc::fairplay::test
