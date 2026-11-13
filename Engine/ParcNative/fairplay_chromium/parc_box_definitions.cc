#include "media/formats/mp4/parc_box_definitions.h"

#include "media/base/video_codecs.h"
#include "media/formats/mp4/box_definitions.h"
#include "media/formats/mp4/box_reader.h"
#include "media/formats/mp4/rcheck.h"

namespace media::mp4 {

struct AMRSpecificBox : Box {
  DECLARE_BOX_METHODS(AMRSpecificBox);
};

struct H263SpecificBox : Box {
  DECLARE_BOX_METHODS(H263SpecificBox);

  uint8_t level = 0;
};

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

bool ParcReadAudioSampleEntryBoxes(BoxReader* reader, AudioSampleEntry* entry) {
  const FourCC format = entry->format;
  const ProtectionSchemeInfo& sinf = entry->sinf;
  const FourCC original_format =
      format == FOURCC_ENCA ? sinf.format.format : format;
  if (original_format == FOURCC_IPCM || original_format == FOURCC_FPCM) {
    RCHECK(entry->channelcount > 0);
    RCHECK(reader->ReadChild(&entry->pcm));
    RCHECK(original_format == FOURCC_IPCM
               ? (entry->pcm.sample_size == 16 ||
                  entry->pcm.sample_size == 24 || entry->pcm.sample_size == 32)
               : (entry->pcm.sample_size == 32 ||
                  entry->pcm.sample_size == 64));
  }

  if (original_format == FOURCC_SAMR || original_format == FOURCC_SAWB) {
    AMRSpecificBox damr;
    RCHECK_MEDIA_LOGGED(reader->ReadChild(&damr), reader->media_log(),
                        "Failure parsing AMRSpecificBox (damr)");
  }

  if (format == FOURCC_ALAC ||
      (format == FOURCC_ENCA && sinf.format.format == FOURCC_ALAC)) {
    RCHECK_MEDIA_LOGGED(reader->ReadChild(&entry->alac), reader->media_log(),
                        "Failure parsing ALACSpecificBox (alac)");
  }
  return true;
}

bool ParcReadH263SampleEntry(BoxReader* reader, VideoSampleEntry* entry) {
  H263SpecificBox d263;
  RCHECK_MEDIA_LOGGED(reader->ReadChild(&d263), reader->media_log(),
                      "Failure parsing H263SpecificBox (d263)");
  entry->video_info.codec = VideoCodec::kH263;
  entry->video_info.level = d263.level;
  entry->frame_bitstream_converter = nullptr;
  return true;
}

}
