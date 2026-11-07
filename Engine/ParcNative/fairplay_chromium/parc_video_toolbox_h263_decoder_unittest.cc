// Installed by the reviewed overlay at
// //media/gpu/mac/parc_video_toolbox_h263_decoder_unittest.cc
// (media/gpu/mac:unit_tests).

#include "media/gpu/mac/parc_video_toolbox_h263_decoder.h"

#include <memory>
#include <vector>

#include "base/functional/bind.h"
#include "media/base/decoder_buffer.h"
#include "media/base/media_util.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

using testing::_;
using testing::DoAll;
using testing::ElementsAreArray;
using testing::InSequence;
using testing::SaveArg;

namespace media {

namespace {

// The starts of two QCIF H.263 pictures: picture start code, temporal
// reference, PTYPE.
constexpr uint8_t kPicture0[] = {0x00, 0x00, 0x80, 0x02, 0x08, 0x12, 0x34};
constexpr uint8_t kPicture1[] = {0x00, 0x00, 0x80, 0x06, 0x08, 0x56};

}  // namespace

class ParcVideoToolboxH263DecoderTest : public testing::Test {
 protected:
  MOCK_METHOD3(OnDecode,
               void(base::apple::ScopedCFTypeRef<CMSampleBufferRef>,
                    VideoToolboxDecompressionSessionMetadata,
                    scoped_refptr<CodecPicture>));
  MOCK_METHOD1(OnOutput, void(scoped_refptr<CodecPicture>));

  static std::vector<uint8_t> SampleData(CMSampleBufferRef sample) {
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
    std::vector<uint8_t> data(CMBlockBufferGetDataLength(block));
    CMBlockBufferCopyDataBytes(block, 0, data.size(), data.data());
    return data;
  }

  ParcVideoToolboxH263Decoder decoder_{
      std::make_unique<NullMediaLog>(),
      base::BindRepeating(&ParcVideoToolboxH263DecoderTest::OnDecode,
                          base::Unretained(this)),
      base::BindRepeating(&ParcVideoToolboxH263DecoderTest::OnOutput,
                          base::Unretained(this)),
      gfx::Size(176, 144)};
};

TEST_F(ParcVideoToolboxH263DecoderTest, EachBufferIsOneSampleAndOnePicture) {
  base::apple::ScopedCFTypeRef<CMSampleBufferRef> sample;
  VideoToolboxDecompressionSessionMetadata metadata;
  scoped_refptr<CodecPicture> decoded;
  scoped_refptr<CodecPicture> output;
  {
    InSequence sequence;
    EXPECT_CALL(*this, OnDecode(_, _, _))
        .WillOnce(DoAll(SaveArg<0>(&sample), SaveArg<1>(&metadata),
                        SaveArg<2>(&decoded)));
    EXPECT_CALL(*this, OnOutput(_)).WillOnce(SaveArg<0>(&output));
  }
  decoder_.SetStream(0, DecoderBuffer::CopyFrom(kPicture0));
  EXPECT_EQ(decoder_.Decode(), AcceleratedVideoDecoder::kRanOutOfStreamData);

  ASSERT_TRUE(sample);
  EXPECT_EQ(CMSampleBufferGetNumSamples(sample.get()), 1);
  EXPECT_EQ(CMSampleBufferGetSampleSize(sample.get(), 0), sizeof(kPicture0));
  EXPECT_THAT(SampleData(sample.get()), ElementsAreArray(kPicture0));
  CMFormatDescriptionRef format =
      CMSampleBufferGetFormatDescription(sample.get());
  EXPECT_EQ(CMFormatDescriptionGetMediaSubType(format),
            kCMVideoCodecType_H263);
  const CMVideoDimensions dimensions =
      CMVideoFormatDescriptionGetDimensions(format);
  EXPECT_EQ(dimensions.width, 176);
  EXPECT_EQ(dimensions.height, 144);
  EXPECT_TRUE(metadata.allow_software_decoding);
  EXPECT_EQ(metadata.visible_rect, gfx::Rect(176, 144));
  ASSERT_TRUE(decoded);
  EXPECT_EQ(decoded, output);
  EXPECT_EQ(decoded->visible_rect(), gfx::Rect(176, 144));

  // Nothing more until the next buffer.
  EXPECT_EQ(decoder_.Decode(), AcceleratedVideoDecoder::kRanOutOfStreamData);
}

TEST_F(ParcVideoToolboxH263DecoderTest, PicturesComeOutInDecodeOrder) {
  std::vector<scoped_refptr<CodecPicture>> decoded(2);
  std::vector<scoped_refptr<CodecPicture>> output(2);
  base::apple::ScopedCFTypeRef<CMSampleBufferRef> second;
  {
    InSequence sequence;
    EXPECT_CALL(*this, OnDecode(_, _, _)).WillOnce(SaveArg<2>(&decoded[0]));
    EXPECT_CALL(*this, OnOutput(_)).WillOnce(SaveArg<0>(&output[0]));
    EXPECT_CALL(*this, OnDecode(_, _, _))
        .WillOnce(DoAll(SaveArg<0>(&second), SaveArg<2>(&decoded[1])));
    EXPECT_CALL(*this, OnOutput(_)).WillOnce(SaveArg<0>(&output[1]));
  }
  decoder_.SetStream(0, DecoderBuffer::CopyFrom(kPicture0));
  EXPECT_EQ(decoder_.Decode(), AcceleratedVideoDecoder::kRanOutOfStreamData);
  decoder_.SetStream(1, DecoderBuffer::CopyFrom(kPicture1));
  EXPECT_EQ(decoder_.Decode(), AcceleratedVideoDecoder::kRanOutOfStreamData);

  EXPECT_EQ(decoded, output);
  EXPECT_NE(output[0], output[1]);
  EXPECT_THAT(SampleData(second.get()), ElementsAreArray(kPicture1));
  EXPECT_TRUE(decoder_.Flush());
}

TEST_F(ParcVideoToolboxH263DecoderTest, ResetDropsTheBufferAndEmptyIsSkipped) {
  EXPECT_CALL(*this, OnDecode(_, _, _)).Times(0);
  EXPECT_CALL(*this, OnOutput(_)).Times(0);
  decoder_.SetStream(0, DecoderBuffer::CopyFrom(kPicture0));
  decoder_.Reset();
  EXPECT_EQ(decoder_.Decode(), AcceleratedVideoDecoder::kRanOutOfStreamData);
  decoder_.SetStream(1, DecoderBuffer::CopyFrom({}));
  EXPECT_EQ(decoder_.Decode(), AcceleratedVideoDecoder::kRanOutOfStreamData);
}

}  // namespace media
