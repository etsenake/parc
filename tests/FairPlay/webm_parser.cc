#include "webm_parser.h"

#include <bit>

#include "fairplay_bitstream.h"

namespace parc::fairplay::test {

namespace {

constexpr uint64_t kInvalid = UINT64_MAX;
constexpr uint64_t kUnknownSize = UINT64_MAX - 1;

class WebmParser {
 public:
  WebmParser(const std::vector<uint8_t>& file, TrackInfo* track, std::vector<Sample>* samples)
      : file_(file), track_(track), samples_(samples) {}

  bool Parse(size_t pos, size_t end) {
    while (pos < end) {
      const uint64_t id = Vint(&pos, true);
      uint64_t size = Vint(&pos, false);
      if (id == kInvalid || size == kInvalid || pos > end) return false;
      if (size == kUnknownSize) size = end - pos;
      if (size > end - pos) return false;
      if (!Element(id, pos, size)) return false;
      pos += size;
    }
    return true;
  }

  uint64_t timecode_scale() const { return timecode_scale_; }
  const std::string& error() const { return error_; }

 private:
  bool Element(uint64_t id, size_t pos, size_t size) {
    switch (id) {
      case 0x18538067:  // Segment
      case 0x1549A966:  // Info
      case 0x1654AE6B:  // Tracks
      case 0x1F43B675:  // Cluster
      case 0xA0:        // BlockGroup
      case 0xE0:        // Video
      case 0xE1:        // Audio
        return Parse(pos, pos + size);
      case 0xAE:  // TrackEntry: the first one only.
        return track_number_ || Parse(pos, pos + size);
      case 0x2AD7B1:
        timecode_scale_ = Uint(pos, size);
        return true;
      case 0xD7:
        track_number_ = Uint(pos, size);
        return true;
      case 0x86: {
        const std::string codec(file_.begin() + pos, file_.begin() + pos + size);
        track_->is_video = codec[0] == 'V';
        track_->original_format = codec == "V_VP9"      ? FourCC('v', 'p', '0', '9')
                                  : codec == "A_VORBIS" ? FourCC('v', 'o', 'r', 'b')
                                                        : 0;
        track_->sample_entry = track_->original_format;
        return true;
      }
      case 0x63A2:
        track_->codec_config.assign(file_.begin() + pos, file_.begin() + pos + size);
        return true;
      case 0xB0:
        track_->width = static_cast<uint16_t>(Uint(pos, size));
        return true;
      case 0xBA:
        track_->height = static_cast<uint16_t>(Uint(pos, size));
        return true;
      case 0x9F:
        track_->channels = static_cast<uint16_t>(Uint(pos, size));
        return true;
      case 0xB5: {  // SamplingFrequency, a 4- or 8-byte float.
        const uint64_t bits = Uint(pos, size);
        track_->sample_rate = static_cast<uint32_t>(
            size == 4 ? std::bit_cast<float>(static_cast<uint32_t>(bits)) : std::bit_cast<double>(bits));
        return true;
      }
      case 0xE7:
        cluster_time_ = Uint(pos, size);
        return true;
      case 0xA3:  // SimpleBlock
      case 0xA1:  // Block
        return Block(id == 0xA3, pos, size);
      default:
        return true;
    }
  }

  bool Block(bool simple, size_t pos, size_t size) {
    size_t at = pos;
    const uint64_t number = Vint(&at, false);
    if (number == kInvalid || at + 3 > pos + size) return false;
    const int16_t relative = static_cast<int16_t>(Uint(at, 2));
    const uint8_t flags = file_[at + 2];
    at += 3;
    if (flags & 0x06) {
      error_ = "laced blocks";
      return false;
    }
    if (number != track_number_) return true;
    Sample sample;
    sample.data.assign(file_.begin() + at, file_.begin() + pos + size);
    sample.pts = sample.dts = static_cast<int64_t>(cluster_time_) + relative;
    // A Block's keyframe flag would be the absence of ReferenceBlock; only
    // audio comes in Blocks here, all of it keyframes.
    sample.is_keyframe = simple ? (flags & 0x80) != 0 : !track_->is_video;
    samples_->push_back(std::move(sample));
    return true;
  }

  // An EBML variable-length integer: an element ID keeps its length marker.
  uint64_t Vint(size_t* pos, bool keep_marker) const {
    if (*pos >= file_.size()) return kInvalid;
    const uint8_t first = file_[*pos];
    int length = 1;
    while (length <= 8 && !(first & (0x80 >> (length - 1)))) ++length;
    if (length > 8 || *pos + length > file_.size()) return kInvalid;
    uint64_t value = keep_marker ? first : first & (0xff >> length);
    bool all_ones = value == static_cast<uint64_t>(0xff >> length);
    for (int k = 1; k < length; ++k) {
      value = (value << 8) | file_[*pos + k];
      all_ones &= file_[*pos + k] == 0xff;
    }
    *pos += length;
    return !keep_marker && all_ones ? kUnknownSize : value;
  }

  uint64_t Uint(size_t pos, size_t size) const {
    uint64_t value = 0;
    for (size_t k = 0; k < size; ++k) value = (value << 8) | file_[pos + k];
    return value;
  }

  const std::vector<uint8_t>& file_;
  TrackInfo* track_;
  std::vector<Sample>* samples_;
  uint64_t track_number_ = 0;
  uint64_t timecode_scale_ = 1000000;
  uint64_t cluster_time_ = 0;
  std::string error_;
};

}  // namespace

bool ParseWebmFile(const std::vector<uint8_t>& file, TrackInfo* track, std::vector<Sample>* samples,
                   std::string* error) {
  WebmParser parser(file, track, samples);
  if (!parser.Parse(0, file.size())) {
    *error = parser.error().empty() ? "malformed WebM" : parser.error();
    return false;
  }
  if (!track->original_format || samples->size() < 2) {
    *error = "no VP9 or Vorbis track";
    return false;
  }
  track->timescale = static_cast<uint32_t>(1000000000 / parser.timecode_scale());
  for (size_t k = 0; k + 1 < samples->size(); ++k) (*samples)[k].duration = (*samples)[k + 1].pts - (*samples)[k].pts;
  samples->back().duration = (*samples)[samples->size() - 2].duration;
  return true;
}

}  // namespace parc::fairplay::test
