// Installed by the reviewed overlay at
// //media/formats/ogg/parc_ogg_stream_parser.cc (media).

#include "media/formats/ogg/parc_ogg_stream_parser.h"

#include <algorithm>
#include <array>
#include <utility>

#include "base/containers/span_reader.h"
#include "base/numerics/byte_conversions.h"
#include "base/numerics/safe_conversions.h"
#include "base/time/time.h"
#include "media/base/bit_reader.h"
#include "media/base/channel_layout.h"
#include "media/base/limits.h"
#include "media/base/media_log.h"
#include "media/base/media_tracks.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/timestamp_constants.h"
#include "media/formats/common/opus_constants.h"
#include "media/formats/webm/webm_cluster_parser.h"

namespace media {

namespace {

constexpr int kTrackId = 1;
constexpr size_t kPageHeaderSize = 27;
constexpr uint8_t kContinuedPacket = 0x01;
constexpr uint8_t kFirstPage = 0x02;
constexpr uint8_t kLastPage = 0x04;
// RFC 7845 section 4.6.
constexpr base::TimeDelta kOpusSeekPreroll = base::Milliseconds(80);

constexpr auto kCapturePattern = std::to_array<uint8_t>({'O', 'g', 'g', 'S'});
constexpr auto kOpusHead =
    std::to_array<uint8_t>({'O', 'p', 'u', 's', 'H', 'e', 'a', 'd'});
constexpr auto kOpusTags =
    std::to_array<uint8_t>({'O', 'p', 'u', 's', 'T', 'a', 'g', 's'});
constexpr auto kVorbis = std::to_array<uint8_t>({'v', 'o', 'r', 'b', 'i', 's'});
constexpr auto kOggFlac = std::to_array<uint8_t>({0x7f, 'F', 'L', 'A', 'C'});
constexpr auto kFlacMarker = std::to_array<uint8_t>({'f', 'L', 'a', 'C'});

bool StartsWith(base::span<const uint8_t> data,
                base::span<const uint8_t> prefix) {
  return data.size() >= prefix.size() && data.first(prefix.size()) == prefix;
}

// The Ogg page checksum (RFC 3533 section 6): CRC-32, polynomial 0x04c11db7,
// unreflected, zero initial value, computed with the CRC field zeroed.
uint32_t PageChecksum(base::span<const uint8_t> page) {
  static constexpr auto kTable = [] {
    std::array<uint32_t, 256> table{};
    for (uint32_t i = 0; i < 256; ++i) {
      uint32_t r = i << 24;
      for (int bit = 0; bit < 8; ++bit) {
        r = (r & 0x80000000u) ? (r << 1) ^ 0x04c11db7u : r << 1;
      }
      table[i] = r;
    }
    return table;
  }();
  uint32_t crc = 0;
  for (size_t i = 0; i < page.size(); ++i) {
    const uint8_t byte = (i >= 22 && i < 26) ? 0 : page[i];
    crc = (crc << 8) ^ kTable[((crc >> 24) ^ byte) & 0xff];
  }
  return crc;
}

// RFC 6716 section 3.1, in 48 kHz samples.
std::optional<int> OpusPacketFrames(base::span<const uint8_t> packet) {
  if (packet.empty()) {
    return std::nullopt;
  }
  int frames = 0;
  switch (packet[0] & 0x03) {
    case 0:
      frames = 1;
      break;
    case 1:
    case 2:
      frames = 2;
      break;
    default:
      if (packet.size() < 2 || !(packet[1] & 0x3f)) {
        return std::nullopt;
      }
      frames = packet[1] & 0x3f;
  }
  const int config = packet[0] >> 3;
  return base::checked_cast<int>(
      int64_t{frames} * WebMClusterParser::kOpusFrameDurationsMu[config] *
      kOpusDefaultSampleRate / base::Time::kMicrosecondsPerSecond);
}

// The block size a FLAC frame header names (FLAC format, "FRAME_HEADER").
std::optional<int> FlacFrameBlockSize(base::span<const uint8_t> frame) {
  if (frame.size() < 5 || frame[0] != 0xff || (frame[1] & 0xfe) != 0xf8) {
    return std::nullopt;
  }
  const int code = frame[2] >> 4;
  if (code == 1) {
    return 192;
  }
  if (code >= 2 && code <= 5) {
    return 576 << (code - 2);
  }
  if (code >= 8) {
    return 256 << (code - 8);
  }
  if (code == 0) {
    return std::nullopt;
  }
  // Codes 6 and 7 store the size after the UTF-8 coded frame or sample
  // number, whose length its first byte's leading ones give.
  size_t number_size = 1;
  if (frame[4] & 0x80) {
    number_size = 0;
    while (number_size < 8 && (frame[4] & (0x80 >> number_size))) {
      ++number_size;
    }
    if (number_size < 2 || number_size > 7) {
      return std::nullopt;
    }
  }
  base::SpanReader reader(frame);
  if (!reader.Skip(4 + number_size)) {
    return std::nullopt;
  }
  if (code == 6) {
    uint8_t size;
    return reader.ReadU8BigEndian(size) ? std::optional<int>(size + 1)
                                        : std::nullopt;
  }
  uint16_t size;
  return reader.ReadU16BigEndian(size) ? std::optional<int>(size + 1)
                                       : std::nullopt;
}

bool IsIdentificationHeader(base::span<const uint8_t> packet) {
  return StartsWith(packet, kOpusHead) || StartsWith(packet, kOggFlac) ||
         (!packet.empty() && packet[0] == 1 &&
          StartsWith(packet.subspan(1u), kVorbis));
}

}  // namespace

struct ParcOggStreamParser::Page {
  uint8_t flags = 0;
  uint32_t serial = 0;
  uint32_t sequence = 0;
  base::span<const uint8_t> lacing;
  base::span<const uint8_t> body;
};

ParcOggStreamParser::ParcOggStreamParser() = default;

ParcOggStreamParser::~ParcOggStreamParser() = default;

void ParcOggStreamParser::Init(
    InitCB init_cb,
    NewConfigCB config_cb,
    NewBuffersCB new_buffers_cb,
    EncryptedMediaInitDataCB encrypted_media_init_data_cb,
    NewMediaSegmentCB new_segment_cb,
    EndMediaSegmentCB end_of_segment_cb,
    MediaLog* media_log) {
  init_cb_ = std::move(init_cb);
  config_cb_ = std::move(config_cb);
  new_buffers_cb_ = std::move(new_buffers_cb);
  new_segment_cb_ = std::move(new_segment_cb);
  end_of_segment_cb_ = std::move(end_of_segment_cb);
  media_log_ = MediaLog::CloneSafely(media_log);
}

void ParcOggStreamParser::Flush() {
  queue_.Reset();
  uninspected_pending_bytes_ = 0;
  partial_packet_.clear();
  last_page_sequence_.reset();
  buffers_.clear();
  in_media_segment_ = false;
  // A partly parsed init segment is discarded; the timeline carries on, as
  // AVStreamDataParser's does after a discontinuity.
  if (!headers_complete_) {
    ResetLogicalStream();
  }
}

bool ParcOggStreamParser::GetGenerateTimestampsFlag() const {
  return false;
}

bool ParcOggStreamParser::AppendToParseBuffer(base::span<const uint8_t> buf) {
  if (failed_) {
    return true;
  }
  CHECK_EQ(uninspected_pending_bytes_, 0);
  if (!queue_.Push(buf)) {
    return false;
  }
  uninspected_pending_bytes_ = base::checked_cast<int>(buf.size());
  return true;
}

StreamParser::ParseStatus ParcOggStreamParser::Parse(
    int max_pending_bytes_to_inspect) {
  if (failed_) {
    return ParseStatus::kFailed;
  }
  base::span<const uint8_t> data = queue_.Data();
  const int increment =
      std::min(max_pending_bytes_to_inspect, uninspected_pending_bytes_);
  uninspected_pending_bytes_ -= increment;
  data = data.first(data.size() - uninspected_pending_bytes_);

  size_t consumed = 0;
  for (;;) {
    const int result = ParsePage(data.subspan(consumed));
    if (result < 0) {
      failed_ = true;
      return ParseStatus::kFailed;
    }
    if (result == 0) {
      break;
    }
    consumed += result;
  }
  queue_.Pop(base::checked_cast<int>(consumed));

  if (!buffers_.empty() && !SendBuffers()) {
    failed_ = true;
    return ParseStatus::kFailed;
  }
  if (in_media_segment_) {
    in_media_segment_ = false;
    end_of_segment_cb_.Run();
  }
  return uninspected_pending_bytes_ > 0 ? ParseStatus::kSuccessHasMoreData
                                        : ParseStatus::kSuccess;
}

int ParcOggStreamParser::ParsePage(base::span<const uint8_t> data) {
  // Resynchronize on the next capture pattern whose page checksum holds, as
  // libogg's ogg_sync_pageseek() does. AVStreamDataParser skips any amount of
  // other data too.
  if (data.size() < kCapturePattern.size()) {
    return 0;
  }
  if (!StartsWith(data, kCapturePattern)) {
    // Stops short of a capture pattern the data may end partway into.
    size_t skip = 1;
    while (skip + kCapturePattern.size() <= data.size() &&
           !StartsWith(data.subspan(skip), kCapturePattern)) {
      ++skip;
    }
    return base::checked_cast<int>(skip);
  }
  if (data.size() < kPageHeaderSize) {
    return 0;
  }
  const size_t segments = data[26];
  if (data.size() < kPageHeaderSize + segments) {
    return 0;
  }
  Page page;
  page.lacing = data.subspan(kPageHeaderSize, segments);
  size_t body_size = 0;
  for (uint8_t lace : page.lacing) {
    body_size += lace;
  }
  const size_t page_size = kPageHeaderSize + segments + body_size;
  if (data.size() < page_size) {
    return 0;
  }
  if (data[4] != 0 || PageChecksum(data.first(page_size)) !=
                          base::U32FromLittleEndian(data.subspan<22, 4>())) {
    return 1;
  }
  page.flags = data[5];
  page.serial = base::U32FromLittleEndian(data.subspan<14, 4>());
  page.sequence = base::U32FromLittleEndian(data.subspan<18, 4>());
  page.body = data.subspan(kPageHeaderSize + segments, body_size);
  return OnPage(page) ? base::checked_cast<int>(page_size) : -1;
}

bool ParcOggStreamParser::OnPage(const Page& page) {
  if (page.flags & kFirstPage) {
    // A first page after the track's headers starts the next link of a
    // chained stream; before them, another stream of the same group.
    if (headers_complete_ || stream_ended_) {
      ResetLogicalStream();
    }
    if (!serial_ && IsIdentificationHeader(page.body)) {
      serial_ = page.serial;
    }
  }
  if (!serial_ || page.serial != *serial_ || stream_ended_) {
    return true;
  }

  // A packet continues only onto the next page; one whose start is lost is
  // dropped.
  const bool continued = page.flags & kContinuedPacket;
  if (!continued || !last_page_sequence_ ||
      page.sequence != *last_page_sequence_ + 1) {
    partial_packet_.clear();
  }
  bool dropping = continued && partial_packet_.empty();
  last_page_sequence_ = page.sequence;

  base::SpanReader body(page.body);
  for (uint8_t lace : page.lacing) {
    base::span<const uint8_t> segment = *body.Read(lace);
    if (!dropping) {
      partial_packet_.insert(partial_packet_.end(), segment.begin(),
                             segment.end());
    }
    if (lace == 255) {
      continue;
    }
    if (dropping) {
      dropping = false;
      continue;
    }
    if (!OnPacket(std::exchange(partial_packet_, {}))) {
      return false;
    }
  }
  if (page.flags & kLastPage) {
    stream_ended_ = true;
    partial_packet_.clear();
  }
  return true;
}

bool ParcOggStreamParser::OnPacket(std::vector<uint8_t> packet) {
  if (!headers_complete_) {
    // Ogg FLAC's audio starts at the first frame, even when no metadata
    // block said it was the last.
    if (codec_ != AudioCodec::kFLAC || packet.empty() || packet[0] != 0xff) {
      return OnHeaderPacket(packet);
    }
    headers_complete_ = true;
    if (!EmitConfig()) {
      return false;
    }
  }
  if (packet.empty()) {
    return true;
  }
  const std::optional<int> frames = PacketFrames(packet);
  if (!frames) {
    MEDIA_LOG(ERROR, media_log_)
        << "Invalid " << GetCodecName(codec_) << " packet in Ogg.";
    return false;
  }
  scoped_refptr<StreamParserBuffer> buffer = StreamParserBuffer::CopyFrom(
      packet, /*is_key_frame=*/true, DemuxerStream::AUDIO, kTrackId);
  buffer->set_timestamp(timestamp_helper_->GetTimestamp());
  buffer->set_duration(timestamp_helper_->GetFrameDuration(*frames));
  timestamp_helper_->AddFrames(*frames);
  buffers_.push_back(std::move(buffer));
  return true;
}

bool ParcOggStreamParser::OnHeaderPacket(base::span<const uint8_t> packet) {
  headers_.emplace_back(packet.begin(), packet.end());
  const size_t index = headers_.size() - 1;
  if (index == 0) {
    return OnIdentificationHeader(packet);
  }
  switch (codec_) {
    case AudioCodec::kOpus:
      if (!StartsWith(packet, kOpusTags)) {
        MEDIA_LOG(ERROR, media_log_) << "Ogg Opus has no OpusTags header.";
        return false;
      }
      headers_complete_ = true;
      break;
    case AudioCodec::kVorbis:
      if (packet.size() < 7 || packet[0] != 2 * index + 1 ||
          !StartsWith(packet.subspan(1u), kVorbis)) {
        MEDIA_LOG(ERROR, media_log_) << "Invalid Ogg Vorbis header.";
        return false;
      }
      if (index == 2) {
        if (!OnVorbisSetupHeader(packet)) {
          MEDIA_LOG(ERROR, media_log_) << "Invalid Vorbis setup header.";
          return false;
        }
        headers_complete_ = true;
      }
      break;
    default:
      // FLAC metadata blocks; the last one sets the top bit of its type.
      if (packet.empty()) {
        return false;
      }
      headers_complete_ = !!(packet[0] & 0x80);
  }
  return !headers_complete_ || EmitConfig();
}

bool ParcOggStreamParser::OnIdentificationHeader(
    base::span<const uint8_t> packet) {
  base::SpanReader reader(packet);
  if (StartsWith(packet, kOpusHead)) {
    // RFC 7845 section 5.1. OpusHead is the extra data Chromium's Opus
    // decoders take, with the pre-skip, output gain and channel mapping.
    uint8_t version, channels, mapping;
    uint16_t pre_skip;
    if (packet.size() < OPUS_EXTRADATA_SIZE || !reader.Skip(8u) ||
        !reader.ReadU8BigEndian(version) || (version & 0xf0) ||
        !reader.ReadU8BigEndian(channels) || !channels ||
        !reader.ReadU16LittleEndian(pre_skip)) {
      return false;
    }
    mapping = packet[OPUS_EXTRADATA_CHANNEL_MAPPING_OFFSET];
    if ((mapping == OPUS_CHANNEL_MAPPING_FAMILY_DEFAULT && channels > 2) ||
        (mapping != OPUS_CHANNEL_MAPPING_FAMILY_DEFAULT &&
         packet.size() < size_t{OPUS_EXTRADATA_STREAM_MAP_OFFSET} + channels)) {
      return false;
    }
    codec_ = AudioCodec::kOpus;
    channels_ = channels;
    sample_rate_ = kOpusDefaultSampleRate;
    pre_skip_ = pre_skip;
    return true;
  }
  if (StartsWith(packet, kOggFlac)) {
    // Ogg FLAC mapping 1.0: 0x7F "FLAC", version, header count, "fLaC", then
    // the STREAMINFO block, whose 34 bytes are FLAC's extra data.
    static constexpr auto kStreamInfoSize = std::to_array<uint8_t>({0, 0, 34});
    uint8_t major, block_type;
    if (!reader.Skip(5u) || !reader.ReadU8BigEndian(major) || major != 1 ||
        !reader.Skip(3u) || !StartsWith(reader.remaining_span(), kFlacMarker) ||
        !reader.Skip(4u) || !reader.ReadU8BigEndian(block_type) ||
        (block_type & 0x7f) != 0 ||
        !StartsWith(reader.remaining_span(), kStreamInfoSize) ||
        !reader.Skip(3u) || reader.remaining() < 34) {
      return false;
    }
    base::span<const uint8_t> stream_info = reader.remaining_span().first(34u);
    // Sample rate (20 bits), channels - 1 (3), bits per sample - 1 (5).
    const uint32_t packed =
        base::U32FromBigEndian(stream_info.subspan<10, 4>());
    sample_rate_ = packed >> 12;
    channels_ = ((packed >> 9) & 0x7) + 1;
    bits_per_sample_ = ((packed >> 4) & 0x1f) + 1;
    if (!sample_rate_) {
      return false;
    }
    codec_ = AudioCodec::kFLAC;
    headers_.back().assign(stream_info.begin(), stream_info.end());
    headers_complete_ = !!(block_type & 0x80);
    return !headers_complete_ || EmitConfig();
  }
  // Vorbis I section 4.2.2.
  uint8_t type, channels, block_sizes, framing;
  uint32_t version, sample_rate;
  if (!reader.ReadU8BigEndian(type) || type != 1 ||
      !StartsWith(reader.remaining_span(), kVorbis) || !reader.Skip(6u) ||
      !reader.ReadU32LittleEndian(version) || version ||
      !reader.ReadU8BigEndian(channels) || !channels ||
      !reader.ReadU32LittleEndian(sample_rate) || !sample_rate ||
      sample_rate > limits::kMaxSampleRate || !reader.Skip(12u) ||
      !reader.ReadU8BigEndian(block_sizes) ||
      !reader.ReadU8BigEndian(framing) || !(framing & 1)) {
    return false;
  }
  vorbis_block_sizes_[0] = 1 << (block_sizes & 0xf);
  vorbis_block_sizes_[1] = 1 << (block_sizes >> 4);
  if (vorbis_block_sizes_[0] < 64 || vorbis_block_sizes_[1] > 8192 ||
      vorbis_block_sizes_[0] > vorbis_block_sizes_[1]) {
    return false;
  }
  codec_ = AudioCodec::kVorbis;
  channels_ = channels;
  sample_rate_ = base::checked_cast<int>(sample_rate);
  return true;
}

// The modes come last in the setup header and can only be found by reading
// it backwards, as libavcodec's vorbis_parser.c does (parse_setup_header()).
bool ParcOggStreamParser::OnVorbisSetupHeader(
    base::span<const uint8_t> packet) {
  std::vector<uint8_t> reversed(packet.rbegin(), packet.rend());
  size_t framing_bits = 0;
  {
    BitReader reader(reversed);
    bool bit = false;
    while (reader.bits_available() > 97 && reader.ReadFlag(&bit) && !bit) {
    }
    if (!bit) {
      return false;
    }
    framing_bits = reader.bits_read();
    size_t mode_count = 0;
    size_t last_mode_count = 0;
    while (reader.bits_available() >= 97) {
      uint8_t mapping;
      uint16_t transform, window;
      if (!reader.ReadBits(8, &mapping) || mapping > 63 ||
          !reader.ReadBits(16, &transform) || transform ||
          !reader.ReadBits(16, &window) || window || !reader.SkipBits(1)) {
        break;
      }
      if (++mode_count > 64) {
        break;
      }
      BitReader count_reader(
          base::span(reversed).subspan(reader.bits_read() / 8));
      uint8_t count;
      if (count_reader.SkipBits(reader.bits_read() % 8) &&
          count_reader.ReadBits(6, &count) && count + 1u == mode_count) {
        last_mode_count = mode_count;
      }
    }
    if (!last_mode_count || last_mode_count > 63) {
      return false;
    }
    vorbis_mode_long_.assign(last_mode_count, false);
  }
  BitReader reader(reversed);
  if (!reader.SkipBits(framing_bits)) {
    return false;
  }
  for (size_t i = vorbis_mode_long_.size(); i-- > 0;) {
    bool flag;
    if (!reader.SkipBits(40) || !reader.ReadFlag(&flag)) {
      return false;
    }
    vorbis_mode_long_[i] = flag;
  }
  vorbis_previous_block_size_ = vorbis_block_sizes_[vorbis_mode_long_[0]];
  return true;
}

bool ParcOggStreamParser::EmitConfig() {
  std::vector<uint8_t> extra_data;
  SampleFormat sample_format = kSampleFormatPlanarF32;
  int codec_delay = 0;
  base::TimeDelta seek_preroll;
  switch (codec_) {
    case AudioCodec::kOpus:
      extra_data = headers_[0];
      sample_format = kSampleFormatF32;
      codec_delay = pre_skip_;
      seek_preroll = kOpusSeekPreroll;
      break;
    case AudioCodec::kVorbis:
      // Xiph lacing of the three headers, as WebM's CodecPrivate carries them.
      extra_data.push_back(2);
      for (size_t i = 0; i < 2; ++i) {
        size_t size = headers_[i].size();
        for (; size >= 255; size -= 255) {
          extra_data.push_back(255);
        }
        extra_data.push_back(static_cast<uint8_t>(size));
      }
      for (const auto& header : headers_) {
        extra_data.insert(extra_data.end(), header.begin(), header.end());
      }
      break;
    default:
      extra_data = headers_[0];
      // As MP4StreamParser takes FLAC's sample size.
      sample_format = bits_per_sample_ <= 8    ? kSampleFormatU8
                      : bits_per_sample_ <= 16 ? kSampleFormatS16
                      : bits_per_sample_ <= 24 ? kSampleFormatS24
                                               : kSampleFormatS32;
  }
  const ChannelLayoutConfig layout = ChannelLayoutConfig::Guess(channels_);
  if (layout.channel_layout() == CHANNEL_LAYOUT_UNSUPPORTED) {
    MEDIA_LOG(ERROR, media_log_) << "Unsupported channel count " << channels_;
    return false;
  }
  AudioDecoderConfig config;
  config.Initialize(codec_, sample_format, layout, sample_rate_, extra_data,
                    EncryptionScheme::kUnencrypted, seek_preroll, codec_delay);
  if (!config.IsValidConfig()) {
    MEDIA_LOG(ERROR, media_log_)
        << "Invalid audio decoder config: " << config.AsHumanReadableString();
    return false;
  }
  // Buffers of the previous link go out with its config, in their own media
  // segment.
  if (!buffers_.empty() && !SendBuffers()) {
    return false;
  }
  if (in_media_segment_) {
    in_media_segment_ = false;
    end_of_segment_cb_.Run();
  }
  config_ = config;
  base::TimeDelta timestamp;
  if (timestamp_helper_) {
    timestamp = timestamp_helper_->GetTimestamp();
  }
  timestamp_helper_ = std::make_unique<AudioTimestampHelper>(sample_rate_);
  timestamp_helper_->SetBaseTimestamp(timestamp);

  auto tracks = std::make_unique<MediaTracks>();
  tracks->AddAudioTrack(config_, true, kTrackId, MediaTrack::Kind("main"),
                        MediaTrack::Label(), MediaTrack::Language());
  if (!config_cb_.Run(std::move(tracks))) {
    return false;
  }
  if (init_cb_) {
    InitParameters params(kInfiniteDuration);
    params.detected_audio_track_count = 1;
    std::move(init_cb_).Run(params);
  }
  return true;
}

std::optional<int> ParcOggStreamParser::PacketFrames(
    base::span<const uint8_t> packet) {
  switch (codec_) {
    case AudioCodec::kOpus:
      return OpusPacketFrames(packet);
    case AudioCodec::kVorbis:
      return VorbisPacketFrames(packet);
    default:
      return FlacFrameBlockSize(packet);
  }
}

// av_vorbis_parse_frame_flags() in libavcodec's vorbis_parser.c, except that
// a one-mode stream's window flags follow the packet type bit, as Vorbis I
// section 4.3.1 places them.
std::optional<int> ParcOggStreamParser::VorbisPacketFrames(
    base::span<const uint8_t> packet) {
  if (packet[0] & 1) {
    return std::nullopt;
  }
  size_t mode = 0;
  size_t mode_bits = 0;
  if (vorbis_mode_long_.size() > 1) {
    while ((size_t{1} << mode_bits) < vorbis_mode_long_.size()) {
      ++mode_bits;
    }
    mode = (packet[0] >> 1) & ((1u << mode_bits) - 1);
  }
  if (mode >= vorbis_mode_long_.size()) {
    return std::nullopt;
  }
  int previous = vorbis_previous_block_size_;
  if (vorbis_mode_long_[mode]) {
    previous = vorbis_block_sizes_[(packet[0] >> (mode_bits + 1)) & 1];
  }
  const int current = vorbis_block_sizes_[vorbis_mode_long_[mode]];
  vorbis_previous_block_size_ = current;
  return (previous + current) / 4;
}

bool ParcOggStreamParser::SendBuffers() {
  if (!in_media_segment_) {
    in_media_segment_ = true;
    new_segment_cb_.Run();
  }
  BufferQueueMap buffers;
  buffers.emplace(kTrackId, std::move(buffers_));
  buffers_.clear();
  return new_buffers_cb_.Run(buffers);
}

void ParcOggStreamParser::ResetLogicalStream() {
  serial_.reset();
  stream_ended_ = false;
  last_page_sequence_.reset();
  partial_packet_.clear();
  codec_ = AudioCodec::kUnknown;
  headers_.clear();
  headers_complete_ = false;
  vorbis_mode_long_.clear();
}

}  // namespace media
