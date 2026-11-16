// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/audio_renderer_impl_test.cc. The fixture is
// derived from Chromium's audio_renderer_impl_unittest.cc (Chromium Authors;
// BSD-style license in Chromium's LICENSE) and contains only Parc regressions.

#include "media/renderers/audio_renderer_impl.h"

#include <algorithm>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/scoped_refptr.h"
#include "base/run_loop.h"
#include "base/synchronization/lock.h"
#include "base/task/single_thread_task_runner.h"
#include "base/test/gmock_callback_support.h"
#include "base/test/simple_test_tick_clock.h"
#include "base/test/task_environment.h"
#include "base/time/time.h"
#include "media/base/audio_bus.h"
#include "media/base/audio_timestamp_helper.h"
#include "media/base/fake_audio_renderer_sink.h"
#include "media/base/media_util.h"
#include "media/base/mock_filters.h"
#include "media/base/mock_media_log.h"
#include "media/base/test_helpers.h"
#include "media/filters/audio_clock.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

using ::base::test::RunOnceCallback;
using ::testing::_;
using ::testing::DoAll;
using ::testing::Invoke;
using ::testing::Return;
using ::testing::SaveArg;

namespace media {
namespace {

struct InputFrames {
  explicit InputFrames(int value) : value(value) {}
  int value;
};

struct OutputFrames {
  explicit OutputFrames(int value) : value(value) {}
  int value;
};

constexpr AudioCodec kCodec = AudioCodec::kVorbis;
constexpr SampleFormat kSampleFormat = kSampleFormatPlanarF32;
constexpr ChannelLayout kChannelLayout = CHANNEL_LAYOUT_STEREO;
constexpr int kChannels = 2;
constexpr int kInputSamplesPerSecond = 5000;
constexpr int kOutputSamplesPerSecond = 10000;
constexpr int kInputFramesChunk = 256;

}

class ParcAudioRendererImplTest : public testing::Test,
                                  public RendererClient {
 public:
  ParcAudioRendererImplTest()
      : hardware_params_(AudioParameters::AUDIO_PCM_LOW_LATENCY,
                         ChannelLayoutConfig::FromLayout<kChannelLayout>(),
                         kOutputSamplesPerSecond,
                         512),
        main_thread_task_runner_(
            base::SingleThreadTaskRunner::GetCurrentDefault()),
        sink_(base::MakeRefCounted<FakeAudioRendererSink>(hardware_params_)),
        demuxer_stream_(DemuxerStream::AUDIO) {
    AudioDecoderConfig config(
        kCodec, kSampleFormat,
        ChannelLayoutConfig::FromLayout<kChannelLayout>(),
        kInputSamplesPerSecond, EmptyExtraData(),
        EncryptionScheme::kUnencrypted);
    demuxer_stream_.set_audio_decoder_config(config);
    EXPECT_CALL(demuxer_stream_, OnRead(_))
        .WillRepeatedly(
            Invoke(this, &ParcAudioRendererImplTest::OnDemuxerRead));
    EXPECT_CALL(demuxer_stream_, SupportsConfigChanges())
        .WillRepeatedly(Return(true));

    renderer_ = std::make_unique<AudioRendererImpl>(
        main_thread_task_runner_, sink_,
        base::BindRepeating(
            &ParcAudioRendererImplTest::CreateAudioDecodersForTest,
            base::Unretained(this)),
        &media_log_, MediaPlayerLoggingID(0));
    renderer_->tick_clock_ = &tick_clock_;
    tick_clock_.Advance(base::Seconds(1));
  }

  std::vector<std::unique_ptr<AudioDecoder>> CreateAudioDecodersForTest() {
    auto decoder = std::make_unique<MockAudioDecoder>();
    EXPECT_CALL(*decoder, Initialize_(_, _, _, _, _))
        .WillOnce(DoAll(SaveArg<3>(&output_cb_),
                        RunOnceCallback<2>(DecoderStatus::Codes::kOk)));
    EXPECT_CALL(*decoder, Decode(_, _))
        .WillRepeatedly(
            Invoke(this, &ParcAudioRendererImplTest::DecodeDecoder));
    EXPECT_CALL(*decoder, Reset_(_))
        .WillRepeatedly(
            Invoke(this, &ParcAudioRendererImplTest::ResetDecoder));
    std::vector<std::unique_ptr<AudioDecoder>> decoders;
    decoders.push_back(std::move(decoder));
    return decoders;
  }

  void OnError(PipelineStatus) override {}
  void OnFallback(PipelineStatus) override {}
  void OnEnded() override {}
  void OnStatisticsUpdate(const PipelineStatistics&) override {}
  MOCK_METHOD2(OnBufferingStateChange,
               void(BufferingState, BufferingStateChangeReason));
  void OnWaiting(WaitingReason) override {}
  void OnAudioConfigChange(const AudioDecoderConfig&) override {}
  void OnVideoConfigChange(const VideoDecoderConfig&) override {}
  void OnVideoNaturalSizeChange(const gfx::Size&) override {}
  void OnVideoOpacityChange(bool) override {}
  void OnVideoFrameRateChange(std::optional<int>) override {}

  void Initialize() {
    WaitableMessageLoopEvent event;
    renderer_->Initialize(&demuxer_stream_, nullptr, this,
                          event.GetPipelineStatusCB());
    event.RunAndWaitForStatus(PIPELINE_OK);
    next_timestamp_ =
        std::make_unique<AudioTimestampHelper>(kInputSamplesPerSecond);
  }

  void Preroll() {
    next_timestamp_->SetBaseTimestamp(base::TimeDelta());
    renderer_->SetMediaTime(base::TimeDelta());
    renderer_->StartPlaying();
    WaitForPendingRead();
    EXPECT_CALL(*this, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                              BUFFERING_CHANGE_REASON_UNKNOWN));
    DeliverRemainingAudio();
  }

  void StartTicking() {
    renderer_->StartTicking();
    renderer_->SetPlaybackRate(1.0);
  }

  std::unique_ptr<AudioRendererImpl> ParcCreateMixedRenderer() {
    std::unique_ptr<AudioRendererImpl> leader = std::move(renderer_);
    renderer_.reset(static_cast<AudioRendererImpl*>(
        leader->ParcCreateMixedRenderer().release()));
    CHECK(renderer_);
    renderer_->tick_clock_ = &tick_clock_;
    Initialize();
    Preroll();
    std::swap(renderer_, leader);
    return leader;
  }

  base::TimeDelta ParcWrittenUpTo(AudioRendererImpl* renderer) {
    base::AutoLock auto_lock(renderer->lock_);
    return renderer->audio_clock_->back_timestamp();
  }

 protected:
  void OnDemuxerRead(DemuxerStream::ReadCB& read_cb) {
    auto buffer = base::MakeRefCounted<DecoderBuffer>(0);
    std::move(read_cb).Run(DemuxerStream::kOk, {std::move(buffer)});
  }

  void WaitForPendingRead() {
    if (decode_cb_) {
      return;
    }
    WaitableMessageLoopEvent event;
    wait_for_pending_decode_cb_ = event.GetClosure();
    event.RunAndWait();
    CHECK(decode_cb_);
  }

  void SatisfyPendingRead(InputFrames frames) {
    CHECK_GT(frames.value, 0);
    CHECK(decode_cb_);
    auto buffer = MakeAudioBuffer<float>(
        kSampleFormat, kChannelLayout, kChannels, kInputSamplesPerSecond, 1.0f,
        0.0f, frames.value, next_timestamp_->GetTimestamp());
    next_timestamp_->AddFrames(frames.value);
    DeliverBuffer(std::move(buffer));
  }

  void DeliverRemainingAudio() {
    while (FramesRemainingInBuffer().value > 0 || decode_cb_) {
      SatisfyPendingRead(InputFrames(kInputFramesChunk));
    }
  }

  OutputFrames FramesBuffered() const {
    return OutputFrames(renderer_->algorithm_->BufferedFrames());
  }

  OutputFrames BufferCapacity() const {
    return OutputFrames(renderer_->algorithm_->QueueCapacity());
  }

  OutputFrames FramesRemainingInBuffer() const {
    return OutputFrames(std::max(0, BufferCapacity().value -
                                       FramesBuffered().value));
  }

  void DecodeDecoder(scoped_refptr<DecoderBuffer> buffer,
                     AudioDecoder::DecodeCB decode_cb) {
    CHECK(main_thread_task_runner_->BelongsToCurrentThread());
    CHECK(!decode_cb_);
    decode_cb_ = std::move(decode_cb);
    if (wait_for_pending_decode_cb_) {
      std::move(wait_for_pending_decode_cb_).Run();
    }
  }

  void ResetDecoder(base::OnceClosure& reset_cb) {
    if (decode_cb_) {
      reset_cb_ = std::move(reset_cb);
      return;
    }
    main_thread_task_runner_->PostTask(FROM_HERE, std::move(reset_cb));
  }

  void DeliverBuffer(scoped_refptr<AudioBuffer> buffer) {
    output_cb_.Run(std::move(buffer));
    std::move(decode_cb_).Run(DecoderStatus::Codes::kOk);
    if (reset_cb_) {
      std::move(reset_cb_).Run();
    }
    base::RunLoop().RunUntilIdle();
  }

  AudioParameters hardware_params_;
  base::test::TaskEnvironment task_environment_;
  const scoped_refptr<base::SingleThreadTaskRunner> main_thread_task_runner_;
  NullMediaLog media_log_;
  std::unique_ptr<AudioRendererImpl> renderer_;
  scoped_refptr<FakeAudioRendererSink> sink_;
  base::SimpleTestTickClock tick_clock_;
  MockDemuxerStream demuxer_stream_;
  AudioDecoder::OutputCB output_cb_;
  AudioDecoder::DecodeCB decode_cb_;
  base::OnceClosure reset_cb_;
  std::unique_ptr<AudioTimestampHelper> next_timestamp_;
  base::OnceClosure wait_for_pending_decode_cb_;
};

TEST_F(ParcAudioRendererImplTest, ParcMixedRendererPlaysInTheOutput) {
  Initialize();
  Preroll();
  std::unique_ptr<AudioRendererImpl> mixed = ParcCreateMixedRenderer();
  StartTicking();
  mixed->StartTicking();
  mixed->SetPlaybackRate(1.0);

  std::unique_ptr<AudioBus> bus = AudioBus::Create(hardware_params_);
  int frames_read = 0;
  for (int i = 0; i < 2; ++i) {
    EXPECT_TRUE(sink_->Render(bus.get(), base::TimeDelta(), &frames_read));
  }
  EXPECT_EQ(frames_read, bus->frames());
  for (float sample : bus->channel(0)) {
    ASSERT_NEAR(2.0f, sample, 0.05f);
  }

  renderer_->ParcSetOwnAudioMuted(true);
  EXPECT_TRUE(sink_->Render(bus.get(), base::TimeDelta(), &frames_read));
  EXPECT_EQ(frames_read, bus->frames());
  for (float sample : bus->channel(0)) {
    ASSERT_NEAR(1.0f, sample, 0.05f);
  }
}

TEST_F(ParcAudioRendererImplTest, ParcMixedRendererKeepsToTheTimeline) {
  Initialize();
  Preroll();
  std::unique_ptr<AudioRendererImpl> mixed = ParcCreateMixedRenderer();
  StartTicking();
  std::unique_ptr<AudioBus> bus = AudioBus::Create(hardware_params_);
  int frames_read = 0;
  for (int i = 0; i < 2; ++i) {
    EXPECT_TRUE(sink_->Render(bus.get(), base::TimeDelta(), &frames_read));
  }
  EXPECT_EQ(ParcWrittenUpTo(mixed.get()), base::TimeDelta());

  mixed->StartTicking();
  mixed->SetPlaybackRate(1.0);
  EXPECT_TRUE(sink_->Render(bus.get(), base::TimeDelta(), &frames_read));
  EXPECT_LE((ParcWrittenUpTo(renderer_.get()) - ParcWrittenUpTo(mixed.get()))
                .magnitude(),
            base::Milliseconds(30));
  EXPECT_GT(ParcWrittenUpTo(mixed.get()), base::Milliseconds(100));
}

}
