// Installed by the reviewed overlay at
// //media/formats/mp2t/parc_es_parser_mpeg_video_unittest.cc
// (media_unittests).

#include "media/formats/mp2t/parc_es_parser_mpeg_video.h"

#include <stdint.h>

#include <vector>

#include "base/functional/bind.h"
#include "base/time/time.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/video_aspect_ratio.h"
#include "media/base/video_decoder_config.h"
#include "media/formats/mp2t/es_parser_test_base.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "ui/gfx/geometry/size.h"

namespace media::mp2t {
namespace {

constexpr int kIntra = 1;
constexpr int kPredictive = 2;
constexpr int kBidirectional = 3;
constexpr int kFrame = 3;
constexpr int kTopField = 1;
constexpr int kBottomField = 2;

// Builds an MPEG-1 or MPEG-2 video elementary stream from the headers this
// parser reads; slices are a few placeholder bytes.
class StreamWriter {
 public:
  void SequenceHeader(int width, int height, int aspect_ratio_code) {
    // 25 frames per second, then bit_rate, vbv_buffer_size and flags.
    Unit(0xB3, {static_cast<uint8_t>(width >> 4),
                static_cast<uint8_t>((width & 0x0F) << 4 | height >> 8),
                static_cast<uint8_t>(height & 0xFF),
                static_cast<uint8_t>(aspect_ratio_code << 4 | 3), 0xFF, 0xFF,
                0xE0, 0x18});
  }
  // Main profile at main level, 4:2:0, progressive or interlaced.
  void SequenceExtension(bool progressive = true) {
    Unit(0xB5, {0x14, static_cast<uint8_t>(progressive ? 0x8A : 0x82), 0x00,
                0x01, 0x00, 0x00});
  }
  void GroupOfPictures(bool closed) {
    Unit(0xB8, {0x00, 0x08, 0x00, static_cast<uint8_t>(closed ? 0x40 : 0)});
  }
  void Picture(int temporal_reference, int type) {
    Unit(0x00, {static_cast<uint8_t>(temporal_reference >> 2),
                static_cast<uint8_t>((temporal_reference & 3) << 6 |
                                     type << 3 | 0x07),
                0xFF, 0xF8});
  }
  // A progressive frame, or a field of an interlaced frame.
  void PictureCodingExtension(int picture_structure) {
    const bool frame = picture_structure == kFrame;
    Unit(0xB5, {0x8F, 0xFF, static_cast<uint8_t>(0xF0 | picture_structure),
                static_cast<uint8_t>(frame ? 0x80 : 0x00),
                static_cast<uint8_t>(frame ? 0x80 : 0x00)});
  }
  void Slice() { Unit(0x01, {0x10, 0x20, 0x30}); }
  void UserData() { Unit(0xB2, {0x47, 0x41, 0x39, 0x34}); }

  // Starts a PES packet here, with `pts` in milliseconds.
  void Pes(int pts) {
    EsParserTestBase::Packet packet;
    packet.offset = stream.size();
    packet.pts = base::Milliseconds(pts);
    packets.push_back(packet);
  }

  std::vector<uint8_t> stream;
  std::vector<EsParserTestBase::Packet> packets;

 private:
  void Unit(uint8_t code, std::vector<uint8_t> bytes) {
    stream.insert(stream.end(), {0x00, 0x00, 0x01, code});
    stream.insert(stream.end(), bytes.begin(), bytes.end());
  }
};

class ParcEsParserMpegVideoTest : public EsParserTestBase,
                                  public testing::Test {
 protected:
  bool Process(StreamWriter& writer) {
    stream_ = writer.stream;
    ComputePacketSize(&writer.packets);
    ParcEsParserMpegVideo es_parser(
        base::BindRepeating(&ParcEsParserMpegVideoTest::OnVideoConfig,
                            base::Unretained(this)),
        base::BindRepeating(&ParcEsParserMpegVideoTest::OnBuffer,
                            base::Unretained(this)));
    return ProcessPesPackets(&es_parser, writer.packets, false);
  }

  void OnVideoConfig(const VideoDecoderConfig& config) {
    config_ = config;
    NewVideoConfig(config);
  }

  void OnBuffer(scoped_refptr<StreamParserBuffer> buffer) {
    buffers_.push_back(buffer);
    EmitBuffer(std::move(buffer));
  }

  // The configuration of one closed GOP's I-picture in a sequence of this
  // size and aspect_ratio_information.
  VideoDecoderConfig ConfigFor(int width,
                               int height,
                               int aspect_ratio_code,
                               bool mpeg2) {
    StreamWriter writer;
    writer.Pes(0);
    writer.SequenceHeader(width, height, aspect_ratio_code);
    if (mpeg2) {
      writer.SequenceExtension();
    }
    writer.GroupOfPictures(/*closed=*/true);
    writer.Picture(0, kIntra);
    if (mpeg2) {
      writer.PictureCodingExtension(kFrame);
    }
    writer.Slice();
    config_ = VideoDecoderConfig();
    EXPECT_TRUE(Process(writer));
    return config_;
  }

  VideoDecoderConfig config_;
  std::vector<scoped_refptr<StreamParserBuffer>> buffers_;
};

// Both field pictures of a frame are one sample, as AVStreamDataParser gives
// them; the configuration's extra data is the sequence header and extension.
TEST_F(ParcEsParserMpegVideoTest, FieldPairIsOneFrame) {
  StreamWriter writer;
  writer.Pes(1000);
  writer.SequenceHeader(720, 576, 3);
  writer.SequenceExtension(/*progressive=*/false);
  writer.GroupOfPictures(/*closed=*/true);
  writer.Picture(0, kIntra);
  writer.PictureCodingExtension(kTopField);
  writer.Slice();
  // A PES packet starting at the second field times that field, not the
  // next frame, which is timed from the frame rate.
  writer.Pes(1020);
  writer.Picture(0, kPredictive);
  writer.PictureCodingExtension(kBottomField);
  writer.Slice();
  const size_t first_frame_size = writer.stream.size();
  writer.Picture(1, kPredictive);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();

  // A field whose partner is missing stays alone when a header follows it;
  // the closed GOP's I-picture is still a key frame.
  writer.Pes(1080);
  writer.Picture(2, kPredictive);
  writer.PictureCodingExtension(kTopField);
  writer.Slice();
  writer.Pes(1120);
  writer.GroupOfPictures(/*closed=*/true);
  writer.Picture(0, kIntra);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();

  ASSERT_TRUE(Process(writer));
  EXPECT_EQ(config_count_, 1u);
  EXPECT_EQ(config_.codec(), VideoCodec::kMPEG2);
  EXPECT_EQ(config_.coded_size(), gfx::Size(720, 576));
  EXPECT_EQ(config_.extra_data(),
            std::vector<uint8_t>(writer.stream.begin(),
                                 writer.stream.begin() + 22));
  ASSERT_EQ(buffers_.size(), 4u);
  EXPECT_EQ(buffers_[0]->size(), first_frame_size);
  EXPECT_TRUE(buffers_[0]->is_key_frame());
  EXPECT_EQ(buffers_[0]->timestamp(), base::Milliseconds(1000));
  EXPECT_FALSE(buffers_[1]->is_key_frame());
  EXPECT_EQ(buffers_[1]->timestamp(), base::Milliseconds(1040));
  EXPECT_FALSE(buffers_[2]->is_key_frame());
  EXPECT_EQ(buffers_[2]->timestamp(), base::Milliseconds(1080));
  EXPECT_TRUE(buffers_[3]->is_key_frame());
  EXPECT_EQ(buffers_[3]->timestamp(), base::Milliseconds(1120));
}

// AVStreamDataParser marks only an I-picture after a closed GOP's header as a
// sync sample: not one in an open GOP, nor one without a GOP header.
TEST_F(ParcEsParserMpegVideoTest, KeyFramesOnlyAtClosedGops) {
  StreamWriter writer;
  writer.Pes(1000);
  writer.SequenceHeader(64, 48, 2);
  writer.SequenceExtension();
  writer.GroupOfPictures(/*closed=*/true);
  writer.Picture(0, kIntra);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();
  writer.Pes(1040);
  writer.Picture(1, kIntra);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();
  writer.Pes(1080);
  writer.SequenceHeader(64, 48, 2);
  writer.SequenceExtension();
  writer.UserData();
  writer.GroupOfPictures(/*closed=*/false);
  writer.Picture(0, kIntra);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();
  writer.Pes(1120);
  writer.GroupOfPictures(/*closed=*/true);
  writer.Picture(0, kIntra);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();

  ASSERT_TRUE(Process(writer));
  // A repeated sequence header with user data after it changes nothing.
  EXPECT_EQ(config_count_, 1u);
  ASSERT_EQ(buffers_.size(), 4u);
  EXPECT_TRUE(buffers_[0]->is_key_frame());
  EXPECT_FALSE(buffers_[1]->is_key_frame());
  EXPECT_FALSE(buffers_[2]->is_key_frame());
  EXPECT_TRUE(buffers_[3]->is_key_frame());
}

// Joining mid-stream: the PES packet's timestamp belongs to a picture before
// the first sequence header, so the closed GOP's I-picture after it waits for
// the GOP's next timestamp, as AVStreamDataParser times it (I at 1920/1800).
TEST_F(ParcEsParserMpegVideoTest, TimesPicturesBeforeTheFirstTimestamp) {
  StreamWriter writer;
  writer.Pes(1760);
  writer.Picture(8, kBidirectional);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();
  writer.SequenceHeader(64, 48, 2);
  writer.SequenceExtension();
  writer.GroupOfPictures(/*closed=*/true);
  writer.Picture(2, kIntra);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();
  writer.Pes(1840);
  writer.Picture(0, kBidirectional);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();
  writer.Pes(1880);
  writer.Picture(1, kBidirectional);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();

  ASSERT_TRUE(Process(writer));
  EXPECT_EQ(buffer_timestamps_, "(1920) (1840) (1880)");
  ASSERT_EQ(buffers_.size(), 3u);
  EXPECT_TRUE(buffers_[0]->is_key_frame());
  EXPECT_EQ(buffers_[0]->GetDecodeTimestamp(),
            DecodeTimestamp::FromMilliseconds(1800));
}

// A field whose partner is missing, then a frame: two samples.
TEST_F(ParcEsParserMpegVideoTest, LoneFieldBeforeFrame) {
  StreamWriter writer;
  writer.Pes(1000);
  writer.SequenceHeader(720, 576, 2);
  writer.SequenceExtension(/*progressive=*/false);
  writer.GroupOfPictures(/*closed=*/true);
  writer.Picture(0, kIntra);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();
  writer.Pes(1040);
  writer.Picture(1, kPredictive);
  writer.PictureCodingExtension(kTopField);
  writer.Slice();
  writer.Pes(1080);
  writer.Picture(2, kPredictive);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();

  ASSERT_TRUE(Process(writer));
  EXPECT_EQ(buffer_timestamps_, "(1000) (1040) (1080)");
}

// Headers with no picture after them are dropped; the sample starts at the
// last sequence header.
TEST_F(ParcEsParserMpegVideoTest, HeadersWithoutPictureStartOver) {
  StreamWriter writer;
  writer.Pes(1000);
  writer.SequenceHeader(64, 48, 2);
  writer.GroupOfPictures(/*closed=*/false);
  writer.SequenceHeader(64, 48, 2);
  const size_t sample_start = writer.stream.size() - 12;
  writer.SequenceExtension();
  writer.GroupOfPictures(/*closed=*/true);
  writer.Picture(0, kIntra);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();

  ASSERT_TRUE(Process(writer));
  ASSERT_EQ(buffers_.size(), 1u);
  EXPECT_EQ(buffers_[0]->size(), writer.stream.size() - sample_start);
  EXPECT_TRUE(buffers_[0]->is_key_frame());

  // A repeated GOP header keeps the sequence header before it as the
  // configuration.
  StreamWriter doubled_gop;
  doubled_gop.Pes(1000);
  doubled_gop.SequenceHeader(64, 48, 2);
  doubled_gop.SequenceExtension();
  doubled_gop.GroupOfPictures(/*closed=*/false);
  doubled_gop.GroupOfPictures(/*closed=*/true);
  doubled_gop.Picture(0, kIntra);
  doubled_gop.PictureCodingExtension(kFrame);
  doubled_gop.Slice();
  buffers_.clear();
  ASSERT_TRUE(Process(doubled_gop));
  EXPECT_EQ(config_count_, 1u);
  EXPECT_EQ(config_.extra_data().size(), 22u);
  ASSERT_EQ(buffers_.size(), 1u);
  EXPECT_TRUE(buffers_[0]->is_key_frame());
}

// Pictures sharing a PES packet are a frame apart, as AVStreamDataParser
// times them, also the first of a GOP. (Mp2tStreamParserTest's
// parc-mpeg2-video-shared-pes.ts has B-pictures too.)
TEST_F(ParcEsParserMpegVideoTest, TimesPicturesWithoutTimestamps) {
  StreamWriter writer;
  writer.Pes(1000);
  writer.SequenceHeader(64, 48, 2);
  writer.SequenceExtension();
  writer.GroupOfPictures(/*closed=*/true);
  for (int temporal_reference : {0, 1, 2}) {
    writer.Picture(temporal_reference,
                   temporal_reference ? kPredictive : kIntra);
    writer.PictureCodingExtension(kFrame);
    writer.Slice();
  }
  writer.GroupOfPictures(/*closed=*/true);
  writer.Picture(0, kIntra);
  writer.PictureCodingExtension(kFrame);
  writer.Slice();

  ASSERT_TRUE(Process(writer));
  EXPECT_EQ(buffer_timestamps_, "(1000) (1040) (1080) (1120)");
  ASSERT_EQ(buffers_.size(), 4u);
  EXPECT_EQ(buffers_[3]->GetDecodeTimestamp(),
            DecodeTimestamp::FromMilliseconds(1120));
  EXPECT_TRUE(buffers_[3]->is_key_frame());
}

// The pixel aspect ratios AVStreamDataParser gives (macOS 27.2).
TEST_F(ParcEsParserMpegVideoTest, PixelAspectRatios) {
  struct {
    int width;
    int height;
    int code;
    bool mpeg2;
    VideoAspectRatio expected;
  } cases[] = {
      {720, 576, 2, true, VideoAspectRatio::PAR(59, 54)},
      {720, 576, 3, true, VideoAspectRatio::PAR(118, 81)},
      {720, 576, 4, true, VideoAspectRatio::PAR(221 * 576, 100 * 720)},
      {720, 480, 2, true, VideoAspectRatio::PAR(10, 11)},
      {720, 480, 3, true, VideoAspectRatio::PAR(40, 33)},
      {704, 576, 2, true, VideoAspectRatio::PAR(4 * 576, 3 * 704)},
      {1440, 1080, 3, true, VideoAspectRatio::PAR(4, 3)},
      {1920, 1080, 3, true, VideoAspectRatio::PAR(1, 1)},
      {720, 576, 1, true, VideoAspectRatio::PAR(1, 1)},
      {720, 576, 5, true, VideoAspectRatio::PAR(1, 1)},
      {352, 240, 12, false, VideoAspectRatio::PAR(10, 11)},
      {352, 240, 6, false, VideoAspectRatio::PAR(33, 40)},
      {320, 240, 2, false, VideoAspectRatio::PAR(49, 33)},
      {320, 240, 15, false, VideoAspectRatio::PAR(1, 1)},
      {352, 288, 1, false, VideoAspectRatio::PAR(59, 54)},
  };
  for (const auto& test : cases) {
    SCOPED_TRACE(testing::Message() << test.width << "x" << test.height
                                    << " code " << test.code);
    const VideoDecoderConfig config =
        ConfigFor(test.width, test.height, test.code, test.mpeg2);
    EXPECT_EQ(config.aspect_ratio(), test.expected);
  }
}

}  // namespace
}  // namespace media::mp2t
