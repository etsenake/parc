// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/renderer_controller_test.cc. The fixture is
// derived from Chromium's renderer_controller_unittest.cc (Chromium Authors;
// BSD-style license in Chromium's LICENSE) and contains only Parc regressions.

#include "media/remoting/renderer_controller.h"

#include <memory>
#include <string>

#include "base/run_loop.h"
#include "base/test/simple_test_tick_clock.h"
#include "base/test/task_environment.h"
#include "media/base/test_helpers.h"
#include "media/base/video_decoder_config.h"
#include "media/remoting/fake_remoter.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {
namespace remoting {

namespace {

PipelineMetadata DefaultMetadata(VideoCodec codec) {
  PipelineMetadata data;
  data.has_audio = true;
  data.has_video = true;
  data.video_decoder_config = TestVideoConfig::Normal(codec);
  data.audio_decoder_config = TestAudioConfig::Normal();
  data.natural_size = gfx::Size(1920, 1080);
  return data;
}

const char kDefaultReceiver[] = "TestingChromeCast";

mojom::RemotingSinkMetadataPtr GetDefaultSinkMetadata(bool enable) {
  mojom::RemotingSinkMetadataPtr metadata = mojom::RemotingSinkMetadata::New();
  if (enable) {
    metadata->features.push_back(mojom::RemotingSinkFeature::RENDERING);
  } else {
    metadata->features.clear();
  }
  metadata->video_capabilities.push_back(
      mojom::RemotingSinkVideoCapability::CODEC_VP8);
  metadata->audio_capabilities.push_back(
      mojom::RemotingSinkAudioCapability::CODEC_BASELINE_SET);
  metadata->friendly_name = kDefaultReceiver;
  return metadata;
}

constexpr base::TimeDelta kDelayedStartDuration = base::Seconds(5);
constexpr double frame_rate = 30;
}  // namespace

class ParcRendererControllerTest : public ::testing::Test,
                                   public MediaObserverClient {
 public:
  ParcRendererControllerTest()
      : controller_(FakeRemoterFactory::CreateController(false)) {}

  ParcRendererControllerTest(const ParcRendererControllerTest&) = delete;
  ParcRendererControllerTest& operator=(const ParcRendererControllerTest&) =
      delete;

  ~ParcRendererControllerTest() override = default;

  void TearDown() final { RunUntilIdle(); }

  static void RunUntilIdle() { base::RunLoop().RunUntilIdle(); }

  // MediaObserverClient implementation.
  void SwitchToRemoteRenderer(
      const std::string& remote_device_friendly_name) override {
    is_rendering_remotely_ = true;
    disable_pipeline_suspend_ = true;
    sink_name_ = remote_device_friendly_name;
  }

  void SwitchToLocalRenderer(ReasonToSwitchToLocal reason) override {
    is_rendering_remotely_ = false;
    disable_pipeline_suspend_ = false;
    sink_name_.clear();
  }

  double Duration() const override { return duration_in_sec_; }

  unsigned DecodedFrameCount() const override { return decoded_frames_; }

  void UpdateRemotePlaybackCompatibility(bool) override {}

  void ParcCastRequestChanged(bool requested) override {
    cast_requested_ = requested;
  }

  void set_pixels_per_second_(double pixels) {
    controller_->pixels_per_second_ = pixels;
  }

  void InitializeControllerWithSink(
      const PipelineMetadata& pipeline_metadata,
      mojom::RemotingSinkMetadataPtr sink_metadata) {
    EXPECT_FALSE(is_rendering_remotely_);
    EXPECT_TRUE(sink_name_.empty());
    controller_->clock_ = &clock_;
    clock_.Advance(base::Seconds(1));
    controller_->SetClient(this);
    controller_->OnSinkAvailable(std::move(sink_metadata));
    controller_->OnRemotePlaybackDisabled(false);
    controller_->OnMetadataChanged(pipeline_metadata);
    controller_->OnPlaying();
    RunUntilIdle();
    PixelRateTimerEnds();
    RunUntilIdle();
    EXPECT_FALSE(is_rendering_remotely_);
    EXPECT_FALSE(disable_pipeline_suspend_);
  }

  void InitializeControllerAndBecomeDominant(
      const PipelineMetadata& pipeline_metadata,
      mojom::RemotingSinkMetadataPtr sink_metadata) {
    InitializeControllerWithSink(pipeline_metadata, std::move(sink_metadata));
    controller_->OnBecameDominantVisibleContent(true);
    RunUntilIdle();
  }

  void PixelRateTimerEnds() {
    EXPECT_TRUE(controller_->pixel_rate_timer_.IsRunning());
    decoded_frames_ = frame_rate * kDelayedStartDuration.InSeconds();
    clock_.Advance(kDelayedStartDuration);
    controller_->pixel_rate_timer_.FireNow();
  }

  void ExpectInRemoting() const {
    EXPECT_TRUE(is_rendering_remotely_);
    EXPECT_TRUE(disable_pipeline_suspend_);
    EXPECT_EQ(kDefaultReceiver, sink_name_);
  }

  void ExpectInLocalRendering() const {
    EXPECT_FALSE(is_rendering_remotely_);
    EXPECT_FALSE(disable_pipeline_suspend_);
    EXPECT_TRUE(sink_name_.empty());
  }

  base::test::SingleThreadTaskEnvironment task_environment_;

 protected:
  bool is_rendering_remotely_ = false;
  bool disable_pipeline_suspend_ = false;
  bool cast_requested_ = false;
  unsigned decoded_frames_ = 0;
  base::SimpleTestTickClock clock_;
  std::string sink_name_;
  std::unique_ptr<RendererController> controller_;
  double duration_in_sec_ = 120;  // 2m duration.
};

TEST_F(ParcRendererControllerTest, ParcOnFrozenKeepsRequestedRemoting) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8),
                               GetDefaultSinkMetadata(false));
  controller_->OnMediaRemotingRequested();
  RunUntilIdle();
  ExpectInRemoting();

  controller_->OnPaused();
  controller_->OnFrozen();
  RunUntilIdle();
  ExpectInRemoting();

  controller_->OnPlaying();
  RunUntilIdle();
  ExpectInRemoting();
}

TEST_F(ParcRendererControllerTest, ParcRequestEndsWithItsUnstartedSession) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8), nullptr);
  // Playing, the element measures its pixel rate before it starts remoting:
  // the requested session comes and times out first.
  set_pixels_per_second_(0);
  decoded_frames_ = 0;
  controller_->OnMediaRemotingRequested();
  controller_->OnSinkAvailable(GetDefaultSinkMetadata(false));
  controller_->OnSinkGone();
  RunUntilIdle();

  // A later tab mirroring session remotes only the dominant video, and hands
  // the receiver back to the tab when the page freezes.
  controller_->OnSinkAvailable(GetDefaultSinkMetadata(true));
  controller_->OnPlaying();
  RunUntilIdle();
  PixelRateTimerEnds();
  RunUntilIdle();
  ExpectInLocalRendering();

  controller_->OnBecameDominantVisibleContent(true);
  RunUntilIdle();
  ExpectInRemoting();
  controller_->OnPaused();
  controller_->OnFrozen();
  RunUntilIdle();
  ExpectInLocalRendering();
}

TEST_F(ParcRendererControllerTest, ParcRequestedSessionStartsOnFrozenElement) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8), nullptr);
  controller_->OnMediaRemotingRequested();
  // The page is left before the requested session comes.
  controller_->OnPaused();
  controller_->OnFrozen();
  controller_->OnSinkAvailable(GetDefaultSinkMetadata(false));
  RunUntilIdle();
  ExpectInRemoting();
}

TEST_F(ParcRendererControllerTest, ParcRequestedSessionStartsBeforePixelRate) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8), nullptr);
  // The element played for less than the pixel rate's measurement.
  set_pixels_per_second_(0);
  controller_->OnMediaRemotingRequested();
  controller_->OnPaused();
  controller_->OnFrozen();
  controller_->OnSinkAvailable(GetDefaultSinkMetadata(false));
  RunUntilIdle();
  ExpectInRemoting();
}

TEST_F(ParcRendererControllerTest,
       ParcRequestedSessionStartsWhenPausedMeasuring) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8), nullptr);
  set_pixels_per_second_(0);
  controller_->OnMediaRemotingRequested();
  controller_->OnSinkAvailable(GetDefaultSinkMetadata(false));
  RunUntilIdle();
  ExpectInLocalRendering();

  // The page is left before the pixel rate's measurement ends.
  controller_->OnPaused();
  controller_->OnFrozen();
  RunUntilIdle();
  ExpectInRemoting();
}

TEST_F(ParcRendererControllerTest,
       ParcUnmeasuredRequestKeepsSinkPixelRateLimit) {
  PipelineMetadata metadata = DefaultMetadata(VideoCodec::kVP8);
  metadata.natural_size = gfx::Size(3840, 2160);
  InitializeControllerWithSink(metadata, nullptr);
  set_pixels_per_second_(0);
  controller_->OnMediaRemotingRequested();
  controller_->OnPaused();
  controller_->OnSinkAvailable(GetDefaultSinkMetadata(false));
  RunUntilIdle();
  ExpectInLocalRendering();
}

TEST_F(ParcRendererControllerTest, ParcUnrequestedRemotingWaitsForPixelRate) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8),
                               GetDefaultSinkMetadata(true));
  set_pixels_per_second_(0);
  decoded_frames_ = 0;
  controller_->OnBecameDominantVisibleContent(true);
  RunUntilIdle();
  ExpectInLocalRendering();

  PixelRateTimerEnds();
  RunUntilIdle();
  ExpectInRemoting();
}

// Parc: the client hears of a request while it connects and casts, and when
// remoting stops.
TEST_F(ParcRendererControllerTest, ParcCastRequestHeldWhileConnecting) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8), nullptr);
  controller_->OnMediaRemotingRequested();
  RunUntilIdle();
  EXPECT_TRUE(cast_requested_);
  ExpectInLocalRendering();

  controller_->OnSinkAvailable(GetDefaultSinkMetadata(false));
  RunUntilIdle();
  ExpectInRemoting();
  EXPECT_TRUE(cast_requested_);

  controller_->OnStopped(mojom::RemotingStopReason::ROUTE_TERMINATED);
  RunUntilIdle();
  EXPECT_FALSE(cast_requested_);
}

TEST_F(ParcRendererControllerTest, ParcCastRequestEndsWhenStartFails) {
  controller_ = FakeRemoterFactory::CreateController(true);
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8), nullptr);
  controller_->OnMediaRemotingRequested();
  EXPECT_TRUE(cast_requested_);
  controller_->OnSinkAvailable(GetDefaultSinkMetadata(false));
  RunUntilIdle();
  ExpectInLocalRendering();
  EXPECT_FALSE(cast_requested_);
}

TEST_F(ParcRendererControllerTest, ParcCastRequestEndsWithItsUnstartedSession) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8), nullptr);
  set_pixels_per_second_(0);
  decoded_frames_ = 0;
  controller_->OnMediaRemotingRequested();
  controller_->OnSinkAvailable(GetDefaultSinkMetadata(false));
  EXPECT_TRUE(cast_requested_);
  controller_->OnSinkGone();
  EXPECT_FALSE(cast_requested_);
}

TEST_F(ParcRendererControllerTest, ParcCastRequestEndsWhenRemotingStops) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8),
                               GetDefaultSinkMetadata(false));
  controller_->OnMediaRemotingRequested();
  RunUntilIdle();
  ExpectInRemoting();
  EXPECT_TRUE(cast_requested_);

  controller_->OnRemotePlaybackDisabled(true);
  RunUntilIdle();
  ExpectInLocalRendering();
  EXPECT_FALSE(cast_requested_);
}

// Remoting a mirrored tab's dominant video is no request.
TEST_F(ParcRendererControllerTest, ParcDominantRemotingIsNoCastRequest) {
  InitializeControllerAndBecomeDominant(DefaultMetadata(VideoCodec::kVP8),
                                        GetDefaultSinkMetadata(true));
  RunUntilIdle();
  ExpectInRemoting();
  EXPECT_FALSE(cast_requested_);
}

namespace {

// Parc: the remoting bridge of the tab a Safari-identity page moved a player
// to.
class ParcNewTabRemoter final : public mojom::Remoter {
 public:
  explicit ParcNewTabRemoter(mojo::PendingRemote<mojom::RemotingSource> source)
      : source_(std::move(source)) {}

  void Start() final {
    ++starts_;
    source_->OnStarted();
  }
  void StartWithPermissionAlreadyGranted() final { Start(); }
  void StartDataStreams(mojo::ScopedDataPipeConsumerHandle audio_pipe,
                        mojo::ScopedDataPipeConsumerHandle video_pipe,
                        mojo::PendingReceiver<mojom::RemotingDataStreamSender>
                            audio_sender_receiver,
                        mojo::PendingReceiver<mojom::RemotingDataStreamSender>
                            video_sender_receiver) final {}
  void Stop(mojom::RemotingStopReason reason) final { ++stops_; }
  void SendMessageToSink(const std::vector<uint8_t>& message) final {}

  mojo::Remote<mojom::RemotingSource> source_;
  int starts_ = 0;
  int stops_ = 0;
};

}  // namespace

// Parc: a moved player's session goes on through the tab that started it, and
// once it ends the player remotes through its new tab's sink alone.
TEST_F(ParcRendererControllerTest, ParcMovedPlayerRemotesThroughItsNewTab) {
  InitializeControllerAndBecomeDominant(DefaultMetadata(VideoCodec::kVP8),
                                        GetDefaultSinkMetadata(true));
  ExpectInRemoting();

  mojo::PendingRemote<mojom::RemotingSource> source;
  auto source_receiver = source.InitWithNewPipeAndPassReceiver();
  ParcNewTabRemoter new_tab(std::move(source));
  mojo::Receiver<mojom::Remoter> new_tab_receiver(&new_tab);
  controller_->ParcMoveToRemoter(std::move(source_receiver),
                                 new_tab_receiver.BindNewPipeAndPassRemote());
  RunUntilIdle();
  ExpectInRemoting();

  controller_->OnBecameDominantVisibleContent(false);
  RunUntilIdle();
  ExpectInLocalRendering();
  controller_->OnBecameDominantVisibleContent(true);
  RunUntilIdle();
  ExpectInLocalRendering();
  EXPECT_EQ(0, new_tab.starts_);
  EXPECT_EQ(0, new_tab.stops_);

  new_tab.source_->OnSinkAvailable(GetDefaultSinkMetadata(true));
  RunUntilIdle();
  ExpectInRemoting();
  EXPECT_EQ(1, new_tab.starts_);
}

// Parc: a request through the tab a player moved from goes with that tab's
// sink, so the player then remotes through its new tab.
TEST_F(ParcRendererControllerTest, ParcMovedPlayerDropsTheOldTabsRequest) {
  InitializeControllerWithSink(DefaultMetadata(VideoCodec::kVP8), nullptr);
  controller_->OnMediaRemotingRequested();
  RunUntilIdle();
  ExpectInLocalRendering();

  mojo::PendingRemote<mojom::RemotingSource> source;
  auto source_receiver = source.InitWithNewPipeAndPassReceiver();
  ParcNewTabRemoter new_tab(std::move(source));
  mojo::Receiver<mojom::Remoter> new_tab_receiver(&new_tab);
  controller_->ParcMoveToRemoter(std::move(source_receiver),
                                 new_tab_receiver.BindNewPipeAndPassRemote());
  controller_->OnSinkGone();
  RunUntilIdle();

  controller_->OnBecameDominantVisibleContent(true);
  new_tab.source_->OnSinkAvailable(GetDefaultSinkMetadata(true));
  RunUntilIdle();
  ExpectInRemoting();
  EXPECT_EQ(1, new_tab.starts_);
}

}  // namespace remoting
}  // namespace media
