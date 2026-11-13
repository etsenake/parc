#ifndef MEDIA_FORMATS_MP2T_PARC_MP2T_STREAM_PARSER_H_
#define MEDIA_FORMATS_MP2T_PARC_MP2T_STREAM_PARSER_H_

#include <stdint.h>

#include <optional>
#include <string>
#include <vector>

#include "media/base/decrypt_config.h"
#include "media/base/stream_parser_buffer.h"

namespace media {

class AudioDecoderConfig;

namespace mp2t::parc_mp2t {

inline constexpr int kStreamTypeMpeg1Video = 0x1;
inline constexpr int kStreamTypeMpeg2Video = 0x2;
inline constexpr int kStreamTypeAC3 = 0x81;
inline constexpr int kStreamTypeEAC3 = 0x87;
inline constexpr int kStreamTypeAC3WithSampleAES = 0xc1;
inline constexpr int kStreamTypeEAC3WithSampleAES = 0xc2;

inline constexpr char kTransportStreamKeyId[] = "TransportStreamIdentifier";

inline void MarkSampleAes(StreamParserBuffer& buffer) {
  buffer.set_decrypt_config(DecryptConfig::CreateCbcsConfig(
      kTransportStreamKeyId,
      std::string(DecryptConfig::kDecryptionKeySize, '\0'), {},
      std::nullopt));
}

AudioDecoderConfig SampleAesAudioConfig(const AudioDecoderConfig& es_config,
                                        const std::vector<uint8_t>& setup_data,
                                        uint32_t audio_type);

}

}

#endif
