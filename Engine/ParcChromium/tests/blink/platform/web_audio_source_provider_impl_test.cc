// Copyright 2026 Parc contributors.

#include "third_party/blink/public/platform/web_audio_source_provider_impl.h"

#include "base/memory/scoped_refptr.h"
#include "base/run_loop.h"
#include "base/test/task_environment.h"
#include "media/base/audio_bus.h"
#include "media/base/audio_parameters.h"
#include "media/base/fake_audio_render_callback.h"
#include "media/base/media_util.h"
#include "media/base/mock_audio_renderer_sink.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/renderer/platform/media/web_audio_source_provider_client.h"

namespace blink {

namespace {

const float kTestVolume = 0.25;
const int kTestSampleRate = 48000;

}

class ParcWebAudioSourceProviderImplTest : public testing::Test,
                                       public WebAudioSourceProviderClient {
 public:
  ParcWebAudioSourceProviderImplTest()
      : params_(media::AudioParameters::AUDIO_PCM_LINEAR,
                media::ChannelLayoutConfig::Stereo(),
                kTestSampleRate,
                64),
        fake_callback_(0.1, kTestSampleRate),
        mock_sink_(base::MakeRefCounted<media::MockAudioRendererSink>()),
        wasp_impl_(
            base::MakeRefCounted<WebAudioSourceProviderImpl>(mock_sink_,
                                                             &media_log_)) {}

  ParcWebAudioSourceProviderImplTest(const ParcWebAudioSourceProviderImplTest&) =
      delete;
  ParcWebAudioSourceProviderImplTest& operator=(
      const ParcWebAudioSourceProviderImplTest&) = delete;
  ~ParcWebAudioSourceProviderImplTest() override = default;

  MOCK_METHOD2(SetFormat, void(uint32_t numberOfChannels, float sampleRate));

 protected:
  base::test::TaskEnvironment task_environment_;

  media::AudioParameters params_;
  media::FakeAudioRenderCallback fake_callback_;
  media::NullMediaLog media_log_;
  scoped_refptr<media::MockAudioRendererSink> mock_sink_;
  scoped_refptr<WebAudioSourceProviderImpl> wasp_impl_;
};

TEST_F(ParcWebAudioSourceProviderImplTest, ParcSwitchSinkKeepsPlaybackState) {
  wasp_impl_->Initialize(params_, &fake_callback_);
  EXPECT_CALL(*mock_sink_, Start());
  wasp_impl_->Start();
  EXPECT_CALL(*mock_sink_, Play());
  wasp_impl_->Play();
  EXPECT_CALL(*mock_sink_, SetVolume(kTestVolume));
  wasp_impl_->SetVolume(kTestVolume);
  testing::Mock::VerifyAndClear(mock_sink_.get());

  auto refused_sink = base::MakeRefCounted<media::MockAudioRendererSink>(
      media::OUTPUT_DEVICE_STATUS_ERROR_NOT_AUTHORIZED);
  EXPECT_CALL(*mock_sink_, Stop()).Times(0);
  wasp_impl_->ParcSwitchSink(refused_sink);
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(refused_sink->callback());
  testing::Mock::VerifyAndClear(mock_sink_.get());

  auto new_sink = base::MakeRefCounted<media::MockAudioRendererSink>();
  {
    testing::InSequence s;
    EXPECT_CALL(*mock_sink_, Stop());
    EXPECT_CALL(*new_sink, SetVolume(kTestVolume));
    EXPECT_CALL(*new_sink, Start());
    EXPECT_CALL(*new_sink, Play());
  }
  wasp_impl_->ParcSwitchSink(new_sink);
  base::RunLoop().RunUntilIdle();
  testing::Mock::VerifyAndClear(mock_sink_.get());
  testing::Mock::VerifyAndClear(new_sink.get());

  ASSERT_TRUE(new_sink->callback());
  auto bus = media::AudioBus::Create(params_);
  bus->Zero();
  new_sink->callback()->Render(base::TimeDelta(), base::TimeTicks::Now(), {},
                               bus.get());
  EXPECT_FALSE(bus->AreFramesZero());

  EXPECT_CALL(*new_sink,
              Pause(media::AudioRendererSink::PauseReason::kPlaybackPaused));
  wasp_impl_->Pause(media::AudioRendererSink::PauseReason::kPlaybackPaused);
  testing::Mock::VerifyAndClear(new_sink.get());

  EXPECT_CALL(*new_sink, Stop());
  EXPECT_CALL(*this, SetFormat(params_.channels(), params_.sample_rate()));
  wasp_impl_->SetClient(this);
  base::RunLoop().RunUntilIdle();
  auto unused_sink = base::MakeRefCounted<media::MockAudioRendererSink>();
  wasp_impl_->ParcSwitchSink(unused_sink);
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(unused_sink->callback());
}

}
