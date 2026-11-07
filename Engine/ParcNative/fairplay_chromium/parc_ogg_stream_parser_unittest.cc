// Installed by the reviewed overlay at
// //media/formats/ogg/parc_ogg_stream_parser_unittest.cc (media_unittests).
// Expected timestamps are those AVStreamDataParser gives the same bytes on
// macOS 27 (Safari's Media Source).

#include "media/formats/ogg/parc_ogg_stream_parser.h"

#include <algorithm>
#include <array>
#include <memory>
#include <string>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "media/base/audio_timestamp_helper.h"
#include "media/base/decoder_buffer.h"
#include "media/base/media_tracks.h"
#include "media/base/media_util.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/test_data_util.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {
namespace {

struct ParsedBuffer {
  base::TimeDelta timestamp;
  base::TimeDelta duration;
  size_t size;
};

class ParcOggStreamParserTest : public testing::Test {
 protected:
  ParcOggStreamParserTest() {
    parser_.Init(base::BindOnce(&ParcOggStreamParserTest::OnInit,
                                base::Unretained(this)),
                 base::BindRepeating(&ParcOggStreamParserTest::OnConfig,
                                     base::Unretained(this)),
                 base::BindRepeating(&ParcOggStreamParserTest::OnBuffers,
                                     base::Unretained(this)),
                 base::DoNothing(),
                 base::BindRepeating(&ParcOggStreamParserTest::OnEvent,
                                     base::Unretained(this), "{"),
                 base::BindRepeating(&ParcOggStreamParserTest::OnEvent,
                                     base::Unretained(this), "}"),
                 &media_log_);
  }

  // Appends `data` `chunk` bytes at a time, parsing each append fully.
  bool Append(base::span<const uint8_t> data, size_t chunk = 0) {
    if (!chunk) {
      chunk = data.size();
    }
    for (size_t offset = 0; offset < data.size(); offset += chunk) {
      if (!parser_.AppendToParseBuffer(
              data.subspan(offset, std::min(chunk, data.size() - offset)))) {
        return false;
      }
      StreamParser::ParseStatus status;
      do {
        status = parser_.Parse(StreamParser::kMaxPendingBytesPerParse);
      } while (status == StreamParser::ParseStatus::kSuccessHasMoreData);
      if (status == StreamParser::ParseStatus::kFailed) {
        return false;
      }
    }
    return true;
  }

  static int64_t Frames(base::TimeDelta time, int sample_rate) {
    return AudioTimestampHelper::TimeToFrames(time, sample_rate);
  }

  void OnInit(const StreamParser::InitParameters& params) {
    EXPECT_EQ(params.duration, kInfiniteDuration);
    EXPECT_EQ(params.detected_audio_track_count, 1);
    events_ += "init";
  }

  bool OnConfig(std::unique_ptr<MediaTracks> tracks) {
    EXPECT_EQ(tracks->tracks().size(), 1u);
    configs_.push_back(
        tracks->getAudioConfig(tracks->tracks()[0]->stream_id()));
    events_ += "config";
    return true;
  }

  bool OnBuffers(const StreamParser::BufferQueueMap& map) {
    EXPECT_EQ(map.size(), 1u);
    if (map.empty()) {
      return false;
    }
    for (const auto& buffer : map.begin()->second) {
      EXPECT_TRUE(buffer->is_key_frame());
      EXPECT_EQ(buffer->type(), DemuxerStream::AUDIO);
      buffers_.push_back(
          {buffer->timestamp(), buffer->duration(), buffer->size()});
    }
    events_ += "buffers";
    return true;
  }

  void OnEvent(const char* event) { events_ += event; }

  NullMediaLog media_log_;
  ParcOggStreamParser parser_;
  std::vector<AudioDecoderConfig> configs_;
  std::vector<ParsedBuffer> buffers_;
  std::string events_;
};

TEST_F(ParcOggStreamParserTest, Opus) {
  scoped_refptr<DecoderBuffer> file = ReadTestDataFile("sfx-opus.ogg");
  ASSERT_TRUE(Append(*file));
  EXPECT_FALSE(parser_.GetGenerateTimestampsFlag());
  EXPECT_EQ(events_, "configinit{buffers}");

  ASSERT_EQ(configs_.size(), 1u);
  const AudioDecoderConfig& config = configs_[0];
  EXPECT_EQ(config.codec(), AudioCodec::kOpus);
  EXPECT_EQ(config.samples_per_second(), 48000);
  EXPECT_EQ(config.channels(), 1);
  EXPECT_EQ(config.codec_delay(), 312);
  EXPECT_EQ(config.seek_preroll(), base::Milliseconds(80));
  // The OpusHead packet: version, channels, pre-skip, rate, gain, mapping.
  EXPECT_EQ(base::span(config.extra_data()), file->subspan(28u, 19u));

  ASSERT_EQ(buffers_.size(), 15u);
  for (int i = 0; i < 15; ++i) {
    EXPECT_EQ(Frames(buffers_[i].timestamp, 48000), 960 * i);
    EXPECT_EQ(Frames(buffers_[i].duration, 48000), 960);
  }
  EXPECT_EQ(buffers_[0].size, 314u);
}

TEST_F(ParcOggStreamParserTest, Vorbis) {
  ASSERT_TRUE(Append(*ReadTestDataFile("sfx.ogg")));
  ASSERT_EQ(configs_.size(), 1u);
  const AudioDecoderConfig& config = configs_[0];
  EXPECT_EQ(config.codec(), AudioCodec::kVorbis);
  EXPECT_EQ(config.samples_per_second(), 44100);
  EXPECT_EQ(config.channels(), 1);
  // Xiph lacing of the 30, 156 and 3077 byte headers.
  ASSERT_EQ(config.extra_data().size(), 3u + 30 + 156 + 3077);
  EXPECT_EQ(config.extra_data()[0], 2);
  EXPECT_EQ(config.extra_data()[1], 30);
  EXPECT_EQ(config.extra_data()[2], 156);
  EXPECT_EQ(config.extra_data()[3], 1);

  // Short then long blocks: 128, 576, then 1024 frames each.
  ASSERT_EQ(buffers_.size(), 17u);
  EXPECT_EQ(buffers_[0].timestamp, base::TimeDelta());
  EXPECT_EQ(Frames(buffers_[0].duration, 44100), 128);
  EXPECT_EQ(Frames(buffers_[1].timestamp, 44100), 128);
  EXPECT_EQ(Frames(buffers_[1].duration, 44100), 576);
  EXPECT_EQ(Frames(buffers_[2].timestamp, 44100), 704);
  EXPECT_EQ(Frames(buffers_[16].timestamp, 44100), 704 + 14 * 1024);
  EXPECT_EQ(Frames(buffers_[16].duration, 44100), 1024);
}

TEST_F(ParcOggStreamParserTest, Flac) {
  ASSERT_TRUE(Append(*ReadTestDataFile("bear-flac.ogg")));
  ASSERT_EQ(configs_.size(), 1u);
  const AudioDecoderConfig& config = configs_[0];
  EXPECT_EQ(config.codec(), AudioCodec::kFLAC);
  EXPECT_EQ(config.samples_per_second(), 8000);
  EXPECT_EQ(config.channels(), 1);
  EXPECT_EQ(config.sample_format(), kSampleFormatS16);
  // The STREAMINFO block.
  EXPECT_EQ(config.extra_data().size(), 34u);

  ASSERT_EQ(buffers_.size(), 15u);
  for (int i = 0; i < 14; ++i) {
    EXPECT_EQ(Frames(buffers_[i].timestamp, 8000), 576 * i);
    EXPECT_EQ(Frames(buffers_[i].duration, 8000), 576);
  }
  // The last frame's header names its own block size.
  EXPECT_EQ(Frames(buffers_[14].timestamp, 8000), 576 * 14);
  EXPECT_EQ(Frames(buffers_[14].duration, 8000), 471);
}

// Each append is its own media segment, and parses as one append does.
TEST_F(ParcOggStreamParserTest, SmallAppends) {
  ASSERT_TRUE(Append(*ReadTestDataFile("sfx.ogg"), 7));
  ASSERT_EQ(configs_.size(), 1u);
  ASSERT_EQ(buffers_.size(), 17u);
  EXPECT_EQ(Frames(buffers_[16].timestamp, 44100), 704 + 14 * 1024);
  EXPECT_EQ(events_.find("{}"), std::string::npos);
}

// A chained stream's second link is a new init segment on the same timeline.
TEST_F(ParcOggStreamParserTest, ChainedLinks) {
  ASSERT_TRUE(Append(*ReadTestDataFile("double-sfx.ogg")));
  EXPECT_EQ(configs_.size(), 2u);
  ASSERT_EQ(buffers_.size(), 34u);
  EXPECT_EQ(Frames(buffers_[17].timestamp, 44100), 16064);
}

// Granule positions don't place samples: data starting mid-stream begins at
// 0, and later pages follow on whatever pages were skipped.
TEST_F(ParcOggStreamParserTest, CountsFromZeroWithoutGranules) {
  scoped_refptr<DecoderBuffer> file =
      ReadTestDataFile("opus-trimming-test.ogg");
  // Pages start at 0, 47, 313, 1575, 2796, 3994, 5186, 6370 and 7347; each
  // audio page holds two 120 ms packets.
  ASSERT_TRUE(Append(file->first(313u)));
  ASSERT_TRUE(Append(file->subspan(3994u, 5186u - 3994u)));
  ASSERT_TRUE(Append(file->subspan(6370u, 7347u - 6370u)));
  ASSERT_EQ(buffers_.size(), 4u);
  for (int i = 0; i < 4; ++i) {
    EXPECT_EQ(Frames(buffers_[i].timestamp, 48000), 5760 * i);
  }
  EXPECT_EQ(buffers_[2].size, 583u);
}

// abort() drops a partial page, so its rest is skipped; the timeline carries
// on.
TEST_F(ParcOggStreamParserTest, FlushDropsPartialPage) {
  scoped_refptr<DecoderBuffer> file =
      ReadTestDataFile("opus-trimming-test.ogg");
  ASSERT_TRUE(Append(file->first(2796u)));
  ASSERT_TRUE(Append(file->subspan(2796u, 250u)));
  ASSERT_EQ(buffers_.size(), 4u);
  parser_.Flush();
  ASSERT_TRUE(Append(file->subspan(3046u, 3994u - 3046u)));
  EXPECT_EQ(buffers_.size(), 4u);
  ASSERT_TRUE(Append(file->subspan(5186u, 6370u - 5186u)));
  ASSERT_EQ(configs_.size(), 1u);
  ASSERT_EQ(buffers_.size(), 6u);
  EXPECT_EQ(Frames(buffers_[4].timestamp, 48000), 4 * 5760);
  EXPECT_EQ(buffers_[4].size, 579u);
  EXPECT_EQ(buffers_[5].size, 572u);
}

// abort() in the middle of the init segment discards it.
TEST_F(ParcOggStreamParserTest, FlushDropsPartialInitSegment) {
  scoped_refptr<DecoderBuffer> file = ReadTestDataFile("sfx-opus.ogg");
  ASSERT_TRUE(Append(file->first(60u)));
  parser_.Flush();
  ASSERT_TRUE(Append(*file));
  EXPECT_EQ(configs_.size(), 1u);
  EXPECT_EQ(buffers_.size(), 15u);
}

// One Ogg page holding `packet`, with its checksum (RFC 3533).
std::vector<uint8_t> OggPage(uint32_t serial,
                             uint8_t flags,
                             uint32_t sequence,
                             const std::vector<uint8_t>& packet) {
  std::vector<uint8_t> page = {'O', 'g', 'g', 'S', 0, flags};
  page.resize(14);
  for (uint32_t value : {serial, sequence}) {
    for (int i = 0; i < 4; ++i) {
      page.push_back(static_cast<uint8_t>(value >> (8 * i)));
    }
  }
  page.resize(26);
  std::vector<uint8_t> lacing(packet.size() / 255, 255);
  lacing.push_back(packet.size() % 255);
  page.push_back(static_cast<uint8_t>(lacing.size()));
  page.insert(page.end(), lacing.begin(), lacing.end());
  page.insert(page.end(), packet.begin(), packet.end());
  uint32_t crc = 0;
  for (uint8_t byte : page) {
    crc ^= static_cast<uint32_t>(byte) << 24;
    for (int bit = 0; bit < 8; ++bit) {
      crc = (crc & 0x80000000u) ? (crc << 1) ^ 0x04c11db7u : crc << 1;
    }
  }
  for (int i = 0; i < 4; ++i) {
    page[22 + i] = static_cast<uint8_t>(crc >> (8 * i));
  }
  return page;
}

// Header and frame fields a page controls fail the append; they don't crash.
TEST_F(ParcOggStreamParserTest, VorbisSampleRateOutOfRangeFails) {
  std::vector<uint8_t> header = {1, 'v', 'o', 'r', 'b',  'i',  's',  0,
                                 0, 0,   0,   1,   0xff, 0xff, 0xff, 0xff};
  header.resize(28);
  header.insert(header.end(), {0xb8, 0x01});
  EXPECT_FALSE(Append(OggPage(1, /*flags=*/0x02, 0, header)));
  EXPECT_TRUE(configs_.empty());
}

TEST_F(ParcOggStreamParserTest, ShortFlacFrameHeaderFails) {
  scoped_refptr<DecoderBuffer> file = ReadTestDataFile("bear-flac.ogg");
  // The header pages end at 226; this frame header names a 16-bit block
  // size after a 7-byte frame number, then ends.
  ASSERT_TRUE(Append(file->first(226u)));
  ASSERT_EQ(configs_.size(), 1u);
  // bear-flac.ogg's serial, so the page belongs to the track.
  EXPECT_FALSE(Append(
      OggPage(0xdee47fb2, /*flags=*/0, 2, {0xff, 0xf8, 0x70, 0x00, 0xfe})));
  EXPECT_TRUE(buffers_.empty());
}

// The two streams' pages interleaved as one group, after junk:
// sfx-opus.ogg's pages start at 0, 47 and 163, sfx.ogg's at 0, 58 and 3332.
std::vector<uint8_t> GroupedStreams(bool opus_first) {
  scoped_refptr<DecoderBuffer> opus = ReadTestDataFile("sfx-opus.ogg");
  scoped_refptr<DecoderBuffer> vorbis = ReadTestDataFile("sfx.ogg");
  const std::vector<base::span<const uint8_t>> opus_pages = {
      opus->first(47u), opus->subspan(47u, 116u),
      base::span(*opus).subspan(163u)};
  const std::vector<base::span<const uint8_t>> vorbis_pages = {
      vorbis->first(58u), vorbis->subspan(58u, 3274u),
      base::span(*vorbis).subspan(3332u)};
  std::vector<uint8_t> grouped(1000, 0x5a);
  for (size_t i = 0; i < 3; ++i) {
    for (base::span<const uint8_t> page :
         opus_first ? std::to_array({opus_pages[i], vorbis_pages[i]})
                    : std::to_array({vorbis_pages[i], opus_pages[i]})) {
      grouped.insert(grouped.end(), page.begin(), page.end());
    }
  }
  return grouped;
}

// The first Opus, Vorbis or FLAC stream of a group is the track; the other
// streams, and data that isn't an Ogg page, are skipped.
TEST_F(ParcOggStreamParserTest, FirstAudioStreamOfGroupIsVorbis) {
  ASSERT_TRUE(Append(GroupedStreams(/*opus_first=*/false)));
  ASSERT_EQ(configs_.size(), 1u);
  EXPECT_EQ(configs_[0].codec(), AudioCodec::kVorbis);
  EXPECT_EQ(buffers_.size(), 17u);
}

TEST_F(ParcOggStreamParserTest, FirstAudioStreamOfGroupIsOpus) {
  ASSERT_TRUE(Append(GroupedStreams(/*opus_first=*/true)));
  ASSERT_EQ(configs_.size(), 1u);
  EXPECT_EQ(configs_[0].codec(), AudioCodec::kOpus);
  EXPECT_EQ(buffers_.size(), 15u);
}

}  // namespace
}  // namespace media
