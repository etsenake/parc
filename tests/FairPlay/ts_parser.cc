#include "ts_parser.h"

#include <iterator>
#include <map>

namespace parc::fairplay::test {
namespace {

struct Pes {
  int64_t pts = -1;
  int64_t dts = -1;
  std::vector<uint8_t> payload;
};

bool IsVideoType(uint8_t type) {
  return type == 0x1b || type == 0xdb;
}

bool IsAudioType(uint8_t type) {
  return type == 0x0f || type == 0xcf;
}

int64_t ReadTimestamp(const uint8_t* p) {
  return (int64_t(p[0] >> 1) & 7) << 30 | int64_t(p[1]) << 22 | int64_t(p[2] >> 1) << 15 |
         int64_t(p[3]) << 7 | int64_t(p[4] >> 1);
}

// The start of every Annex B start code (its leading zeros included) in |es|.
std::vector<size_t> StartCodes(const std::vector<uint8_t>& es) {
  std::vector<size_t> codes;
  for (size_t i = 0; i + 3 <= es.size(); ++i) {
    if (es[i] == 0 && es[i + 1] == 0 && es[i + 2] == 1) {
      codes.push_back(i > 0 && es[i - 1] == 0 ? i - 1 : i);
      i += 2;
    }
  }
  return codes;
}

void SplitAccessUnits(const std::vector<Pes>& pes, std::vector<Sample>* samples) {
  // The elementary stream with each PES's start offset and timestamps.
  std::vector<uint8_t> es;
  std::map<size_t, const Pes*> starts;
  for (const Pes& unit : pes) {
    starts[es.size()] = &unit;
    es.insert(es.end(), unit.payload.begin(), unit.payload.end());
  }
  std::vector<size_t> auds;
  for (size_t code : StartCodes(es)) {
    size_t header = code + (es[code + 2] == 1 ? 3 : 4);
    if (header < es.size() && (es[header] & 0x1f) == 9) auds.push_back(code);
  }
  for (size_t n = 0; n < auds.size(); ++n) {
    const size_t begin = auds[n];
    const size_t end = n + 1 < auds.size() ? auds[n + 1] : es.size();
    Sample sample;
    sample.data.assign(es.begin() + begin, es.begin() + end);
    auto pes_it = starts.upper_bound(begin);
    const Pes* unit = std::prev(pes_it)->second;
    sample.pts = unit->pts;
    sample.dts = unit->dts >= 0 ? unit->dts : unit->pts;
    for (size_t code : StartCodes(sample.data)) {
      size_t header = code + (sample.data[code + 2] == 1 ? 3 : 4);
      if (header < sample.data.size() && (sample.data[header] & 0x1f) == 5) sample.is_keyframe = true;
    }
    samples->push_back(std::move(sample));
  }
  // EsAdapterVideo's durations: the distance to the next frame's DTS.
  for (size_t n = 0; n < samples->size(); ++n) {
    Sample& sample = (*samples)[n];
    sample.duration = n + 1 < samples->size() ? (*samples)[n + 1].dts - sample.dts
                                              : n ? (*samples)[n - 1].duration : 3000;
  }
}

void SplitAdtsFrames(const std::vector<Pes>& pes, std::vector<Sample>* samples) {
  static const int kRates[] = {96000, 88200, 64000, 48000, 44100, 32000, 24000,
                               22050, 16000, 12000, 11025, 8000,  7350};
  int64_t next = -1;
  for (const Pes& unit : pes) {
    const std::vector<uint8_t>& p = unit.payload;
    bool first = true;
    for (size_t i = 0; i + 7 <= p.size();) {
      if (p[i] != 0xff || (p[i + 1] & 0xf6) != 0xf0) {
        ++i;
        continue;
      }
      const size_t length = (size_t(p[i + 3] & 3) << 11) | (size_t(p[i + 4]) << 3) | (p[i + 5] >> 5);
      const int index = (p[i + 2] >> 2) & 0xf;
      if (length < 7 || i + length > p.size() || index > 12) break;
      const int64_t duration = 1024 * 90000 / kRates[index];
      if (first && unit.pts >= 0) next = unit.pts;
      first = false;
      if (next >= 0) {
        Sample sample;
        sample.data.assign(p.begin() + i, p.begin() + i + length);
        sample.pts = sample.dts = next;
        sample.duration = duration;
        sample.is_keyframe = true;
        samples->push_back(std::move(sample));
        next += duration;
      }
      i += length;
    }
  }
}

}  // namespace

bool ParseTransportStream(const std::vector<uint8_t>& data, bool video, TsElementaryStream* stream,
                          std::string* error) {
  int pmt_pid = -1;
  int es_pid = -1;
  std::vector<Pes> pes;
  for (size_t at = 0; at + 188 <= data.size(); at += 188) {
    const uint8_t* p = data.data() + at;
    if (p[0] != 0x47) {
      *error = "TS packet without sync byte";
      return false;
    }
    const int pid = ((p[1] & 0x1f) << 8) | p[2];
    const bool unit_start = p[1] & 0x40;
    const int control = (p[3] >> 4) & 3;
    size_t offset = 4;
    if (control & 2) offset += 1 + p[4];
    if (!(control & 1) || offset >= 188) continue;
    const uint8_t* payload = p + offset;
    const size_t size = 188 - offset;
    if ((pid == 0 || pid == pmt_pid) && unit_start) {
      // Sections that fit their packet only, as the vector's do.
      const size_t pointer = 1 + size_t(payload[0]);
      const uint8_t* section = payload + pointer;
      const size_t length = pointer + 3 <= size ? ((section[1] & 0xf) << 8) | section[2] : 0;
      if (length < 13 || pointer + 3 + length > size) {
        *error = "PSI section doesn't fit its packet";
        return false;
      }
      if (pid == 0) {
        pmt_pid = ((section[10] & 0x1f) << 8) | section[11];
        continue;
      }
      if (es_pid >= 0) continue;
      const size_t program_info = ((section[10] & 0xf) << 8) | section[11];
      for (size_t i = 12 + program_info; i + 5 <= 3 + length - 4;) {
        const uint8_t type = section[i];
        const size_t info = ((section[i + 3] & 0xf) << 8) | section[i + 4];
        if (i + 5 + info > 3 + length - 4) break;
        if (video ? IsVideoType(type) : IsAudioType(type)) {
          es_pid = ((section[i + 1] & 0x1f) << 8) | section[i + 2];
          stream->stream_type = type;
          stream->descriptors.assign(section + i + 5, section + i + 5 + info);
          break;
        }
        i += 5 + info;
      }
      continue;
    }
    if (pid != es_pid) continue;
    if (unit_start) {
      const uint8_t flags = size >= 9 ? payload[7] : 0;
      if (size < 9 || payload[0] || payload[1] || payload[2] != 1 || 9u + payload[8] > size ||
          ((flags & 0x80) && payload[8] < 5) || ((flags & 0xc0) == 0xc0 && payload[8] < 10)) {
        *error = "PES without start code or with a header past its packet";
        return false;
      }
      Pes unit;
      if (flags & 0x80) unit.pts = ReadTimestamp(payload + 9);
      if ((flags & 0xc0) == 0xc0) unit.dts = ReadTimestamp(payload + 14);
      const size_t header = 9 + payload[8];
      unit.payload.assign(payload + header, payload + size);
      pes.push_back(std::move(unit));
    } else if (!pes.empty()) {
      pes.back().payload.insert(pes.back().payload.end(), payload, payload + size);
    }
  }
  if (es_pid < 0 || pes.empty()) {
    *error = video ? "no H.264 stream" : "no ADTS stream";
    return false;
  }
  if (video) {
    SplitAccessUnits(pes, &stream->samples);
  } else {
    SplitAdtsFrames(pes, &stream->samples);
  }
  return !stream->samples.empty();
}

uint32_t TsAudioSetupType(const std::vector<uint8_t>& descriptors) {
  for (size_t i = 0; i + 2 <= descriptors.size(); i += 2 + descriptors[i + 1]) {
    const size_t length = descriptors[i + 1];
    if (length < 12 || i + 2 + length > descriptors.size()) continue;
    const uint8_t* d = descriptors.data() + i + 2;
    if (descriptors[i] == 5 && std::string(d, d + 4) == "apad")
      return uint32_t(d[4]) << 24 | uint32_t(d[5]) << 16 | uint32_t(d[6]) << 8 | d[7];
  }
  return 0;
}

std::vector<uint8_t> TsAudioSetupConfig(const std::vector<uint8_t>& descriptors) {
  for (size_t i = 0; i + 2 <= descriptors.size(); i += 2 + descriptors[i + 1]) {
    const uint8_t* d = descriptors.data() + i + 2;
    const size_t length = descriptors[i + 1];
    // registration_descriptor: 'apad', audio_type, priming, version,
    // setup_data_length, setup_data.
    if (descriptors[i] != 0x05 || length < 12 || i + 2 + length > descriptors.size() ||
        std::string(d, d + 4) != "apad") {
      continue;
    }
    const size_t setup = d[11];
    if (12 + setup > length) return {};
    return std::vector<uint8_t>(d + 12, d + 12 + setup);
  }
  return {};
}

}  // namespace parc::fairplay::test
