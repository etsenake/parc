// Installed by the reviewed overlay at
// //content/renderer/media/fairplay/native_hls_unittest.cc (content_unittests,
// macOS). The render-process state mapping of Safari's native HLS route
// (NATIVE_HLS.md "Media element state and events"): what the GPU AVPlayer
// reports through media.mojom.FairPlayHlsPlayerClient becomes the pipeline's
// metadata, duration, buffered ranges, buffering state, time, ended, waiting
// and errors, and the pipeline's commands become the player's.

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/run_loop.h"
#include "base/test/mock_callback.h"
#include "base/test/task_environment.h"
#include "base/time/time.h"
#include "base/unguessable_token.h"
#include "content/renderer/media/fairplay/native_hls_demuxer.h"
#include "content/renderer/media/fairplay/native_hls_renderer.h"
#include "media/base/eme_constants.h"
#include "media/base/media_util.h"
#include "media/base/mock_demuxer_host.h"
#include "media/base/mock_filters.h"
#include "media/base/mock_video_renderer_sink.h"
#include "media/base/renderer_factory.h"
#include "media/base/test_helpers.h"
#include "media/base/timestamp_constants.h"
#include "media/base/video_frame.h"
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "ui/gfx/geometry/size_f.h"
#include "url/gurl.h"

namespace parc::fairplay {
namespace {

using ::testing::_;
using ::testing::InSequence;
using ::testing::NiceMock;
using ::testing::StrictMock;

constexpr char kPlaylist[] = "https://media.example/master.m3u8";

// The GPU player: records commands and answers Seek when told (the test
// answers Initialize with OnInitialized on the client pipe).
class FakePlayer : public media::mojom::FairPlayHlsPlayer {
 public:
  void Initialize(const GURL& url,
                  const std::string& mime_type,
                  const gfx::SizeF& video_layer_size,
                  float video_layer_scale) override {
    url_ = url;
    video_layer_size_ = video_layer_size;
    video_layer_scale_ = video_layer_scale;
    initialized_ = true;
  }
  void PrepareToPlay() override { prepared_ = true; }
  void SetCdm(const std::optional<base::UnguessableToken>& cdm_id,
              SetCdmCallback callback) override {
    cdm_ids_.push_back(cdm_id);
    if (holds_cdm_answers_) {
      cdm_answers_.push_back(std::move(callback));
      return;
    }
    std::move(callback).Run(accepts_cdm_);
  }
  void Play(double rate) override { commands_.push_back(rate); }
  void Pause() override { commands_.push_back(0); }
  void Seek(base::TimeDelta time,
            base::TimeDelta tolerance_before,
            SeekCallback callback) override {
    seek_time_ = time;
    seek_tolerance_ = tolerance_before;
    seek_cb_ = std::move(callback);
  }
  void SetVolume(float volume) override { volume_ = volume; }
  void SetMuted(bool muted) override {}
  void SetPreservesPitch(bool preserves_pitch) override {
    preserves_pitch_ = preserves_pitch;
  }
  void ProvideClearKey(const std::string& key_id,
                       const std::vector<uint8_t>& key) override {
    clear_keys_.emplace_back(key_id, key);
  }
  void SetAudioTrackEnabled(const std::string& key, bool enabled) override {}
  void SetTextTrackMode(const std::string& key,
                        media::mojom::FairPlayHlsTextTrackMode mode) override {
  }
  void Suspend() override {}
  void Resume() override {}
  void SetPlaybackTarget(const std::string& output_context_id,
                         bool should_play) override {
    targets_.push_back({output_context_id, should_play, initialized_});
  }
  void SetWirelessVideoPlaybackDisabled(bool disabled) override {
    wireless_disabled_.push_back(disabled);
  }

  struct Target {
    std::string id;
    bool should_play;
    bool after_initialize;
  };
  std::vector<Target> targets_;
  std::vector<bool> wireless_disabled_;
  GURL url_;
  gfx::SizeF video_layer_size_;
  float video_layer_scale_ = 0;
  bool initialized_ = false;
  bool prepared_ = false;
  SeekCallback seek_cb_;
  std::optional<base::TimeDelta> seek_time_;
  base::TimeDelta seek_tolerance_;
  std::vector<double> commands_;  // Play(rate) or 0 for Pause().
  std::vector<std::optional<base::UnguessableToken>> cdm_ids_;
  bool accepts_cdm_ = true;
  // SetCdm answers wait in `cdm_answers_` for the test.
  bool holds_cdm_answers_ = false;
  std::vector<SetCdmCallback> cdm_answers_;
  std::vector<std::pair<std::string, std::vector<uint8_t>>> clear_keys_;
  float volume_ = -1;
  std::optional<bool> preserves_pitch_;
};

media::mojom::FairPlayHlsMetadataPtr Metadata(base::TimeDelta duration) {
  auto metadata = media::mojom::FairPlayHlsMetadata::New();
  metadata->has_audio = true;
  metadata->has_video = true;
  metadata->natural_size = gfx::Size(1920, 1080);
  metadata->audio_codec = media::AudioCodec::kAAC;
  metadata->video_codec = media::VideoCodec::kHEVC;
  metadata->duration = duration;
  metadata->buffered.push_back(media::mojom::FairPlayHlsTimeRange::New(
      base::TimeDelta(), base::Seconds(12)));
  return metadata;
}

class NativeHlsTest : public testing::Test {
 protected:
  void SetUp() override {
    mojo::PendingRemote<media::mojom::FairPlayHlsPlayer> player;
    player_receiver_.Bind(player.InitWithNewPipeAndPassReceiver());
    mojo::PendingRemote<media::mojom::FairPlayHlsPlayerClient> client;
    auto client_receiver = client.InitWithNewPipeAndPassReceiver();
    client_.Bind(std::move(client));

    media::ParcNativeHlsDemuxerParams params;
    params.url = GURL(kPlaylist);
    params.media_task_runner = task_environment_.GetMainThreadTaskRunner();
    params.media_log = &media_log_;
    params.encrypted_media_init_data_cb = encrypted_cb_.Get();
    params.key_request_cb = key_request_cb_.Get();
    params.start_load_cb = start_load_cb_.Get();
    params.time_jumped_cb = time_jumped_cb_.Get();
    params.wireless_cb = wireless_cb_.Get();
    params.video_layer_size = gfx::SizeF(640, 360);
    params.video_layer_scale = 2;
    params.playback_target_id = initial_target_id_;
    params.should_play_to_playback_target = initial_should_play_;
    params.wireless_video_playback_disabled = initial_wireless_disabled_;
    demuxer_ = std::make_unique<NativeHlsDemuxer>(
        std::move(params), std::move(player), std::move(client_receiver));
  }

  void TearDown() override {
    renderer_.reset();
    demuxer_->Stop();
    demuxer_.reset();
    task_environment_.RunUntilIdle();
  }

  // Initializes the demuxer and answers with `metadata`.
  media::PipelineStatus InitializeWith(
      media::mojom::FairPlayHlsMetadataPtr metadata) {
    std::optional<media::PipelineStatus> status;
    demuxer_->Initialize(&host_,
                         base::BindOnce(
                             [](std::optional<media::PipelineStatus>* out,
                                media::PipelineStatus s) { *out = s; },
                             &status));
    task_environment_.RunUntilIdle();
    EXPECT_TRUE(player_.initialized_);
    // The element's size reaches the player with the load (WebKit's initial
    // video layer size).
    EXPECT_EQ(gfx::SizeF(640, 360), player_.video_layer_size_);
    EXPECT_EQ(2, player_.video_layer_scale_);
    client_->OnInitialized(std::move(metadata));
    task_environment_.RunUntilIdle();
    EXPECT_TRUE(status);
    return status.value_or(media::PipelineStatus(media::PIPELINE_OK));
  }

  void CreateRenderer() {
    renderer_ = std::make_unique<NativeHlsRenderer>(
        task_environment_.GetMainThreadTaskRunner(), &sink_);
    base::MockCallback<media::PipelineStatusCallback> init_cb;
    EXPECT_CALL(init_cb, Run(media::HasStatusCode(media::PIPELINE_OK)));
    renderer_->Initialize(demuxer_.get(), &renderer_client_, init_cb.Get());
  }

  base::test::TaskEnvironment task_environment_;
  media::NullMediaLog media_log_;
  FakePlayer player_;
  mojo::Receiver<media::mojom::FairPlayHlsPlayer> player_receiver_{&player_};
  mojo::Remote<media::mojom::FairPlayHlsPlayerClient> client_;
  base::MockCallback<media::Demuxer::EncryptedMediaInitDataCB> encrypted_cb_;
  base::MockCallback<base::RepeatingCallback<void(const std::string&)>>
      key_request_cb_;
  base::MockCallback<NativeHlsDemuxer::StartLoadCallback> start_load_cb_;
  base::MockCallback<base::RepeatingClosure> time_jumped_cb_;
  base::MockCallback<base::RepeatingCallback<void(bool)>> wireless_cb_;
  // The element's AirPlay state when the demuxer is made.
  std::string initial_target_id_;
  bool initial_should_play_ = false;
  bool initial_wireless_disabled_ = false;
  NiceMock<media::MockDemuxerHost> host_;
  NiceMock<media::MockRendererClient> renderer_client_;
  NiceMock<media::MockVideoRendererSink> sink_;
  std::unique_ptr<NativeHlsDemuxer> demuxer_;
  std::unique_ptr<NativeHlsRenderer> renderer_;
};

TEST(NativeHlsTimeTest, Interpolates) {
  const base::TimeTicks capture = base::TimeTicks() + base::Seconds(100);
  const base::TimeDelta duration = base::Seconds(60);
  // Paused: the reported time.
  EXPECT_EQ(InterpolateNativeHlsTime(base::Seconds(5), 0, capture,
                                     capture + base::Seconds(3), duration),
            base::Seconds(5));
  // Playing at 1 and at 2.
  EXPECT_EQ(InterpolateNativeHlsTime(base::Seconds(5), 1, capture,
                                     capture + base::Seconds(3), duration),
            base::Seconds(8));
  EXPECT_EQ(InterpolateNativeHlsTime(base::Seconds(5), 2, capture,
                                     capture + base::Seconds(3), duration),
            base::Seconds(11));
  // Never past the duration, unless the stream is live.
  EXPECT_EQ(InterpolateNativeHlsTime(base::Seconds(59), 1, capture,
                                     capture + base::Seconds(3), duration),
            duration);
  EXPECT_EQ(InterpolateNativeHlsTime(base::Seconds(59), 1, capture,
                                     capture + base::Seconds(3),
                                     media::kInfiniteDuration),
            base::Seconds(62));
  // A clock that hasn't reported yet doesn't advance; nothing goes negative.
  EXPECT_EQ(InterpolateNativeHlsTime(base::Seconds(1), 1, base::TimeTicks(),
                                     capture, duration),
            base::Seconds(1));
  EXPECT_EQ(InterpolateNativeHlsTime(base::Seconds(-1), 0, capture, capture,
                                     duration),
            base::TimeDelta());
}

TEST(NativeHlsTimeTest, ReverseClockAndStartBoundary) {
  const auto capture = base::TimeTicks::Now();
  EXPECT_EQ(InterpolateNativeHlsTime(base::Seconds(5), -2, capture,
                                   capture + base::Seconds(1), base::Seconds(60)),
            base::Seconds(3));
  EXPECT_EQ(InterpolateNativeHlsTime(base::Seconds(1), -2, capture,
                                   capture + base::Seconds(1), base::Seconds(60)),
            base::TimeDelta());
}

TEST(NativeHlsErrorTest, InitializeFailureStatus) {
  // The item's own error (Safari's MEDIA_ERR_NETWORK, for example) wins.
  EXPECT_EQ(NativeHlsDemuxer::InitializeFailureStatus(
                media::PipelineStatus(media::PIPELINE_ERROR_NETWORK))
                .code(),
            media::PIPELINE_ERROR_NETWORK);
  EXPECT_EQ(NativeHlsDemuxer::InitializeFailureStatus(std::nullopt).code(),
            media::DEMUXER_ERROR_COULD_NOT_OPEN);
}

TEST_F(NativeHlsTest, MetadataBecomesStreamsDurationAndBuffered) {
  EXPECT_CALL(host_, SetDuration(base::Seconds(60)));
  EXPECT_CALL(host_, OnBufferedTimeRangesChanged(_))
      .WillOnce([](const media::Ranges<base::TimeDelta>& ranges) {
        ASSERT_EQ(ranges.size(), 1u);
        EXPECT_EQ(ranges.end(0), base::Seconds(12));
      });
  EXPECT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  EXPECT_EQ(player_.url_, GURL(kPlaylist));

  auto streams = demuxer_->GetAllStreams();
  ASSERT_EQ(streams.size(), 2u);
  EXPECT_EQ(streams[0]->type(), media::DemuxerStream::AUDIO);
  EXPECT_EQ(streams[0]->audio_decoder_config().codec(),
            media::AudioCodec::kAAC);
  EXPECT_FALSE(streams[0]->audio_decoder_config().is_encrypted());
  EXPECT_EQ(streams[1]->type(), media::DemuxerStream::VIDEO);
  EXPECT_EQ(streams[1]->video_decoder_config().codec(),
            media::VideoCodec::kHEVC);
  EXPECT_EQ(streams[1]->video_decoder_config().natural_size(),
            gfx::Size(1920, 1080));
  EXPECT_FALSE(streams[1]->video_decoder_config().is_encrypted());
  EXPECT_TRUE(demuxer_->IsSeekable());
  EXPECT_EQ(demuxer_->GetParcNativeHlsSource(), demuxer_.get());
  EXPECT_EQ(demuxer_->GetDemuxerType(), media::DemuxerType::kManifestDemuxer);
}

TEST_F(NativeHlsTest, TimelineFollowsThePlayer) {
  auto metadata = Metadata(media::kInfiniteDuration);
  metadata->seekable.push_back(media::mojom::FairPlayHlsTimeRange::New(
      base::Seconds(10), media::kInfiniteDuration));
  metadata->start_date = base::Time::FromSecondsSinceUnixEpoch(1700000000);
  ASSERT_TRUE(InitializeWith(std::move(metadata)).is_ok());
  std::optional<media::Demuxer::ParcNativeTimeline> timeline =
      demuxer_->GetParcNativeTimeline();
  ASSERT_TRUE(timeline);
  ASSERT_EQ(timeline->seekable.size(), 1u);
  EXPECT_EQ(timeline->seekable.start(0), base::Seconds(10));
  EXPECT_EQ(timeline->seekable.end(0), media::kInfiniteDuration);
  EXPECT_EQ(timeline->start_date,
            base::Time::FromSecondsSinceUnixEpoch(1700000000));
  EXPECT_EQ(demuxer_->GetTimelineOffset(),
            base::Time::FromSecondsSinceUnixEpoch(1700000000));

  std::vector<media::mojom::FairPlayHlsTimeRangePtr> window;
  window.push_back(media::mojom::FairPlayHlsTimeRange::New(
      base::Seconds(20), media::kInfiniteDuration));
  client_->OnSeekableRangesChanged(std::move(window));
  client_->OnStartDateChanged(std::nullopt);
  task_environment_.RunUntilIdle();
  timeline = demuxer_->GetParcNativeTimeline();
  ASSERT_TRUE(timeline);
  EXPECT_EQ(timeline->seekable.start(0), base::Seconds(20));
  EXPECT_FALSE(timeline->start_date);
}

TEST_F(NativeHlsTest, LiveIsInfiniteAndNotSeekable) {
  EXPECT_CALL(host_, SetDuration(media::kInfiniteDuration));
  EXPECT_TRUE(InitializeWith(Metadata(media::kInfiniteDuration)).is_ok());
  EXPECT_FALSE(demuxer_->IsSeekable());
}

TEST_F(NativeHlsTest, ItemErrorBeforeMetadataFailsInitialize) {
  client_->OnError(media::PipelineStatus(media::PIPELINE_ERROR_NETWORK),
                   "playlist 404");
  EXPECT_EQ(InitializeWith(nullptr).code(), media::PIPELINE_ERROR_NETWORK);
}

TEST_F(NativeHlsTest, FailureWithoutErrorIsCouldNotOpen) {
  EXPECT_EQ(InitializeWith(nullptr).code(),
            media::DEMUXER_ERROR_COULD_NOT_OPEN);
}

TEST_F(NativeHlsTest, ErrorWithoutRendererGoesToHost) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  EXPECT_CALL(host_, OnDemuxerError(media::HasStatusCode(
                         media::PIPELINE_ERROR_DECODE)));
  client_->OnError(media::PipelineStatus(media::PIPELINE_ERROR_DECODE), "");
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, ErrorWithRendererGoesToRendererClient) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  EXPECT_CALL(host_, OnDemuxerError(_)).Times(0);
  EXPECT_CALL(renderer_client_, OnError(media::HasStatusCode(
                                    media::PIPELINE_ERROR_DECODE)));
  client_->OnError(media::PipelineStatus(media::PIPELINE_ERROR_DECODE), "");
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, SkdKeyRequestRaisesEncrypted) {
  const std::string uri = "skd://key-1";
  EXPECT_CALL(encrypted_cb_,
              Run(media::EmeInitDataType::SKD,
                  std::vector<uint8_t>(uri.begin(), uri.end())));
  client_->OnEncrypted("skd", std::vector<uint8_t>(uri.begin(), uri.end()));
  task_environment_.RunUntilIdle();
}

// Key-session creation fails in generateRequest, on the CDM pipe. The
// native player stays usable and reports encrypted without a MediaError.
TEST_F(NativeHlsTest, AttachedKeySessionFailureKeepsNativePlayerUsable) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  NiceMock<media::MockCdmContext> cdm_context;
  cdm_context.set_cdm_id(base::UnguessableToken::Create());
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(true));
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_CALL(renderer_client_, OnError(_)).Times(0);
  EXPECT_CALL(renderer_client_, OnWaiting(_)).Times(0);
  const std::string uri = "skd://key-1";
  EXPECT_CALL(encrypted_cb_, Run(media::EmeInitDataType::SKD,
                               std::vector<uint8_t>(uri.begin(), uri.end())));
  client_->OnEncrypted("skd", std::vector<uint8_t>(uri.begin(), uri.end()));
  task_environment_.RunUntilIdle();
  EXPECT_CALL(attached_cb, Run(true));
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, LoadsGoToTheElementsLoader) {
  EXPECT_CALL(start_load_cb_, Run(_, _, _))
      .WillOnce([](media::mojom::FairPlayHlsRequestPtr request,
                   mojo::PendingReceiver<media::mojom::FairPlayHlsLoad>,
                   mojo::PendingRemote<media::mojom::FairPlayHlsLoadClient>) {
        EXPECT_EQ(request->url, GURL("https://media.example/v/0.ts"));
      });
  mojo::PendingRemote<media::mojom::FairPlayHlsLoad> load;
  mojo::PendingRemote<media::mojom::FairPlayHlsLoadClient> load_client;
  auto load_client_receiver = load_client.InitWithNewPipeAndPassReceiver();
  client_->StartLoad(media::mojom::FairPlayHlsRequest::New(
                         GURL("https://media.example/v/0.ts"), "GET",
                         base::flat_map<std::string, std::string>()),
                     load.InitWithNewPipeAndPassReceiver(),
                     std::move(load_client));
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, ClearKeyReachesThePlayer) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  const std::vector<uint8_t> key(16, 0x2a);
  demuxer_->ParcProvideClearKey("key-1", key);
  task_environment_.RunUntilIdle();
  ASSERT_EQ(player_.clear_keys_.size(), 1u);
  EXPECT_EQ(player_.clear_keys_[0].first, "key-1");
  EXPECT_EQ(player_.clear_keys_[0].second, key);
}

// WebKit's mediaEngineUpdated: a new player gets the element's target and
// disabled flag, before AVFoundation makes its AVPlayer.
class NativeHlsAirPlayTest : public NativeHlsTest {
 protected:
  void SetUp() override {
    initial_target_id_ = "6F1B3B57-0D0B-4B4A-9C55-3C3E2E3B1A11";
    initial_should_play_ = true;
    initial_wireless_disabled_ = true;
    NativeHlsTest::SetUp();
  }
};

TEST_F(NativeHlsAirPlayTest, TargetReachesThePlayerBeforeInitialize) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  ASSERT_EQ(player_.targets_.size(), 1u);
  EXPECT_EQ(player_.targets_[0].id, initial_target_id_);
  EXPECT_TRUE(player_.targets_[0].should_play);
  EXPECT_FALSE(player_.targets_[0].after_initialize);
  EXPECT_EQ(player_.wireless_disabled_, std::vector<bool>{true});
}

TEST_F(NativeHlsTest, AirPlayTargetChangesReachThePlayer) {
  demuxer_->ParcSetPlaybackTarget("6F1B3B57-0D0B-4B4A-9C55-3C3E2E3B1A11",
                                  true);
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  demuxer_->ParcSetPlaybackTarget("6F1B3B57-0D0B-4B4A-9C55-3C3E2E3B1A11",
                                  false);
  demuxer_->ParcSetWirelessVideoPlaybackDisabled(true);
  task_environment_.RunUntilIdle();
  ASSERT_EQ(player_.targets_.size(), 2u);
  // Set before the pipe was bound: sent with the load, before Initialize.
  EXPECT_TRUE(player_.targets_[0].should_play);
  EXPECT_FALSE(player_.targets_[0].after_initialize);
  EXPECT_FALSE(player_.targets_[1].should_play);
  EXPECT_TRUE(player_.targets_[1].after_initialize);
  EXPECT_EQ(player_.wireless_disabled_, std::vector<bool>{true});
}

TEST_F(NativeHlsTest, WirelessStateReachesTheElement) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  {
    InSequence sequence;
    EXPECT_CALL(wireless_cb_, Run(true));
    EXPECT_CALL(wireless_cb_, Run(false));
  }
  client_->OnPlaybackTargetIsWirelessChanged(true);
  client_->OnPlaybackTargetIsWirelessChanged(false);
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, KeyRequestComesBeforeEncrypted) {
  const std::string uri = "skd://key-1";
  {
    InSequence sequence;
    EXPECT_CALL(key_request_cb_, Run(uri));
    EXPECT_CALL(encrypted_cb_, Run(media::EmeInitDataType::SKD, _));
  }
  client_->OnKeyRequest(uri);
  client_->OnEncrypted("skd", std::vector<uint8_t>(uri.begin(), uri.end()));
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, WaitingForKeyReachesALaterRenderer) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  client_->OnWaiting(media::WaitingReason::kNoDecryptionKey);
  task_environment_.RunUntilIdle();
  EXPECT_CALL(renderer_client_,
              OnWaiting(media::WaitingReason::kNoDecryptionKey));
  CreateRenderer();
}

// The GPU player decides at each key request whether it held a CDM, as
// WebKit's player does (MediaPlayerPrivateAVFoundationObjC::
// shouldWaitForLoadingOfResource), and reports the wait only without one. A
// request that came before SetCdm reached it waits even when SetCdm's answer
// gets here first: the two cross on different pipes.
TEST_F(NativeHlsTest, WaitsWhenThePlayerSaysSoWithACdmAttached) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  NiceMock<media::MockCdmContext> cdm_context;
  cdm_context.set_cdm_id(base::UnguessableToken::Create());
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(true));
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_CALL(renderer_client_,
              OnWaiting(media::WaitingReason::kNoDecryptionKey));
  client_->OnWaiting(media::WaitingReason::kNoDecryptionKey);
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, WaitingWithACdmAttachedReachesALaterRenderer) {
  NiceMock<media::MockCdmContext> cdm_context;
  cdm_context.set_cdm_id(base::UnguessableToken::Create());
  demuxer_->SetCdmForNativePlayer(&cdm_context);
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  client_->OnWaiting(media::WaitingReason::kNoDecryptionKey);
  task_environment_.RunUntilIdle();
  EXPECT_CALL(renderer_client_,
              OnWaiting(media::WaitingReason::kNoDecryptionKey));
  CreateRenderer();
}

TEST_F(NativeHlsTest, ARefusedCdmMayBeOfferedAgain) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  player_.accepts_cdm_ = false;
  NiceMock<media::MockCdmContext> cdm_context;
  cdm_context.set_cdm_id(base::UnguessableToken::Create());
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(false));
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();

  player_.accepts_cdm_ = true;
  base::MockCallback<NativeHlsSource::CdmAttachedCB> again_cb;
  EXPECT_CALL(again_cb, Run(true));
  renderer_->SetCdm(&cdm_context, again_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(player_.cdm_ids_.size(), 2u);
}

// The pipeline hands the demuxer its CDM, then the renderer offers the same
// one: the offer is answered with the player's own answer to the first.
TEST_F(NativeHlsTest, ASecondOfferOfAnUnansweredCdmWaitsForThePlayer) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  player_.holds_cdm_answers_ = true;
  for (bool accepts : {false, true}) {
    SCOPED_TRACE(accepts ? "accepted" : "refused");
    NiceMock<media::MockCdmContext> cdm_context;
    cdm_context.set_cdm_id(base::UnguessableToken::Create());
    demuxer_->SetCdmForNativePlayer(&cdm_context);
    base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
    EXPECT_CALL(attached_cb, Run(_)).Times(0);
    renderer_->SetCdm(&cdm_context, attached_cb.Get());
    task_environment_.RunUntilIdle();
    testing::Mock::VerifyAndClearExpectations(&attached_cb);
    ASSERT_EQ(player_.cdm_answers_.size(), 1u);

    EXPECT_CALL(attached_cb, Run(accepts));
    std::move(player_.cdm_answers_[0]).Run(accepts);
    player_.cdm_answers_.clear();
    task_environment_.RunUntilIdle();
  }
}

// A CDM offered again after another one was sent goes to the player again
// and takes the answer to that SetCdm, not to its first one.
TEST_F(NativeHlsTest, ACdmOfferedAgainAfterAnotherTakesItsOwnAnswer) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  player_.holds_cdm_answers_ = true;
  NiceMock<media::MockCdmContext> first;
  first.set_cdm_id(base::UnguessableToken::Create());
  NiceMock<media::MockCdmContext> second;
  second.set_cdm_id(base::UnguessableToken::Create());
  base::MockCallback<NativeHlsSource::CdmAttachedCB> first_cb;
  base::MockCallback<NativeHlsSource::CdmAttachedCB> second_cb;
  base::MockCallback<NativeHlsSource::CdmAttachedCB> again_cb;
  renderer_->SetCdm(&first, first_cb.Get());
  renderer_->SetCdm(&second, second_cb.Get());
  renderer_->SetCdm(&first, again_cb.Get());
  task_environment_.RunUntilIdle();
  ASSERT_EQ(player_.cdm_answers_.size(), 3u);
  EXPECT_EQ(player_.cdm_ids_[2], *first.GetCdmId());

  EXPECT_CALL(first_cb, Run(true));
  EXPECT_CALL(second_cb, Run(true));
  EXPECT_CALL(again_cb, Run(_)).Times(0);
  std::move(player_.cdm_answers_[0]).Run(true);
  std::move(player_.cdm_answers_[1]).Run(true);
  task_environment_.RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&again_cb);

  EXPECT_CALL(again_cb, Run(false));
  std::move(player_.cdm_answers_[2]).Run(false);
  task_environment_.RunUntilIdle();
}

// A lost GPU player refuses the offers it hadn't answered, as MojoRenderer
// does.
TEST_F(NativeHlsTest, ALostPlayerRefusesUnansweredCdmOffers) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  player_.holds_cdm_answers_ = true;
  NiceMock<media::MockCdmContext> cdm_context;
  cdm_context.set_cdm_id(base::UnguessableToken::Create());
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  base::MockCallback<NativeHlsSource::CdmAttachedCB> again_cb;
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  renderer_->SetCdm(&cdm_context, again_cb.Get());
  task_environment_.RunUntilIdle();

  EXPECT_CALL(attached_cb, Run(false));
  EXPECT_CALL(again_cb, Run(false));
  EXPECT_CALL(renderer_client_,
              OnError(media::HasStatusCode(media::PIPELINE_ERROR_DISCONNECTED)));
  player_receiver_.reset();
  task_environment_.RunUntilIdle();
  player_.cdm_answers_.clear();
}

TEST_F(NativeHlsTest, BufferingStateFollowsPlaybackStart) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  {
    InSequence sequence;
    EXPECT_CALL(renderer_client_,
                OnBufferingStateChange(media::BUFFERING_HAVE_ENOUGH,
                                       media::BUFFERING_CHANGE_REASON_UNKNOWN));
    EXPECT_CALL(renderer_client_,
                OnBufferingStateChange(media::BUFFERING_HAVE_NOTHING,
                                       media::DEMUXER_UNDERFLOW));
    EXPECT_CALL(renderer_client_,
                OnBufferingStateChange(media::BUFFERING_HAVE_ENOUGH,
                                       media::BUFFERING_CHANGE_REASON_UNKNOWN));
  }
  // playbackLikelyToKeepUp before the pipeline starts: held until then.
  client_->OnBufferingStateChange(media::BUFFERING_HAVE_ENOUGH);
  task_environment_.RunUntilIdle();
  renderer_->StartPlayingFrom(base::TimeDelta());
  // Repeats aren't reported again.
  client_->OnBufferingStateChange(media::BUFFERING_HAVE_ENOUGH);
  client_->OnBufferingStateChange(media::BUFFERING_HAVE_NOTHING);
  task_environment_.RunUntilIdle();
  // A flush (seek) silences reports until playback starts again.
  base::MockCallback<base::OnceClosure> flush_cb;
  EXPECT_CALL(flush_cb, Run());
  renderer_->Flush(flush_cb.Get());
  client_->OnBufferingStateChange(media::BUFFERING_HAVE_ENOUGH);
  task_environment_.RunUntilIdle();
  renderer_->StartPlayingFrom(base::Seconds(30));
  task_environment_.RunUntilIdle();
}

// PipelineImpl posts a seek's completion right after StartPlayingFrom()
// returns, and WebMediaPlayerImpl drops buffering states that reach it before
// that completion. The state after every start comes in a later task, as
// RendererImpl's does, even when the player had enough data all along.
TEST_F(NativeHlsTest, StateAfterEveryStartComesInALaterTask) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  client_->OnBufferingStateChange(media::BUFFERING_HAVE_ENOUGH);
  task_environment_.RunUntilIdle();

  EXPECT_CALL(renderer_client_, OnBufferingStateChange(_, _)).Times(0);
  renderer_->StartPlayingFrom(base::TimeDelta());
  testing::Mock::VerifyAndClearExpectations(&renderer_client_);
  EXPECT_CALL(renderer_client_,
              OnBufferingStateChange(media::BUFFERING_HAVE_ENOUGH,
                                     media::BUFFERING_CHANGE_REASON_UNKNOWN))
      .Times(1);
  task_environment_.RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&renderer_client_);

  // A seek within what AVPlayer holds: no change reaches the facade.
  base::MockCallback<base::OnceClosure> flush_cb;
  EXPECT_CALL(flush_cb, Run());
  renderer_->Flush(flush_cb.Get());
  EXPECT_CALL(renderer_client_, OnBufferingStateChange(_, _)).Times(0);
  renderer_->StartPlayingFrom(base::Seconds(30));
  testing::Mock::VerifyAndClearExpectations(&renderer_client_);
  EXPECT_CALL(renderer_client_,
              OnBufferingStateChange(media::BUFFERING_HAVE_ENOUGH,
                                     media::BUFFERING_CHANGE_REASON_UNKNOWN))
      .Times(1);
  task_environment_.RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&renderer_client_);

  // A flush before the report: the next start reports, once.
  EXPECT_CALL(flush_cb, Run());
  renderer_->Flush(flush_cb.Get());
  renderer_->StartPlayingFrom(base::Seconds(40));
  EXPECT_CALL(flush_cb, Run());
  renderer_->Flush(flush_cb.Get());
  renderer_->StartPlayingFrom(base::Seconds(50));
  EXPECT_CALL(renderer_client_,
              OnBufferingStateChange(media::BUFFERING_HAVE_ENOUGH,
                                     media::BUFFERING_CHANGE_REASON_UNKNOWN))
      .Times(1);
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, RateAndVolumeDriveThePlayer) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  renderer_->StartPlayingFrom(base::TimeDelta());
  renderer_->SetPlaybackRate(1.5);
  renderer_->SetPlaybackRate(-1);
  renderer_->SetPlaybackRate(32);
  renderer_->SetPlaybackRate(0.01);
  renderer_->SetPlaybackRate(0);
  renderer_->SetVolume(0.25f);
  task_environment_.RunUntilIdle();
  EXPECT_EQ(player_.commands_, (std::vector<double>{1.5, -1, 32, 0.01, 0}));
  EXPECT_FLOAT_EQ(player_.volume_, 0.25f);
  EXPECT_EQ(renderer_->GetRendererType(), media::RendererType::kFairPlayHls);
}

TEST_F(NativeHlsTest, VolumeAndPitchSetBeforeInitializeReachThePlayer) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  // PipelineImpl::InitializeRenderer: a muted autoplay video is volume 0.
  renderer_ = std::make_unique<NativeHlsRenderer>(
      task_environment_.GetMainThreadTaskRunner(), &sink_);
  renderer_->SetPreservesPitch(false);
  renderer_->SetVolume(0);
  base::MockCallback<media::PipelineStatusCallback> init_cb;
  EXPECT_CALL(init_cb, Run(media::HasStatusCode(media::PIPELINE_OK)));
  renderer_->Initialize(demuxer_.get(), &renderer_client_, init_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_FLOAT_EQ(player_.volume_, 0.f);
  EXPECT_EQ(player_.preserves_pitch_, false);
}

TEST_F(NativeHlsTest, TimeComesFromThePlayersClock) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  client_->OnTimeUpdate(base::Seconds(7), 0, base::TimeTicks::Now());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(renderer_->GetMediaTime(), base::Seconds(7));

  // During a seek the target; after it, the target until the player reports.
  base::MockCallback<media::PipelineStatusCallback> seek_cb;
  EXPECT_CALL(seek_cb, Run(media::HasStatusCode(media::PIPELINE_OK)));
  demuxer_->Seek(base::Seconds(40), seek_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(player_.seek_time_, base::Seconds(40));
  EXPECT_EQ(player_.seek_tolerance_, base::TimeDelta());
  EXPECT_EQ(renderer_->GetMediaTime(), base::Seconds(40));
  std::move(player_.seek_cb_).Run(true, base::Seconds(40));
  task_environment_.RunUntilIdle();
  EXPECT_EQ(renderer_->GetMediaTime(), base::Seconds(40));
  EXPECT_EQ(demuxer_->ParcTakeFastSeekLanding(), std::nullopt);
}

// The player's backward jump reaches the element (WebKit's
// mediaPlayerTimeChanged), unless a seek the player hadn't received answers
// for the time.
TEST_F(NativeHlsTest, TimeJumpedBackwardReachesTheElement) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  EXPECT_CALL(time_jumped_cb_, Run()).Times(1);
  client_->OnTimeUpdate(base::Seconds(4), 1, base::TimeTicks::Now());
  client_->OnTimeJumpedBackward(0);
  task_environment_.RunUntilIdle();
  EXPECT_EQ(renderer_->GetMediaTime().InSeconds(), 4);
  testing::Mock::VerifyAndClearExpectations(&time_jumped_cb_);

  EXPECT_CALL(time_jumped_cb_, Run()).Times(0);
  base::MockCallback<media::PipelineStatusCallback> seek_cb;
  EXPECT_CALL(seek_cb, Run(media::HasStatusCode(media::PIPELINE_OK)));
  demuxer_->Seek(base::Seconds(40), seek_cb.Get());
  client_->OnTimeJumpedBackward(0);
  task_environment_.RunUntilIdle();
  std::move(player_.seek_cb_).Run(true, base::Seconds(40));
  task_environment_.RunUntilIdle();
  EXPECT_EQ(renderer_->GetMediaTime().InSeconds(), 40);

  demuxer_->Stop();
  client_->OnTimeJumpedBackward(1);
  task_environment_.RunUntilIdle();
}

// A jump after the player finished a seek whose reply is still to come: the
// seek keeps the time the player jumped to.
TEST_F(NativeHlsTest, TimeJumpedBackwardAfterSeekKeepsItsTime) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  EXPECT_CALL(time_jumped_cb_, Run()).Times(0);
  base::MockCallback<media::PipelineStatusCallback> seek_cb;
  EXPECT_CALL(seek_cb, Run(media::HasStatusCode(media::PIPELINE_OK)));
  demuxer_->Seek(base::Seconds(40), seek_cb.Get());
  task_environment_.RunUntilIdle();
  client_->OnTimeUpdate(base::Seconds(40), 0, base::TimeTicks::Now());
  client_->OnTimeUpdate(base::Seconds(12), 0, base::TimeTicks::Now());
  client_->OnTimeJumpedBackward(1);
  task_environment_.RunUntilIdle();
  std::move(player_.seek_cb_).Run(true, base::Seconds(40));
  task_environment_.RunUntilIdle();
  EXPECT_EQ(renderer_->GetMediaTime(), base::Seconds(12));
}

// HTMLMediaElement.fastSeek: the tolerance reaches AVPlayer for the seek to
// its target only, and the clock and the pipeline take where it landed.
TEST_F(NativeHlsTest, FastSeekLandsWhereThePlayerDid) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  base::MockCallback<media::PipelineStatusCallback> seek_cb;
  EXPECT_CALL(seek_cb, Run(media::HasStatusCode(media::PIPELINE_OK))).Times(2);

  demuxer_->ParcSetFastSeek(base::Seconds(30), base::Seconds(12));
  demuxer_->Seek(base::Seconds(20), seek_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(player_.seek_tolerance_, base::TimeDelta());
  std::move(player_.seek_cb_).Run(true, base::Seconds(20));
  task_environment_.RunUntilIdle();
  EXPECT_EQ(demuxer_->ParcTakeFastSeekLanding(), std::nullopt);

  demuxer_->Seek(base::Seconds(30), seek_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(player_.seek_tolerance_, base::Seconds(12));
  std::move(player_.seek_cb_).Run(true, base::Seconds(24));
  task_environment_.RunUntilIdle();
  EXPECT_EQ(renderer_->GetMediaTime(), base::Seconds(24));
  EXPECT_EQ(demuxer_->ParcTakeFastSeekLanding(), base::Seconds(24));
  EXPECT_EQ(demuxer_->ParcTakeFastSeekLanding(), std::nullopt);
}

TEST_F(NativeHlsTest, EndedOncePerRun) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  CreateRenderer();
  EXPECT_CALL(renderer_client_, OnEnded()).Times(1);
  // Not before playback starts, then once.
  client_->OnEnded();
  task_environment_.RunUntilIdle();
  renderer_->StartPlayingFrom(base::TimeDelta());
  client_->OnEnded();
  client_->OnEnded();
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, LayerPaintsAHoleFrame) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  const base::UnguessableToken token = base::UnguessableToken::Create();
  // Registered before the renderer exists: replayed when it attaches.
  client_->OnLayerRegistered(token, gfx::Size(1920, 1080));
  task_environment_.RunUntilIdle();
  EXPECT_CALL(sink_, PaintSingleFrame(_, true))
      .WillOnce([](scoped_refptr<media::VideoFrame> frame, bool) {
        ASSERT_TRUE(frame);
        EXPECT_EQ(frame->natural_size(), gfx::Size(1920, 1080));
      });
  CreateRenderer();
  // A new size repaints after the element hears it.
  {
    InSequence sequence;
    EXPECT_CALL(renderer_client_,
                OnVideoNaturalSizeChange(gfx::Size(1280, 720)));
    EXPECT_CALL(sink_, PaintSingleFrame(_, true));
  }
  client_->OnNaturalSizeChange(gfx::Size(1280, 720));
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, CdmReachesThePlayerByIdOnce) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  NiceMock<media::MockCdmContext> cdm_context;
  const base::UnguessableToken cdm_id = base::UnguessableToken::Create();
  cdm_context.set_cdm_id(cdm_id);
  demuxer_->SetCdmForNativePlayer(&cdm_context);
  CreateRenderer();
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(true));
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(player_.cdm_ids_,
            (std::vector<std::optional<base::UnguessableToken>>{cdm_id}));
}

// setMediaKeys(null) on a Safari-identity page (PipelineImpl's
// SetCdm(nullptr)): the player detaches the CDM, as WebKit's
// cdmInstanceDetached, and the same MediaKeys set again reach it again.
TEST_F(NativeHlsTest, NullCdmDetachesAndTheSameCdmReattaches) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  NiceMock<media::MockCdmContext> cdm_context;
  const base::UnguessableToken cdm_id = base::UnguessableToken::Create();
  cdm_context.set_cdm_id(cdm_id);
  NiceMock<media::MockCdmContext> other_cdm_context;
  const base::UnguessableToken other_cdm_id = base::UnguessableToken::Create();
  other_cdm_context.set_cdm_id(other_cdm_id);
  CreateRenderer();
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(true)).Times(7);
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  renderer_->SetCdm(nullptr, attached_cb.Get());
  task_environment_.RunUntilIdle();

  // Set again, including before the null's reply, it reaches the player.
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  renderer_->SetCdm(nullptr, attached_cb.Get());
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  renderer_->SetCdm(nullptr, attached_cb.Get());
  renderer_->SetCdm(&other_cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(player_.cdm_ids_,
            (std::vector<std::optional<base::UnguessableToken>>{
                cdm_id, std::nullopt, cdm_id, std::nullopt, cdm_id,
                std::nullopt, other_cdm_id}));
}

// A replacement the player refuses leaves it the CDM before, which a null
// then detaches.
TEST_F(NativeHlsTest, NullCdmDetachesAfterARefusedReplacement) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  NiceMock<media::MockCdmContext> cdm_context;
  const base::UnguessableToken cdm_id = base::UnguessableToken::Create();
  cdm_context.set_cdm_id(cdm_id);
  NiceMock<media::MockCdmContext> other_cdm_context;
  const base::UnguessableToken other_cdm_id = base::UnguessableToken::Create();
  other_cdm_context.set_cdm_id(other_cdm_id);
  CreateRenderer();
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  {
    InSequence sequence;
    EXPECT_CALL(attached_cb, Run(true));
    EXPECT_CALL(attached_cb, Run(false));
    EXPECT_CALL(attached_cb, Run(true));
  }
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  player_.accepts_cdm_ = false;
  renderer_->SetCdm(&other_cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  player_.accepts_cdm_ = true;
  renderer_->SetCdm(nullptr, attached_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(player_.cdm_ids_,
            (std::vector<std::optional<base::UnguessableToken>>{
                cdm_id, other_cdm_id, std::nullopt}));
}

TEST_F(NativeHlsTest, EarlyCdmOfferWaitsForThePlayersAcceptanceOrRefusal) {
  NiceMock<media::MockCdmContext> cdm_context;
  cdm_context.set_cdm_id(base::UnguessableToken::Create());
  player_.holds_cdm_answers_ = true;
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(testing::_)).Times(0);
  demuxer_->SetCdmForNativePlayer(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  ASSERT_EQ(1u, player_.cdm_answers_.size());
  testing::Mock::VerifyAndClearExpectations(&attached_cb);
  EXPECT_CALL(attached_cb, Run(false));
  std::move(player_.cdm_answers_[0]).Run(false);
  task_environment_.RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&attached_cb);
  EXPECT_CALL(attached_cb, Run(testing::_)).Times(0);
  demuxer_->SetCdmForNativePlayer(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  ASSERT_EQ(2u, player_.cdm_answers_.size());
  testing::Mock::VerifyAndClearExpectations(&attached_cb);
  EXPECT_CALL(attached_cb, Run(true));
  std::move(player_.cdm_answers_[1]).Run(true);
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, LoadStoppedWithoutAPlayerResolvesEarlyCdmOffer) {
  NiceMock<media::MockCdmContext> cdm_context;
  cdm_context.set_cdm_id(base::UnguessableToken::Create());
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(testing::_)).Times(0);
  demuxer_->SetCdm(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&attached_cb);
  EXPECT_CALL(attached_cb, Run(true));
  demuxer_->Stop();
}

TEST_F(NativeHlsTest, StoppingAStartedPlayerRefusesEarlyCdmOffer) {
  NiceMock<media::MockCdmContext> cdm_context;
  cdm_context.set_cdm_id(base::UnguessableToken::Create());
  player_.holds_cdm_answers_ = true;
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(testing::_)).Times(0);
  demuxer_->SetCdm(&cdm_context, attached_cb.Get());
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  testing::Mock::VerifyAndClearExpectations(&attached_cb);
  EXPECT_CALL(attached_cb, Run(false));
  demuxer_->Stop();
}

TEST_F(NativeHlsTest, ANewCdmOfferAfterPlayerLossIsRefused) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  player_receiver_.reset();
  task_environment_.RunUntilIdle();
  NiceMock<media::MockCdmContext> cdm_context;
  cdm_context.set_cdm_id(base::UnguessableToken::Create());
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(false));
  demuxer_->SetCdmForNativePlayer(&cdm_context, attached_cb.Get());
  task_environment_.RunUntilIdle();
}

TEST_F(NativeHlsTest, CdmSetBeforeInitializeReachesThePlayer) {
  ASSERT_TRUE(InitializeWith(Metadata(base::Seconds(60))).is_ok());
  NiceMock<media::MockCdmContext> cdm_context;
  const base::UnguessableToken cdm_id = base::UnguessableToken::Create();
  cdm_context.set_cdm_id(cdm_id);
  // PipelineImpl::InitializeRenderer sets the CDM first.
  renderer_ = std::make_unique<NativeHlsRenderer>(
      task_environment_.GetMainThreadTaskRunner(), &sink_);
  base::MockCallback<NativeHlsSource::CdmAttachedCB> attached_cb;
  EXPECT_CALL(attached_cb, Run(true));
  renderer_->SetCdm(&cdm_context, attached_cb.Get());
  base::MockCallback<media::PipelineStatusCallback> init_cb;
  EXPECT_CALL(init_cb, Run(media::HasStatusCode(media::PIPELINE_OK)));
  renderer_->Initialize(demuxer_.get(), &renderer_client_, init_cb.Get());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(player_.cdm_ids_,
            (std::vector<std::optional<base::UnguessableToken>>{cdm_id}));
}

}  // namespace
}  // namespace parc::fairplay
