#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "fmp4_parser.h"

namespace parc::fairplay::test {

struct TsElementaryStream {
  uint8_t stream_type = 0;
  std::vector<uint8_t> descriptors;
  std::vector<Sample> samples;
};

bool ParseTransportStream(const std::vector<uint8_t>& data, bool video, TsElementaryStream* stream,
                          std::string* error);

uint32_t TsAudioSetupType(const std::vector<uint8_t>& descriptors);
std::vector<uint8_t> TsAudioSetupConfig(const std::vector<uint8_t>& descriptors);

}
