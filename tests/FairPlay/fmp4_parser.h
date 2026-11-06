// Minimal CMAF/fMP4 parser for the FairPlay proof. It yields what Chromium's
// MP4StreamParser hands a renderer (media/formats/mp4 at the pinned tag):
// codec config, sinf/schm/tenc, and per sample its bytes, timing, keyframe
// flag and DecryptConfig (key ID, IV, subsamples from senc or saiz/saio,
// pattern), with Chromium's reframing available on top.
#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "fairplay_types.h"

namespace parc::fairplay::test {

// A 'seig' sample group description (CencSampleEncryptionInformationGroupEntry).
struct SeigEntry {
  bool is_protected = false;
  EncryptionPattern pattern;
  uint8_t per_sample_iv_size = 0;
  std::vector<uint8_t> key_id;
  std::vector<uint8_t> constant_iv;
};

struct TrackInfo {
  uint32_t track_id = 0;
  uint32_t timescale = 0;
  bool is_video = false;
  uint32_t sample_entry = 0;     // encv/enca/avc1/hvc1/mp4a...
  uint32_t original_format = 0;  // frma, or the sample entry when clear.
  std::vector<uint8_t> codec_config;  // avcC/hvcC/av1C payload, or AAC AudioSpecificConfig.
  std::vector<uint8_t> dolby_vision_config;  // dvcC/dvvC payload.
  std::vector<uint8_t> esds_payload;  // esds FullBox payload (audio).
  std::vector<uint8_t> sinf_payload;  // As found in the file.
  std::vector<uint8_t> sample_entry_box;  // The stsd entry, whole.
  uint16_t width = 0;
  uint16_t height = 0;
  uint16_t channels = 0;
  uint32_t sample_rate = 0;
  uint32_t scheme_type = 0;
  TrackEncryption encryption;
  int64_t edit_media_time = 0;  // First non-empty elst entry.
  uint32_t default_sample_duration = 0;
  uint32_t default_sample_size = 0;
  uint32_t default_sample_flags = 0;
  std::vector<uint8_t> pssh_boxes;  // moov 'pssh' boxes, concatenated (cenc init data).
  std::vector<SeigEntry> seig;      // stbl-level 'seig' descriptions.
};

struct Sample {
  std::vector<uint8_t> data;
  int64_t dts = 0;  // Track timescale, edit list applied (as Chromium does).
  int64_t pts = 0;
  int64_t duration = 0;
  bool is_keyframe = false;
  std::optional<DecryptInfo> decrypt;  // Raw: IV as stored (empty for a constant IV).
  bool aux_from_saio = false;          // Encryption info read via saiz/saio.
};

bool ParseInitSegment(const std::vector<uint8_t>& data, TrackInfo* track, std::string* error);

// Parses moof/mdat pairs. When both senc and saiz/saio are present, both are
// read and must agree; |error| reports a mismatch.
bool ParseMediaSegment(const std::vector<uint8_t>& data,
                       const TrackInfo& track,
                       std::vector<Sample>* samples,
                       std::string* error);

// Samples of a progressive (unfragmented) MP4 from its moov sample tables
// (clear tracks only).
bool ParseProgressiveFile(const std::vector<uint8_t>& data,
                          const TrackInfo& track,
                          std::vector<Sample>* samples,
                          std::string* error);

// Chromium's DecoderBuffer form of |sample|: H.264/HEVC converted to Annex B
// with parameter sets inserted before keyframes (AVC::ConvertFrameToAnnexB,
// InsertParamSetsAnnexB), AAC prefixed with ADTS (PrepareAACBuffer), times in
// microseconds with no decode timestamp (mojom::DecoderBuffer has none), the
// constant IV copied in and every IV padded to 16 bytes
// (TrackRunIterator::GetDecryptConfig), subsamples adjusted to match.
EncodedSample ChromiumBuffer(const TrackInfo& track, const Sample& sample,
                             std::vector<uint8_t>* storage, DecryptInfo* decrypt_storage);

// The ISO form AVStreamDataParser would see: bytes untouched, track timescale,
// IV only when stored per sample.
EncodedSample IsoBuffer(const TrackInfo& track, const Sample& sample);

// Chromium-side conversions, exposed for self-tests.
bool AvcToAnnexB(const std::vector<uint8_t>& record,
                 bool hevc,
                 bool insert_parameter_sets,
                 std::vector<uint8_t>* data,
                 std::vector<SubsampleEntry>* subsamples);
std::vector<uint8_t> AdtsHeader(const std::vector<uint8_t>& audio_specific_config,
                                size_t payload_size);
// AudioSpecificConfig object type, and the core type for SBR/PS (5, 29).
int AacObjectType(const std::vector<uint8_t>& audio_specific_config, bool core);
// The AudioSpecificConfig inside an ES_Descriptor or 'esds' payload.
std::vector<uint8_t> AscFromDescriptor(const uint8_t* data, size_t size);

std::string FourCCString(uint32_t value);
std::string Hex(const std::vector<uint8_t>& bytes);

}  // namespace parc::fairplay::test
