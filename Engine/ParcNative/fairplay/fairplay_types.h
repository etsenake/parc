// Engine-independent types shared by the FairPlay key session and renderer.
// Pure C++ so Chromium .cc files can include them; the implementations are
// ObjC++ (.mm, ARC) over AVFoundation/CoreMedia.
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace parc::fairplay {

// Posts |task| to the owner's sequence. Every public method of FairPlayCdm and
// FairPlayRenderer must be called on that sequence, and every client callback
// runs on it (base::SequencedTaskRunner::PostTask in the engine).
using PostTask = std::function<void(std::function<void()>)>;

// Rational time, like CMTime. Chromium passes microseconds (timescale 1e6).
struct MediaTime {
  int64_t value = 0;
  int32_t timescale = 0;  // 0 means invalid.

  static MediaTime FromMicroseconds(int64_t microseconds) {
    return {microseconds, 1000000};
  }
  static MediaTime Invalid() { return {}; }
  bool IsValid() const { return timescale > 0; }
  double InSeconds() const {
    return IsValid() ? static_cast<double>(value) / timescale : 0.0;
  }
  int64_t InMicroseconds() const {
    if (!IsValid()) {
      return 0;
    }
    return static_cast<int64_t>(static_cast<__int128>(value) * 1000000 / timescale);
  }
};

enum class EncryptionScheme { kUnencrypted, kCenc, kCbcs };

// cbcs pattern in 16-byte blocks. {0, 0} means every complete block is
// encrypted (CMAF cbcs audio).
struct EncryptionPattern {
  uint8_t crypt_byte_block = 0;
  uint8_t skip_byte_block = 0;
};

struct SubsampleEntry {
  uint32_t clear_bytes = 0;
  uint32_t cypher_bytes = 0;
};

// Per-sample decryption parameters, mirroring media::DecryptConfig.
struct DecryptInfo {
  EncryptionScheme scheme = EncryptionScheme::kCbcs;
  std::vector<uint8_t> key_id;  // 16 bytes.
  // 8 or 16 bytes. Chromium copies a tenc constant IV into every sample and
  // zero-pads 8-byte IVs to 16; both forms are accepted.
  std::vector<uint8_t> iv;
  // Empty means the whole sample is protected.
  std::vector<SubsampleEntry> subsamples;
  std::optional<EncryptionPattern> pattern;  // cbcs only.
};

// One access unit. |data| is borrowed for the duration of the Enqueue call.
struct EncodedSample {
  const uint8_t* data = nullptr;
  size_t size = 0;
  MediaTime pts;
  MediaTime dts;  // Invalid means same as pts.
  MediaTime duration;
  bool is_keyframe = false;
  std::optional<DecryptInfo> decrypt;  // nullopt for clear samples.
};

// Track-level protection, from 'schm'/'tenc' (or Chromium's
// EncryptionScheme on the decoder config plus the first DecryptConfig).
struct TrackEncryption {
  EncryptionScheme scheme = EncryptionScheme::kUnencrypted;
  std::vector<uint8_t> default_key_id;  // 16 bytes.
  EncryptionPattern default_pattern;
  uint8_t default_per_sample_iv_size = 0;  // 0 when a constant IV is used.
  std::vector<uint8_t> default_constant_iv;
};

enum class VideoCodec { kH264, kHEVC };
enum class AudioCodec { kAAC, kAC3, kEAC3 };

// How video access units are framed. ISO-BMFF samples are length-prefixed;
// Chromium's MP4 parser converts H.264/HEVC to Annex B and re-inserts
// parameter sets on keyframes before handing buffers to a renderer.
enum class BitstreamFormat { kLengthPrefixed, kAnnexB };

// Chromium's MP4 parser prepends a 7-byte ADTS header to every AAC sample.
enum class AudioFraming { kRaw, kADTS };

struct VideoConfig {
  VideoCodec codec = VideoCodec::kH264;
  // AVCDecoderConfigurationRecord ('avcC' payload) or
  // HEVCDecoderConfigurationRecord ('hvcC' payload).
  std::vector<uint8_t> extra_data;
  BitstreamFormat format = BitstreamFormat::kLengthPrefixed;
  int32_t coded_width = 0;
  int32_t coded_height = 0;
  int32_t natural_width = 0;   // 0 means coded size.
  int32_t natural_height = 0;
  TrackEncryption encryption;
};

struct AudioConfig {
  AudioCodec codec = AudioCodec::kAAC;
  // AAC: AudioSpecificConfig. AC-3: 'dac3' payload. E-AC-3: 'dec3' payload.
  std::vector<uint8_t> extra_data;
  AudioFraming framing = AudioFraming::kRaw;
  int32_t sample_rate = 0;
  int32_t channels = 0;
  TrackEncryption encryption;
};

// Rejections map onto media::CdmPromise::Exception.
enum class Exception {
  kNone,
  kNotSupported,
  kInvalidState,
  kTypeError,
  kQuotaExceeded,
};

struct Result {
  Exception exception = Exception::kNone;
  uint32_t system_code = 0;  // NSError code when an Apple API failed.
  std::string message;

  bool ok() const { return exception == Exception::kNone; }
  static Result Ok() { return {}; }
  static Result Error(Exception exception,
                      std::string message,
                      uint32_t system_code = 0) {
    return {exception, system_code, std::move(message)};
  }
};

}  // namespace parc::fairplay
