#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "fairplay_types.h"

namespace parc::fairplay::test {

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
  uint32_t sample_entry = 0;
  uint32_t original_format = 0;
  std::vector<uint8_t> codec_config;
  std::vector<uint8_t> dolby_vision_config;
  std::vector<uint8_t> esds_payload;
  std::vector<uint8_t> sinf_payload;
  std::vector<uint8_t> sample_entry_box;
  uint16_t width = 0;
  uint16_t height = 0;
  uint16_t channels = 0;
  uint32_t sample_rate = 0;
  uint32_t scheme_type = 0;
  TrackEncryption encryption;
  int64_t edit_media_time = 0;
  uint32_t default_sample_duration = 0;
  uint32_t default_sample_size = 0;
  uint32_t default_sample_flags = 0;
  std::vector<uint8_t> pssh_boxes;
  std::vector<SeigEntry> seig;
};

struct Sample {
  std::vector<uint8_t> data;
  int64_t dts = 0;
  int64_t pts = 0;
  int64_t duration = 0;
  bool is_keyframe = false;
  std::optional<DecryptInfo> decrypt;
  bool aux_from_saio = false;
};

bool ParseInitSegment(const std::vector<uint8_t>& data, TrackInfo* track, std::string* error);

bool ParseMediaSegment(const std::vector<uint8_t>& data,
                       const TrackInfo& track,
                       std::vector<Sample>* samples,
                       std::string* error);

bool ParseProgressiveFile(const std::vector<uint8_t>& data,
                          const TrackInfo& track,
                          std::vector<Sample>* samples,
                          std::string* error);

EncodedSample ChromiumBuffer(const TrackInfo& track, const Sample& sample,
                             std::vector<uint8_t>* storage, DecryptInfo* decrypt_storage);

EncodedSample IsoBuffer(const TrackInfo& track, const Sample& sample);

bool AvcToAnnexB(const std::vector<uint8_t>& record,
                 bool hevc,
                 bool insert_parameter_sets,
                 std::vector<uint8_t>* data,
                 std::vector<SubsampleEntry>* subsamples);
std::vector<uint8_t> AdtsHeader(const std::vector<uint8_t>& audio_specific_config,
                                size_t payload_size);
int AacObjectType(const std::vector<uint8_t>& audio_specific_config, bool core);
std::vector<uint8_t> AscFromDescriptor(const uint8_t* data, size_t size);

std::string FourCCString(uint32_t value);
std::string Hex(const std::vector<uint8_t>& bytes);

}
