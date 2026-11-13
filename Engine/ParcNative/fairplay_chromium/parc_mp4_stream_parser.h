#ifndef MEDIA_FORMATS_MP4_PARC_MP4_STREAM_PARSER_H_
#define MEDIA_FORMATS_MP4_PARC_MP4_STREAM_PARSER_H_

#include <stddef.h>
#include <stdint.h>

#include <algorithm>
#include <cstring>
#include <optional>
#include <utility>
#include <vector>

#include "base/containers/span.h"
#include "base/containers/to_vector.h"
#include "media/base/audio_codecs.h"
#include "media/base/channel_layout.h"
#include "media/base/sample_format.h"
#include "media/base/video_color_space.h"
#include "media/formats/mp4/box_definitions.h"
#include "media/formats/mp4/fourccs.h"

namespace media {

class MediaLog;

namespace mp4 {

namespace parc_mp4 {

void AddSinfInitData(const ProtectionSchemeInfo& sinf,
                     std::vector<std::vector<uint8_t>>* init_data);

bool AudioEntryConfig(FourCC audio_format,
                      const AudioSampleEntry& entry,
                      bool amr,
                      bool ignore_declared_codecs,
                      bool has_alac,
                      MediaLog* media_log,
                      AudioCodec* codec,
                      ChannelLayoutConfig* channel_layout_config,
                      int* sample_per_second,
                      std::vector<uint8_t>* extra_data);

std::optional<SampleFormat> AudioSampleFormat(FourCC audio_format,
                                              AudioCodec codec,
                                              bool amr,
                                              const AudioSampleEntry& entry);

std::pair<bool, bool> DolbyVisionLayers(const VideoSampleEntry& entry);

bool IsDolbyVisionSdr(const VideoSampleEntry& entry, bool dolby_vision);

VideoColorSpace DolbyVisionColorSpace(const DolbyVisionInfo& dv_info,
                                      bool dolby_vision);

inline bool PreparePcmSample(const AudioSampleEntry& entry,
                      bool encrypted,
                      base::span<const uint8_t> buf,
                      size_t sample_size,
                      std::vector<uint8_t>& frame_buf) {
  const FourCC format =
      entry.format == FOURCC_ENCA ? entry.sinf.format.format : entry.format;
  if (format != FOURCC_IPCM && format != FOURCC_FPCM) {
    return true;
  }
  const size_t width = entry.pcm.sample_size / 8;
  if (!width || !entry.channelcount ||
      sample_size % (width * entry.channelcount) != 0)
    return false;
  if (encrypted && (!(entry.pcm.format_flags & 1) || width == 8))
    return false;
  if (!encrypted) {
    frame_buf = base::ToVector(buf.first(sample_size));
    if (!(entry.pcm.format_flags & 1)) {
      for (size_t i = 0; i < frame_buf.size(); i += width)
        std::reverse(frame_buf.begin() + i, frame_buf.begin() + i + width);
    }
    if (format == FOURCC_FPCM && width == 8) {
      for (size_t i = 0; i < frame_buf.size() / 8; ++i) {
        double value;
        memcpy(&value, frame_buf.data() + i * 8, 8);
        const float converted = static_cast<float>(value);
        memcpy(frame_buf.data() + i * 4, &converted, 4);
      }
      frame_buf.resize(frame_buf.size() / 2);
    }
  }
  return true;
}

}

}

}

#endif
