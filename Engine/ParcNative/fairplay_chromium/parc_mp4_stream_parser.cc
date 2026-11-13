#include "media/formats/mp4/parc_mp4_stream_parser.h"

#include <algorithm>
#include <cstring>
#include <string>

#include "base/base64.h"
#include "base/containers/to_vector.h"
#include "media/base/media_log.h"
#include "media/base/video_codecs.h"
#include "media/formats/mp4/box_definitions.h"
#include "media/media_buildflags.h"

#if BUILDFLAG(USE_PROPRIETARY_CODECS)
#include "media/formats/mp4/dolby_vision.h"
#endif

namespace media::mp4::parc_mp4 {

void AddSinfInitData(const ProtectionSchemeInfo& sinf,
                     std::vector<std::vector<uint8_t>>* init_data) {
  if (sinf.raw_payload.empty()) {
    return;
  }
  const std::string json =
      "{\"sinf\":[\"" + base::Base64Encode(sinf.raw_payload) + "\"]}";
  init_data->emplace_back(json.begin(), json.end());
}

bool AudioEntryConfig(FourCC audio_format,
                      const AudioSampleEntry& entry,
                      bool amr,
                      bool ignore_declared_codecs,
                      bool has_alac,
                      MediaLog* media_log,
                      AudioCodec* codec,
                      ChannelLayoutConfig* channel_layout_config,
                      int* sample_per_second,
                      std::vector<uint8_t>* extra_data) {
  if (audio_format == FOURCC_IPCM || audio_format == FOURCC_FPCM) {
    if (!ignore_declared_codecs)
      return false;
    if (entry.format == FOURCC_ENCA &&
        (!(entry.pcm.format_flags & 1) || entry.pcm.sample_size == 64))
      return false;
    *codec = AudioCodec::kPCM;
    *channel_layout_config = ChannelLayoutConfig::Guess(entry.channelcount);
    *sample_per_second = entry.samplerate;
    return true;
  }
  if (amr) {
    *codec = audio_format == FOURCC_SAMR ? AudioCodec::kAMR_NB
                                         : AudioCodec::kAMR_WB;
    *channel_layout_config = ChannelLayoutConfig::Mono();
    *sample_per_second = audio_format == FOURCC_SAMR ? 8000 : 16000;
    return true;
  }
  if (!has_alac && !ignore_declared_codecs) {
    MEDIA_LOG(ERROR, media_log) << "ALAC audio stream detected in MP4, "
                                   "mismatching what is specified in "
                                   "the mimetype.";
    return false;
  }
  *codec = AudioCodec::kALAC;
  *channel_layout_config = ChannelLayoutConfig::Guess(entry.alac.channel_count);
  *sample_per_second = entry.alac.sample_rate;
  *extra_data = entry.alac.config;
  return true;
}

std::optional<SampleFormat> AudioSampleFormat(FourCC audio_format,
                                              AudioCodec codec,
                                              bool amr,
                                              const AudioSampleEntry& entry) {
  if (audio_format == FOURCC_FPCM) {
    return kSampleFormatF32;
  }
  if (audio_format == FOURCC_IPCM) {
    return entry.pcm.sample_size == 16   ? kSampleFormatS16
           : entry.pcm.sample_size == 24 ? kSampleFormatS24
                                         : kSampleFormatS32;
  }
  if (amr) {
    return kSampleFormatS16;
  }
  if (codec == AudioCodec::kALAC) {
    return entry.alac.bit_depth == 16   ? kSampleFormatS16
           : entry.alac.bit_depth == 32 ? kSampleFormatS32
                                        : kSampleFormatS24;
  }
  return std::nullopt;
}

std::pair<bool, bool> DolbyVisionLayers(const VideoSampleEntry& entry) {
  if (!entry.dv_info.has_value()) {
    return {false, false};
  }
  const VideoCodecProfile profile = entry.dv_info->codec_info.profile;
  const FourCC video_format =
      entry.format == FOURCC_ENCV ? entry.sinf.format.format : entry.format;
  const bool decodes_as_dolby_vision =
      profile == DOLBYVISION_PROFILE5 || profile == DOLBYVISION_PROFILE8 ||
      (profile == DOLBYVISION_PROFILE10 && video_format != FOURCC_AV01);
  return {entry.dv_info->parc_base_codec_info.has_value() &&
              !decodes_as_dolby_vision,
          decodes_as_dolby_vision};
}

bool IsDolbyVisionSdr(const VideoSampleEntry& entry, bool dolby_vision) {
  return dolby_vision && entry.dv_info &&
         (entry.dv_info->codec_info.profile == DOLBYVISION_PROFILE8 ||
          entry.dv_info->codec_info.profile == DOLBYVISION_PROFILE10) &&
         entry.dv_info->parc_compatibility_id == 2;
}

VideoColorSpace DolbyVisionColorSpace(const DolbyVisionInfo& dv_info,
                                      bool dolby_vision) {
#if BUILDFLAG(USE_PROPRIETARY_CODECS)
  if (dolby_vision && dv_info.codec_info.profile == DOLBYVISION_PROFILE10) {
    return ParseDolbyVisionColorSpace(DOLBYVISION_PROFILE8,
                                      dv_info.parc_compatibility_id);
  }
#endif
  return dv_info.color_space;
}

}
