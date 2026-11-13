#ifndef MEDIA_RENDERERS_PARC_AUDIO_RENDERER_AAC_H_
#define MEDIA_RENDERERS_PARC_AUDIO_RENDERER_AAC_H_

#include <stdint.h>

#include <array>
#include <vector>

#include "build/build_config.h"
#include "media/base/audio_codecs.h"
#include "media/base/audio_decoder_config.h"

#if BUILDFLAG(IS_MAC)
namespace media {

inline bool ParcMayDoubleAacRate(const AudioDecoderConfig& config) {
  if (config.codec() != AudioCodec::kAAC ||
      config.profile() == AudioCodecProfile::kXHE_AAC ||
      config.samples_per_second() > 24000) {
    return false;
  }
  const std::vector<uint8_t>& audio_specific_config = config.extra_data();
  if (audio_specific_config.empty()) {
    return true;
  }
  if (audio_specific_config.size() != 2) {
    return false;
  }
  constexpr auto kCoreRates =
      std::to_array<int>({24000, 22050, 16000, 12000, 11025, 8000});
  const uint32_t object_type = audio_specific_config[0] >> 3;
  const uint32_t frequency_index = ((audio_specific_config[0] & 0x07) << 1) |
                                   (audio_specific_config[1] >> 7);
  const uint32_t channel_config = (audio_specific_config[1] >> 3) & 0x0f;
  return object_type == 2 && frequency_index >= 6 && frequency_index <= 11 &&
         channel_config >= 1 && channel_config <= 7 &&
         (audio_specific_config[1] & 0x07) == 0 &&
         kCoreRates[frequency_index - 6] == config.samples_per_second();
}

}
#endif

#endif
