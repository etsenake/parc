#include "fairplay_bitstream.h"

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

std::vector<uint8_t> AacMagicCookie(const std::vector<uint8_t>& audio_specific_config) {
  // DecoderConfigDescriptor: AAC (0x40), audio stream (5 << 2 | reserved 1),
  // zero buffer size and bitrates, then DecoderSpecificInfo.
  std::vector<uint8_t> decoder_config{0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  Append(&decoder_config, Descriptor(0x05, audio_specific_config));
  std::vector<uint8_t> es{0, 0, 0};  // ES_ID 0, no stream dependence/URL/OCR.
  Append(&es, Descriptor(0x04, decoder_config));
  Append(&es, Descriptor(0x06, {0x02}));  // SLConfigDescriptor, predefined MP4.
  std::vector<uint8_t> es_descriptor = Descriptor(0x03, es);
  return MakeBox(FourCC('e', 's', 'd', 's'), es_descriptor);
}

}  // namespace parc::fairplay
