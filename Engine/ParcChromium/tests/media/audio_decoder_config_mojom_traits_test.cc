// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/audio_decoder_config_mojom_traits_test.cc.
// The test is derived from Chromium's matching unittest (Chromium Authors;
// BSD-style license in Chromium's LICENSE).

#include "media/mojo/mojom/audio_decoder_config_mojom_traits.h"

#include <cstdint>
#include <utility>
#include <vector>

#include "base/time/time.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/media_util.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {

TEST(ParcAudioDecoderConfigStructTraitsTest,
     TransportStreamAudioTypeSurvivesMojo) {
  AudioDecoderConfig input;
  input.Initialize(AudioCodec::kAAC, kSampleFormatU8,
                   ChannelLayoutConfig::FromLayout<CHANNEL_LAYOUT_SURROUND>(),
                   48000, EmptyExtraData(), EncryptionScheme::kUnencrypted,
                   base::TimeDelta(), 0);
  input.set_profile(AudioCodecProfile::kXHE_AAC);
  input.set_parc_ts_audio_type(0x7a616368);
  std::vector<uint8_t> data = mojom::AudioDecoderConfig::Serialize(&input);
  AudioDecoderConfig output;
  ASSERT_TRUE(mojom::AudioDecoderConfig::Deserialize(std::move(data), &output));
  EXPECT_EQ(output.parc_ts_audio_type(), input.parc_ts_audio_type());
  EXPECT_TRUE(output.Matches(input));
}

}  // namespace media
