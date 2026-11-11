#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "fmp4_parser.h"

namespace parc::fairplay::test {

bool ParseWebmFile(const std::vector<uint8_t>& file, TrackInfo* track, std::vector<Sample>* samples,
                   std::string* error);

}
