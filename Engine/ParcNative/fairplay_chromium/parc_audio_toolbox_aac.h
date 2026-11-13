#ifndef MEDIA_FILTERS_MAC_PARC_AUDIO_TOOLBOX_AAC_H_
#define MEDIA_FILTERS_MAC_PARC_AUDIO_TOOLBOX_AAC_H_

#include <AudioToolbox/AudioToolbox.h>
#include <stddef.h>
#include <stdint.h>

#include <optional>
#include <vector>

#include "base/containers/span.h"
#include "media/base/audio_codecs.h"
#include "media/base/audio_decoder_config.h"
#include "media/formats/mpeg/adts_constants.h"

namespace media {

class MediaLog;

namespace parc_audio_toolbox {

inline bool DecodesWithAudioToolbox(const AudioDecoderConfig& config) {
  return config.codec() == AudioCodec::kAAC ||
         config.codec() == AudioCodec::kALAC ||
         config.codec() == AudioCodec::kAMR_NB ||
         config.codec() == AudioCodec::kAMR_WB;
}

inline bool IsAmr(const AudioDecoderConfig& config) {
  return config.codec() == AudioCodec::kAMR_NB ||
         config.codec() == AudioCodec::kAMR_WB;
}

inline bool MayArriveAsAdts(const AudioDecoderConfig& config) {
  return config.codec() == AudioCodec::kAAC &&
         config.profile() != AudioCodecProfile::kXHE_AAC;
}

inline bool TakesConfigFromAdts(const AudioDecoderConfig& config) {
  return MayArriveAsAdts(config) && config.extra_data().empty();
}

inline size_t AdtsHeaderSize(base::span<const uint8_t> data) {
  if (data.size() < kADTSHeaderMinSize || data[0] != 0xff ||
      (data[1] & 0xf6) != 0xf0) {
    return 0;
  }
  const size_t frame_size =
      ((data[3] & 0x03) << 11) | (data[4] << 3) | (data[5] >> 5);
  const size_t header_size =
      (data[1] & 0x01) ? kADTSHeaderSizeNoCrc : kADTSHeaderSizeWithCrc;
  if (frame_size != data.size() || frame_size <= header_size) {
    return 0;
  }
  return header_size;
}

inline bool DrainsAtEndOfStream(const AudioDecoderConfig& config) {
  return MayArriveAsAdts(config);
}

std::vector<AudioStreamPacketDescription> AmrPackets(
    AudioCodec codec,
    base::span<const uint8_t> sample);

std::vector<uint8_t> AdtsAudioSpecificConfig(base::span<const uint8_t> adts);

std::optional<int> ImplicitSbrRate(
    const std::vector<uint8_t>& audio_specific_config,
    base::span<const uint8_t> access_unit,
    int sample_rate);

bool AacInputFormat(const std::vector<uint8_t>& audio_specific_config,
                    int sample_rate,
                    std::vector<uint8_t>& magic_cookie,
                    AudioStreamBasicDescription& input_format,
                    MediaLog* media_log);

bool AlacOrAmrInputFormat(const AudioDecoderConfig& config,
                          std::vector<uint8_t>& magic_cookie,
                          AudioStreamBasicDescription& input_format,
                          MediaLog* media_log);

}

}

#endif
