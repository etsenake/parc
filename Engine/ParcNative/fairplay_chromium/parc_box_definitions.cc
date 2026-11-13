#include "media/formats/mp4/box_definitions.h"

#include "media/formats/mp4/rcheck.h"

namespace media::mp4 {

PCMConfiguration::PCMConfiguration() = default;
PCMConfiguration::PCMConfiguration(const PCMConfiguration& other) = default;
PCMConfiguration::~PCMConfiguration() = default;
FourCC PCMConfiguration::BoxType() const { return FOURCC_PCMC; }
bool PCMConfiguration::Parse(BoxReader* reader) {
  RCHECK(reader->ReadFullBoxHeader());
  RCHECK(reader->version() == 0 && reader->flags() == 0);
  return reader->Read1(&format_flags) && reader->Read1(&sample_size);
}

ALACSpecificBox::ALACSpecificBox() = default;

ALACSpecificBox::ALACSpecificBox(const ALACSpecificBox& other) = default;

ALACSpecificBox::~ALACSpecificBox() = default;

FourCC ALACSpecificBox::BoxType() const {
  return FOURCC_ALAC;
}

bool ALACSpecificBox::Parse(BoxReader* reader) {
  constexpr size_t kConfigSize = 24;
  RCHECK(reader->ReadFullBoxHeader());
  RCHECK_MEDIA_LOGGED(reader->version() == 0 && reader->flags() == 0,
                      reader->media_log(),
                      "Only version 0, flags 0 ALACSpecificBox is supported.");
  RCHECK_MEDIA_LOGGED(reader->ReadVec(&config, kConfigSize),
                      reader->media_log(),
                      "ALACSpecificBox is missing its ALACSpecificConfig.");
  const uint32_t frame_length = uint32_t{config[0]} << 24 |
                                uint32_t{config[1]} << 16 |
                                uint32_t{config[2]} << 8 | config[3];
  bit_depth = config[5];
  channel_count = config[9];
  sample_rate = uint32_t{config[20]} << 24 | uint32_t{config[21]} << 16 |
                uint32_t{config[22]} << 8 | config[23];
  RCHECK_MEDIA_LOGGED(frame_length > 0 && config[4] == 0 &&
                          (bit_depth == 16 || bit_depth == 20 ||
                           bit_depth == 24 || bit_depth == 32) &&
                          channel_count > 0 && sample_rate > 0,
                      reader->media_log(),
                      "Unsupported ALACSpecificConfig.");
  return true;
}

AMRSpecificBox::AMRSpecificBox() = default;
AMRSpecificBox::AMRSpecificBox(const AMRSpecificBox& other) = default;
AMRSpecificBox::~AMRSpecificBox() = default;
FourCC AMRSpecificBox::BoxType() const {
  return FOURCC_DAMR;
}
bool AMRSpecificBox::Parse(BoxReader* reader) {
  return reader->SkipBytes(9);
}

H263SpecificBox::H263SpecificBox() = default;
H263SpecificBox::H263SpecificBox(const H263SpecificBox& other) = default;
H263SpecificBox::~H263SpecificBox() = default;
FourCC H263SpecificBox::BoxType() const {
  return FOURCC_D263;
}
bool H263SpecificBox::Parse(BoxReader* reader) {
  return reader->SkipBytes(5) && reader->Read1(&level) &&
         reader->SkipBytes(1);
}

}
