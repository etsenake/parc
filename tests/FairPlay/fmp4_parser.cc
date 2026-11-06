#include "fmp4_parser.h"

#include <algorithm>
#include <cstdio>
#include <functional>

#include "fairplay_bitstream.h"

namespace parc::fairplay::test {
namespace {

uint32_t Be16(const uint8_t* p) { return (uint32_t(p[0]) << 8) | p[1]; }
uint32_t Be32(const uint8_t* p) {
  return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | p[3];
}
uint64_t Be64(const uint8_t* p) { return (uint64_t(Be32(p)) << 32) | Be32(p + 4); }

struct Box {
  uint32_t type = 0;
  const uint8_t* start = nullptr;    // Box header.
  const uint8_t* payload = nullptr;
  size_t payload_size = 0;
  size_t size = 0;
};

// Calls |visit| for each box in [data, data + size); false if malformed.
bool Boxes(const uint8_t* data, size_t size, const std::function<bool(const Box&)>& visit) {
  size_t offset = 0;
  while (offset + 8 <= size) {
    uint64_t box_size = Be32(data + offset);
    size_t header = 8;
    if (box_size == 1) {
      if (offset + 16 > size) return false;
      box_size = Be64(data + offset + 8);
      header = 16;
    } else if (box_size == 0) {
      box_size = size - offset;
    }
    if (box_size < header || box_size > size - offset) return false;
    Box box{Be32(data + offset + 4), data + offset, data + offset + header,
            size_t(box_size) - header, size_t(box_size)};
    if (!visit(box)) return false;
    offset += size_t(box_size);
  }
  return offset == size;
}

const std::vector<uint32_t> kContainers = {FourCC('m', 'o', 'o', 'v'), FourCC('t', 'r', 'a', 'k'),
                                           FourCC('m', 'd', 'i', 'a'), FourCC('m', 'i', 'n', 'f'),
                                           FourCC('s', 't', 'b', 'l'), FourCC('e', 'd', 't', 's'),
                                           FourCC('m', 'v', 'e', 'x'), FourCC('s', 'i', 'n', 'f'),
                                           FourCC('s', 'c', 'h', 'i')};

bool IsContainer(uint32_t type) {
  for (uint32_t c : kContainers) {
    if (c == type) return true;
  }
  return false;
}

void ParseTenc(const Box& box, TrackEncryption* tenc) {
  const uint8_t* p = box.payload;
  if (box.payload_size < 24) return;
  uint8_t version = p[0];
  if (version >= 1) {
    tenc->default_pattern.crypt_byte_block = p[5] >> 4;
    tenc->default_pattern.skip_byte_block = p[5] & 0x0f;
  }
  bool is_protected = p[6] != 0;
  tenc->default_per_sample_iv_size = p[7];
  tenc->default_key_id.assign(p + 8, p + 24);
  if (is_protected && tenc->default_per_sample_iv_size == 0 && box.payload_size >= 25) {
    uint8_t size = p[24];
    if (box.payload_size >= 25u + size) tenc->default_constant_iv.assign(p + 25, p + 25 + size);
  }
}

std::vector<SeigEntry> ParseSgpdSeig(const Box& box) {
  std::vector<SeigEntry> entries;
  const uint8_t* p = box.payload;
  size_t n = box.payload_size;
  if (n < 12 || Be32(p + 4) != FourCC('s', 'e', 'i', 'g')) return entries;
  uint8_t version = p[0];
  size_t pos = 8;
  uint32_t default_length = 0;
  if (version == 1) {
    default_length = Be32(p + pos);
    pos += 4;
  } else if (version >= 2) {
    pos += 4;  // default_sample_description_index
  }
  if (pos + 4 > n) return entries;
  uint32_t count = Be32(p + pos);
  pos += 4;
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t length = default_length;
    if (version == 1 && default_length == 0) {
      if (pos + 4 > n) break;
      length = Be32(p + pos);
      pos += 4;
    }
    if (pos + 20 > n) break;
    SeigEntry entry;
    entry.pattern.crypt_byte_block = p[pos + 1] >> 4;
    entry.pattern.skip_byte_block = p[pos + 1] & 0x0f;
    entry.is_protected = p[pos + 2] != 0;
    entry.per_sample_iv_size = p[pos + 3];
    entry.key_id.assign(p + pos + 4, p + pos + 20);
    size_t used = 20;
    if (entry.is_protected && entry.per_sample_iv_size == 0 && pos + 21 <= n) {
      uint8_t size = p[pos + 20];
      if (pos + 21 + size <= n) entry.constant_iv.assign(p + pos + 21, p + pos + 21 + size);
      used += 1 + size;
    }
    entries.push_back(entry);
    pos += length ? length : used;
  }
  return entries;
}

std::vector<uint8_t> AscFromEsds(const uint8_t* p, size_t n) {
  // Skip version/flags, then walk descriptors to DecoderSpecificInfo (5).
  size_t pos = 4;
  auto read_descriptor = [&](uint8_t* tag, size_t* length) {
    if (pos + 2 > n) return false;
    *tag = p[pos++];
    *length = 0;
    for (int i = 0; i < 4 && pos < n; ++i) {
      uint8_t b = p[pos++];
      *length = (*length << 7) | (b & 0x7f);
      if (!(b & 0x80)) break;
    }
    return true;
  };
  uint8_t tag = 0;
  size_t length = 0;
  if (!read_descriptor(&tag, &length) || tag != 3) return {};
  pos += 2;  // ES_ID
  uint8_t flags = p[pos++];
  if (flags & 0x80) pos += 2;
  if (flags & 0x40) pos += 1 + p[pos];
  if (flags & 0x20) pos += 2;
  if (!read_descriptor(&tag, &length) || tag != 4) return {};
  pos += 13;
  if (!read_descriptor(&tag, &length) || tag != 5 || pos + length > n) return {};
  return std::vector<uint8_t>(p + pos, p + pos + length);
}

}  // namespace

std::string FourCCString(uint32_t v) {
  char s[5] = {char(v >> 24), char(v >> 16), char(v >> 8), char(v), 0};
  return s;
}

std::string Hex(const std::vector<uint8_t>& bytes) {
  std::string out;
  char buf[3];
  for (uint8_t b : bytes) {
    snprintf(buf, sizeof(buf), "%02x", b);
    out += buf;
  }
  return out;
}

bool ParseInitSegment(const std::vector<uint8_t>& data, TrackInfo* track, std::string* error) {
  bool ok = true;
  std::function<bool(const Box&)> visit = [&](const Box& box) -> bool {
    const uint8_t* p = box.payload;
    size_t n = box.payload_size;
    switch (box.type) {
      case FourCC('t', 'k', 'h', 'd'):
        if (n >= 24) track->track_id = Be32(p + (p[0] == 1 ? 20 : 12));
        return true;
      case FourCC('m', 'd', 'h', 'd'):
        if (n >= 24) track->timescale = Be32(p + (p[0] == 1 ? 20 : 12));
        return true;
      case FourCC('h', 'd', 'l', 'r'):
        if (n >= 12) track->is_video = Be32(p + 8) == FourCC('v', 'i', 'd', 'e');
        return true;
      case FourCC('e', 'l', 's', 't'): {
        if (n < 8) return true;
        uint8_t version = p[0];
        uint32_t count = Be32(p + 4);
        size_t pos = 8;
        for (uint32_t i = 0; i < count; ++i) {
          int64_t media_time = 0;
          if (version == 1) {
            if (pos + 20 > n) break;
            media_time = int64_t(Be64(p + pos + 8));
            pos += 20;
          } else {
            if (pos + 12 > n) break;
            media_time = int32_t(Be32(p + pos + 4));
            pos += 12;
          }
          if (media_time >= 0) {
            track->edit_media_time = media_time;
            break;
          }
        }
        return true;
      }
      case FourCC('t', 'r', 'e', 'x'):
        if (n >= 24) {
          track->default_sample_duration = Be32(p + 12);
          track->default_sample_size = Be32(p + 16);
          track->default_sample_flags = Be32(p + 20);
        }
        return true;
      case FourCC('p', 's', 's', 'h'):
        track->pssh_boxes.insert(track->pssh_boxes.end(), box.start, box.start + box.size);
        return true;
      case FourCC('s', 'g', 'p', 'd'): {
        std::vector<SeigEntry> seig = ParseSgpdSeig(box);
        track->seig.insert(track->seig.end(), seig.begin(), seig.end());
        return true;
      }
      case FourCC('s', 't', 's', 'd'): {
        if (n < 8) return false;
        // First sample entry only.
        const uint8_t* entry = p + 8;
        size_t entry_size = Be32(entry);
        if (entry_size < 8 || entry_size > n - 8) return false;
        track->sample_entry = Be32(entry + 4);
        track->original_format = track->sample_entry;
        size_t children = 0;
        if (track->is_video) {
          track->width = uint16_t(Be16(entry + 8 + 24));
          track->height = uint16_t(Be16(entry + 8 + 26));
          children = 8 + 78;
        } else {
          track->channels = uint16_t(Be16(entry + 8 + 16));
          track->sample_rate = Be32(entry + 8 + 24) >> 16;
          children = 8 + 28;
        }
        return Boxes(entry + children, entry_size - children, [&](const Box& child) {
          const uint8_t* c = child.payload;
          switch (child.type) {
            case FourCC('a', 'v', 'c', 'C'):
            case FourCC('h', 'v', 'c', 'C'):
              track->codec_config.assign(c, c + child.payload_size);
              break;
            case FourCC('e', 's', 'd', 's'):
              track->esds_payload.assign(c, c + child.payload_size);
              track->codec_config = AscFromEsds(c, child.payload_size);
              break;
            case FourCC('s', 'i', 'n', 'f'):
              track->sinf_payload.assign(c, c + child.payload_size);
              return Boxes(c, child.payload_size, [&](const Box& s) {
                if (s.type == FourCC('f', 'r', 'm', 'a') && s.payload_size >= 4) {
                  track->original_format = Be32(s.payload);
                } else if (s.type == FourCC('s', 'c', 'h', 'm') && s.payload_size >= 8) {
                  track->scheme_type = Be32(s.payload + 4);
                } else if (s.type == FourCC('s', 'c', 'h', 'i')) {
                  return Boxes(s.payload, s.payload_size, [&](const Box& t) {
                    if (t.type == FourCC('t', 'e', 'n', 'c')) ParseTenc(t, &track->encryption);
                    return true;
                  });
                }
                return true;
              });
            default:
              break;
          }
          return true;
        });
      }
      default:
        if (IsContainer(box.type)) return Boxes(p, n, visit);
        return true;
    }
  };
  ok = Boxes(data.data(), data.size(), visit);
  if (!ok || !track->timescale || track->codec_config.empty()) {
    *error = "malformed init segment";
    return false;
  }
  if (track->scheme_type == FourCC('c', 'b', 'c', 's')) {
    track->encryption.scheme = EncryptionScheme::kCbcs;
  } else if (track->scheme_type == FourCC('c', 'e', 'n', 'c')) {
    track->encryption.scheme = EncryptionScheme::kCenc;
  }
  return true;
}

bool ParseMediaSegment(const std::vector<uint8_t>& data,
                       const TrackInfo& track,
                       std::vector<Sample>* samples,
                       std::string* error) {
  const uint8_t* moof = nullptr;
  bool ok = Boxes(data.data(), data.size(), [&](const Box& top) -> bool {
    if (top.type != FourCC('m', 'o', 'o', 'f')) return true;
    moof = top.start;
    return Boxes(top.payload, top.payload_size, [&](const Box& traf) -> bool {
      if (traf.type != FourCC('t', 'r', 'a', 'f')) return true;
      uint32_t flags = 0;
      uint64_t base = uint64_t(moof - data.data());
      uint32_t default_duration = track.default_sample_duration;
      uint32_t default_size = track.default_sample_size;
      uint32_t default_flags = track.default_sample_flags;
      uint64_t decode_time = 0;
      struct Entry {
        uint64_t offset;
        uint32_t size, duration, flags;
        int64_t cto;
      };
      std::vector<Entry> entries;
      std::vector<uint8_t> senc;
      uint32_t senc_flags = 0;
      std::vector<uint8_t> saiz_sizes;
      uint8_t saiz_default = 0;
      uint32_t saiz_count = 0;
      std::vector<uint64_t> saio_offsets;
      std::vector<uint32_t> group_index;  // Per sample, seig.
      std::vector<SeigEntry> local_seig;
      bool parsed = Boxes(traf.payload, traf.payload_size, [&](const Box& b) -> bool {
        const uint8_t* p = b.payload;
        size_t n = b.payload_size;
        switch (b.type) {
          case FourCC('t', 'f', 'h', 'd'): {
            flags = Be32(p) & 0xffffff;
            size_t pos = 8;
            if (flags & 0x1) { base = Be64(p + pos); pos += 8; }
            if (flags & 0x2) pos += 4;
            if (flags & 0x8) { default_duration = Be32(p + pos); pos += 4; }
            if (flags & 0x10) { default_size = Be32(p + pos); pos += 4; }
            if (flags & 0x20) { default_flags = Be32(p + pos); pos += 4; }
            return pos <= n;
          }
          case FourCC('t', 'f', 'd', 't'):
            decode_time = p[0] == 1 ? Be64(p + 4) : Be32(p + 4);
            return true;
          case FourCC('t', 'r', 'u', 'n'): {
            uint8_t version = p[0];
            uint32_t tf = Be32(p) & 0xffffff;
            uint32_t count = Be32(p + 4);
            size_t pos = 8;
            int32_t data_offset = 0;
            if (tf & 0x1) { data_offset = int32_t(Be32(p + pos)); pos += 4; }
            uint32_t first_flags = 0;
            bool has_first = tf & 0x4;
            if (has_first) { first_flags = Be32(p + pos); pos += 4; }
            uint64_t offset = base + int64_t(data_offset);
            for (uint32_t i = 0; i < count; ++i) {
              Entry e{offset, default_size, default_duration, default_flags, 0};
              if (tf & 0x100) { e.duration = Be32(p + pos); pos += 4; }
              if (tf & 0x200) { e.size = Be32(p + pos); pos += 4; }
              if (tf & 0x400) { e.flags = Be32(p + pos); pos += 4; }
              else if (i == 0 && has_first) e.flags = first_flags;
              if (tf & 0x800) {
                e.cto = version ? int64_t(int32_t(Be32(p + pos))) : int64_t(Be32(p + pos));
                pos += 4;
              }
              if (pos > n) return false;
              offset += e.size;
              entries.push_back(e);
            }
            return true;
          }
          case FourCC('s', 'e', 'n', 'c'):
            senc_flags = Be32(p) & 0xffffff;
            senc.assign(p + 4, p + n);
            return true;
          case FourCC('s', 'a', 'i', 'z'): {
            size_t pos = 4;
            if (Be32(p) & 1) pos += 8;
            saiz_default = p[pos];
            saiz_count = Be32(p + pos + 1);
            pos += 5;
            if (!saiz_default) saiz_sizes.assign(p + pos, p + std::min(n, pos + saiz_count));
            return true;
          }
          case FourCC('s', 'a', 'i', 'o'): {
            uint8_t version = p[0];
            size_t pos = 4;
            if (Be32(p) & 1) pos += 8;
            uint32_t count = Be32(p + pos);
            pos += 4;
            for (uint32_t i = 0; i < count; ++i) {
              saio_offsets.push_back(version ? Be64(p + pos) : Be32(p + pos));
              pos += version ? 8 : 4;
            }
            return true;
          }
          case FourCC('s', 'b', 'g', 'p'): {
            if (Be32(p + 4) != FourCC('s', 'e', 'i', 'g')) return true;
            size_t pos = 8 + (p[0] == 1 ? 4 : 0);
            uint32_t count = Be32(p + pos);
            pos += 4;
            for (uint32_t i = 0; i < count && pos + 8 <= n; ++i, pos += 8) {
              group_index.insert(group_index.end(), Be32(p + pos), Be32(p + pos + 4));
            }
            return true;
          }
          case FourCC('s', 'g', 'p', 'd'):
            local_seig = ParseSgpdSeig(b);
            return true;
          default:
            return true;
        }
      });
      if (!parsed) return false;

      // Encryption info for sample |i|: protection, key, IV size.
      auto seig_for = [&](size_t i) -> const SeigEntry* {
        if (i >= group_index.size() || group_index[i] == 0) return nullptr;
        uint32_t index = group_index[i];
        if (index > 0x10000) {
          index -= 0x10000;
          return index <= local_seig.size() ? &local_seig[index - 1] : nullptr;
        }
        return index <= track.seig.size() ? &track.seig[index - 1] : nullptr;
      };
      const bool track_protected = track.encryption.scheme != EncryptionScheme::kUnencrypted;

      // Per-sample aux info from senc and, independently, from saiz/saio.
      struct Aux {
        std::vector<uint8_t> iv;
        std::vector<SubsampleEntry> subsamples;
      };
      auto parse_aux = [&](const uint8_t* p, size_t n, size_t iv_size, bool has_subsamples,
                           Aux* aux) -> size_t {
        if (n < iv_size) return 0;
        aux->iv.assign(p, p + iv_size);
        size_t pos = iv_size;
        if (has_subsamples) {
          if (pos + 2 > n) return 0;
          uint32_t count = Be16(p + pos);
          pos += 2;
          for (uint32_t k = 0; k < count; ++k) {
            if (pos + 6 > n) return 0;
            aux->subsamples.push_back({Be16(p + pos), Be32(p + pos + 2)});
            pos += 6;
          }
        }
        return pos;
      };
      auto iv_size_for = [&](size_t i) -> size_t {
        const SeigEntry* g = seig_for(i);
        return g ? g->per_sample_iv_size : track.encryption.default_per_sample_iv_size;
      };
      std::vector<Aux> from_senc, from_saio;
      if (!senc.empty() && track_protected) {
        uint32_t count = Be32(senc.data());
        size_t pos = 4;
        for (uint32_t i = 0; i < count; ++i) {
          Aux aux;
          size_t used = parse_aux(senc.data() + pos, senc.size() - pos, iv_size_for(i),
                                  senc_flags & 2, &aux);
          if (!used && (iv_size_for(i) || (senc_flags & 2))) return false;
          pos += used;
          from_senc.push_back(aux);
        }
      }
      if (saiz_count && !saio_offsets.empty() && track_protected) {
        uint64_t offset = uint64_t(moof - data.data()) + saio_offsets[0];
        for (uint32_t i = 0; i < saiz_count; ++i) {
          size_t size = saiz_default ? saiz_default : saiz_sizes[i];
          if (offset + size > data.size()) return false;
          Aux aux;
          parse_aux(data.data() + offset, size, iv_size_for(i), size > iv_size_for(i), &aux);
          offset += size;
          from_saio.push_back(aux);
        }
      }
      if (!from_senc.empty() && !from_saio.empty()) {
        for (size_t i = 0; i < from_senc.size() && i < from_saio.size(); ++i) {
          bool same = from_senc[i].iv == from_saio[i].iv &&
                      from_senc[i].subsamples.size() == from_saio[i].subsamples.size();
          for (size_t k = 0; same && k < from_senc[i].subsamples.size(); ++k) {
            same = from_senc[i].subsamples[k].clear_bytes == from_saio[i].subsamples[k].clear_bytes &&
                   from_senc[i].subsamples[k].cypher_bytes == from_saio[i].subsamples[k].cypher_bytes;
          }
          if (!same) {
            *error = "senc and saiz/saio disagree at sample " + std::to_string(i);
            return false;
          }
        }
      }
      const std::vector<Aux>& aux = !from_saio.empty() ? from_saio : from_senc;

      uint64_t dts = decode_time;
      for (size_t i = 0; i < entries.size(); ++i) {
        const Entry& e = entries[i];
        if (e.offset + e.size > data.size()) return false;
        Sample s;
        s.data.assign(data.begin() + e.offset, data.begin() + e.offset + e.size);
        s.dts = int64_t(dts) - track.edit_media_time;
        s.pts = s.dts + e.cto;
        s.duration = e.duration;
        s.is_keyframe = !track.is_video || !(e.flags & 0x10000);
        s.aux_from_saio = !from_saio.empty();
        const SeigEntry* g = seig_for(i);
        bool is_protected = g ? g->is_protected : track_protected;
        if (is_protected) {
          DecryptInfo d;
          d.scheme = track.encryption.scheme;
          d.key_id = g ? g->key_id : track.encryption.default_key_id;
          if (i < aux.size()) {
            d.iv = aux[i].iv;
            d.subsamples = aux[i].subsamples;
          }
          if (d.scheme == EncryptionScheme::kCbcs) {
            d.pattern = g ? g->pattern : track.encryption.default_pattern;
          }
          s.decrypt = d;
        }
        dts += e.duration;
        samples->push_back(std::move(s));
      }
      return true;
    });
  });
  if (!ok) {
    if (error->empty()) *error = "malformed media segment";
    return false;
  }
  return true;
}

bool AvcToAnnexB(const std::vector<uint8_t>& record,
                 bool hevc,
                 bool insert_parameter_sets,
                 std::vector<uint8_t>* data,
                 std::vector<SubsampleEntry>* subsamples) {
  if (record.size() < (hevc ? 23u : 7u)) return false;
  size_t length_size = (record[hevc ? 21 : 4] & 3) + 1;
  std::vector<std::vector<uint8_t>> parameter_sets;
  if (hevc) {
    size_t pos = 23;
    uint8_t arrays = record[22];
    for (uint8_t a = 0; a < arrays && pos + 3 <= record.size(); ++a) {
      uint8_t type = record[pos] & 0x3f;
      uint32_t count = Be16(&record[pos + 1]);
      pos += 3;
      for (uint32_t k = 0; k < count && pos + 2 <= record.size(); ++k) {
        uint32_t len = Be16(&record[pos]);
        pos += 2;
        if (pos + len > record.size()) return false;
        if (type >= 32 && type <= 34) {
          parameter_sets.emplace_back(record.begin() + pos, record.begin() + pos + len);
        }
        pos += len;
      }
    }
  } else {
    size_t pos = 6;
    uint32_t sps = record[5] & 0x1f;
    for (int list = 0; list < 2; ++list) {
      uint32_t count = list == 0 ? sps : record[pos++];
      for (uint32_t k = 0; k < count && pos + 2 <= record.size(); ++k) {
        uint32_t len = Be16(&record[pos]);
        pos += 2;
        if (pos + len > record.size()) return false;
        parameter_sets.emplace_back(record.begin() + pos, record.begin() + pos + len);
        pos += len;
      }
    }
  }

  // AVC::ConvertFrameToAnnexB: each length prefix becomes 00 00 00 01; the
  // subsample holding the prefix absorbs the size change.
  auto subsample_at = [&](size_t offset) -> SubsampleEntry* {
    if (!subsamples || subsamples->empty()) return nullptr;
    size_t start = 0;
    for (SubsampleEntry& entry : *subsamples) {
      size_t end = start + entry.clear_bytes + entry.cypher_bytes;
      if (offset < end) return &entry;
      start = end;
    }
    return &subsamples->back();
  };
  std::vector<uint8_t> out;
  std::vector<std::pair<SubsampleEntry*, int>> deltas;
  size_t pos = 0;
  size_t first_nal_end = 0;
  bool first_is_aud = false;
  while (pos + length_size <= data->size()) {
    size_t len = 0;
    for (size_t k = 0; k < length_size; ++k) len = (len << 8) | (*data)[pos + k];
    if (!len || pos + length_size + len > data->size()) return false;
    if (SubsampleEntry* entry = subsample_at(pos)) deltas.push_back({entry, 4 - int(length_size)});
    out.insert(out.end(), {0, 0, 0, 1});
    out.insert(out.end(), data->begin() + pos + length_size, data->begin() + pos + length_size + len);
    if (pos == 0) {
      uint8_t type = hevc ? ((*data)[length_size] >> 1) & 0x3f : (*data)[length_size] & 0x1f;
      first_is_aud = hevc ? type == 35 : type == 9;
      first_nal_end = out.size();
    }
    pos += length_size + len;
  }
  if (pos != data->size()) return false;
  for (auto& [entry, delta] : deltas) {
    entry->clear_bytes = uint32_t(int64_t(entry->clear_bytes) + delta);
  }
  if (insert_parameter_sets && !parameter_sets.empty()) {
    std::vector<uint8_t> annex_b;
    for (const auto& set : parameter_sets) {
      annex_b.insert(annex_b.end(), {0, 0, 0, 1});
      annex_b.insert(annex_b.end(), set.begin(), set.end());
    }
    size_t insert_at = first_is_aud ? first_nal_end : 0;
    if (SubsampleEntry* entry = subsample_at(insert_at)) {
      entry->clear_bytes += uint32_t(annex_b.size());
    }
    out.insert(out.begin() + insert_at, annex_b.begin(), annex_b.end());
  }
  data->swap(out);
  return true;
}

std::vector<uint8_t> AdtsHeader(const std::vector<uint8_t>& asc, size_t payload_size) {
  if (asc.size() < 2) return {};
  uint8_t object_type = asc[0] >> 3;
  uint8_t frequency_index = uint8_t(((asc[0] & 7) << 1) | (asc[1] >> 7));
  uint8_t channel_config = (asc[1] >> 3) & 0x0f;
  size_t frame_length = payload_size + 7;
  return {0xff,
          0xf1,
          uint8_t(((object_type - 1) << 6) | (frequency_index << 2) | (channel_config >> 2)),
          uint8_t(((channel_config & 3) << 6) | (frame_length >> 11)),
          uint8_t((frame_length >> 3) & 0xff),
          uint8_t(((frame_length & 7) << 5) | 0x1f),
          0xfc};
}

EncodedSample ChromiumBuffer(const TrackInfo& track, const Sample& sample,
                             std::vector<uint8_t>* storage, DecryptInfo* decrypt_storage) {
  *storage = sample.data;
  std::vector<SubsampleEntry> subsamples;
  if (sample.decrypt) subsamples = sample.decrypt->subsamples;
  if (track.is_video) {
    bool hevc = track.original_format == FourCC('h', 'v', 'c', '1') ||
                track.original_format == FourCC('h', 'e', 'v', '1');
    AvcToAnnexB(track.codec_config, hevc, sample.is_keyframe, storage,
                sample.decrypt ? &subsamples : nullptr);
  } else {
    std::vector<uint8_t> header = AdtsHeader(track.codec_config, storage->size());
    if (sample.decrypt) {
      if (subsamples.empty()) {
        subsamples.push_back({uint32_t(header.size()), uint32_t(storage->size())});
      } else {
        subsamples[0].clear_bytes += uint32_t(header.size());
      }
    }
    storage->insert(storage->begin(), header.begin(), header.end());
  }
  auto micros = [&](int64_t ticks) {
    return MediaTime::FromMicroseconds(ticks * 1000000 / int64_t(track.timescale));
  };
  EncodedSample out;
  out.data = storage->data();
  out.size = storage->size();
  out.pts = micros(sample.pts);
  out.dts = micros(sample.dts);
  out.duration = micros(sample.duration);
  out.is_keyframe = sample.is_keyframe;
  if (sample.decrypt) {
    *decrypt_storage = *sample.decrypt;
    decrypt_storage->subsamples = subsamples;
    std::vector<uint8_t> iv =
        sample.decrypt->iv.empty() ? track.encryption.default_constant_iv : sample.decrypt->iv;
    iv.resize(16, 0);
    decrypt_storage->iv = iv;
    out.decrypt = *decrypt_storage;
  }
  return out;
}

EncodedSample IsoBuffer(const TrackInfo& track, const Sample& sample) {
  EncodedSample out;
  out.data = sample.data.data();
  out.size = sample.data.size();
  int32_t ts = int32_t(track.timescale);
  out.pts = {sample.pts, ts};
  out.dts = {sample.dts, ts};
  out.duration = {sample.duration, ts};
  out.is_keyframe = sample.is_keyframe;
  out.decrypt = sample.decrypt;
  return out;
}

}  // namespace parc::fairplay::test
