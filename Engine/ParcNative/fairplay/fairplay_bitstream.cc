#include "fairplay_bitstream.h"

#include <algorithm>
#include <cstring>

namespace parc::fairplay {
namespace {

void AppendBE32(std::vector<uint8_t>* out, uint32_t value) {
  out->push_back(static_cast<uint8_t>(value >> 24));
  out->push_back(static_cast<uint8_t>(value >> 16));
  out->push_back(static_cast<uint8_t>(value >> 8));
  out->push_back(static_cast<uint8_t>(value));
}

void Append(std::vector<uint8_t>* out, const std::vector<uint8_t>& bytes) {
  out->insert(out->end(), bytes.begin(), bytes.end());
}

// MPEG-4 Systems descriptor: tag, expandable length, body.
std::vector<uint8_t> Descriptor(uint8_t tag, const std::vector<uint8_t>& body) {
  std::vector<uint8_t> out{tag};
  size_t size = body.size();
  if (size < 0x80) {
    out.push_back(static_cast<uint8_t>(size));
  } else {
    out.push_back(static_cast<uint8_t>(0x80 | ((size >> 21) & 0x7f)));
    out.push_back(static_cast<uint8_t>(0x80 | ((size >> 14) & 0x7f)));
    out.push_back(static_cast<uint8_t>(0x80 | ((size >> 7) & 0x7f)));
    out.push_back(static_cast<uint8_t>(size & 0x7f));
  }
  Append(&out, body);
  return out;
}

struct StartCode {
  size_t begin;          // First byte of the start code (leading zeros).
  size_t payload;        // First byte of the NAL unit.
  size_t subsample;      // Index of the subsample whose clear range holds it.
};

// MSB-first bit reader; reads past the end set failed() and return 0.
class BitReader {
 public:
  BitReader(const uint8_t* data, size_t size) : data_(data), size_(size) {}
  uint64_t Get(int bits) {
    uint64_t value = 0;
    for (int i = 0; i < bits; ++i) {
      if (position_ >= size_ * 8) {
        failed_ = true;
        return 0;
      }
      value = (value << 1) | ((data_[position_ / 8] >> (7 - position_ % 8)) & 1);
      ++position_;
    }
    return value;
  }
  // AV1 uvlc().
  uint64_t Uvlc() {
    int leading_zeros = 0;
    while (!failed_ && Get(1) == 0) {
      if (++leading_zeros >= 32) {
        failed_ = true;
        return 0;
      }
    }
    return leading_zeros ? Get(leading_zeros) + ((uint64_t{1} << leading_zeros) - 1) : 0;
  }
  bool failed() const { return failed_; }

 private:
  const uint8_t* data_;
  size_t size_;
  size_t position_ = 0;
  bool failed_ = false;
};

// AV1 leb128() at |data|; returns bytes used, 0 if malformed.
size_t ReadLeb128(const uint8_t* data, size_t size, uint64_t* value) {
  *value = 0;
  for (size_t i = 0; i < 8 && i < size; ++i) {
    *value |= static_cast<uint64_t>(data[i] & 0x7f) << (7 * i);
    if (!(data[i] & 0x80)) {
      return i + 1;
    }
  }
  return 0;
}

}  // namespace

bool ConvertAnnexBToLengthPrefixed(const uint8_t* data,
                                   size_t size,
                                   std::vector<SubsampleEntry>* subsamples,
                                   std::vector<uint8_t>* output) {
  output->clear();
  if (!data || size < 4) {
    return false;
  }

  // Clear ranges in input coordinates. A null |subsamples| is a clear sample.
  struct Range {
    size_t begin;
    size_t end;
  };
  std::vector<Range> clear_ranges;
  if (!subsamples) {
    clear_ranges.push_back({0, size});
  } else {
    if (subsamples->empty()) {
      return false;  // Whole-sample encryption can't be NAL-parsed.
    }
    size_t offset = 0;
    for (const SubsampleEntry& entry : *subsamples) {
      clear_ranges.push_back({offset, offset + entry.clear_bytes});
      offset += static_cast<size_t>(entry.clear_bytes) + entry.cypher_bytes;
    }
    if (offset != size) {
      return false;
    }
  }

  std::vector<StartCode> start_codes;
  for (size_t index = 0; index < clear_ranges.size(); ++index) {
    const Range& range = clear_ranges[index];
    size_t i = range.begin;
    while (i + 3 <= range.end) {
      if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
        size_t begin = i;
        while (begin > range.begin && data[begin - 1] == 0) {
          --begin;
        }
        start_codes.push_back({begin, i + 3, index});
        i += 3;
      } else {
        ++i;
      }
    }
  }
  if (start_codes.empty()) {
    return false;
  }
  // Nothing but zero bytes may precede the first start code; they are part of
  // it because the leading-zero scan above stops only at a range boundary.
  if (start_codes.front().begin != 0) {
    return false;
  }

  std::vector<int64_t> delta(subsamples ? subsamples->size() : 0, 0);
  output->reserve(size + 4 * start_codes.size());
  for (size_t n = 0; n < start_codes.size(); ++n) {
    const StartCode& code = start_codes[n];
    size_t end = n + 1 < start_codes.size() ? start_codes[n + 1].begin : size;
    if (end <= code.payload) {
      return false;  // Empty NAL unit.
    }
    size_t nal_size = end - code.payload;
    if (nal_size > 0xffffffffu) {
      return false;
    }
    AppendBE32(output, static_cast<uint32_t>(nal_size));
    output->insert(output->end(), data + code.payload, data + end);
    if (subsamples) {
      delta[code.subsample] += 4 - static_cast<int64_t>(code.payload - code.begin);
    }
  }
  if (subsamples) {
    for (size_t index = 0; index < subsamples->size(); ++index) {
      int64_t clear = static_cast<int64_t>((*subsamples)[index].clear_bytes) + delta[index];
      if (clear < 0 || clear > 0xffffffffLL) {
        return false;
      }
      (*subsamples)[index].clear_bytes = static_cast<uint32_t>(clear);
    }
  }
  return true;
}

size_t AdtsHeaderSize(const uint8_t* data, size_t size) {
  if (!data || size < 7 || data[0] != 0xff || (data[1] & 0xf6) != 0xf0) {
    return 0;
  }
  size_t header = (data[1] & 0x01) ? 7 : 9;
  size_t frame_length = (static_cast<size_t>(data[3] & 0x03) << 11) |
                        (static_cast<size_t>(data[4]) << 3) |
                        (static_cast<size_t>(data[5]) >> 5);
  if (frame_length < header || frame_length > size) {
    return 0;
  }
  return header;
}

bool RemoveLeadingClearBytes(size_t header_size,
                             size_t payload_size,
                             std::vector<SubsampleEntry>* subsamples) {
  if (subsamples->empty()) {
    return header_size == 0;
  }
  SubsampleEntry& first = subsamples->front();
  if (first.clear_bytes < header_size) {
    return false;
  }
  first.clear_bytes -= static_cast<uint32_t>(header_size);
  if (subsamples->size() == 1 && first.clear_bytes == 0 &&
      first.cypher_bytes == payload_size) {
    subsamples->clear();
  }
  return true;
}

std::vector<uint8_t> SubsampleAuxiliaryData(
    const std::vector<SubsampleEntry>& subsamples) {
  std::vector<uint8_t> out(subsamples.size() * 2 * sizeof(uint32_t));
  uint8_t* cursor = out.data();
  for (const SubsampleEntry& entry : subsamples) {
    std::memcpy(cursor, &entry.clear_bytes, sizeof(uint32_t));
    cursor += sizeof(uint32_t);
    std::memcpy(cursor, &entry.cypher_bytes, sizeof(uint32_t));
    cursor += sizeof(uint32_t);
  }
  return out;
}

std::vector<uint8_t> TrackEncryptionBoxPayload(const TrackEncryption& tenc) {
  const bool protected_track = tenc.scheme != EncryptionScheme::kUnencrypted;
  const uint8_t version = tenc.scheme == EncryptionScheme::kCbcs ? 1 : 0;
  std::vector<uint8_t> out{version, 0, 0, 0, 0};
  out.push_back(version ? static_cast<uint8_t>((tenc.default_pattern.crypt_byte_block << 4) |
                                               (tenc.default_pattern.skip_byte_block & 0x0f))
                        : 0);
  out.push_back(protected_track ? 1 : 0);
  out.push_back(tenc.default_per_sample_iv_size);
  for (size_t i = 0; i < 16; ++i) {
    out.push_back(i < tenc.default_key_id.size() ? tenc.default_key_id[i] : 0);
  }
  if (protected_track && tenc.default_per_sample_iv_size == 0) {
    out.push_back(static_cast<uint8_t>(tenc.default_constant_iv.size()));
    Append(&out, tenc.default_constant_iv);
  }
  return out;
}

std::vector<uint8_t> MakeBox(uint32_t type, const std::vector<uint8_t>& payload) {
  std::vector<uint8_t> out;
  out.reserve(8 + payload.size());
  AppendBE32(&out, static_cast<uint32_t>(8 + payload.size()));
  AppendBE32(&out, type);
  Append(&out, payload);
  return out;
}

std::vector<uint8_t> ProtectionSchemeInfoPayload(uint32_t original_format,
                                                 const TrackEncryption& tenc) {
  std::vector<uint8_t> frma;
  AppendBE32(&frma, original_format);
  std::vector<uint8_t> schm{0, 0, 0, 0};
  AppendBE32(&schm, tenc.scheme == EncryptionScheme::kCenc ? FourCC('c', 'e', 'n', 'c')
                                                           : FourCC('c', 'b', 'c', 's'));
  AppendBE32(&schm, 0x00010000);
  std::vector<uint8_t> out = MakeBox(FourCC('f', 'r', 'm', 'a'), frma);
  Append(&out, MakeBox(FourCC('s', 'c', 'h', 'm'), schm));
  Append(&out, MakeBox(FourCC('s', 'c', 'h', 'i'),
                       MakeBox(FourCC('t', 'e', 'n', 'c'), TrackEncryptionBoxPayload(tenc))));
  return out;
}

std::vector<uint8_t> AacEsdsPayload(const std::vector<uint8_t>& audio_specific_config) {
  // DecoderConfigDescriptor: MPEG-4 audio (0x40), audio stream (5 << 2 |
  // reserved 1), zero buffer size and bitrates, then DecoderSpecificInfo.
  std::vector<uint8_t> decoder_config{0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  Append(&decoder_config, Descriptor(0x05, audio_specific_config));
  std::vector<uint8_t> es{0, 0, 0};  // ES_ID 0, no stream dependence/URL/OCR.
  Append(&es, Descriptor(0x04, decoder_config));
  Append(&es, Descriptor(0x06, {0x02}));  // SLConfigDescriptor, predefined MP4.
  std::vector<uint8_t> out{0, 0, 0, 0};  // version, flags
  Append(&out, Descriptor(0x03, es));
  return out;
}

std::vector<uint8_t> VisualSampleEntry(uint32_t type,
                                       uint16_t width,
                                       uint16_t height,
                                       const std::vector<std::vector<uint8_t>>& children) {
  std::vector<uint8_t> payload(6, 0);                 // reserved
  payload.insert(payload.end(), {0, 1});              // data_reference_index
  payload.insert(payload.end(), 16, 0);               // pre_defined, reserved
  payload.push_back(static_cast<uint8_t>(width >> 8));
  payload.push_back(static_cast<uint8_t>(width));
  payload.push_back(static_cast<uint8_t>(height >> 8));
  payload.push_back(static_cast<uint8_t>(height));
  AppendBE32(&payload, 0x00480000);                   // horizresolution, 72 dpi
  AppendBE32(&payload, 0x00480000);                   // vertresolution
  AppendBE32(&payload, 0);                            // reserved
  payload.insert(payload.end(), {0, 1});              // frame_count
  payload.insert(payload.end(), 32, 0);               // compressorname
  payload.insert(payload.end(), {0x00, 0x18, 0xff, 0xff});  // depth, pre_defined -1
  for (const auto& child : children) {
    Append(&payload, child);
  }
  return MakeBox(type, payload);
}

std::vector<uint8_t> AudioSampleEntry(uint32_t type,
                                      uint16_t channels,
                                      uint32_t sample_rate,
                                      const std::vector<std::vector<uint8_t>>& children) {
  std::vector<uint8_t> payload(6, 0);                 // reserved
  payload.insert(payload.end(), {0, 1});              // data_reference_index
  payload.insert(payload.end(), 8, 0);                // reserved
  payload.push_back(static_cast<uint8_t>(channels >> 8));
  payload.push_back(static_cast<uint8_t>(channels));
  payload.insert(payload.end(), {0, 16, 0, 0, 0, 0});  // samplesize, pre_defined, reserved
  AppendBE32(&payload, sample_rate <= 0xffff ? sample_rate << 16 : 0);
  for (const auto& child : children) {
    Append(&payload, child);
  }
  return MakeBox(type, payload);
}

std::vector<uint8_t> ProtectSampleEntry(const std::vector<uint8_t>& entry,
                                        bool video,
                                        const TrackEncryption& tenc) {
  if (entry.size() < 8) {
    return {};
  }
  uint32_t original = (static_cast<uint32_t>(entry[4]) << 24) | (static_cast<uint32_t>(entry[5]) << 16) |
                      (static_cast<uint32_t>(entry[6]) << 8) | entry[7];
  std::vector<uint8_t> out = entry;
  Append(&out, MakeBox(FourCC('s', 'i', 'n', 'f'), ProtectionSchemeInfoPayload(original, tenc)));
  uint32_t size = static_cast<uint32_t>(out.size());
  out[0] = static_cast<uint8_t>(size >> 24);
  out[1] = static_cast<uint8_t>(size >> 16);
  out[2] = static_cast<uint8_t>(size >> 8);
  out[3] = static_cast<uint8_t>(size);
  const char* type = video ? "encv" : "enca";
  std::copy(type, type + 4, out.begin() + 4);
  return out;
}

std::optional<std::vector<uint8_t>> Av1SequenceHeaderObu(const uint8_t* data, size_t size) {
  constexpr int kObuSequenceHeader = 1;
  size_t pos = 0;
  while (pos < size) {
    const uint8_t header = data[pos];
    const int type = (header >> 3) & 0x0f;
    const bool extension = header & 0x04;
    const bool has_size = header & 0x02;
    const size_t header_size = 1 + (extension ? 1 : 0);
    if (pos + header_size > size) {
      return std::nullopt;
    }
    uint64_t obu_size = size - pos - header_size;
    size_t leb_size = 0;
    if (has_size) {
      leb_size = ReadLeb128(data + pos + header_size, size - pos - header_size, &obu_size);
      if (!leb_size) {
        return std::nullopt;
      }
    }
    const size_t payload = pos + header_size + leb_size;
    if (obu_size > size - payload) {
      return std::nullopt;
    }
    if (type == kObuSequenceHeader) {
      std::vector<uint8_t> obu(data + pos, data + pos + header_size);
      obu[0] |= 0x02;  // obu_has_size_field
      uint64_t remaining = obu_size;
      do {
        uint8_t byte = remaining & 0x7f;
        remaining >>= 7;
        obu.push_back(static_cast<uint8_t>(byte | (remaining ? 0x80 : 0)));
      } while (remaining);
      obu.insert(obu.end(), data + payload, data + payload + obu_size);
      return obu;
    }
    pos = payload + static_cast<size_t>(obu_size);
  }
  return std::nullopt;
}

std::optional<std::vector<uint8_t>> Av1CodecConfigurationRecord(
    const std::vector<uint8_t>& sequence_header_obu) {
  if (sequence_header_obu.size() < 3) {
    return std::nullopt;
  }
  const bool extension = sequence_header_obu[0] & 0x04;
  size_t header = 1 + (extension ? 1 : 0);
  uint64_t obu_size = 0;
  size_t leb = ReadLeb128(sequence_header_obu.data() + header, sequence_header_obu.size() - header, &obu_size);
  if (!leb || obu_size > sequence_header_obu.size() - header - leb) {
    return std::nullopt;
  }
  BitReader r(sequence_header_obu.data() + header + leb, static_cast<size_t>(obu_size));
  // sequence_header_obu() (AV1 spec 5.5), as far as color_config().
  const int seq_profile = static_cast<int>(r.Get(3));
  r.Get(1);  // still_picture
  const bool reduced_still_picture_header = r.Get(1);
  int seq_level_idx_0 = 0;
  int seq_tier_0 = 0;
  if (reduced_still_picture_header) {
    seq_level_idx_0 = static_cast<int>(r.Get(5));
  } else {
    bool decoder_model_info_present = false;
    int buffer_delay_length = 0;
    if (r.Get(1)) {  // timing_info_present_flag
      r.Get(32);     // num_units_in_display_tick
      r.Get(32);     // time_scale
      if (r.Get(1)) r.Uvlc();  // equal_picture_interval, num_ticks_per_picture_minus_1
      decoder_model_info_present = r.Get(1);
      if (decoder_model_info_present) {
        buffer_delay_length = static_cast<int>(r.Get(5)) + 1;
        r.Get(32);  // num_units_in_decoding_tick
        r.Get(5);   // buffer_removal_time_length_minus_1
        r.Get(5);   // frame_presentation_time_length_minus_1
      }
    }
    const bool initial_display_delay_present = r.Get(1);
    const int operating_points = static_cast<int>(r.Get(5)) + 1;
    for (int i = 0; i < operating_points && !r.failed(); ++i) {
      r.Get(12);  // operating_point_idc
      int level = static_cast<int>(r.Get(5));
      int tier = level > 7 ? static_cast<int>(r.Get(1)) : 0;
      if (i == 0) {
        seq_level_idx_0 = level;
        seq_tier_0 = tier;
      }
      if (decoder_model_info_present && r.Get(1)) {
        r.Get(buffer_delay_length);  // decoder_buffer_delay
        r.Get(buffer_delay_length);  // encoder_buffer_delay
        r.Get(1);                    // low_delay_mode_flag
      }
      if (initial_display_delay_present && r.Get(1)) {
        r.Get(4);  // initial_display_delay_minus_1
      }
    }
  }
  const int width_bits = static_cast<int>(r.Get(4)) + 1;
  const int height_bits = static_cast<int>(r.Get(4)) + 1;
  r.Get(width_bits);
  r.Get(height_bits);
  if (!reduced_still_picture_header && r.Get(1)) {  // frame_id_numbers_present_flag
    r.Get(4);
    r.Get(3);
  }
  r.Get(1);  // use_128x128_superblock
  r.Get(1);  // enable_filter_intra
  r.Get(1);  // enable_intra_edge_filter
  if (!reduced_still_picture_header) {
    r.Get(1);  // enable_interintra_compound
    r.Get(1);  // enable_masked_compound
    r.Get(1);  // enable_warped_motion
    r.Get(1);  // enable_dual_filter
    const bool enable_order_hint = r.Get(1);
    if (enable_order_hint) {
      r.Get(1);  // enable_jnt_comp
      r.Get(1);  // enable_ref_frame_mvs
    }
    int force_screen_content_tools = 2;  // SELECT_SCREEN_CONTENT_TOOLS
    if (!r.Get(1)) {                     // seq_choose_screen_content_tools
      force_screen_content_tools = static_cast<int>(r.Get(1));
    }
    if (force_screen_content_tools > 0 && !r.Get(1)) {  // seq_choose_integer_mv
      r.Get(1);                                          // seq_force_integer_mv
    }
    if (enable_order_hint) {
      r.Get(3);  // order_hint_bits_minus_1
    }
  }
  r.Get(1);  // enable_superres
  r.Get(1);  // enable_cdef
  r.Get(1);  // enable_restoration
  // color_config()
  const int high_bitdepth = static_cast<int>(r.Get(1));
  int twelve_bit = 0;
  if (seq_profile == 2 && high_bitdepth) {
    twelve_bit = static_cast<int>(r.Get(1));
  }
  const int monochrome = seq_profile == 1 ? 0 : static_cast<int>(r.Get(1));
  int color_primaries = 2, transfer = 2, matrix = 2;
  if (r.Get(1)) {  // color_description_present_flag
    color_primaries = static_cast<int>(r.Get(8));
    transfer = static_cast<int>(r.Get(8));
    matrix = static_cast<int>(r.Get(8));
  }
  int subsampling_x = 1, subsampling_y = 1, chroma_sample_position = 0;
  if (monochrome) {
    r.Get(1);  // color_range
  } else if (color_primaries == 1 && transfer == 13 && matrix == 0) {
    subsampling_x = subsampling_y = 0;  // sRGB, 4:4:4
  } else {
    r.Get(1);  // color_range
    if (seq_profile == 0) {
      subsampling_x = subsampling_y = 1;
    } else if (seq_profile == 1) {
      subsampling_x = subsampling_y = 0;
    } else if (twelve_bit) {
      subsampling_x = static_cast<int>(r.Get(1));
      subsampling_y = subsampling_x ? static_cast<int>(r.Get(1)) : 0;
    } else {
      subsampling_x = 1;
      subsampling_y = 0;
    }
    if (subsampling_x && subsampling_y) {
      chroma_sample_position = static_cast<int>(r.Get(2));
    }
  }
  if (r.failed()) {
    return std::nullopt;
  }
  std::vector<uint8_t> record{
      0x81,  // marker, version 1
      static_cast<uint8_t>((seq_profile << 5) | (seq_level_idx_0 & 0x1f)),
      static_cast<uint8_t>((seq_tier_0 << 7) | (high_bitdepth << 6) | (twelve_bit << 5) | (monochrome << 4) |
                           (subsampling_x << 3) | (subsampling_y << 2) | (chroma_sample_position & 3)),
      0x00,  // no initial_presentation_delay
  };
  Append(&record, sequence_header_obu);
  return record;
}

std::vector<uint8_t> DolbyVisionConfigurationRecord(int profile, int level, int compatibility_id) {
  std::vector<uint8_t> record(24, 0);
  record[0] = 1;  // dv_version_major
  record[1] = 0;  // dv_version_minor
  const uint16_t fields = static_cast<uint16_t>(((profile & 0x7f) << 9) | ((level & 0x3f) << 3) |
                                                (1 << 2) |  // rpu_present
                                                (0 << 1) |  // el_present
                                                1);         // bl_present
  record[2] = static_cast<uint8_t>(fields >> 8);
  record[3] = static_cast<uint8_t>(fields);
  record[4] = static_cast<uint8_t>((compatibility_id & 0x0f) << 4);
  return record;
}

namespace {

std::vector<uint8_t> Dac3(int fscod, int bsid, int bsmod, int acmod, int lfeon, int bit_rate_code) {
  const uint32_t bits = (uint32_t(fscod) << 22) | (uint32_t(bsid) << 17) | (uint32_t(bsmod) << 14) |
                        (uint32_t(acmod) << 11) | (uint32_t(lfeon) << 10) | (uint32_t(bit_rate_code) << 5);
  return {static_cast<uint8_t>(bits >> 16), static_cast<uint8_t>(bits >> 8), static_cast<uint8_t>(bits)};
}

// Whether bytes [offset, offset + length) of a sample are clear. A null
// layout means a clear sample; an empty one, a wholly protected sample.
bool IsClear(const std::vector<SubsampleEntry>* subsamples, size_t offset, size_t length) {
  if (!subsamples) {
    return true;
  }
  size_t pos = 0;
  for (const SubsampleEntry& entry : *subsamples) {
    if (offset < pos) {
      return false;
    }
    const size_t clear_end = pos + entry.clear_bytes;
    if (offset + length <= clear_end) {
      return true;
    }
    pos = clear_end + entry.cypher_bytes;
  }
  return false;
}

// fscod for 48/44.1/32 kHz, -1 otherwise.
int FscodFor(int sample_rate) {
  return sample_rate == 48000 ? 0 : sample_rate == 44100 ? 1 : sample_rate == 32000 ? 2 : -1;
}

// acmod/lfeon for a channel count: 1 1/0, 2 2/0, 3 3/0, 4 2/2, 5 3/2, and
// 6, 7 or 8 as 3/2+LFE (for 6.1 and 7.1 that is the independent substream's
// 5.1 core; the extra channels ride in a dependent substream the config
// can't describe).
bool LayoutFor(int channels, int* acmod, int* lfeon) {
  static const int kAcmod[9] = {-1, 1, 2, 3, 6, 7, 7, 7, 7};
  if (channels < 1 || channels > 8) return false;
  *acmod = kAcmod[channels];
  *lfeon = channels >= 6;
  return true;
}

}  // namespace

std::optional<std::vector<uint8_t>> Ac3SpecificBoxPayload(const uint8_t* data, size_t size,
                                                          const std::vector<SubsampleEntry>* subsamples) {
  // Syncword, crc1 and the BSI fields read below fit in 8 bytes.
  if (size < 8 || !IsClear(subsamples, 0, 8) || data[0] != 0x0b || data[1] != 0x77) {
    return std::nullopt;
  }
  BitReader r(data + 4, size - 4);  // after syncword and crc1
  const int fscod = static_cast<int>(r.Get(2));
  const int frmsizecod = static_cast<int>(r.Get(6));
  const int bsid = static_cast<int>(r.Get(5));
  const int bsmod = static_cast<int>(r.Get(3));
  const int acmod = static_cast<int>(r.Get(3));
  if ((acmod & 1) && acmod != 1) r.Get(2);  // cmixlev
  if (acmod & 4) r.Get(2);                  // surmixlev
  if (acmod == 2) r.Get(2);                 // dsurmod
  const int lfeon = static_cast<int>(r.Get(1));
  if (r.failed() || fscod == 3 || bsid > 8 || frmsizecod > 37) {
    return std::nullopt;
  }
  return Dac3(fscod, bsid, bsmod, acmod, lfeon, frmsizecod >> 1);
}

std::optional<std::vector<uint8_t>> Ac3SpecificBoxFromConfig(int sample_rate, int channels) {
  int acmod = 0, lfeon = 0;
  const int fscod = FscodFor(sample_rate);
  if (fscod < 0 || !LayoutFor(channels, &acmod, &lfeon)) {
    return std::nullopt;
  }
  return Dac3(fscod, 8, 0, acmod, lfeon, 0);
}

int DefaultDolbyVisionCompatibilityId(int profile) {
  return profile == 8 ? 1 : profile == 9 ? 2 : 0;
}

namespace {

struct Eac3Substream {
  int fscod = 0, bsid = 0, acmod = 0, lfeon = 0, dependents = 0, chan_loc = 0;
};

std::vector<uint8_t> Dec3(uint64_t data_rate_kbps, const std::vector<Eac3Substream>& independent) {
  std::vector<uint8_t> out;
  uint64_t accumulator = 0;
  int count = 0;
  auto put = [&](uint64_t value, int bits) {
    for (int i = bits - 1; i >= 0; --i) {
      accumulator = (accumulator << 1) | ((value >> i) & 1);
      if (++count == 8) {
        out.push_back(static_cast<uint8_t>(accumulator));
        accumulator = 0;
        count = 0;
      }
    }
  };
  put(std::min<uint64_t>(data_rate_kbps, 0x1fff), 13);  // data_rate
  put(independent.size() - 1, 3);                         // num_ind_sub
  for (const Eac3Substream& sub : independent) {
    put(sub.fscod, 2);
    put(sub.bsid, 5);
    put(0, 1);  // reserved
    put(0, 1);  // asvc
    put(0, 3);  // bsmod
    put(sub.acmod, 3);
    put(sub.lfeon, 1);
    put(0, 3);  // reserved
    put(sub.dependents, 4);
    if (sub.dependents) {
      put(sub.chan_loc & 0x1ff, 9);
    } else {
      put(0, 1);  // reserved
    }
  }
  return out;
}

}  // namespace

std::optional<std::vector<uint8_t>> Eac3SpecificBoxPayload(const uint8_t* data, size_t size,
                                                           const std::vector<SubsampleEntry>* subsamples) {
  std::vector<Eac3Substream> independent;
  std::vector<int> independent_ids;
  std::vector<std::pair<int, int>> dependent_ids;  // (parent index, substreamid)
  std::vector<std::pair<int, int>> rated;           // (strmtyp class, substreamid) counted once
  int current = -1;  // Index in |independent| of the latest independent syncframe.
  uint64_t bits_per_second = 0;
  size_t pos = 0;
  while (pos + 6 <= size) {
    // The header fields read below (through chanmap) fit in 12 bytes.
    if (!IsClear(subsamples, pos, std::min<size_t>(12, size - pos)) || data[pos] != 0x0b || data[pos + 1] != 0x77) {
      break;
    }
    BitReader r(data + pos + 2, size - pos - 2);
    const int strmtyp = static_cast<int>(r.Get(2));
    const int substreamid = static_cast<int>(r.Get(3));
    const size_t frame_bytes = (static_cast<size_t>(r.Get(11)) + 1) * 2;
    const int fscod = static_cast<int>(r.Get(2));
    int blocks = 6;
    int sample_rate = 0;
    if (fscod == 3) {
      const int fscod2 = static_cast<int>(r.Get(2));
      sample_rate = fscod2 == 0 ? 24000 : fscod2 == 1 ? 22050 : fscod2 == 2 ? 16000 : 0;
    } else {
      static const int kBlocks[4] = {1, 2, 3, 6};
      blocks = kBlocks[r.Get(2)];
      sample_rate = fscod == 0 ? 48000 : fscod == 1 ? 44100 : 32000;
    }
    const int acmod = static_cast<int>(r.Get(3));
    const int lfeon = static_cast<int>(r.Get(1));
    const int bsid = static_cast<int>(r.Get(5));
    r.Get(5);                  // dialnorm
    if (r.Get(1)) r.Get(8);    // compre, compr
    if (acmod == 0) {
      r.Get(5);                // dialnorm2
      if (r.Get(1)) r.Get(8);  // compr2e, compr2
    }
    int chanmap = 0;
    if (strmtyp == 1 && r.Get(1)) {  // chanmape
      chanmap = static_cast<int>(r.Get(16));
    }
    if (r.failed() || !sample_rate || bsid <= 10 || bsid > 16 || frame_bytes > size - pos || strmtyp == 3) {
      return std::nullopt;
    }
    // A dependent substream belongs to the independent substream of the
    // latest independent syncframe (frames of several programs interleave).
    const int kind = strmtyp == 1 ? 1 : 0;
    if (kind == 0) {
      auto it = std::find(independent_ids.begin(), independent_ids.end(), substreamid);
      if (it == independent_ids.end()) {
        independent_ids.push_back(substreamid);
        independent.push_back({fscod == 3 ? 3 : fscod, bsid, acmod, lfeon, 0, 0});
        current = static_cast<int>(independent.size()) - 1;
      } else {
        current = static_cast<int>(it - independent_ids.begin());
      }
    }
    // A substream's rate counts once, however many syncframes (1, 2 or 3
    // blocks each) make up its six blocks in this access unit.
    const std::pair<int, int> rate_key{kind == 1 ? 100 + current : 0, substreamid};
    if (std::find(rated.begin(), rated.end(), rate_key) == rated.end()) {
      rated.push_back(rate_key);
      bits_per_second += uint64_t(frame_bytes) * 8 * uint64_t(sample_rate) / (uint64_t(blocks) * 256);
    }
    if (kind == 1 && current >= 0) {
      const std::pair<int, int> dependent{current, substreamid};
      if (std::find(dependent_ids.begin(), dependent_ids.end(), dependent) == dependent_ids.end()) {
        dependent_ids.push_back(dependent);
        ++independent[current].dependents;
      }
      // chanmap numbers its locations from the MSB (bit 0 = L); dec3's
      // chan_loc numbers them from the LSB: bit k is chanmap location 5 + k
      // (Lc/Rc, Lrs/Rrs, Cs, Ts, Lsd/Rsd, Lw/Rw, Lvh/Rvh, Cvh) and bit 8 is
      // location 14 (LFE2). Dolby's muxer writes Lrs/Rrs as 0x002 (checked
      // against DASH-IF's 7.1 channel-ID stream).
      int chan_loc = (chanmap >> 1) & 1 ? 0x100 : 0;
      for (int k = 0; k < 8; ++k) {
        chan_loc |= ((chanmap >> (10 - k)) & 1) << k;
      }
      independent[current].chan_loc |= chan_loc;
    }
    pos += frame_bytes;
  }
  if (independent.empty() || independent.size() > 8) {
    return std::nullopt;
  }
  return Dec3(bits_per_second / 1000, independent);
}

std::optional<std::vector<uint8_t>> Eac3SpecificBoxFromConfig(int sample_rate, int channels) {
  int acmod = 0, lfeon = 0;
  const int fscod = FscodFor(sample_rate);
  if (fscod < 0 || !LayoutFor(channels, &acmod, &lfeon)) {
    return std::nullopt;
  }
  return Dec3(0, {{fscod, 16, acmod, lfeon, 0, 0}});
}

std::optional<uint32_t> ParameterSetId(bool hevc, const uint8_t* nal, size_t size) {
  const size_t header = hevc ? 2 : 1;
  if (size <= header) {
    return std::nullopt;
  }
  const int type = hevc ? (nal[0] >> 1) & 0x3f : nal[0] & 0x1f;
  // An HEVC SPS ID follows profile_tier_level, at most ~100 bytes in.
  std::vector<uint8_t> rbsp;
  int zeros = 0;
  for (size_t i = header; i < size && rbsp.size() < 128; ++i) {
    if (zeros >= 2 && nal[i] == 0x03) {
      zeros = 0;
      continue;
    }
    zeros = nal[i] == 0 ? zeros + 1 : 0;
    rbsp.push_back(nal[i]);
  }
  BitReader r(rbsp.data(), rbsp.size());
  uint64_t id = 0;
  uint64_t max_id = 0;
  if (!hevc && type == 7) {
    r.Get(24);  // profile_idc, constraint flags, level_idc
    id = r.Uvlc();
    max_id = 31;
  } else if (!hevc && type == 8) {
    id = r.Uvlc();
    max_id = 255;
  } else if (hevc && type == 32) {
    id = r.Get(4);
    max_id = 15;
  } else if (hevc && type == 33) {
    r.Get(4);  // sps_video_parameter_set_id
    const int sub_layers = static_cast<int>(r.Get(3));
    r.Get(1);       // sps_temporal_id_nesting_flag
    r.Get(88 + 8);  // general profile, tier and level
    bool profile_present[8] = {}, level_present[8] = {};
    for (int i = 0; i < sub_layers; ++i) {
      profile_present[i] = r.Get(1);
      level_present[i] = r.Get(1);
    }
    if (sub_layers > 0) {
      r.Get(2 * (8 - sub_layers));  // reserved_zero_2bits
    }
    for (int i = 0; i < sub_layers; ++i) {
      if (profile_present[i]) r.Get(88);
      if (level_present[i]) r.Get(8);
    }
    id = r.Uvlc();
    max_id = 15;
  } else if (hevc && type == 34) {
    id = r.Uvlc();
    max_id = 63;
  } else {
    return std::nullopt;
  }
  if (r.failed() || id > max_id) {
    return std::nullopt;
  }
  return static_cast<uint32_t>(id);
}

}  // namespace parc::fairplay
