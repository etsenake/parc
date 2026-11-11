// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/video_decoder_config_mojom_traits_test.cc.
// The test is derived from Chromium's matching unittest (Chromium Authors;
// BSD-style license in Chromium's LICENSE).

#include "media/mojo/mojom/video_decoder_config_mojom_traits.h"

#include <utility>

#include "media/base/media_util.h"
#include "media/base/video_decoder_config.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {

namespace {

static const gfx::Size kCodedSize(320, 240);
static const gfx::Rect kVisibleRect(320, 240);
static const gfx::Size kNaturalSize(320, 240);

}  // namespace

TEST(ParcVideoDecoderConfigStructTraitsTest, SafariDolbyVisionSDRSurvivesMojo) {
  for (bool safari_sdr : {false, true}) {
    VideoDecoderConfig input(
        VideoCodec::kDolbyVision, DOLBYVISION_PROFILE8,
        VideoDecoderConfig::AlphaMode::kIsOpaque, VideoColorSpace::REC709(),
        kNoTransformation, kCodedSize, kVisibleRect, kNaturalSize,
        EmptyExtraData(), EncryptionScheme::kUnencrypted);
    input.set_parc_dolby_vision_sdr(safari_sdr);
    auto data = media::mojom::VideoDecoderConfig::Serialize(&input);
    VideoDecoderConfig output;
    ASSERT_TRUE(media::mojom::VideoDecoderConfig::Deserialize(std::move(data),
                                                              &output));
    EXPECT_EQ(safari_sdr, output.parc_dolby_vision_sdr());
    EXPECT_TRUE(output.Matches(input));
  }
}

}  // namespace media
