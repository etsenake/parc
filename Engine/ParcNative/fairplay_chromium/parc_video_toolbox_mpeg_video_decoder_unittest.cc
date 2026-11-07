// Installed by the reviewed overlay at
// //media/gpu/mac/parc_video_toolbox_mpeg_video_decoder_unittest.cc
// (media_unittests).

#include "media/gpu/mac/parc_video_toolbox_mpeg_video_decoder.h"

#include <CoreMedia/CoreMedia.h>

#include <memory>
#include <vector>

#include "base/containers/span.h"
#include "media/base/decoder_buffer.h"
#include "media/base/media_util.h"
#include "media/gpu/codec_picture.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

using testing::_;
using testing::InSequence;
using testing::SaveArg;

namespace media {

namespace {

// 64x48 MPEG-2 (main profile, 4:2:0) sequence header and extension, from
// the overlay's parc-mpeg2-video.ts.
constexpr uint8_t kSequenceHeaders[] = {
    0x00, 0x00, 0x01, 0xB3, 0x04, 0x00, 0x30, 0x33, 0xFF, 0xFF, 0xE0,
    0x10, 0x00, 0x00, 0x01, 0xB5, 0x14, 0x8A, 0x00, 0x01, 0x00, 0x00};

// A coded frame: a picture header of `picture_coding_type`, then a slice.
std::vector<uint8_t> Frame(int picture_coding_type) {
  return {0x00, 0x00, 0x01, 0x00, 0x00,
          static_cast<uint8_t>(picture_coding_type << 3 | 0x07), 0xFF, 0xF8,
          0x00, 0x00, 0x01, 0x01, 0x10, 0x20};
}

scoped_refptr<DecoderBuffer> Buffer(std::vector<uint8_t> data) {
  return DecoderBuffer::CopyFrom(data);
}

}  // namespace

class ParcVideoToolboxMpegVideoDecoderTest : public testing::Test {
 protected:
  MOCK_METHOD3(OnDecode,
               void(base::apple::ScopedCFTypeRef<CMSampleBufferRef>,
                    VideoToolboxDecompressionSessionMetadata,
                    scoped_refptr<CodecPicture>));
  MOCK_METHOD1(OnOutput, void(scoped_refptr<CodecPicture>));

  std::unique_ptr<ParcVideoToolboxMpegVideoDecoder> CreateDecoder(
      base::span<const uint8_t> extra_data) {
    return std::make_unique<ParcVideoToolboxMpegVideoDecoder>(
        std::make_unique<NullMediaLog>(),
        base::BindRepeating(&ParcVideoToolboxMpegVideoDecoderTest::OnDecode,
                            base::Unretained(this)),
        base::BindRepeating(&ParcVideoToolboxMpegVideoDecoderTest::OnOutput,
                            base::Unretained(this)),
        extra_data);
  }

  AcceleratedVideoDecoder::DecodeResult Decode(
      ParcVideoToolboxMpegVideoDecoder& decoder,
      std::vector<uint8_t> data) {
    decoder.SetStream(-1, Buffer(std::move(data)));
    return decoder.Decode();
  }
};

// The configuration's sequence header gives the sample's format; each buffer
// is one sample, in software where the Mac has no MPEG-2 hardware.
TEST_F(ParcVideoToolboxMpegVideoDecoderTest, SampleFormatFromExtraData) {
  auto decoder = CreateDecoder(kSequenceHeaders);
  base::apple::ScopedCFTypeRef<CMSampleBufferRef> sample;
  VideoToolboxDecompressionSessionMetadata metadata;
  EXPECT_CALL(*this, OnDecode(_, _, _))
      .WillOnce(testing::DoAll(SaveArg<0>(&sample), SaveArg<1>(&metadata)));
  EXPECT_EQ(Decode(*decoder, Frame(1)),
            AcceleratedVideoDecoder::kRanOutOfStreamData);

  ASSERT_TRUE(sample);
  CMFormatDescriptionRef format =
      CMSampleBufferGetFormatDescription(sample.get());
  EXPECT_EQ(CMFormatDescriptionGetMediaSubType(format),
            kCMVideoCodecType_MPEG2Video);
  const CMVideoDimensions dimensions =
      CMVideoFormatDescriptionGetDimensions(format);
  EXPECT_EQ(dimensions.width, 64);
  EXPECT_EQ(dimensions.height, 48);
  EXPECT_EQ(CMSampleBufferGetTotalSampleSize(sample.get()), Frame(1).size());
  EXPECT_TRUE(metadata.allow_software_decoding);
  EXPECT_EQ(metadata.chroma_sampling, VideoChromaSampling::k420);
  EXPECT_EQ(metadata.visible_rect, gfx::Rect(64, 48));
  EXPECT_EQ(decoder->GetPicSize(), gfx::Size(64, 48));
}

// A sequence header without a sequence_extension is MPEG-1.
TEST_F(ParcVideoToolboxMpegVideoDecoderTest, Mpeg1InBandSequenceHeader) {
  auto decoder = CreateDecoder({});
  // Nothing decodes before a sequence header.
  EXPECT_CALL(*this, OnDecode(_, _, _)).Times(0);
  EXPECT_EQ(Decode(*decoder, Frame(1)),
            AcceleratedVideoDecoder::kRanOutOfStreamData);
  testing::Mock::VerifyAndClearExpectations(this);

  std::vector<uint8_t> data(std::begin(kSequenceHeaders),
                            std::begin(kSequenceHeaders) + 12);
  const std::vector<uint8_t> frame = Frame(1);
  data.insert(data.end(), frame.begin(), frame.end());
  base::apple::ScopedCFTypeRef<CMSampleBufferRef> sample;
  EXPECT_CALL(*this, OnDecode(_, _, _)).WillOnce(SaveArg<0>(&sample));
  EXPECT_EQ(Decode(*decoder, data),
            AcceleratedVideoDecoder::kRanOutOfStreamData);
  ASSERT_TRUE(sample);
  EXPECT_EQ(CMFormatDescriptionGetMediaSubType(
                CMSampleBufferGetFormatDescription(sample.get())),
            kCMVideoCodecType_MPEG1Video);
}

// Decode order I P B B P, display order I B B P P: each I- or P-picture is
// output when the next one decodes, or at a flush; B-pictures right away.
TEST_F(ParcVideoToolboxMpegVideoDecoderTest, OutputsInDisplayOrder) {
  auto decoder = CreateDecoder(kSequenceHeaders);
  std::vector<scoped_refptr<CodecPicture>> decoded;
  std::vector<scoped_refptr<CodecPicture>> output;
  EXPECT_CALL(*this, OnDecode(_, _, _))
      .WillRepeatedly([&](auto, auto, scoped_refptr<CodecPicture> picture) {
        decoded.push_back(std::move(picture));
      });
  EXPECT_CALL(*this, OnOutput(_))
      .WillRepeatedly([&](scoped_refptr<CodecPicture> picture) {
        output.push_back(std::move(picture));
      });

  for (int type : {1, 2, 3, 3, 2}) {
    EXPECT_EQ(Decode(*decoder, Frame(type)),
              AcceleratedVideoDecoder::kRanOutOfStreamData);
  }
  ASSERT_EQ(decoded.size(), 5u);
  EXPECT_EQ(output, (std::vector<scoped_refptr<CodecPicture>>{
                        decoded[0], decoded[2], decoded[3], decoded[1]}));
  EXPECT_TRUE(decoder->Flush());
  ASSERT_EQ(output.size(), 5u);
  EXPECT_EQ(output[4], decoded[4]);

  // Reset drops the held picture.
  EXPECT_EQ(Decode(*decoder, Frame(1)),
            AcceleratedVideoDecoder::kRanOutOfStreamData);
  decoder->Reset();
  EXPECT_TRUE(decoder->Flush());
  EXPECT_EQ(output.size(), 5u);
}

}  // namespace media
