// Installed by the reviewed overlay at
// //media/formats/mp2t/parc_es_parser_mpeg_video.cc (media).

#include "media/formats/mp2t/parc_es_parser_mpeg_video.h"

#include <algorithm>
#include <array>
#include <utility>
#include <vector>

#include "base/logging.h"
#include "base/numerics/safe_conversions.h"
#include "media/base/bit_reader.h"
#include "media/base/encryption_scheme.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/timestamp_constants.h"
#include "media/base/video_aspect_ratio.h"
#include "media/base/video_color_space.h"
#include "media/base/video_transformation.h"
#include "media/formats/common/offset_byte_queue.h"
#include "media/formats/mp2t/mp2t_common.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

namespace media::mp2t {

namespace {

// ISO/IEC 13818-2 table 6-1.
constexpr uint8_t kPictureStartCode = 0x00;
constexpr uint8_t kSequenceHeaderCode = 0xB3;
constexpr uint8_t kExtensionStartCode = 0xB5;
constexpr uint8_t kGroupStartCode = 0xB8;
// Table 6-2.
constexpr uint32_t kSequenceExtensionId = 1;
constexpr uint32_t kPictureCodingExtensionId = 8;
// Table 6-12.
constexpr uint32_t kIntraCoded = 1;
// Table 6-14: top field, bottom field.
constexpr uint32_t kTopField = 1;
constexpr uint32_t kBottomField = 2;

// frame_rate_code 1 to 8 (table 6-4), as frames per second num / den.
constexpr std::array<std::pair<int, int>, 8> kFrameRates = {{
    {24000, 1001},
    {24, 1},
    {25, 1},
    {30000, 1001},
    {30, 1},
    {50, 1},
    {60000, 1001},
    {60, 1},
}};

// The pixel aspect ratio AVStreamDataParser gives an MPEG-1 sequence's
// pel_aspect_ratio 1 to 14 (kCMFormatDescriptionExtension_PixelAspectRatio,
// macOS 27.2): each code's 1 / height-to-width ratio (ISO/IEC 11172-2
// 2.4.3.2), Rec. 601's for codes 3, 8 and 12, and 33:40 for code 6.
constexpr std::array<std::pair<int, int>, 14> kMpeg1PixelAspectRatios = {{
    {1, 1},
    {49, 33},
    {118, 81},
    {239, 182},
    {36, 29},
    {33, 40},
    {169, 151},
    {59, 54},
    {54, 53},
    {196, 201},
    {187, 200},
    {10, 11},
    {127, 147},
    {134, 161},
}};

}  // namespace

ParcEsParserMpegVideo::ParcEsParserMpegVideo(
    EsAdapterVideo::NewVideoConfigCB new_video_config_cb,
    EsAdapterVideo::EmitBufferCB emit_buffer_cb)
    : es_adapter_(std::move(new_video_config_cb), std::move(emit_buffer_cb)) {}

ParcEsParserMpegVideo::~ParcEsParserMpegVideo() = default;

void ParcEsParserMpegVideo::Flush() {
  flushing_ = true;
  bool parsed = ParseFromEsQueue();
  flushing_ = false;
  if (parsed && picture_pos_ >= 0) {
    EmitAccessUnit(es_queue_->tail());
  }
  EmitUntimed();
  es_adapter_.Flush();
}

void ParcEsParserMpegVideo::ResetInternal() {
  unit_pos_ = -1;
  search_pos_ = 0;
  access_unit_pos_ = -1;
  sequence_pos_ = -1;
  sequence_end_pos_ = -1;
  picture_pos_ = -1;
  last_picture_pos_ = -1;
  fields_ = 0;
  closed_gop_ = false;
  has_gop_header_ = false;
  sequence_.reset();
  sequence_headers_.clear();
  sequence_changed_ = false;
  gop_pts_ = kNoTimestamp;
  max_temporal_reference_ = -1;
  last_dts_ = kNoDecodeTimestamp;
  untimed_.clear();
  last_video_decoder_config_ = VideoDecoderConfig();
  es_adapter_.Reset();
}

std::optional<int64_t> ParcEsParserMpegVideo::FindStartCode(int64_t pos) {
  constexpr uint8_t kPrefix[] = {0x00, 0x00, 0x01};
  const int64_t from = std::max(pos, search_pos_);
  base::span<const uint8_t> data = es_queue_->DataAt(from);
  auto found = std::ranges::search(data, kPrefix).begin();
  if (found == data.end()) {
    // A prefix may continue in the next bytes pushed.
    search_pos_ = std::max(from, es_queue_->tail() - 2);
    return std::nullopt;
  }
  const int64_t start = from + (found - data.begin());
  search_pos_ = start + 3;
  return start;
}

bool ParcEsParserMpegVideo::ParseFromEsQueue() {
  while (true) {
    if (unit_pos_ < 0) {
      std::optional<int64_t> start = FindStartCode(es_queue_->head());
      if (!start) {
        if (access_unit_pos_ < 0) {
          es_queue_->Trim(search_pos_);
        }
        return true;
      }
      unit_pos_ = *start;
    }
    // A unit is complete when the next start code arrives, or at a flush.
    std::optional<int64_t> next = FindStartCode(unit_pos_ + 3);
    if (!next && !flushing_) {
      return true;
    }
    RCHECK(ReadUnit(unit_pos_, next.value_or(es_queue_->tail())));
    if (!next) {
      unit_pos_ = -1;
      return true;
    }
    unit_pos_ = *next;
    es_queue_->Trim(access_unit_pos_ < 0 ? unit_pos_ : access_unit_pos_);
  }
}

bool ParcEsParserMpegVideo::ReadUnit(int64_t pos, int64_t end) {
  base::span<const uint8_t> unit = es_queue_->DataAt(pos).first(
      base::checked_cast<size_t>(end - pos));
  if (unit.size() < 4) {
    return true;
  }
  const uint8_t code = unit[3];
  const bool starts_header = code == kSequenceHeaderCode ||
                             code == kGroupStartCode ||
                             code == kPictureStartCode;
  // A lone field pairs only with the picture right after it.
  if (starts_header && picture_pos_ >= 0 &&
      (code != kPictureStartCode || fields_ != 1)) {
    RCHECK(EmitAccessUnit(pos));
  }
  if ((code == kGroupStartCode || code == kPictureStartCode) &&
      sequence_pos_ >= 0 && sequence_end_pos_ < 0) {
    sequence_end_pos_ = pos;
    base::span<const uint8_t> headers = es_queue_->DataAt(sequence_pos_).first(
        base::checked_cast<size_t>(pos - sequence_pos_));
    sequence_headers_.assign(headers.begin(), headers.end());
    sequence_changed_ = true;
  }
  // Headers without a picture after them start over, so the queue keeps
  // at most one set of them.
  if (picture_pos_ < 0 && ((code == kSequenceHeaderCode && sequence_pos_ >= 0) ||
                           (code == kGroupStartCode && has_gop_header_))) {
    access_unit_pos_ = -1;
    sequence_pos_ = -1;
    sequence_end_pos_ = -1;
    has_gop_header_ = false;
    closed_gop_ = false;
  }
  if (starts_header && access_unit_pos_ < 0) {
    access_unit_pos_ = pos;
  }
  if (access_unit_pos_ < 0) {
    return true;
  }

  BitReader reader(unit.subspan(4u));
  switch (code) {
    case kSequenceHeaderCode: {
      // ISO/IEC 13818-2 6.2.2.1.
      Sequence sequence;
      RCHECK(reader.ReadBits(12, &sequence.width));
      RCHECK(reader.ReadBits(12, &sequence.height));
      RCHECK(reader.ReadBits(4, &sequence.aspect_ratio_information));
      RCHECK(reader.ReadBits(4, &sequence.frame_rate_code));
      sequence_ = sequence;
      sequence_pos_ = pos;
      sequence_end_pos_ = -1;
      break;
    }
    case kExtensionStartCode: {
      uint32_t id;
      RCHECK(reader.ReadBits(4, &id));
      if (id == kSequenceExtensionId && sequence_pos_ >= 0 &&
          sequence_end_pos_ < 0) {
        // 6.2.2.3: profile_and_level_indication, progressive_sequence and
        // chroma_format, then the size extensions; bit_rate_extension,
        // marker_bit, vbv_buffer_size_extension and low_delay, then the
        // frame rate extensions.
        uint32_t horizontal_size_extension, vertical_size_extension;
        RCHECK(reader.SkipBits(8 + 1 + 2));
        RCHECK(reader.ReadBits(2, &horizontal_size_extension));
        RCHECK(reader.ReadBits(2, &vertical_size_extension));
        RCHECK(reader.SkipBits(12 + 1 + 8 + 1));
        RCHECK(reader.ReadBits(2, &sequence_->frame_rate_extension_n));
        RCHECK(reader.ReadBits(5, &sequence_->frame_rate_extension_d));
        sequence_->width |= horizontal_size_extension << 12;
        sequence_->height |= vertical_size_extension << 12;
        sequence_->mpeg2 = true;
      } else if (id == kPictureCodingExtensionId && picture_pos_ >= 0) {
        // 6.2.3.1: the f_codes and intra_dc_precision, then picture_structure.
        // A field picture holds one field of the frame.
        uint32_t picture_structure;
        RCHECK(reader.SkipBits(16 + 2));
        RCHECK(reader.ReadBits(2, &picture_structure));
        if (picture_structure == kTopField ||
            picture_structure == kBottomField) {
          --fields_;
        } else if (fields_ == 3) {
          // A frame after a field whose partner is missing: the field is a
          // sample of its own.
          const int64_t frame_pos = last_picture_pos_;
          last_picture_pos_ = picture_pos_;
          RCHECK(EmitAccessUnit(frame_pos));
          access_unit_pos_ = picture_pos_ = last_picture_pos_ = frame_pos;
          fields_ = 2;
          RCHECK(ReadPictureHeader(frame_pos));
        }
      }
      break;
    }
    case kGroupStartCode:
      // 6.2.2.6: time_code, then closed_gop.
      has_gop_header_ = true;
      RCHECK(reader.SkipBits(25));
      RCHECK(reader.ReadFlag(&closed_gop_));
      break;
    case kPictureStartCode:
      fields_ += 2;
      last_picture_pos_ = pos;
      if (picture_pos_ < 0) {
        picture_pos_ = pos;
        RCHECK(ReadPictureHeader(pos));
      }
      break;
  }
  return true;
}

bool ParcEsParserMpegVideo::ReadPictureHeader(int64_t pos) {
  // 6.2.3: temporal_reference, picture_coding_type.
  BitReader reader(es_queue_->DataAt(pos + 4));
  return reader.ReadBits(10, &temporal_reference_) &&
         reader.ReadBits(3, &picture_coding_type_);
}

bool ParcEsParserMpegVideo::EmitAccessUnit(int64_t end) {
  const int64_t access_unit_pos = std::exchange(access_unit_pos_, -1);
  sequence_pos_ = -1;
  sequence_end_pos_ = -1;
  const int64_t picture_pos = std::exchange(picture_pos_, -1);
  const int64_t last_picture_pos = std::exchange(last_picture_pos_, -1);
  const bool key_frame = std::exchange(closed_gop_, false) &&
                         picture_coding_type_ == kIntraCoded;
  const bool new_gop = std::exchange(has_gop_header_, false);
  fields_ = 0;
  // A PES packet's timestamp is its first picture's (ISO/IEC 13818-1
  // 2.4.3.7), so one starting at a second field is spent here too.
  TimingDesc timing = GetTimingDescriptor(picture_pos);
  if (last_picture_pos > picture_pos) {
    GetTimingDescriptor(last_picture_pos);
  }
  // No sequence header yet: nothing can decode it.
  if (!sequence_) {
    return true;
  }
  if (std::exchange(sequence_changed_, false)) {
    RCHECK(UpdateVideoDecoderConfig(sequence_headers_));
  }

  base::TimeDelta frame_duration;
  if (sequence_->frame_rate_code >= 1 &&
      sequence_->frame_rate_code <= kFrameRates.size()) {
    // 6.3.3: frame_rate_value * (n + 1) / (d + 1).
    const auto [num, den] = kFrameRates[sequence_->frame_rate_code - 1];
    frame_duration = base::Seconds(1) * den *
                     (sequence_->frame_rate_extension_d + 1) /
                     (num * (sequence_->frame_rate_extension_n + 1));
  }
  if (new_gop) {
    if (gop_pts_ != kNoTimestamp) {
      gop_pts_ += frame_duration * (max_temporal_reference_ + 1);
    }
    max_temporal_reference_ = -1;
  }
  max_temporal_reference_ = std::max(max_temporal_reference_,
                                     static_cast<int>(temporal_reference_));
  scoped_refptr<StreamParserBuffer> buffer = StreamParserBuffer::CopyFrom(
      es_queue_->DataAt(access_unit_pos)
          .first(base::checked_cast<size_t>(end - access_unit_pos)),
      key_frame, DemuxerStream::VIDEO, kMp2tVideoTrackId);
  if (timing.pts == kNoTimestamp && gop_pts_ != kNoTimestamp &&
      frame_duration.is_positive()) {
    timing.pts = gop_pts_ + frame_duration * temporal_reference_;
    timing.dts = last_dts_ + frame_duration;
  }
  if (timing.pts == kNoTimestamp) {
    // Before the first timestamp: wait for one in the same GOP, no longer
    // than timestamps may be apart (ISO/IEC 13818-1 2.7.4).
    if (new_gop || !frame_duration.is_positive() ||
        frame_duration * untimed_.size() > base::Milliseconds(700)) {
      RCHECK(EmitUntimed());
    }
    if (frame_duration.is_positive()) {
      untimed_.emplace_back(std::move(buffer), temporal_reference_);
      return true;
    }
  }
  if (timing.pts != kNoTimestamp) {
    if (timing.dts == kNoDecodeTimestamp) {
      timing.dts = DecodeTimestamp::FromPresentationTime(timing.pts);
    }
    gop_pts_ = timing.pts - frame_duration * temporal_reference_;
    // The pictures waiting in this GOP precede this one a frame apart.
    if (!new_gop) {
      for (size_t i = 0; i < untimed_.size(); ++i) {
        auto& [untimed, temporal_reference] = untimed_[i];
        untimed->set_timestamp(gop_pts_ + frame_duration * temporal_reference);
        untimed->SetDecodeTimestamp(timing.dts -
                                    frame_duration * (untimed_.size() - i));
      }
    }
    RCHECK(EmitUntimed());
  }
  last_dts_ = timing.dts;
  buffer->SetDecodeTimestamp(timing.dts);
  buffer->set_timestamp(timing.pts);
  return es_adapter_.OnNewBuffer(std::move(buffer));
}

bool ParcEsParserMpegVideo::EmitUntimed() {
  std::vector<std::pair<scoped_refptr<StreamParserBuffer>, uint32_t>> untimed;
  untimed.swap(untimed_);
  for (auto& [buffer, temporal_reference] : untimed) {
    RCHECK(es_adapter_.OnNewBuffer(std::move(buffer)));
  }
  return true;
}

bool ParcEsParserMpegVideo::UpdateVideoDecoderConfig(
    base::span<const uint8_t> sequence_headers) {
  const gfx::Size size(base::checked_cast<int>(sequence_->width),
                       base::checked_cast<int>(sequence_->height));
  const gfx::Rect visible_rect(size);
  const uint32_t code = sequence_->aspect_ratio_information;

  // The pixel aspect ratio AVStreamDataParser gives the sequence. MPEG-2
  // codes 2, 3 and 4 are 4:3, 16:9 and 2.21:1 pictures (table 6-3), taken
  // over the whole frame (not sequence_display_extension's size), with Rec.
  // 601's pixels at 720x576 and 720x480; any other code is square.
  std::pair<int, int> pixel_aspect_ratio = {1, 1};
  if (!sequence_->mpeg2) {
    if (size == gfx::Size(352, 288)) {
      pixel_aspect_ratio = {59, 54};
    } else if (code >= 1 && code <= kMpeg1PixelAspectRatios.size()) {
      pixel_aspect_ratio = kMpeg1PixelAspectRatios[code - 1];
    }
  } else if (code == 2 && size == gfx::Size(720, 576)) {
    pixel_aspect_ratio = {59, 54};
  } else if (code == 3 && size == gfx::Size(720, 576)) {
    pixel_aspect_ratio = {118, 81};
  } else if (code == 2 && size == gfx::Size(720, 480)) {
    pixel_aspect_ratio = {10, 11};
  } else if (code == 3 && size == gfx::Size(720, 480)) {
    pixel_aspect_ratio = {40, 33};
  } else if (code >= 2 && code <= 4) {
    constexpr std::array<std::pair<int, int>, 3> kDisplayAspectRatios = {
        {{4, 3}, {16, 9}, {221, 100}}};
    const auto [width, height] = kDisplayAspectRatios[code - 2];
    pixel_aspect_ratio = {width * size.height(), height * size.width()};
  }
  const VideoAspectRatio aspect_ratio =
      VideoAspectRatio::PAR(pixel_aspect_ratio.first, pixel_aspect_ratio.second);

  VideoDecoderConfig config(
      VideoCodec::kMPEG2, VIDEO_CODEC_PROFILE_UNKNOWN,
      VideoDecoderConfig::AlphaMode::kIsOpaque, VideoColorSpace::REC709(),
      kNoTransformation, size, visible_rect,
      aspect_ratio.GetNaturalSize(visible_rect),
      std::vector<uint8_t>(sequence_headers.begin(), sequence_headers.end()),
      EncryptionScheme::kUnencrypted);
  config.set_aspect_ratio(aspect_ratio);
  if (!config.IsValidConfig()) {
    DVLOG(1) << "Invalid video config: " << config.AsHumanReadableString();
    return false;
  }
  // The decoder reads repeated sequence headers in the stream, so new
  // quantiser matrices or user data in one are no new configuration.
  VideoDecoderConfig unchanged_extra_data = config;
  unchanged_extra_data.SetExtraData(last_video_decoder_config_.extra_data());
  if (!unchanged_extra_data.Matches(last_video_decoder_config_)) {
    // Pictures waiting for a timestamp belong to the configuration before.
    RCHECK(EmitUntimed());
    last_video_decoder_config_ = config;
    es_adapter_.OnConfigChanged(config);
  }
  return true;
}

}  // namespace media::mp2t
