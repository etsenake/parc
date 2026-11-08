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
  // Invalid when unknown, as from Chromium's DecoderBuffer (it carries no
  // decode timestamp): AVFoundation then decodes in enqueue order.
  MediaTime dts;
  MediaTime duration;
  bool is_keyframe = false;
  std::optional<DecryptInfo> decrypt;  // nullopt for clear samples.
};

// Track-level protection, from 'schm'/'tenc'. Only |scheme| is required:
// Chromium gives a renderer just the decoder config's EncryptionScheme, so
// when the key ID, pattern or IV fields are empty the renderer takes them
// from each sample's DecryptInfo (protected formats are built per key ID from
// the first encrypted sample, which also handles clear lead).
struct TrackEncryption {
  EncryptionScheme scheme = EncryptionScheme::kUnencrypted;
  std::vector<uint8_t> default_key_id;  // 16 bytes.
  EncryptionPattern default_pattern;
  uint8_t default_per_sample_iv_size = 0;  // 0 when a constant IV is used.
  std::vector<uint8_t> default_constant_iv;
};

enum class VideoCodec { kH264, kHEVC, kDolbyVision, kAV1 };
// kAAC covers every AudioSpecificConfig object type: LC, HE-AAC (5),
// HE-AACv2 (29) and xHE-AAC/USAC (42).
enum class AudioCodec { kAAC, kAC3, kEAC3, kFLAC, kOpus, kALAC, kPCM };

// How video access units are framed. ISO-BMFF samples are length-prefixed;
// Chromium's MP4 parser converts H.264, HEVC and Dolby Vision (not profile
// 10) to Annex B and re-inserts parameter sets on keyframes before handing
// buffers to a renderer. AV1 stays as stored (kLengthPrefixed).
enum class BitstreamFormat { kLengthPrefixed, kAnnexB };

// Chromium's MP4 parser prepends a 7-byte ADTS header to AAC samples whose
// config fits ADTS (not xHE-AAC). With kADTS a header is stripped when present.
enum class AudioFraming { kRaw, kADTS };

struct VideoConfig {
  VideoCodec codec = VideoCodec::kH264;
  // ISO sample entry type: 0 picks avc1, hvc1, dvh1 or av01. Pass avc3, hev1
  // or dvhe for streams whose parameter sets travel in-band; the renderer
  // presents them as avc1, hvc1 and dvh1 (VideoToolbox configures only from
  // the record), so their protected types are qavc, qhvc and qdh1.
  uint32_t sample_entry = 0;
  // AVCDecoderConfigurationRecord ('avcC' payload), HEVCDecoderConfigurationRecord
  // ('hvcC', also for Dolby Vision) or AV1CodecConfigurationRecord ('av1C').
  // May be empty, as Chromium's MP4 parser always leaves it: the renderer then
  // builds it from the first keyframe (in-band SPS/PPS/VPS, or AV1's sequence
  // header OBU), and rebuilds it whenever a keyframe brings different ones.
  std::vector<uint8_t> extra_data;
  // Dolby Vision: DOVIDecoderConfigurationRecord, carried as 'dvcC' for
  // profiles up to 7 and 'dvvC' from 8. Profile 10 is kAV1 with sample entry
  // 'dav1'. When empty and dolby_vision_profile
  // is set (Chromium carries only profile and level), it is built from
  // profile, level and compatibility ID; -1 means unknown and takes
  // DefaultDolbyVisionCompatibilityId (0 for profile 5).
  std::vector<uint8_t> dolby_vision_config;
  int dolby_vision_profile = -1;
  int dolby_vision_level = 0;
  int dolby_vision_compatibility_id = -1;
  BitstreamFormat format = BitstreamFormat::kLengthPrefixed;
  int32_t coded_width = 0;
  int32_t coded_height = 0;
  int32_t natural_width = 0;   // 0 means coded size.
  int32_t natural_height = 0;
  TrackEncryption encryption;
};

struct AudioConfig {
  AudioCodec codec = AudioCodec::kAAC;
  // AAC: AudioSpecificConfig (any object type; required). AC-3: 'dac3'
  // payload. E-AC-3: 'dec3' payload. For AC-3/E-AC-3 it may be empty, as
  // Chromium leaves it: the renderer builds it from the first syncframe's
  // clear header, or from sample_rate and channels when it is encrypted.
  // FLAC: the 34-byte STREAMINFO block (Chromium's, from 'dfLa'; required).
  // Opus: the OpusHead Chromium builds from 'dOps' (required).
  // ALAC: the 24-byte ALACSpecificConfig (Chromium's, from the 'alac' box), or
  // Apple's magic cookie with its 'alac' atom (FFmpeg's); required.
  // PCM: none (see pcm_bits).
  std::vector<uint8_t> extra_data;
  AudioFraming framing = AudioFraming::kRaw;
  int32_t sample_rate = 0;
  int32_t channels = 0;
  // PCM: interleaved little-endian samples of 16, 24 or 32 bits, or 32-bit
  // float, as Chromium's MP4 parser gives ISO 23003-5 'ipcm' and 'fpcm'.
  int32_t pcm_bits = 0;
  bool pcm_float = false;
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
