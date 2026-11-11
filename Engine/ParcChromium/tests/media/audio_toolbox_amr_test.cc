// Copyright 2026 Parc contributors.

#include "media/filters/mac/audio_toolbox_audio_decoder.h"

#include <memory>
#include <utility>
#include <vector>

#include "base/functional/callback_helpers.h"
#include "base/test/bind.h"
#include "base/test/task_environment.h"
#include "base/test/test_future.h"
#include "base/time/time.h"
#include "media/base/audio_buffer.h"
#include "media/base/audio_codecs.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/audio_sample_types.h"
#include "media/base/channel_layout.h"
#include "media/base/decoder_buffer.h"
#include "media/base/media_log.h"
#include "media/base/test_helpers.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {

// A 3GPP AMR sample holds several frames, which AudioToolbox takes one per
// packet; each sample comes out whole, as one buffer.
TEST(AudioToolboxAmrTest, DecodesEveryFrameOfEachSample) {
  base::test::TaskEnvironment task_environment;
  for (const bool wideband : {false, true}) {
    SCOPED_TRACE(wideband ? "AMR-WB" : "AMR-NB");
    const int sample_rate = wideband ? 16000 : 8000;
    const int frames_per_packet = sample_rate / 50;
    AudioToolboxAudioDecoder decoder(std::make_unique<NullMediaLog>());
    std::vector<scoped_refptr<AudioBuffer>> outputs;
    base::test::TestFuture<DecoderStatus> initialized;
    decoder.Initialize(
        AudioDecoderConfig(
            wideband ? AudioCodec::kAMR_WB : AudioCodec::kAMR_NB,
            kSampleFormatS16, ChannelLayoutConfig::Mono(), sample_rate,
            EmptyExtraData(), EncryptionScheme::kUnencrypted),
        nullptr, initialized.GetCallback(),
        base::BindLambdaForTesting([&outputs](scoped_refptr<AudioBuffer> buffer) {
          outputs.push_back(std::move(buffer));
        }),
        base::DoNothing());
    ASSERT_TRUE(initialized.Get().is_ok());

    // Nine 12.2 kbit/s (AMR-WB 23.85) frames, then a NO_DATA one.
    std::vector<uint8_t> sample;
    for (int i = 0; i < 9; ++i) {
      sample.push_back(wideband ? 0x44 : 0x3c);
      for (int j = 0; j < (wideband ? 60 : 31); ++j) {
        sample.push_back(static_cast<uint8_t>(i * 37 + j * 11));
      }
    }
    sample.push_back(0x7c);
    for (int i = 0; i < 2; ++i) {
      scoped_refptr<DecoderBuffer> buffer = DecoderBuffer::CopyFrom(sample);
      buffer->set_timestamp(base::Milliseconds(200 * i));
      buffer->set_duration(base::Milliseconds(200));
      base::test::TestFuture<DecoderStatus> decoded;
      decoder.Decode(std::move(buffer), decoded.GetCallback());
      ASSERT_TRUE(decoded.Get().is_ok());
    }

    // AudioToolbox trims its decoder delay, under a frame, from the first.
    ASSERT_EQ(outputs.size(), 2u);
    EXPECT_GT(outputs[0]->frame_count(), 9 * frames_per_packet);
    EXPECT_EQ(outputs[1]->frame_count(), 10 * frames_per_packet);
    EXPECT_EQ(outputs[1]->sample_rate(), sample_rate);
    EXPECT_EQ(outputs[1]->channel_count(), 1);
  }
}

}  // namespace media
