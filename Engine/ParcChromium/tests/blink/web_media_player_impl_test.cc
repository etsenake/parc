// Copyright 2026 Parc contributors.
// The fixture is derived from Chromium's web_media_player_impl_unittest.cc
// (Copyright 2016 The Chromium Authors; BSD-style license in Chromium's
// LICENSE) and contains only Parc's media-player regressions.

#include "third_party/blink/renderer/platform/media/web_media_player_impl.h"

#include "base/test/scoped_command_line.h"
#include "media/base/parc_av1_support.h"

#include <stdint.h>

#include <algorithm>
#include <atomic>
#include <memory>
#include <string>
#include <string_view>
#include <utility>

#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/ref_counted.h"
#include "base/memory/scoped_refptr.h"
#include "base/run_loop.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/stringprintf.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/test/bind.h"
#include "base/test/gmock_callback_support.h"
#include "base/test/metrics/histogram_tester.h"
#include "base/test/mock_callback.h"
#include "base/test/run_until.h"
#include "base/test/scoped_feature_list.h"
#include "base/threading/thread.h"
#include "base/time/time.h"
#include "base/trace_event/memory_dump_manager.h"
#include "build/build_config.h"
#include "cc/layers/layer.h"
#include "components/viz/test/test_context_provider.h"
#include "media/base/decoder_buffer.h"
#include "media/base/key_systems_impl.h"
#include "media/base/media_content_type.h"
#include "media/base/media_log.h"
#include "media/base/media_observer.h"
#include "media/base/media_switches.h"
#include "media/base/mock_audio_renderer_sink.h"
#include "media/base/mock_filters.h"
#include "media/base/mock_media_log.h"
#include "media/base/test_data_util.h"
#include "media/base/test_helpers.h"
#include "media/base/mock_demuxer_host.h"
#include "media/cdm/clear_key_cdm_common.h"
#include "media/filters/chunk_demuxer.h"
#include "media/filters/pipeline_controller.h"
#if BUILDFLAG(ENABLE_HLS_DEMUXER)
#include "media/filters/hls_data_source_provider_impl.h"
#endif
#include "media/mojo/mojom/media_metrics_provider.mojom-blink.h"
#include "media/mojo/services/media_metrics_provider.h"
#include "media/mojo/services/video_decode_stats_recorder.h"
#include "media/mojo/services/watch_time_recorder.h"
#include "media/renderers/default_decoder_factory.h"
#include "media/renderers/renderer_impl_factory.h"
#include "mojo/public/cpp/bindings/pending_associated_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/common/thread_safe_browser_interface_broker_proxy.h"
#include "third_party/blink/public/common/tokens/tokens.h"
#include "third_party/blink/public/platform/cross_variant_mojo_util.h"
#include "third_party/blink/public/platform/media/web_media_player_builder.h"
#include "third_party/blink/public/platform/media/web_media_player_delegate.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/public/platform/web_media_player_encrypted_media_client.h"
#include "third_party/blink/public/platform/web_media_player_source.h"
#include "third_party/blink/public/platform/web_security_origin.h"
#include "third_party/blink/public/platform/web_surface_layer_bridge.h"
#include "third_party/blink/public/platform/web_url_response.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_local_frame_client.h"
#include "third_party/blink/public/web/web_testing_support.h"
#include "third_party/blink/public/web/web_view.h"
#include "third_party/blink/public/web/web_widget.h"
#include "third_party/blink/renderer/core/frame/frame_test_helpers.h"
#include "third_party/blink/renderer/platform/content_decryption_module_result.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/persistent.h"
#include "third_party/blink/renderer/platform/media/buffered_data_source_host_impl.h"
#include "third_party/blink/renderer/platform/media/media_player_client.h"
#include "third_party/blink/renderer/platform/media/parc_media_player_client.h"
#include "third_party/blink/renderer/platform/media/parc_web_media_player_rules.h"
#include "third_party/blink/renderer/platform/media/parc_web_media_player_state.h"
#include "third_party/blink/renderer/platform/media/power_status_helper.h"
#include "third_party/blink/renderer/platform/media/resource_multi_buffer_data_provider.h"
#include "third_party/blink/renderer/platform/media/testing/mock_resource_fetch_context.h"
#include "third_party/blink/renderer/platform/media/testing/mock_web_associated_url_loader.h"
#include "third_party/blink/renderer/platform/media/video_decode_stats_reporter.h"
#include "third_party/blink/renderer/platform/media/video_frame_compositor.h"
#include "third_party/blink/renderer/platform/media/web_audio_source_provider_client.h"
#include "third_party/blink/renderer/platform/media/web_content_decryption_module_impl.h"
#include "third_party/blink/renderer/platform/scheduler/public/page_scheduler.h"
#include "third_party/blink/renderer/platform/testing/task_environment.h"
#include "third_party/blink/renderer/platform/weborigin/kurl.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "third_party/blink/renderer/platform/wtf/vector.h"
#include "ui/gfx/geometry/size.h"

namespace blink {

namespace {

using ::base::test::RunClosure;
using ::base::test::RunOnceCallback;
using ::media::TestAudioConfig;
using ::media::TestVideoConfig;
using ::testing::_;
using ::testing::AnyNumber;
using ::testing::InSequence;
using ::testing::NiceMock;
using ::testing::Return;
using ::testing::ReturnRef;
using ::testing::StrictMock;
using ::testing::WithoutArgs;

constexpr char kAudioOnlyTestFile[] = "sfx-opus-441.webm";
constexpr char kVideoOnlyTestFile[] = "bear-320x240-video-only.webm";

constexpr base::TimeDelta kAudioOnlyTestFileDuration = base::Milliseconds(296);

enum class BackgroundBehaviorType { Page, Frame };

MATCHER(NonNullNonEmptySpan, "") {
  return arg.data() && !arg.empty();
}

class MockMediaObserver : public media::MediaObserver {
 public:
  MOCK_METHOD1(OnBecameDominantVisibleContent, void(bool));
  MOCK_METHOD1(OnMetadataChanged, void(const media::PipelineMetadata&));
  MOCK_METHOD1(OnRemotePlaybackDisabled, void(bool));
  MOCK_METHOD0(OnMediaRemotingRequested, void());
  MOCK_METHOD0(OnHlsManifestDetected, void());
  MOCK_METHOD0(OnPlaying, void());
  MOCK_METHOD0(OnPaused, void());
  MOCK_METHOD0(OnFrozen, void());
  MOCK_METHOD1(OnDataSourceInitialized, void(const GURL&));
  MOCK_METHOD1(SetClient, void(media::MediaObserverClient*));

  base::WeakPtr<MediaObserver> AsWeakPtr() {
    return weak_ptr_factory_.GetWeakPtr();
  }

 private:
  base::WeakPtrFactory<MediaObserver> weak_ptr_factory_{this};
};

class MockWebMediaPlayerClient
    : public GarbageCollected<MockWebMediaPlayerClient>,
      public MediaPlayerClient,
      public ParcMediaPlayerClient {
 public:
  MockWebMediaPlayerClient() = default;

  void Trace(Visitor* visitor) const override {
    MediaPlayerClient::Trace(visitor);
  }

  MockWebMediaPlayerClient(const MockWebMediaPlayerClient&) = delete;
  MockWebMediaPlayerClient& operator=(const MockWebMediaPlayerClient&) = delete;

  MOCK_METHOD0(NetworkStateChanged, void());
  MOCK_METHOD0(ReadyStateChanged, void());
  MOCK_METHOD0(TimeChanged, void());
  MOCK_METHOD0(Repaint, void());
  MOCK_METHOD0(DurationChanged, void());
  MOCK_METHOD0(SizeChanged, void());
  MOCK_METHOD1(SetCcLayer, void(cc::Layer*));
  MOCK_METHOD1(AddTrack, void(const media::MediaTrack& track));
  MOCK_METHOD1(RemoveTrack, void(const media::MediaTrack&));
  MOCK_METHOD2(SetTrackState,
               void(const media::MediaTrack&, media::MediaTrack::State));
  MOCK_METHOD1(MediaSourceOpened, void(std::unique_ptr<WebMediaSource>));
  MOCK_METHOD2(RemotePlaybackCompatibilityChanged, void(const KURL&, bool));
  MOCK_METHOD0(WasAlwaysMuted, bool());
  MOCK_METHOD0(HasSelectedVideoTrack, bool());
  MOCK_METHOD0(GetSelectedVideoTrackId, WebMediaPlayer::TrackId());
  MOCK_METHOD0(HasNativeControls, bool());
  MOCK_METHOD0(IsAudioElement, bool());
  MOCK_CONST_METHOD0(GetDisplayType, WebMediaPlayer::DisplayType());
  MOCK_CONST_METHOD0(IsInAutoPIP, bool());
  MOCK_METHOD1(MediaRemotingStarted, void(const WebString&));
  MOCK_METHOD1(MediaRemotingStopped, void(int));
  MOCK_METHOD0(PictureInPictureStopped, void());
  MOCK_METHOD0(OnPictureInPictureStateChange, void());
  MOCK_CONST_METHOD0(CouldPlayIfEnoughData, bool());
  MOCK_METHOD0(ResumePlayback, void());
  MOCK_METHOD1(PausePlayback, void(WebMediaPlayer::PauseReason));
  MOCK_METHOD0(DidPlayerStartPlaying, void());
  MOCK_METHOD1(DidPlayerPaused, void(bool));
  MOCK_METHOD1(DidPlayerMutedStatusChange, void(bool));
  MOCK_METHOD6(DidMediaMetadataChange,
               void(bool,
                    bool,
                    media::AudioCodec,
                    media::VideoCodec,
                    media::MediaContentType,
                    bool));
  MOCK_METHOD4(DidPlayerMediaPositionStateChange,
               void(double,
                    base::TimeDelta,
                    base::TimeDelta position,
                    bool end_of_media));
  MOCK_METHOD0(DidDisableAudioOutputSinkChanges, void());
  MOCK_METHOD1(DidUseAudioServiceChange, void(bool uses_audio_service));
  MOCK_METHOD1(DidPlayerSizeChange, void(const gfx::Size&));
  ParcMediaPlayerClient* ParcClient() override { return this; }
  MOCK_METHOD3(ParcReportMediaMetadata,
               void(bool, bool, media::MediaContentType));
  MOCK_METHOD1(OnRemotePlaybackDisabled, void(bool));
  MOCK_METHOD0(OnFrameHidden, void());
  MOCK_METHOD0(OnFrameShown, void());
  MOCK_METHOD0(DidBufferUnderflow, void());
  MOCK_METHOD0(DidSeek, void());
  MOCK_METHOD2(OnFirstFrame, void(base::TimeTicks, size_t));
  MOCK_METHOD0(OnRequestVideoFrameCallback, void());
  MOCK_METHOD0(GetElementId, int());
  MOCK_CONST_METHOD0(PresentsParcSafariIdentity, bool());
};

class MockWebMediaPlayerEncryptedMediaClient
    : public WebMediaPlayerEncryptedMediaClient {
 public:
  MockWebMediaPlayerEncryptedMediaClient() = default;

  MockWebMediaPlayerEncryptedMediaClient(
      const MockWebMediaPlayerEncryptedMediaClient&) = delete;
  MockWebMediaPlayerEncryptedMediaClient& operator=(
      const MockWebMediaPlayerEncryptedMediaClient&) = delete;

  MOCK_METHOD2(Encrypted,
               void(media::EmeInitDataType, base::span<const uint8_t>));
  MOCK_METHOD0(DidBlockPlaybackWaitingForKey, void());
  MOCK_METHOD0(DidResumePlaybackBlockedForKey, void());
};

#if BUILDFLAG(IS_MAC)
class ParcKeyRequestCdmContext : public media::CdmContext {
 public:
  std::unique_ptr<media::CallbackRegistration> RegisterEventCB(
      EventCB event_cb) override {
    return event_callbacks_.Register(std::move(event_cb));
  }

  bool RequiresFairPlayRenderer() override {
    return requires_fairplay_renderer;
  }

  void ParcHasSessionForInitData(media::EmeInitDataType init_data_type,
                                 const std::vector<uint8_t>& init_data,
                                 ParcHasSessionForInitDataCB done) override {
    asked_types.push_back(init_data_type);
    const bool has_session =
        (init_data_type == media::EmeInitDataType::SKD ||
         init_data_type == media::EmeInitDataType::SINF ||
         init_data_type == media::EmeInitDataType::MPTS) &&
        std::ranges::find(requested_keys, init_data) != requested_keys.end();
    if (defer_answers) {
      deferred_answers.push_back(base::BindOnce(std::move(done), has_session));
      return;
    }
    std::move(done).Run(has_session);
  }

  void AnswerDeferred() {
    for (base::OnceClosure& answer : std::exchange(deferred_answers, {})) {
      std::move(answer).Run();
    }
  }

  void NotifyStatusesChanged() {
    event_callbacks_.Notify(Event::kParcKeyStatusesChanged);
  }

  void NotifyAdditionalUsableKey() {
    event_callbacks_.Notify(Event::kHasAdditionalUsableKey);
  }

  std::vector<std::vector<uint8_t>> requested_keys;
  std::vector<media::EmeInitDataType> asked_types;
  bool requires_fairplay_renderer = false;
  bool defer_answers = false;
  std::vector<base::OnceClosure> deferred_answers;

 private:
  media::CallbackRegistry<EventCB::RunType> event_callbacks_;
};

class ParcCdmContextRef : public media::CdmContextRef {
 public:
  explicit ParcCdmContextRef(media::CdmContext* cdm_context)
      : cdm_context_(cdm_context) {}
  media::CdmContext* GetCdmContext() override { return cdm_context_; }

 private:
  raw_ptr<media::CdmContext> cdm_context_;
};

std::vector<uint8_t> SkdInitData(std::string_view uri) {
  return std::vector<uint8_t>(uri.begin(), uri.end());
}
#endif

#if BUILDFLAG(IS_MAC)
class ParcFairPlayCdmContext : public media::MockCdmContext {
 public:
  bool RequiresFairPlayRenderer() override { return true; }
  void ParcHasSessionForInitData(media::EmeInitDataType init_data_type,
                                 const std::vector<uint8_t>& init_data,
                                 ParcHasSessionForInitDataCB done) override {
    std::move(done).Run(true);
  }
};

class ParcCdmResult final : public ContentDecryptionModuleResult {
 public:
  void Complete() override { completed = true; }
  void CompleteWithContentDecryptionModule(
      std::unique_ptr<WebContentDecryptionModule>) override {}
  void CompleteWithSession(
      WebContentDecryptionModuleResult::SessionStatus) override {}
  void CompleteWithKeyStatus(
      WebEncryptedMediaKeyInformation::KeyStatus) override {}
  void CompleteWithError(WebContentDecryptionModuleException,
                         uint32_t,
                         const WebString&) override {
    failed = true;
  }

  bool completed = false;
  bool failed = false;
};
#endif

class MockWebMediaPlayerDelegate : public WebMediaPlayerDelegate {
 public:
  MockWebMediaPlayerDelegate() = default;
  ~MockWebMediaPlayerDelegate() override = default;

  int AddObserver(Observer* observer) override {
    DCHECK_EQ(nullptr, observer_);
    observer_ = observer;
    return player_id_;
  }

  void RemoveObserver(int player_id) override {
    DCHECK_EQ(player_id_, player_id);
    observer_ = nullptr;
  }

  MOCK_METHOD4(DidMediaMetadataChange,
               void(int, bool, bool, media::MediaContentType));

  void DidPlay(int player_id) override { DCHECK_EQ(player_id_, player_id); }

  void DidPause(int player_id, bool reached_end_of_stream) override {
    DCHECK_EQ(player_id_, player_id);
  }

  void PlayerGone(int player_id) override { DCHECK_EQ(player_id_, player_id); }

  void SetIdle(int player_id, bool is_idle) override {
    DCHECK_EQ(player_id_, player_id);
    is_idle_ = is_idle;
    is_stale_ &= is_idle;
  }

  bool IsIdle(int player_id) override {
    DCHECK_EQ(player_id_, player_id);
    return is_idle_;
  }

  void ClearStaleFlag(int player_id) override {
    DCHECK_EQ(player_id_, player_id);
    is_stale_ = false;
  }

  bool IsStale(int player_id) override {
    DCHECK_EQ(player_id_, player_id);
    return is_stale_;
  }

  bool IsPageHidden() override { return is_page_hidden_; }

  void SetPageHiddenForTesting(bool is_page_hidden) {
    is_page_hidden_ = is_page_hidden;
  }

  int player_id() { return player_id_; }
  bool has_observer() const { return observer_; }

 private:
  raw_ptr<Observer, UnprotectedInRelease | DanglingUntriaged> observer_ =
      nullptr;
  int player_id_ = 1234;
  bool is_idle_ = false;
  bool is_stale_ = false;
  bool is_page_hidden_ = false;
};

class MockSurfaceLayerBridge : public WebSurfaceLayerBridge {
 public:
  MOCK_CONST_METHOD0(GetCcLayer, cc::Layer*());
  MOCK_CONST_METHOD0(GetFrameSinkId, const viz::FrameSinkId&());
  MOCK_CONST_METHOD0(GetSurfaceId, const viz::SurfaceId&());
  MOCK_METHOD0(ClearSurfaceId, void());
  MOCK_METHOD1(SetContentsOpaque, void(bool));
  MOCK_METHOD0(CreateSurfaceLayer, void());
  MOCK_METHOD0(ClearObserver, void());
  MOCK_METHOD0(RegisterFrameSinkHierarchy, void());
  MOCK_METHOD0(UnregisterFrameSinkHierarchy, void());
  MOCK_METHOD1(ReparentFrameSinkHierarchy, void(const viz::FrameSinkId&));
};

class MockVideoFrameCompositor : public VideoFrameCompositor {
 public:
  MockVideoFrameCompositor(
      const scoped_refptr<base::SingleThreadTaskRunner>& task_runner)
      : VideoFrameCompositor(task_runner, nullptr) {}
  ~MockVideoFrameCompositor() override = default;

  MOCK_METHOD1(SetOnFramePresentedCallback, void(OnNewFramePresentedCB));
  MOCK_METHOD1(SetIsPageVisible, void(bool));
  MOCK_METHOD0(
      GetLastPresentedFrameMetadata,
      std::unique_ptr<WebMediaPlayer::VideoFramePresentationMetadata>());
  MOCK_METHOD0(GetCurrentFrameOnAnyThread, scoped_refptr<media::VideoFrame>());
  MOCK_METHOD1(UpdateCurrentFrameIfStale,
               void(VideoFrameCompositor::UpdateType));
  MOCK_METHOD3(EnableSubmission,
               void(const viz::SurfaceId&, media::VideoTransformation, bool));
};

}

class ParcWebMediaPlayerImplTest
    : public testing::Test,
      private WebTestingSupport::WebScopedMockScrollbars {
 public:
  base::test::ScopedCommandLine av1_command_line_;

  ParcWebMediaPlayerImplTest()
      : media_thread_("MediaThreadForTest"),
        context_provider_(viz::TestContextProvider::CreateGLES()),
        audio_parameters_(media::TestAudioParameters::Normal()),
        client_(MakeGarbageCollected<NiceMock<MockWebMediaPlayerClient>>()),
        memory_dump_manager_(
            base::trace_event::MemoryDumpManager::CreateInstanceForTesting()) {
    av1_command_line_.GetProcessCommandLine()->AppendSwitchASCII(
        media::kParcAV1HardwareDecoder, "1");
    web_view_helper_.Initialize();
    media_thread_.StartAndWaitForTesting();
  }

  void InitializeSurfaceLayerBridge() {
    surface_layer_bridge_ =
        std::make_unique<NiceMock<MockSurfaceLayerBridge>>();
    surface_layer_bridge_ptr_ = surface_layer_bridge_.get();

    EXPECT_CALL(*client_, SetCcLayer(_)).Times(0);
    ON_CALL(*surface_layer_bridge_ptr_, GetSurfaceId())
        .WillByDefault(ReturnRef(surface_id_));
  }

  ParcWebMediaPlayerImplTest(const ParcWebMediaPlayerImplTest&) = delete;
  ParcWebMediaPlayerImplTest& operator=(const ParcWebMediaPlayerImplTest&) = delete;

  ~ParcWebMediaPlayerImplTest() override {
    if (!wmpi_)
      return;
    EXPECT_CALL(*client_, SetCcLayer(nullptr));
    EXPECT_CALL(*client_, MediaRemotingStopped(_));

    wmpi_->Shutdown();
    wmpi_.reset();
    if (parc_demuxer_) {
      parc_demuxer_->Shutdown();
    }

    CycleThreads();
  }

 protected:
  void InitializeWebMediaPlayerImpl(
      std::unique_ptr<media::Demuxer> demuxer_override = nullptr) {
    EXPECT_CALL(*this, IsShuttingDown())
        .Times(AnyNumber())
        .WillRepeatedly(Return(false));

    auto media_log = std::make_unique<NiceMock<media::MockMediaLog>>();
    InitializeSurfaceLayerBridge();

    ASSERT_FALSE(media_log_) << "Reinitialization of media_log_ is disallowed";
    media_log_ = media_log.get();

    auto factory_selector = std::make_unique<media::RendererFactorySelector>();
    renderer_factory_selector_ = factory_selector.get();
    decoder_factory_ = std::make_unique<media::DefaultDecoderFactory>(nullptr);
    media::MediaPlayerLoggingID player_id =
        media::GetNextMediaPlayerLoggingID();
#if BUILDFLAG(IS_ANDROID)
    factory_selector->AddBaseFactory(
        media::RendererType::kRendererImpl,
        std::make_unique<media::RendererImplFactory>(
            media_log.get(), decoder_factory_.get(),
            media::RendererImplFactory::GetGpuFactoriesCB(), player_id));
    factory_selector->StartRequestRemotePlayStateCB(base::DoNothing());
#else
    factory_selector->AddBaseFactory(
        media::RendererType::kRendererImpl,
        std::make_unique<media::RendererImplFactory>(
            media_log.get(), decoder_factory_.get(),
            media::RendererImplFactory::GetGpuFactoriesCB(), player_id,
            nullptr));
#endif

    mojo::Remote<media::mojom::blink::MediaMetricsProvider> provider;
    media::MediaMetricsProvider::Create(
        media::MediaMetricsProvider::BrowsingMode::kNormal,
        media::MediaMetricsProvider::FrameStatus::kNotTopFrame,
        ukm::kInvalidSourceId, media::VideoDecodePerfHistory::SaveCallback(),
        BindRepeating(&ParcWebMediaPlayerImplTest::IsShuttingDown,
                      Unretained(this)),
        media::PictureInPictureEventsInfo::AutoPipReasonCallback(),
        CrossVariantMojoReceiver<
            media::mojom::MediaMetricsProviderInterfaceBase>(
            provider.BindNewPipeAndPassReceiver()));

    provider->Initialize(false, media::mojom::MediaURLScheme::kHttp,
                         media::mojom::MediaStreamType::kNone);

    audio_sink_ =
        base::MakeRefCounted<NiceMock<media::MockAudioRendererSink>>();

    url_index_ = std::make_unique<UrlIndex>(&mock_resource_fetch_context_,
                                            media_thread_.task_runner());

    auto compositor = std::make_unique<NiceMock<MockVideoFrameCompositor>>(
        media_thread_.task_runner());
    compositor_ = compositor.get();

    CHECK(!wmpi_);
    WebLocalFrame* frame = GetWebLocalFrame();
    wmpi_ = std::make_unique<WebMediaPlayerImpl>(
        frame->Scheduler(), frame->GetSecurityOrigin(),
        frame->GetDocument().Url(), frame->GetDocument().Title(),
        BindRepeating(&WebLocalFrame::HasTransientUserActivation,
                      Unretained(frame)),
        client_.Get(), &encrypted_client_, &delegate_,
        std::move(factory_selector), url_index_.get(), std::move(compositor),
        std::move(media_log), player_id, WebMediaPlayerBuilder::DeferLoadCB(),
        audio_sink_, media_thread_.task_runner(), media_thread_.task_runner(),
        media_thread_.task_runner(), media_thread_.task_runner(), nullptr,
        media::RequestRoutingTokenCallback(), mock_observer_.AsWeakPtr(), false,
        provider.Unbind(),
        blink::BindOnce(&ParcWebMediaPlayerImplTest::CreateMockSurfaceLayerBridge,
                        base::Unretained(this)),
        viz::TestContextProvider::CreateGLES(), is_background_suspend_enabled_,
        is_background_video_playback_enabled_, true,
        std::move(demuxer_override), nullptr);
  }

  std::unique_ptr<WebSurfaceLayerBridge> CreateMockSurfaceLayerBridge(
      WebSurfaceLayerBridgeObserver*,
      cc::UpdateSubmissionStateCB) {
    return std::move(surface_layer_bridge_);
  }

  WebLocalFrame* GetWebLocalFrame() {
    return web_view_helper_.LocalMainFrame();
  }

  void SetNetworkState(WebMediaPlayer::NetworkState state) {
    EXPECT_CALL(*client_, NetworkStateChanged());
    wmpi_->SetNetworkState(state);
  }

  void SetReadyState(WebMediaPlayer::ReadyState state) {
    EXPECT_CALL(*client_, ReadyStateChanged());
    wmpi_->SetReadyState(state);
  }

  void SetDuration(base::TimeDelta value) {
    wmpi_->SetPipelineMediaDurationForTest(value);
    wmpi_->OnDurationChange();
  }

  MOCK_METHOD(bool, IsShuttingDown, ());

  base::TimeDelta GetCurrentTimeInternal() {
    return wmpi_->GetCurrentTimeInternal();
  }

  void SetPaused(bool is_paused) { wmpi_->paused_ = is_paused; }
  void SetSeeking(bool is_seeking) { wmpi_->seeking_ = is_seeking; }
  bool IsPaused() const { return wmpi_->paused_; }
  void OnEnded() { wmpi_->OnEnded(); }
  void SetHasFirstFrame() { wmpi_->has_first_frame_ = true; }
  void SetBufferedBytes(int64_t buffered_bytes, int64_t total_bytes) {
    wmpi_->buffered_data_source_host_->SetTotalBytes(total_bytes);
    wmpi_->buffered_data_source_host_->AddBufferedByteRange(0, buffered_bytes);
  }
  void OnPipelineSeeked(bool time_updated) {
    wmpi_->OnPipelineSeeked(time_updated);
  }
  bool ShouldNotifyTimeChanged() const {
    return wmpi_->should_notify_time_changed_;
  }
  void PaintFrame() {
    compositor_->PaintSingleFrame(
        media::VideoFrame::CreateBlackFrame(gfx::Size(16, 16)),
        false);
  }
  void SetWasSuspendedForFrameClosed(bool is_suspended) {
    wmpi_->was_suspended_for_frame_closed_or_frozen_ = is_suspended;
  }

  void SetMetadata(bool has_audio, bool has_video) {
    wmpi_->SetNetworkState(WebMediaPlayer::kNetworkStateLoaded);

    EXPECT_CALL(*client_, ReadyStateChanged());
    wmpi_->SetReadyState(WebMediaPlayer::kReadyStateHaveMetadata);
    wmpi_->pipeline_metadata_.has_audio = has_audio;
    wmpi_->pipeline_metadata_.has_video = has_video;

    if (has_video) {
      wmpi_->pipeline_metadata_.video_decoder_config =
          TestVideoConfig::Normal();
    }

    if (has_audio) {
      wmpi_->pipeline_metadata_.audio_decoder_config =
          TestAudioConfig::Normal();
    }
  }

  void OnMetadata(const media::PipelineMetadata& metadata) {
    wmpi_->OnMetadata(metadata);
  }

  void OnWaiting(media::WaitingReason reason) { wmpi_->OnWaiting(reason); }

#if BUILDFLAG(IS_MAC)
  void OnEncryptedMediaInitData(media::EmeInitDataType init_data_type,
                                const std::vector<uint8_t>& init_data) {
    wmpi_->OnEncryptedMediaInitData(init_data_type, init_data);
  }

  void ParcPlayNativeHls() {
    wmpi_->renderer_type_ = media::RendererType::kFairPlayHls;
  }
  bool ParcFileOnNativeRoute() const {
    return wmpi_->parc_->file_on_native_route_;
  }
  bool ParcSwitchingRoute() const {
    return wmpi_->parc_->route_switch_.has_value();
  }
  bool HasDataSource() const {
    return wmpi_->demuxer_manager_->HasDataSource();
  }
  void ParcReportReadyState(WebMediaPlayer::ReadyState state) {
    wmpi_->SetReadyState(state);
  }
  void ParcReportDurationChange() { wmpi_->OnDurationChange(); }
  void ParcReportNativeReadyState(media::ParcNativeHlsReadyState state) {
    wmpi_->ParcNativeHlsReadyStateChanged(state);
  }
  void ParcServeOverHttps() {
    wmpi_->demuxer_manager_->SetLoadedUrl(
        GURL("https://example.com/episode.mp3"));
    wmpi_->ParcCheckFileTargetSupport();
  }
  void ParcMakeLive(const GURL& url) {
    wmpi_->parc_->file_streaming_ = true;
    wmpi_->demuxer_manager_->SetLoadedUrl(url);
  }
  GURL LoadedUrl() const { return wmpi_->demuxer_manager_->LoadedUrl(); }
  base::TimeDelta PipelineTime() const {
    return wmpi_->pipeline_controller_->GetMediaTime();
  }
  void ParcAddTrack(const media::MediaTrack& track) { wmpi_->AddTrack(track); }
  parc::fairplay::NativeHlsSource::FileTracks ParcFileTrackChoices() const {
    return wmpi_->ParcFileTrackChoices();
  }
  void ParcFailPendingCdmAfterSourceCheck() {
    wmpi_->pending_cdm_context_ref_ =
        std::make_unique<ParcCdmContextRef>(&parc_cdm_context_);
    wmpi_->OnEncryptedMediaInitData(media::EmeInitDataType::SINF, {1});
    wmpi_->OnCdmAttached(false);
  }
  void ParcSourceKeyChanged(const std::string& id,
                            const std::vector<uint8_t>& data) {
    wmpi_->parc_->SourceKeyChanged(id, media::EmeInitDataType::SINF, data);
  }
  void ParcMediaSource() {
    wmpi_->load_type_ = WebMediaPlayer::kLoadTypeMediaSource;
  }
  void ParcPlayChromiumRenderer() {
    wmpi_->renderer_type_ = media::RendererType::kRendererImpl;
  }
  void ParcPlayFairPlayRenderer() {
    wmpi_->renderer_type_ = media::RendererType::kFairPlay;
  }
  bool ParcRestartPending() const {
    return wmpi_->pending_suspend_resume_cycle_;
  }
  void ParcHandOffOrRestart() { wmpi_->ParcHandOffOrRestart(); }

  void ParcSetKeyRequestCdm() {
    DCHECK(web_cdm_);
    EXPECT_CALL(*mock_cdm_, GetCdmContext())
        .WillRepeatedly(Return(&parc_cdm_context_));
    wmpi_->SetCdmInternal(web_cdm_.get());
    CycleThreads();
  }

  void ParcAttachCdm() { ParcAttachCdm(&parc_cdm_context_); }
  void ParcAttachCdm(media::CdmContext* cdm_context) {
    wmpi_->pending_cdm_context_ref_ =
        std::make_unique<ParcCdmContextRef>(cdm_context);
    wmpi_->OnCdmAttached(true);
  }
#endif

  void OnVideoNaturalSizeChange(const gfx::Size& size) {
    wmpi_->OnVideoNaturalSizeChange(size);
  }

  void OnVideoConfigChange(const media::VideoDecoderConfig& config) {
    wmpi_->OnVideoConfigChange(config);
  }

#if BUILDFLAG(IS_MAC)
  void ParcAddStreamsWithoutRestart(
      const media::PipelineMetadata& added,
      const std::vector<media::ChunkDemuxer::ParcAddedTrack>& tracks) {
    ASSERT_EQ(wmpi_->GetReadyState(),
              WebMediaPlayer::kReadyStateHaveEnoughData);
    ASSERT_TRUE(wmpi_->Paused());
    EXPECT_CALL(*client_, ReadyStateChanged());
    wmpi_->ParcOnSourceBufferStreamsAdded(added, tracks);
    EXPECT_EQ(wmpi_->GetReadyState(), WebMediaPlayer::kReadyStateHaveMetadata);
    EXPECT_FALSE(wmpi_->pending_suspend_resume_cycle_);
    testing::Mock::VerifyAndClearExpectations(client_.Get());
    EXPECT_CALL(*client_, ReadyStateChanged()).Times(AnyNumber());
    CycleThreads();
    EXPECT_FALSE(IsSuspended());
    EXPECT_FALSE(wmpi_->pending_suspend_resume_cycle_);
    EXPECT_TRUE(wmpi_->Paused());
  }

  void ParcAddStreamsAndWaitForRestart(
      const media::PipelineMetadata& added,
      const std::vector<media::ChunkDemuxer::ParcAddedTrack>& tracks) {
    ASSERT_EQ(wmpi_->GetReadyState(),
              WebMediaPlayer::kReadyStateHaveEnoughData);
    ASSERT_TRUE(wmpi_->Paused());
    EXPECT_CALL(*client_, ReadyStateChanged());
    wmpi_->ParcOnSourceBufferStreamsAdded(added, tracks);
    EXPECT_EQ(wmpi_->GetReadyState(), WebMediaPlayer::kReadyStateHaveMetadata);
    EXPECT_TRUE(wmpi_->pending_suspend_resume_cycle_);
    testing::Mock::VerifyAndClearExpectations(client_.Get());

    while (wmpi_->GetReadyState() <
           WebMediaPlayer::kReadyStateHaveEnoughData) {
      base::RunLoop loop;
      EXPECT_CALL(*client_, ReadyStateChanged())
          .WillRepeatedly(RunClosure(loop.QuitClosure()));
      loop.Run();
      testing::Mock::VerifyAndClearExpectations(client_.Get());
    }
    EXPECT_CALL(*client_, ReadyStateChanged()).Times(AnyNumber());
    CycleThreads();
    EXPECT_FALSE(IsSuspended());
    EXPECT_TRUE(wmpi_->Paused());
  }

  bool ParcAwaitsAddedStreamsRenderer() const {
    return wmpi_->parc_->awaits_added_streams_renderer_;
  }

  void ParcSetPendingFairPlayCdm() {
    wmpi_->pending_cdm_context_ref_ =
        std::make_unique<ParcCdmContextRef>(&parc_fairplay_cdm_context_);
  }

  bool ParcFairPlayPlays(const media::VideoDecoderConfig& video,
                         const media::AudioDecoderConfig& audio) {
    wmpi_->pipeline_metadata_.has_video = true;
    wmpi_->pipeline_metadata_.video_decoder_config = video;
    wmpi_->pipeline_metadata_.has_audio = true;
    wmpi_->pipeline_metadata_.audio_decoder_config = audio;
    return wmpi_->ParcFairPlayPlaysCurrentStreams();
  }
  void ParcClearChunkDemuxer() { wmpi_->parc_->chunk_demuxer_ = nullptr; }
#endif

  bool IsSuspended() { return wmpi_->pipeline_controller_->IsSuspended(); }

  bool IsPipelineStable() { return wmpi_->pipeline_controller_->IsStable(); }

  bool IsPipelineSuspended() {
    return wmpi_->pipeline_controller_->IsPipelineSuspended();
  }

  void FreezePage(bool frozen) {
    PageScheduler* scheduler = web_view_helper_.GetWebView()->Scheduler();
    if (frozen) {
      scheduler->SetPageVisible(false);
      scheduler->SetPageFrozen(true);
    } else {
      scheduler->SetPageFrozen(false);
      scheduler->SetPageVisible(true);
    }
  }

  bool IsStreaming() const { return wmpi_->IsStreaming(); }

  void SetRemoteRenderingWithoutRestart() {
    wmpi_->ParcSetRemoteRendering(true);
    wmpi_->disable_pipeline_auto_suspend_ = true;
  }

#if BUILDFLAG(ENABLE_HLS_DEMUXER)
  std::unique_ptr<media::HlsDataSourceProviderImpl> CreateHlsProvider() {
    return std::make_unique<media::HlsDataSourceProviderImpl>(
        wmpi_->CreateHlsDataSourceFactory());
  }

  void ReadHlsSegment(media::HlsDataSourceProvider& provider,
                      WebAssociatedURLLoaderClient*& client,
                      bool& runs_while_frozen,
                      bool& read) {
    EXPECT_CALL(mock_resource_fetch_context_, CreateUrlLoader(_))
        .WillOnce([&](const WebAssociatedURLLoaderOptions&) {
          auto loader =
              std::make_unique<NiceMock<MockWebAssociatedURLLoader>>();
          EXPECT_CALL(*loader, ParcSetRunsWhileFrozen(_))
              .WillRepeatedly(testing::SaveArg<0>(&runs_while_frozen));
          EXPECT_CALL(*loader, LoadAsynchronously(_, _))
              .WillOnce(testing::SaveArg<1>(&client));
          return loader;
        });
    provider.ReadFromUrl(
        {GURL("https://example.com/segment.ts"), std::nullopt,
         media::DataSource::CacheMode::kHitCache},
        base::BindLambdaForTesting(
            [&read](media::HlsDataSourceProvider::ReadResult result) {
              read = result.has_value();
            }));
  }

  void ServeHlsSegment(WebAssociatedURLLoaderClient* client) {
    WebURLResponse response(KURL("https://example.com/segment.ts"));
    response.SetHttpHeaderField(WebString("Content-Length"), WebString("4"));
    response.SetExpectedContentLength(4);
    response.SetHttpStatusCode(200);
    client->DidReceiveResponse(response);
    client->DidReceiveData(base::span_from_cstring("data"));
    client->DidFinishLoading();
  }
#endif

  int64_t GetDataSourceMemoryUsage() const {
    return wmpi_->demuxer_manager_->GetDataSourceMemoryUsage();
  }

  void SetDelegateState(WebMediaPlayerImpl::DelegateState state) {
    wmpi_->SetDelegateState(state, false);
  }

  void SetUpMediaSuspend(bool enable) {
    is_background_suspend_enabled_ = enable;
  }

  void SetUpBackgroundVideoPlayback(bool enable) {
    is_background_video_playback_enabled_ = enable;
  }

  bool IsPausedBecausePageHidden() const {
    return wmpi_->IsPausedBecausePageHidden();
  }

  bool IsPausedBecauseFrameHidden() const {
    return wmpi_->IsPausedBecauseFrameHidden();
  }

  void HidePlayerPage() {
    base::RunLoop loop;
    EXPECT_CALL(*compositor_, SetIsPageVisible(false))
        .WillOnce(RunClosure(loop.QuitClosure()));

    delegate_.SetPageHiddenForTesting(true);
    SetWasSuspendedForFrameClosed(false);

    wmpi_->OnPageHidden();

    loop.Run();

    testing::Mock::VerifyAndClearExpectations(compositor_);
  }

  void ShowPlayerPage() {
    base::RunLoop loop;
    EXPECT_CALL(*compositor_, SetIsPageVisible(true))
        .WillOnce(RunClosure(loop.QuitClosure()));

    delegate_.SetPageHiddenForTesting(false);
    SetWasSuspendedForFrameClosed(false);

    wmpi_->OnPageShown();

    loop.Run();

    testing::Mock::VerifyAndClearExpectations(compositor_);
  }

  void HidePlayerFrame() {
    SetWasSuspendedForFrameClosed(false);
    wmpi_->OnFrameHidden();
  }

  void ShowPlayerFrame() {
    SetWasSuspendedForFrameClosed(false);
    wmpi_->OnFrameShown();
  }

  void BackgroundPlayer(BackgroundBehaviorType type) {
    switch (type) {
      case BackgroundBehaviorType::Page:
        HidePlayerPage();
        return;
      case BackgroundBehaviorType::Frame:
        HidePlayerFrame();
        return;
    }

    NOTREACHED();
  }

  void ForegroundPlayer(BackgroundBehaviorType type) {
    switch (type) {
      case BackgroundBehaviorType::Page:
        ShowPlayerPage();
        return;
      case BackgroundBehaviorType::Frame:
        ShowPlayerFrame();
        return;
    }

    NOTREACHED();
  }

  void Play() { wmpi_->Play(); }

  void Pause(WebMediaPlayer::PauseReason pause_reason) {
    wmpi_->Pause(pause_reason);
  }

  void SetSuspendState(bool is_suspended) {
    wmpi_->SetSuspendState(is_suspended);
  }

  void SetLoadType(WebMediaPlayer::LoadType load_type) {
    wmpi_->load_type_ = load_type;
  }

  bool IsPageHidden() const { return wmpi_->IsPageHidden(); }

  bool ShouldCancelUponDefer() const {
    auto* ds = wmpi_->demuxer_manager_->GetDataSourceForTesting();
    CHECK_NE(ds, nullptr);
    return static_cast<const MultiBufferDataSource*>(ds)
        ->cancel_on_defer_for_testing();
  }

  MultiBufferDataSource* GetMultiBufferDataSource() {
    auto* ds = wmpi_->demuxer_manager_->GetDataSourceForTesting();
    CHECK_NE(ds, nullptr);
    return static_cast<MultiBufferDataSource*>(ds);
  }

  scoped_refptr<media::VideoFrame> CreateFrame() {
    gfx::Size size(8, 8);
    return media::VideoFrame::CreateFrame(media::PIXEL_FORMAT_I420, size,
                                          gfx::Rect(size), size,
                                          base::TimeDelta());
  }

  void RequestVideoFrameCallback() { wmpi_->RequestVideoFrameCallback(); }
  void GetVideoFramePresentationMetadata() {
    wmpi_->GetVideoFramePresentationMetadata();
  }
  void UpdateFrameIfStale() { wmpi_->UpdateFrameIfStale(); }

  void OnNewFramePresentedCallback() { wmpi_->OnNewFramePresentedCallback(); }

  scoped_refptr<media::VideoFrame> GetCurrentFrameFromCompositor() {
    return wmpi_->GetCurrentFrameFromCompositor();
  }

  enum class LoadType { kFullyBuffered, kStreaming };
  void Load(std::string data_file,
            LoadType load_type = LoadType::kFullyBuffered) {
    const bool is_streaming = load_type == LoadType::kStreaming;

    const KURL kTestURL(
        String::FromUtf8(std::string(is_streaming ? "http" : "file") +
                         "://example.com/sample.webm"));

    const bool should_have_client =
        !wmpi_->demuxer_manager_->HasDemuxerOverride();
    WebAssociatedURLLoaderClient* client = nullptr;
    if (should_have_client) {
      EXPECT_CALL(mock_resource_fetch_context_, CreateUrlLoader(_))
          .WillRepeatedly(
              [&client](const WebAssociatedURLLoaderOptions&) {
                auto a =
                    std::make_unique<NiceMock<MockWebAssociatedURLLoader>>();
                EXPECT_CALL(*a, LoadAsynchronously(_, _))
                    .WillRepeatedly(testing::SaveArg<1>(&client));
                return a;
              });
    }

    wmpi_->Load(WebMediaPlayer::kLoadTypeURL,
                WebMediaPlayerSource(WebURL(kTestURL)),
                WebMediaPlayer::kCorsModeUnspecified,
                false);

    base::RunLoop().RunUntilIdle();
    if (!should_have_client) {
      return;
    }
    EXPECT_TRUE(client);

    scoped_refptr<media::DecoderBuffer> data =
        media::ReadTestDataFile(data_file);

    WebURLResponse response(kTestURL);
    response.SetHttpHeaderField(
        WebString("Content-Length"),
        WebString::FromUtf8(is_streaming ? "-1"
                                         : base::NumberToString(data->size())));
    response.SetExpectedContentLength(is_streaming ? -1 : data->size());
    response.SetHttpStatusCode(200);
    client->DidReceiveResponse(response);

    client->DidReceiveData(base::as_chars(base::span(*data)));

    if (!is_streaming)
      client->DidFinishLoading();
  }

  void LoadAndWaitForReadyState(std::string data_file,
                                WebMediaPlayer::ReadyState ready_state) {
    Load(data_file);
    while (wmpi_->GetReadyState() < ready_state) {
      base::RunLoop loop;
      EXPECT_CALL(*client_, ReadyStateChanged())
          .WillRepeatedly(RunClosure(loop.QuitClosure()));
      loop.Run();

      testing::Mock::VerifyAndClearExpectations(client_.Get());
    }

    EXPECT_TRUE(HasDataSource());
    EXPECT_TRUE(wmpi_->demuxer_manager_->HasDemuxer());

    if (ready_state > WebMediaPlayer::kReadyStateHaveCurrentData)
      EXPECT_FALSE(wmpi_->seeking_);
  }

  void LoadAndWaitForCurrentData(std::string data_file) {
    LoadAndWaitForReadyState(data_file,
                             WebMediaPlayer::kReadyStateHaveCurrentData);
  }

  void CycleThreads() {
    base::RunLoop().RunUntilIdle();

    media_thread_.FlushForTesting();

    base::RunLoop().RunUntilIdle();
  }

  void OnProgress() { wmpi_->OnProgress(); }

  void StartParcMediaSource(bool safari_identity) {
    ON_CALL(*client_, PresentsParcSafariIdentity())
        .WillByDefault(Return(safari_identity));
    parc_demuxer_ = std::make_unique<media::ChunkDemuxer>(
        base::DoNothing(), base::DoNothing(), base::DoNothing(),
        &parc_media_log_);
    parc_demuxer_->Initialize(&parc_demuxer_host_, base::DoNothing());
    ASSERT_EQ(parc_demuxer_->AddId("audio", "audio/webm", "vorbis"),
              media::ChunkDemuxer::kOk);
    parc_demuxer_->SetTracksWatcher("audio", base::DoNothing());
    wmpi_->load_type_ = WebMediaPlayer::kLoadTypeMediaSource;
    wmpi_->parc_->chunk_demuxer_ = parc_demuxer_.get();
    SetMetadata(true, false);
    SetPaused(true);
  }

  void AppendParcMediaSource(base::TimeDelta start,
                             base::TimeDelta end,
                             const std::string& id = "audio") {
    scoped_refptr<media::DecoderBuffer> data =
        media::ReadTestDataFile("bear-320x240-audio-only.webm");
    ASSERT_TRUE(parc_demuxer_->AppendToParseBuffer(id, base::span(*data)));
    base::TimeDelta offset;
    media::StreamParser::ParseStatus status;
    do {
      status = parc_demuxer_->RunSegmentParserLoop(id, start, end, &offset);
    } while (status == media::StreamParser::ParseStatus::kSuccessHasMoreData);
    ASSERT_EQ(status, media::StreamParser::ParseStatus::kSuccess);
    wmpi_->OnProgress();
  }

  void OnCdmCreated(base::RepeatingClosure quit_closure,
                    std::unique_ptr<WebContentDecryptionModule> cdm,
                    media::CreateCdmStatus status) {
    LOG_IF(ERROR, status != media::CreateCdmStatus::kSuccess)
        << "status = " << static_cast<int>(status);
    EXPECT_TRUE(cdm);
    web_cdm_ = std::move(cdm);
    quit_closure.Run();
  }

  void CreateCdm() {
    media::CdmConfig cdm_config = {media::kClearKeyKeySystem, false, false,
                                   false};
    auto test_origin =
        WebSecurityOrigin::CreateFromString(WebString("https://test.origin"));

    if (!key_systems_) {
      key_systems_ =
          std::make_unique<media::KeySystemsImpl>(base::NullCallback());
    }
    base::RunLoop run_loop;
    WebContentDecryptionModuleImpl::Create(
        &mock_cdm_factory_, key_systems_.get(), test_origin, cdm_config,
        blink::BindOnce(&ParcWebMediaPlayerImplTest::OnCdmCreated, Unretained(this),
                        run_loop.QuitClosure()));
    run_loop.Run();
    EXPECT_TRUE(web_cdm_);
  }

  void SetCdm() {
    DCHECK(web_cdm_);
    EXPECT_CALL(*mock_cdm_, GetCdmContext())
        .WillRepeatedly(Return(&mock_cdm_context_));
    wmpi_->SetCdmInternal(web_cdm_.get());
  }

#if BUILDFLAG(IS_MAC)
  void ParcSetFairPlayCdmOnSafariMediaSource() {
    DCHECK(web_cdm_);
    ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
    wmpi_->load_type_ = WebMediaPlayer::kLoadTypeMediaSource;
    EXPECT_CALL(*mock_cdm_, GetCdmContext())
        .WillRepeatedly(Return(&parc_fairplay_cdm_context_));
    wmpi_->SetCdmInternal(web_cdm_.get());
    CycleThreads();
  }

  void ParcAppendSinf() {
    wmpi_->OnEncryptedMediaInitData(media::EmeInitDataType::SINF,
                                    std::vector<uint8_t>{1, 2, 3});
    CycleThreads();
  }
#endif

  test::TaskEnvironment task_environment_;

  base::Thread media_thread_;

  frame_test_helpers::WebViewHelper web_view_helper_;

  scoped_refptr<viz::TestContextProvider> context_provider_;
  raw_ptr<NiceMock<MockVideoFrameCompositor>,
          UnprotectedInRelease | DanglingUntriaged>
      compositor_;

  scoped_refptr<NiceMock<media::MockAudioRendererSink>> audio_sink_;
  MockResourceFetchContext mock_resource_fetch_context_;
  std::unique_ptr<UrlIndex> url_index_;

  media::AudioParameters audio_parameters_;

  bool is_background_suspend_enabled_ = false;
  bool is_background_video_playback_enabled_ = true;

  Persistent<NiceMock<MockWebMediaPlayerClient>> client_;
  MockWebMediaPlayerEncryptedMediaClient encrypted_client_;

  std::unique_ptr<media::KeySystemsImpl> key_systems_;

  scoped_refptr<media::MockCdm> mock_cdm_ =
      base::MakeRefCounted<media::MockCdm>();
  media::MockCdmFactory mock_cdm_factory_{mock_cdm_};
  std::unique_ptr<WebContentDecryptionModule> web_cdm_;
  media::MockCdmContext mock_cdm_context_;
#if BUILDFLAG(IS_MAC)
  ParcFairPlayCdmContext parc_fairplay_cdm_context_;
  ParcKeyRequestCdmContext parc_cdm_context_;
#endif

  viz::FrameSinkId frame_sink_id_ = viz::FrameSinkId(1, 1);
  viz::LocalSurfaceId local_surface_id_ = viz::LocalSurfaceId(
      11,
      base::UnguessableToken::CreateForTesting(0x111111, 0));
  viz::SurfaceId surface_id_ =
      viz::SurfaceId(frame_sink_id_, local_surface_id_);

  NiceMock<MockWebMediaPlayerDelegate> delegate_;
  NiceMock<MockWebMediaPlayerDelegate> moved_to_delegate_;
  StrictMock<MockResourceFetchContext> moved_to_fetch_context_;
  std::unique_ptr<UrlIndex> moved_to_url_index_;
  frame_test_helpers::WebViewHelper moved_to_view_helper_;

  std::unique_ptr<NiceMock<MockSurfaceLayerBridge>> surface_layer_bridge_;
  raw_ptr<NiceMock<MockSurfaceLayerBridge>,
          UnprotectedInRelease | DanglingUntriaged>
      surface_layer_bridge_ptr_ = nullptr;

  raw_ptr<NiceMock<media::MockMediaLog>,
          UnprotectedInRelease | DanglingUntriaged>
      media_log_ = nullptr;

  raw_ptr<media::RendererFactorySelector,
          UnprotectedInRelease | DanglingUntriaged>
      renderer_factory_selector_ = nullptr;

  std::unique_ptr<media::DecoderFactory> decoder_factory_;

  NiceMock<MockMediaObserver> mock_observer_;

  NiceMock<media::MockMediaLog> parc_media_log_;
  NiceMock<media::MockDemuxerHost> parc_demuxer_host_;
  std::unique_ptr<media::ChunkDemuxer> parc_demuxer_;

  std::unique_ptr<WebMediaPlayerImpl> wmpi_;

  std::unique_ptr<base::trace_event::MemoryDumpManager> memory_dump_manager_;
};

TEST_F(ParcWebMediaPlayerImplTest, ParcSafariRefusesUndeclaredAV1WithoutHardware) {
  InitializeWebMediaPlayerImpl();
  av1_command_line_.GetProcessCommandLine()->AppendSwitchASCII(
      media::kParcAV1HardwareDecoder, "0");
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  media::PipelineMetadata metadata;
  metadata.has_video = true;
  metadata.video_decoder_config = TestVideoConfig::Normal(media::VideoCodec::kAV1);
  EXPECT_CALL(*client_, NetworkStateChanged());
  OnMetadata(metadata);
  EXPECT_EQ(wmpi_->GetNetworkState(), WebMediaPlayer::kNetworkStateFormatError);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcChromeTakesUndeclaredAV1WithoutHardware) {
  InitializeWebMediaPlayerImpl();
  av1_command_line_.GetProcessCommandLine()->AppendSwitchASCII(
      media::kParcAV1HardwareDecoder, "0");
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(false));
  media::PipelineMetadata metadata;
  metadata.has_video = true;
  metadata.video_decoder_config = TestVideoConfig::Normal(media::VideoCodec::kAV1);
  OnMetadata(metadata);
  EXPECT_NE(wmpi_->GetNetworkState(), WebMediaPlayer::kNetworkStateFormatError);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcBackwardEndKeepsTheTime) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  wmpi_->SetRate(-1.0);

  EXPECT_CALL(*client_, TimeChanged());
  OnEnded();
  EXPECT_FALSE(wmpi_->IsEnded());
  EXPECT_EQ(0, wmpi_->CurrentTime());
}

class ParcWebMediaPlayerImplReverseRouteTest
    : public ParcWebMediaPlayerImplTest,
      public testing::WithParamInterface<media::RendererType> {};

TEST_P(ParcWebMediaPlayerImplReverseRouteTest, FrozenRouteReportsItsActualRate) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  auto factory = std::make_unique<media::MockRendererFactory>();
  auto time = std::make_shared<std::atomic<int64_t>>(1000000);
  media::MockRenderer* renderer = nullptr;
  EXPECT_CALL(*factory, CreateRenderer(_, _, _, _, _, _))
      .WillOnce(testing::WithoutArgs([&]() {
        auto mock = std::make_unique<NiceMock<media::MockRenderer>>(GetParam());
        renderer = mock.get();
        ON_CALL(*mock, GetMediaTime()).WillByDefault([time]() {
          return base::Microseconds(time->load());
        });
        EXPECT_CALL(*mock, OnInitialize(_, _, _))
            .WillOnce(RunOnceCallback<2>(media::PIPELINE_OK));
        return mock;
      }));
  renderer_factory_selector_->AddFactory(GetParam(), std::move(factory));
  renderer_factory_selector_->SetBaseRendererType(GetParam());
  Load(kAudioOnlyTestFile);
  CycleThreads();
  ASSERT_TRUE(renderer);
  SetReadyState(WebMediaPlayer::kReadyStateHaveFutureData);
  wmpi_->SetRate(-1.0);
  EXPECT_CALL(*renderer, SetPlaybackRate(0.0)).Times(testing::AtLeast(1));
  EXPECT_CALL(*renderer, SetPlaybackRate(testing::Lt(0.0))).Times(0);
  Play();
  CycleThreads();

  EXPECT_CALL(*client_, DidPlayerMediaPositionStateChange(
                           0.0, kAudioOnlyTestFileDuration, base::Seconds(1),
                           false));
  wmpi_->OnTimeUpdate();
  EXPECT_EQ(1.0, wmpi_->CurrentTime());
  testing::Mock::VerifyAndClearExpectations(client_.Get());
  EXPECT_CALL(*client_, DidPlayerMediaPositionStateChange(_, _, _, _)).Times(0);
  CycleThreads();
  wmpi_->OnTimeUpdate();
  EXPECT_EQ(1.0, wmpi_->CurrentTime());
  testing::Mock::VerifyAndClearExpectations(client_.Get());

  time->store(500000);
  EXPECT_CALL(*client_, DidPlayerMediaPositionStateChange(
                           0.0, kAudioOnlyTestFileDuration, base::Seconds(0.5),
                           false));
  wmpi_->OnTimeUpdate();
  EXPECT_EQ(0.5, wmpi_->CurrentTime());
  testing::Mock::VerifyAndClearExpectations(client_.Get());

  EXPECT_CALL(*renderer, SetPlaybackRate(1.0));
  wmpi_->SetRate(1.0);
  CycleThreads();
  EXPECT_CALL(*client_, DidPlayerMediaPositionStateChange(
                           1.0, kAudioOnlyTestFileDuration, base::Seconds(0.5),
                           false));
  wmpi_->OnTimeUpdate();
}

INSTANTIATE_TEST_SUITE_P(
    Parc, ParcWebMediaPlayerImplReverseRouteTest,
    testing::Values(media::RendererType::kFlinging,
                    media::RendererType::kCourier,
                    media::RendererType::kFairPlay));

#if BUILDFLAG(IS_MAC)
TEST_F(ParcWebMediaPlayerImplTest, ParcReversingRoutesKeepNegativePositionRate) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  wmpi_->SetRate(-1.0);
  Play();
  ParcPlayChromiumRenderer();
  EXPECT_CALL(*client_, DidPlayerMediaPositionStateChange(
                           -1.0, kAudioOnlyTestFileDuration, base::TimeDelta(),
                           false));
  wmpi_->OnTimeUpdate();
  testing::Mock::VerifyAndClearExpectations(client_.Get());
  ParcPlayNativeHls();
  wmpi_->SetRate(-2.0);
  EXPECT_CALL(*client_, DidPlayerMediaPositionStateChange(
                           -2.0, kAudioOnlyTestFileDuration, base::TimeDelta(),
                           false));
  wmpi_->OnTimeUpdate();
}
#endif

TEST_F(ParcWebMediaPlayerImplTest, SafariIdentity_EndedWhilePausedTellsClient) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  ASSERT_TRUE(IsPaused());
  EXPECT_CALL(*client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(*client_, TimeChanged());
  OnEnded();
  EXPECT_TRUE(wmpi_->IsEnded());
}

TEST_F(ParcWebMediaPlayerImplTest, EndedWhilePausedDoesNotTellClient) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  ASSERT_TRUE(IsPaused());
  EXPECT_CALL(*client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(false));
  EXPECT_CALL(*client_, TimeChanged()).Times(0);
  OnEnded();
  EXPECT_TRUE(wmpi_->IsEnded());
}

class ParcWebMediaPlayerImplUrlSeekTest : public ParcWebMediaPlayerImplTest {
 protected:
  void SetUpPlayer(bool safari_identity,
                   bool has_video,
                   bool has_first_frame = true) {
    InitializeWebMediaPlayerImpl();
    ON_CALL(*client_, PresentsParcSafariIdentity())
        .WillByDefault(Return(safari_identity));
    SetMetadata(true, has_video);
    SetDuration(base::Seconds(10));
    SetBufferedBytes(100, 1000);
    SetReadyState(WebMediaPlayer::kReadyStateHaveEnoughData);
    if (has_first_frame) {
      SetHasFirstFrame();
    }
    testing::Mock::VerifyAndClearExpectations(client_.Get());
  }
};

TEST_F(ParcWebMediaPlayerImplUrlSeekTest,
       SafariSeekIntoBufferedKeepsReadyState) {
  SetUpPlayer(true, true);

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(*client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
  EXPECT_TRUE(wmpi_->Seeking());

  OnPipelineSeeked(true);
  CycleThreads();
  EXPECT_FALSE(wmpi_->Seeking());
  testing::Mock::VerifyAndClearExpectations(client_.Get());

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(*client_, TimeChanged());
  PaintFrame();
  CycleThreads();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
  testing::Mock::VerifyAndClearExpectations(client_.Get());

  EXPECT_CALL(*client_, TimeChanged()).Times(0);
  PaintFrame();
  CycleThreads();
}

TEST_F(ParcWebMediaPlayerImplUrlSeekTest, SafariAudioSeekEndsWithPipelineSeek) {
  SetUpPlayer(true, false);

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(*client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  testing::Mock::VerifyAndClearExpectations(client_.Get());

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(*client_, TimeChanged());
  OnPipelineSeeked(true);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
}

TEST_F(ParcWebMediaPlayerImplUrlSeekTest, SafariSeekIgnoresEarlierSeeksFrame) {
  SetUpPlayer(true, true);

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(*client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  OnPipelineSeeked(true);
  CycleThreads();
  wmpi_->Seek(0.7);
  PaintFrame();
  media_thread_.FlushForTesting();
  OnPipelineSeeked(true);
  CycleThreads();
  testing::Mock::VerifyAndClearExpectations(client_.Get());

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(*client_, TimeChanged());
  PaintFrame();
  CycleThreads();
}

TEST_F(ParcWebMediaPlayerImplUrlSeekTest, SafariSeekBeforeFirstFrameWaits) {
  SetUpPlayer(true, true,
              false);

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(*client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  OnPipelineSeeked(true);
  CycleThreads();
  PaintFrame();
  CycleThreads();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
  EXPECT_TRUE(ShouldNotifyTimeChanged());
}

TEST_F(ParcWebMediaPlayerImplUrlSeekTest,
       SafariSeekOutsideBufferedLowersReadyState) {
  SetUpPlayer(true, true);

  EXPECT_CALL(*client_, ReadyStateChanged());
  EXPECT_CALL(*client_, TimeChanged()).Times(0);
  wmpi_->Seek(5);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());
  OnPipelineSeeked(true);
  PaintFrame();
  CycleThreads();
}

TEST_F(ParcWebMediaPlayerImplUrlSeekTest, ChromeSeekLowersReadyState) {
  SetUpPlayer(false, true);

  EXPECT_CALL(*client_, ReadyStateChanged());
  EXPECT_CALL(*client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());
  OnPipelineSeeked(true);
  PaintFrame();
  CycleThreads();
}

#if BUILDFLAG(IS_MAC)
class ParcWebMediaPlayerImplFileAirPlayTest : public ParcWebMediaPlayerImplTest {
 protected:
  void LoadFile(bool safari_identity) {
    InitializeWebMediaPlayerImpl();
    ON_CALL(*client_, PresentsParcSafariIdentity())
        .WillByDefault(Return(safari_identity));
    wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
    LoadAndWaitForReadyState("bear-audio-10s-CBR-has-TOC.mp3",
                             WebMediaPlayer::kReadyStateHaveEnoughData);
    ParcServeOverHttps();
    EXPECT_CALL(*client_, ReadyStateChanged()).Times(AnyNumber());
    EXPECT_CALL(*client_, TimeChanged()).Times(AnyNumber());
    wmpi_->Seek(2);
    for (int i = 0; i < 100 && wmpi_->Seeking(); ++i) {
      CycleThreads();
    }
    ASSERT_FALSE(wmpi_->Seeking());
    testing::Mock::VerifyAndClearExpectations(client_.Get());
  }
  void SwitchLiveStream(std::optional<double> seek_during_switch);
};

void ParcWebMediaPlayerImplFileAirPlayTest::SwitchLiveStream(
    std::optional<double> seek_during_switch) {
  LoadFile(true);
  const GURL file_url = LoadedUrl();
  ParcServeOverHttps();
  ParcMakeLive(file_url);
  wmpi_->ParcSetPlaybackTarget("context", true);
  ASSERT_TRUE(ParcSwitchingRoute());
  if (seek_during_switch) {
    EXPECT_CALL(*client_, TimeChanged()).Times(testing::AtLeast(1));
    wmpi_->Seek(*seek_during_switch);
  }
  for (int i = 0; i < 200 && ParcSwitchingRoute(); ++i) {
    CycleThreads();
  }
  ASSERT_FALSE(ParcSwitchingRoute());
  EXPECT_FALSE(ParcFileOnNativeRoute());
}

TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, SafariFileSupportsTarget) {
  LoadFile(true);
  EXPECT_TRUE(wmpi_->ParcSupportsPlaybackTarget());
}

TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, ChromeFileKeepsItsPipeline) {
  LoadFile(false);
  EXPECT_FALSE(wmpi_->ParcSupportsPlaybackTarget());
  wmpi_->ParcSetPlaybackTarget("context", true);
  EXPECT_FALSE(ParcFileOnNativeRoute());
  EXPECT_FALSE(ParcSwitchingRoute());
  EXPECT_TRUE(HasDataSource());
}

TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, NotPlayingToTargetStays) {
  LoadFile(true);
  wmpi_->ParcSetPlaybackTarget("context", false);
  wmpi_->ParcSetPlaybackTarget("", true);
  EXPECT_FALSE(ParcFileOnNativeRoute());
  EXPECT_FALSE(ParcSwitchingRoute());
  EXPECT_FALSE(wmpi_->Seeking());
  EXPECT_TRUE(HasDataSource());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcFiniteStreamDoesNotSupportTarget) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  Load("bear_192kHz.wav", LoadType::kStreaming);
  while (wmpi_->GetReadyState() < WebMediaPlayer::kReadyStateHaveMetadata) {
    base::RunLoop loop;
    EXPECT_CALL(*client_, ReadyStateChanged())
        .WillRepeatedly(RunClosure(loop.QuitClosure()));
    loop.Run();
    testing::Mock::VerifyAndClearExpectations(client_.Get());
  }
  ASSERT_TRUE(IsStreaming());
  EXPECT_FALSE(wmpi_->ParcSupportsPlaybackTarget());
}

TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, SwitchHoldsWhatTheElementSees) {
  LoadFile(true);
  const double duration = wmpi_->Duration();
  const WebMediaPlayer::ReadyState ready_state = wmpi_->GetReadyState();

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(*client_, DurationChanged()).Times(0);
  EXPECT_CALL(*client_, TimeChanged()).Times(0);
  wmpi_->ParcSetPlaybackTarget("context", true);
  EXPECT_TRUE(ParcFileOnNativeRoute());
  ASSERT_TRUE(ParcSwitchingRoute());
  EXPECT_FALSE(HasDataSource());
  ParcReportReadyState(WebMediaPlayer::kReadyStateHaveMetadata);
  ParcReportDurationChange();
  EXPECT_NEAR(wmpi_->CurrentTime(), 2, 0.05);
  EXPECT_EQ(wmpi_->Duration(), duration);
  EXPECT_EQ(wmpi_->GetReadyState(), ready_state);
  testing::Mock::VerifyAndClearExpectations(client_.Get());

  ParcReportReadyState(WebMediaPlayer::kReadyStateHaveMetadata);
  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  OnPipelineSeeked(false);
  EXPECT_FALSE(ParcSwitchingRoute());
  EXPECT_EQ(wmpi_->GetReadyState(), ready_state);
  testing::Mock::VerifyAndClearExpectations(client_.Get());
  EXPECT_CALL(*client_, ReadyStateChanged());
  ParcReportReadyState(WebMediaPlayer::kReadyStateHaveCurrentData);
}

TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, LiveStreamKeepsItsTime) {
  SwitchLiveStream(std::nullopt);
  ASSERT_LT(PipelineTime(), base::Seconds(0.5));
  EXPECT_NEAR(wmpi_->CurrentTime(), 2, 0.05);
  ASSERT_FALSE(wmpi_->Buffered().empty());
  EXPECT_NEAR(wmpi_->Buffered()[0].start, 2, 0.05);
}

TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, LiveStreamSeekDuringSwitch) {
  SwitchLiveStream(5);
  ASSERT_LT(PipelineTime(), base::Seconds(0.5));
  EXPECT_FALSE(wmpi_->Seeking());
  EXPECT_NEAR(wmpi_->CurrentTime(), 5, 0.05);
}

TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, TrackChoicesByPosition) {
  LoadFile(true);
  media::MediaTracks tracks;
  tracks
      .AddAudioTrack(TestAudioConfig::Normal(), false, 2,
                     media::MediaTrack::Kind("main"),
                     media::MediaTrack::Label(""),
                     media::MediaTrack::Language("fr"))
      ->set_id(media::MediaTrack::Id("2"));
  tracks
      .AddVideoTrack(TestVideoConfig::Normal(), true, 3,
                     media::MediaTrack::Kind("main"),
                     media::MediaTrack::Label(""),
                     media::MediaTrack::Language(""))
      ->set_id(media::MediaTrack::Id("3"));
  tracks
      .AddVideoTrack(TestVideoConfig::Normal(), false, 4,
                     media::MediaTrack::Kind("main"),
                     media::MediaTrack::Label(""),
                     media::MediaTrack::Language(""))
      ->set_id(media::MediaTrack::Id("4"));
  for (const auto& track : tracks.tracks()) {
    ParcAddTrack(*track);
  }

  parc::fairplay::NativeHlsSource::FileTracks choices = ParcFileTrackChoices();
  EXPECT_EQ(choices.audio_count, 2u);
  EXPECT_EQ(choices.audio, std::vector<uint32_t>{0});
  EXPECT_EQ(choices.video_count, 2u);
  EXPECT_EQ(choices.video, 0u);

  wmpi_->ParcEnabledAudioTracksChanged({WebString::FromUtf8("2")});
  wmpi_->SelectedVideoTrackChanged(WebString::FromUtf8("4"));
  choices = ParcFileTrackChoices();
  EXPECT_EQ(choices.audio, std::vector<uint32_t>{1});
  EXPECT_EQ(choices.video, 1u);

  wmpi_->ParcEnabledAudioTracksChanged(
      {WebString::FromUtf8("1"), WebString::FromUtf8("2")});
  wmpi_->SelectedVideoTrackChanged(std::nullopt);
  choices = ParcFileTrackChoices();
  EXPECT_EQ(choices.audio, (std::vector<uint32_t>{0, 1}));
  EXPECT_EQ(choices.video, std::nullopt);
}

TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, NativeRouteTakesAVPlayerState) {
  LoadFile(true);
  wmpi_->ParcSetPlaybackTarget("context", true);
  ASSERT_TRUE(ParcSwitchingRoute());
  ParcPlayNativeHls();

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  OnPipelineSeeked(false);
  EXPECT_FALSE(ParcSwitchingRoute());
  EXPECT_EQ(wmpi_->GetReadyState(), WebMediaPlayer::kReadyStateHaveEnoughData);
  testing::Mock::VerifyAndClearExpectations(client_.Get());

  EXPECT_CALL(*client_, ReadyStateChanged());
  ParcReportNativeReadyState(media::ParcNativeHlsReadyState::kHaveCurrentData);
  EXPECT_EQ(wmpi_->GetReadyState(), WebMediaPlayer::kReadyStateHaveCurrentData);
}
#endif

#if BUILDFLAG(IS_MAC)
TEST_F(ParcWebMediaPlayerImplTest, ParcSafariMediaKeysNullDetachesFairPlayCdm) {
  InitializeWebMediaPlayerImpl();
  CreateCdm();
  ParcSetFairPlayCdmOnSafariMediaSource();

  EXPECT_CALL(encrypted_client_, Encrypted(_, _)).Times(0);
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey()).Times(0);
  ParcAppendSinf();
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  Persistent<ParcCdmResult> result = MakeGarbageCollected<ParcCdmResult>();
  wmpi_->SetContentDecryptionModule(nullptr, result->Result());
  CycleThreads();
  EXPECT_TRUE(result->completed);
  EXPECT_FALSE(result->failed);

  EXPECT_CALL(encrypted_client_,
              Encrypted(media::EmeInitDataType::SINF, NonNullNonEmptySpan()));
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
  ParcAppendSinf();
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  ParcSetFairPlayCdmOnSafariMediaSource();
  EXPECT_CALL(encrypted_client_, Encrypted(_, _)).Times(0);
  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey());
  ParcAppendSinf();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcChromeMediaKeysNullStillRefused) {
  InitializeWebMediaPlayerImpl();
  CreateCdm();
  ParcSetFairPlayCdmOnSafariMediaSource();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(false));

  Persistent<ParcCdmResult> result = MakeGarbageCollected<ParcCdmResult>();
  wmpi_->SetContentDecryptionModule(nullptr, result->Result());
  CycleThreads();
  EXPECT_TRUE(result->failed);
}
#endif

#if BUILDFLAG(IS_MAC)
TEST_F(ParcWebMediaPlayerImplTest, ParcStalledKeyWaitEndsOnlyForThatKey) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcPlayNativeHls();
  const std::vector<uint8_t> key_a = SkdInitData("skd://a");
  const std::vector<uint8_t> key_b = SkdInitData("skd://b");

  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SKD, _));
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
  OnEncryptedMediaInitData(media::EmeInitDataType::SKD, key_a);
  OnWaiting(media::WaitingReason::kNoDecryptionKey);
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey()).Times(0);
  parc_cdm_context_.requested_keys = {key_b};
  ParcAttachCdm();
  parc_cdm_context_.NotifyAdditionalUsableKey();
  base::RunLoop().RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey());
  parc_cdm_context_.requested_keys.push_back(key_a);
  parc_cdm_context_.NotifyAdditionalUsableKey();
  base::RunLoop().RunUntilIdle();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcStallAfterItsKeyArrivedWaitsThenResumes) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcPlayNativeHls();
  const std::vector<uint8_t> key_a = SkdInitData("skd://a");
  parc_cdm_context_.requested_keys = {key_a};
  ParcAttachCdm();
  parc_cdm_context_.NotifyAdditionalUsableKey();
  base::RunLoop().RunUntilIdle();

  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SKD, _));
  {
    InSequence sequence;
    EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
    EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey());
  }
  OnEncryptedMediaInitData(media::EmeInitDataType::SKD, key_a);
  OnWaiting(media::WaitingReason::kNoDecryptionKey);
  base::RunLoop().RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SKD, _));
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
  OnEncryptedMediaInitData(media::EmeInitDataType::SKD,
                           SkdInitData("skd://c"));
  OnWaiting(media::WaitingReason::kNoDecryptionKey);
  base::RunLoop().RunUntilIdle();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcStalledKeyWaitEndsOnAttachWithItsKey) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcPlayNativeHls();
  const std::vector<uint8_t> key_a = SkdInitData("skd://a");

  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SKD, _));
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
  OnEncryptedMediaInitData(media::EmeInitDataType::SKD, key_a);
  OnWaiting(media::WaitingReason::kNoDecryptionKey);
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey());
  parc_cdm_context_.requested_keys = {key_a};
  ParcAttachCdm();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcKeyEventDuringStallCheckDecides) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcPlayNativeHls();
  const std::vector<uint8_t> key_a = SkdInitData("skd://a");
  ParcAttachCdm();
  parc_cdm_context_.defer_answers = true;

  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SKD, _));
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey()).Times(0);
  OnEncryptedMediaInitData(media::EmeInitDataType::SKD, key_a);
  OnWaiting(media::WaitingReason::kNoDecryptionKey);
  parc_cdm_context_.requested_keys = {key_a};
  parc_cdm_context_.NotifyAdditionalUsableKey();
  base::RunLoop().RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey());
  parc_cdm_context_.AnswerDeferred();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcStallCheckingDetachedCdmWaits) {
  InitializeWebMediaPlayerImpl();
  CreateCdm();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcPlayNativeHls();
  const std::vector<uint8_t> key_a = SkdInitData("skd://a");
  parc_cdm_context_.requires_fairplay_renderer = true;
  parc_cdm_context_.requested_keys = {key_a};
  ParcSetKeyRequestCdm();
  parc_cdm_context_.defer_answers = true;

  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SKD, _));
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
  OnEncryptedMediaInitData(media::EmeInitDataType::SKD, key_a);
  OnWaiting(media::WaitingReason::kNoDecryptionKey);
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey()).Times(0);
  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey()).Times(0);
  Persistent<ParcCdmResult> result = MakeGarbageCollected<ParcCdmResult>();
  wmpi_->SetContentDecryptionModule(nullptr, result->Result());
  CycleThreads();
  EXPECT_TRUE(result->completed);
  parc_cdm_context_.AnswerDeferred();
  CycleThreads();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcSrcAttachedCdmDoesNotWait) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcAttachCdm();
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey()).Times(0);
  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey()).Times(0);
  OnWaiting(media::WaitingReason::kNoDecryptionKey);
  parc_cdm_context_.NotifyStatusesChanged();
  base::RunLoop().RunUntilIdle();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcMediaSourceWaitsForEverySourceBuffer) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcMediaSource();
  ParcAttachCdm();
  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SINF, _))
      .Times(2);
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey()).Times(1);
  ParcSourceKeyChanged("audio", {1});
  ParcSourceKeyChanged("video", {2});
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey()).Times(0);
  parc_cdm_context_.requested_keys = {{1}};
  parc_cdm_context_.NotifyStatusesChanged();
  base::RunLoop().RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey()).Times(1);
  parc_cdm_context_.requested_keys.push_back({2});
  parc_cdm_context_.NotifyStatusesChanged();
  base::RunLoop().RunUntilIdle();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcMediaSourceReportsMptsInitData) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcMediaSource();
  ParcAttachCdm();
  const std::vector<uint8_t> mpts = {'{', '}'};
  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::MPTS, _));
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
  OnEncryptedMediaInitData(media::EmeInitDataType::MPTS, mpts);
  base::RunLoop().RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);

  EXPECT_CALL(encrypted_client_, Encrypted(_, _)).Times(0);
  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey());
  parc_cdm_context_.requested_keys = {mpts};
  parc_cdm_context_.NotifyStatusesChanged();
  base::RunLoop().RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&encrypted_client_);
  EXPECT_THAT(parc_cdm_context_.asked_types,
              testing::Each(media::EmeInitDataType::MPTS));

  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(false));
  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::MPTS, _));
  OnEncryptedMediaInitData(media::EmeInitDataType::MPTS, mpts);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcRemovedSourceDoesNotHoldWaitOrAcceptOldCheck) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcMediaSource();
  ParcAttachCdm();
  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SINF, _));
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
  ParcSourceKeyChanged("video", {2});
  parc_cdm_context_.defer_answers = true;
  parc_cdm_context_.NotifyStatusesChanged();
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey());
  ParcSourceKeyChanged("video", {});
  parc_cdm_context_.AnswerDeferred();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcResolvedSourceDoesNotEmitOldEncryptedEvent) {
  InitializeWebMediaPlayerImpl();
  CreateCdm();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcMediaSource();
  parc_cdm_context_.requires_fairplay_renderer = true;
  parc_cdm_context_.requested_keys = {{1}};
  ParcSetKeyRequestCdm();
  EXPECT_CALL(encrypted_client_, Encrypted(_, _)).Times(0);
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey()).Times(0);
  OnEncryptedMediaInitData(media::EmeInitDataType::SINF, {1});
  parc_cdm_context_.requested_keys.clear();
  parc_cdm_context_.NotifyStatusesChanged();
  CycleThreads();
  Persistent<ParcCdmResult> result = MakeGarbageCollected<ParcCdmResult>();
  wmpi_->SetContentDecryptionModule(nullptr, result->Result());
  CycleThreads();
  EXPECT_TRUE(result->completed);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcReplacementIgnoresOldSourceCheck) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcMediaSource();
  ParcAttachCdm();
  parc_cdm_context_.defer_answers = true;
  EXPECT_CALL(encrypted_client_, Encrypted(_, _)).Times(0);
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey()).Times(0);
  OnEncryptedMediaInitData(media::EmeInitDataType::SINF, {1});
  parc_cdm_context_.defer_answers = false;
  parc_cdm_context_.requested_keys = {{1}};
  ParcAttachCdm();
  parc_cdm_context_.AnswerDeferred();
  CycleThreads();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcRejectedCdmCannotEndSourceWait) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcMediaSource();
  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SINF, _))
      .Times(2);
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey()).Times(1);
  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey()).Times(0);
  OnEncryptedMediaInitData(media::EmeInitDataType::SINF, {1});
  parc_cdm_context_.requested_keys = {{1}};
  parc_cdm_context_.defer_answers = true;
  ParcFailPendingCdmAfterSourceCheck();
  parc_cdm_context_.AnswerDeferred();
  CycleThreads();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcMediaSourceDetachedCdmIgnoresInFlightSuccess) {
  InitializeWebMediaPlayerImpl();
  CreateCdm();
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcMediaSource();
  parc_cdm_context_.requires_fairplay_renderer = true;
  ParcSetKeyRequestCdm();
  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::SINF, _));
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey());
  OnEncryptedMediaInitData(media::EmeInitDataType::SINF, {1});
  parc_cdm_context_.requested_keys = {{1}};
  parc_cdm_context_.defer_answers = true;
  parc_cdm_context_.NotifyStatusesChanged();
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey()).Times(0);
  Persistent<ParcCdmResult> result = MakeGarbageCollected<ParcCdmResult>();
  wmpi_->SetContentDecryptionModule(nullptr, result->Result());
  CycleThreads();
  EXPECT_TRUE(result->completed);
  parc_cdm_context_.AnswerDeferred();
  CycleThreads();
}
#endif

#if BUILDFLAG(IS_WIN)

#endif

#if BUILDFLAG(IS_MAC)
TEST_F(ParcWebMediaPlayerImplTest, ParcStreamsAddedJoinRenderer) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kVideoOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveEnoughData);
  ASSERT_FALSE(wmpi_->HasAudio());

  media::PipelineMetadata added;
  added.has_audio = true;
  added.audio_decoder_config = TestAudioConfig::Normal();
  ParcAddStreamsWithoutRestart(
      added, {{media::DemuxerStream::AUDIO, media::MediaTrack::Id("2")}});
  EXPECT_TRUE(wmpi_->HasAudio());
  EXPECT_TRUE(ParcAwaitsAddedStreamsRenderer());

  EXPECT_CALL(*surface_layer_bridge_ptr_, ClearObserver());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcStreamsAddedMixingAudioJoinsRendererImpl) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveEnoughData);

  ParcAddStreamsWithoutRestart(
      media::PipelineMetadata(),
      {{media::DemuxerStream::AUDIO, media::MediaTrack::Id("2")}});
  EXPECT_TRUE(ParcAwaitsAddedStreamsRenderer());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcStreamsAddedEncryptedJoinsRendererImpl) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kVideoOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveEnoughData);

  media::PipelineMetadata added;
  added.has_audio = true;
  added.audio_decoder_config = TestAudioConfig::NormalEncrypted();
  ParcAddStreamsWithoutRestart(
      added, {{media::DemuxerStream::AUDIO, media::MediaTrack::Id("2")}});
  EXPECT_TRUE(wmpi_->HasAudio());
  EXPECT_TRUE(ParcAwaitsAddedStreamsRenderer());

  EXPECT_CALL(*surface_layer_bridge_ptr_, ClearObserver());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcStreamsAddedForFairPlayRestart) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kVideoOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveEnoughData);

  ParcSetPendingFairPlayCdm();
  media::PipelineMetadata added;
  added.has_audio = true;
  added.audio_decoder_config = TestAudioConfig::NormalEncrypted();
  ParcAddStreamsAndWaitForRestart(
      added, {{media::DemuxerStream::AUDIO, media::MediaTrack::Id("2")}});
  EXPECT_TRUE(wmpi_->HasAudio());

  EXPECT_CALL(*surface_layer_bridge_ptr_, ClearObserver());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcSafariFairPlayPlaysVp9AndVorbis) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(true);
  const media::VideoDecoderConfig dolby_vision =
      TestVideoConfig::NormalCodecProfile(media::VideoCodec::kDolbyVision,
                                          media::DOLBYVISION_PROFILE5);
  const media::AudioDecoderConfig vorbis = TestAudioConfig::Normal();
  ASSERT_EQ(vorbis.codec(), media::AudioCodec::kVorbis);
  const media::VideoDecoderConfig vp9_profile2 =
      TestVideoConfig::NormalCodecProfile(media::VideoCodec::kVP9,
                                          media::VP9PROFILE_PROFILE2);
  const media::AudioDecoderConfig aac(
      media::AudioCodec::kAAC, media::kSampleFormatPlanarF32,
      media::ChannelLayoutConfig::Stereo(), 44100, std::vector<uint8_t>(),
      media::EncryptionScheme::kUnencrypted);

  EXPECT_TRUE(ParcFairPlayPlays(dolby_vision, vorbis));
  EXPECT_TRUE(ParcFairPlayPlays(vp9_profile2, aac));
  EXPECT_FALSE(ParcFairPlayPlays(
      TestVideoConfig::NormalCodecProfile(media::VideoCodec::kVP9,
                                          media::VP9PROFILE_PROFILE1),
      vorbis));
  EXPECT_TRUE(
      ParcFairPlayChangeTypeSupported(true, "video/webm", "vp09.00.10.08"));
  EXPECT_TRUE(
      ParcFairPlayChangeTypeSupported(true, "video/webm", "vp09.02.10.10"));
  EXPECT_FALSE(
      ParcFairPlayChangeTypeSupported(true, "video/webm", "vp09.01.10.08"));
  EXPECT_TRUE(ParcFairPlayChangeTypeSupported(true, "audio/webm", "vorbis"));
  EXPECT_TRUE(
      ParcFairPlayChangeTypeSupported(true, "video/mp4", "av01.0.04M.08"));

  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(false));
  EXPECT_FALSE(ParcFairPlayPlays(dolby_vision, vorbis));
  EXPECT_FALSE(ParcFairPlayPlays(vp9_profile2, aac));
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcClearChunkDemuxer();
  EXPECT_FALSE(ParcFairPlayPlays(dolby_vision, vorbis));
  EXPECT_FALSE(
      ParcFairPlayChangeTypeSupported(false, "video/webm", "vp09.00.10.08"));
  EXPECT_FALSE(ParcFairPlayChangeTypeSupported(false, "audio/webm", "vorbis"));
  EXPECT_FALSE(
      ParcFairPlayChangeTypeSupported(false, "video/mp4", "av01.0.04M.08"));
  EXPECT_TRUE(
      ParcFairPlayChangeTypeSupported(false, "video/mp4", "avc1.64001f"));
}
#endif

#if BUILDFLAG(IS_MAC)
TEST_F(ParcWebMediaPlayerImplTest, ParcHandOffWaitsForASeek) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kVideoOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveEnoughData);
  ParcPlayChromiumRenderer();
  wmpi_->Seek(0.5);
  ParcHandOffOrRestart();
  EXPECT_FALSE(ParcRestartPending());
  CycleThreads();

  EXPECT_CALL(*surface_layer_bridge_ptr_, ClearObserver());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcFairPlayRendererTakesLateKeysInPlace) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kVideoOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveEnoughData);
  ParcPlayFairPlayRenderer();

  parc_cdm_context_.requires_fairplay_renderer = true;
  ParcAttachCdm();
  EXPECT_FALSE(ParcRestartPending());
  CycleThreads();
  EXPECT_FALSE(IsSuspended());
  EXPECT_FALSE(ParcRestartPending());

  ParcAttachCdm(&parc_fairplay_cdm_context_);
  EXPECT_FALSE(ParcRestartPending());
  CycleThreads();
  EXPECT_FALSE(IsSuspended());
  EXPECT_FALSE(ParcRestartPending());

  EXPECT_CALL(*surface_layer_bridge_ptr_, ClearObserver());
}
#endif

class ParcWebMediaPlayerImplHiddenVideoTest
    : public ParcWebMediaPlayerImplTest,
      public ::testing::WithParamInterface<bool> {
 protected:
  bool PresentsSafariIdentity() const { return GetParam(); }

  void PlayVideoOnly() {
    std::unique_ptr<media::MockDemuxer> demuxer =
        std::make_unique<NiceMock<media::MockDemuxer>>();
    ON_CALL(*demuxer, IsSeekable()).WillByDefault(Return(true));
    InitializeWebMediaPlayerImpl(std::move(demuxer));
    Load(kVideoOnlyTestFile);
    EXPECT_FALSE(IsSuspended());

    media::PipelineMetadata metadata;
    metadata.has_video = true;
    metadata.video_decoder_config = TestVideoConfig::Normal();
    EXPECT_CALL(delegate_, DidMediaMetadataChange(_, false, true, _)).Times(2);
    OnMetadata(metadata);

    ON_CALL(*client_, PresentsParcSafariIdentity())
        .WillByDefault(Return(PresentsSafariIdentity()));
    SetReadyState(WebMediaPlayer::kReadyStateHaveFutureData);
    SetSeeking(false);
    Play();
  }
};

TEST_P(ParcWebMediaPlayerImplHiddenVideoTest, PageHidden) {
  PlayVideoOnly();

  EXPECT_CALL(*client_, PausePlayback(WebMediaPlayer::PauseReason::kPageHidden))
      .Times(PresentsSafariIdentity() ? 0 : 1);
  BackgroundPlayer(BackgroundBehaviorType::Page);
  EXPECT_EQ(!PresentsSafariIdentity(), IsPausedBecausePageHidden());

  EXPECT_CALL(*client_, ResumePlayback())
      .Times(PresentsSafariIdentity() ? 0 : 1);
  ForegroundPlayer(BackgroundBehaviorType::Page);
  EXPECT_FALSE(IsPausedBecausePageHidden());
}

TEST_P(ParcWebMediaPlayerImplHiddenVideoTest, FrameHiddenWithPolicy) {
  PlayVideoOnly();
  wmpi_->SetShouldPauseWhenFrameIsHidden(true);

  EXPECT_CALL(*client_,
              PausePlayback(WebMediaPlayer::PauseReason::kFrameHidden));
  BackgroundPlayer(BackgroundBehaviorType::Frame);
  EXPECT_TRUE(IsPausedBecauseFrameHidden());
}

INSTANTIATE_TEST_SUITE_P(SafariIdentity,
                         ParcWebMediaPlayerImplHiddenVideoTest,
                         ::testing::Bool());

TEST_F(ParcWebMediaPlayerImplTest, ParcOnFrozenWhileRemotingKeepsPipeline) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SwitchToRemoteRenderer("TV");
  ASSERT_FALSE(IsSuspended());

  EXPECT_CALL(mock_observer_, OnFrozen());
  wmpi_->OnFrozen();
  EXPECT_FALSE(IsSuspended());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcOnFrozenWhileRemotingKeepsStreamingReader) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  Load("bear_192kHz.wav", LoadType::kStreaming);
  while (wmpi_->GetReadyState() < WebMediaPlayer::kReadyStateHaveMetadata) {
    base::RunLoop loop;
    EXPECT_CALL(*client_, ReadyStateChanged())
        .WillRepeatedly(RunClosure(loop.QuitClosure()));
    loop.Run();
    testing::Mock::VerifyAndClearExpectations(client_.Get());
  }
  EXPECT_CALL(*client_, ReadyStateChanged()).Times(AnyNumber());
  ASSERT_TRUE(IsStreaming());
  ASSERT_FALSE(ShouldCancelUponDefer());

  SetRemoteRenderingWithoutRestart();
  wmpi_->OnFrozen();
  EXPECT_FALSE(ShouldCancelUponDefer());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcFrozenInBackForwardCacheKeepsPipeline) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  LoadAndWaitForCurrentData(kAudioOnlyTestFile);
  ASSERT_FALSE(IsStreaming());
  ASSERT_FALSE(IsSuspended());
  ASSERT_FALSE(ShouldCancelUponDefer());

  EXPECT_CALL(mock_observer_, OnFrozen());
  wmpi_->ParcOnFrozenInBackForwardCache();
  EXPECT_FALSE(IsSuspended());
  EXPECT_TRUE(ShouldCancelUponDefer());
}

TEST_F(ParcWebMediaPlayerImplTest,
       ParcCastStartedInBackForwardCacheReachesReceiver) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  ASSERT_TRUE(base::test::RunUntil([&] { return IsPipelineStable(); }));

  FreezePage(true);
  wmpi_->ParcOnFrozenInBackForwardCache();
  wmpi_->SwitchToRemoteRenderer("TV");
  EXPECT_TRUE(base::test::RunUntil([&] { return IsPipelineStable(); }));
  EXPECT_FALSE(IsSuspended());
  FreezePage(false);
}

TEST_F(ParcWebMediaPlayerImplTest,
       ParcCastStartedAfterFrozenSuspendReachesReceiver) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  ASSERT_TRUE(base::test::RunUntil([&] { return IsPipelineStable(); }));

  FreezePage(true);
  wmpi_->OnFrozen();
  CycleThreads();
  CycleThreads();
  ASSERT_FALSE(IsPipelineSuspended());

  wmpi_->SwitchToRemoteRenderer("TV");
  EXPECT_TRUE(base::test::RunUntil([&] { return IsPipelineStable(); }));
  EXPECT_FALSE(IsSuspended());
  FreezePage(false);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcFrozenPlayerNotCastingWaitsForItsPage) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  ASSERT_TRUE(base::test::RunUntil([&] { return IsPipelineStable(); }));

  FreezePage(true);
  wmpi_->OnFrozen();
  CycleThreads();
  CycleThreads();
  EXPECT_FALSE(IsPipelineSuspended());

  FreezePage(false);
  EXPECT_TRUE(base::test::RunUntil([&] { return IsPipelineSuspended(); }));
}

TEST_F(ParcWebMediaPlayerImplTest, ParcOnFrozenWhileCastingKeepsReader) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  LoadAndWaitForCurrentData(kAudioOnlyTestFile);
  ASSERT_FALSE(IsStreaming());

  SetRemoteRenderingWithoutRestart();
  wmpi_->OnFrozen();
  EXPECT_FALSE(ShouldCancelUponDefer());
}

TEST_F(ParcWebMediaPlayerImplTest,
       ParcFrozenInBackForwardCacheWhileCastingKeepsReader) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  LoadAndWaitForCurrentData(kAudioOnlyTestFile);
  ASSERT_FALSE(IsStreaming());

  SetRemoteRenderingWithoutRestart();
  wmpi_->ParcOnFrozenInBackForwardCache();
  EXPECT_FALSE(ShouldCancelUponDefer());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcCastStartedWhileFrozenReadsOn) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  ASSERT_TRUE(base::test::RunUntil([&] { return IsPipelineStable(); }));

  FreezePage(true);
  wmpi_->ParcOnFrozenInBackForwardCache();
  ASSERT_TRUE(ShouldCancelUponDefer());
  wmpi_->SwitchToRemoteRenderer("TV");
  EXPECT_TRUE(base::test::RunUntil([&] { return IsPipelineStable(); }));
  EXPECT_FALSE(ShouldCancelUponDefer());

  MultiBufferDataSource* data_source = GetMultiBufferDataSource();
  data_source->StopPreloading();
  uint8_t byte = 0;
  bool read = false;
  data_source->Read(0, base::span_from_ref(byte),
                    base::BindLambdaForTesting(
                        [&](int bytes_read) { read = bytes_read == 1; }));
  EXPECT_TRUE(base::test::RunUntil([&] { return read; }));
  FreezePage(false);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcFrozenSourceNotCastingWaitsForItsPage) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  ASSERT_TRUE(base::test::RunUntil([&] { return IsPipelineStable(); }));

  FreezePage(true);
  wmpi_->ParcOnFrozenInBackForwardCache();
  EXPECT_TRUE(ShouldCancelUponDefer());
  MultiBufferDataSource* data_source = GetMultiBufferDataSource();
  uint8_t byte = 0;
  bool read = false;
  data_source->Read(0, base::span_from_ref(byte),
                    base::BindLambdaForTesting(
                        [&](int bytes_read) { read = bytes_read == 1; }));
  CycleThreads();
  CycleThreads();
  EXPECT_FALSE(read);

  FreezePage(false);
  EXPECT_TRUE(base::test::RunUntil([&] { return read; }));
}

TEST_F(ParcWebMediaPlayerImplTest, ParcConnectingCastKeepsReaderWhileCached) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  LoadAndWaitForCurrentData(kAudioOnlyTestFile);

  wmpi_->ParcSetCastPrompted(true);
  wmpi_->ParcOnFrozenInBackForwardCache();
  EXPECT_FALSE(ShouldCancelUponDefer());

  wmpi_->ParcCastRequestChanged(true);
  wmpi_->ParcSetCastPrompted(false);
  wmpi_->ParcOnFrozenInBackForwardCache();
  EXPECT_FALSE(ShouldCancelUponDefer());

  wmpi_->ParcCastRequestChanged(false);
  wmpi_->ParcOnFrozenInBackForwardCache();
  EXPECT_TRUE(ShouldCancelUponDefer());
}

#if BUILDFLAG(ENABLE_HLS_DEMUXER)
TEST_F(ParcWebMediaPlayerImplTest, ParcHlsSegmentReadsWhileCastingFromFrozenPage) {
  InitializeWebMediaPlayerImpl();
  auto provider = CreateHlsProvider();
  SetRemoteRenderingWithoutRestart();
  FreezePage(true);

  WebAssociatedURLLoaderClient* client = nullptr;
  bool runs_while_frozen = false;
  bool read = false;
  ReadHlsSegment(*provider, client, runs_while_frozen, read);
  ASSERT_TRUE(base::test::RunUntil([&] { return client != nullptr; }));
  EXPECT_TRUE(runs_while_frozen);
  ServeHlsSegment(client);
  EXPECT_TRUE(base::test::RunUntil([&] { return read; }));
  FreezePage(false);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcHlsSegmentNotCastingWaitsForFrozenPage) {
  InitializeWebMediaPlayerImpl();
  auto provider = CreateHlsProvider();
  FreezePage(true);

  WebAssociatedURLLoaderClient* client = nullptr;
  bool runs_while_frozen = false;
  bool read = false;
  ReadHlsSegment(*provider, client, runs_while_frozen, read);
  CycleThreads();
  CycleThreads();
  EXPECT_FALSE(client);

  FreezePage(false);
  ASSERT_TRUE(base::test::RunUntil([&] { return client != nullptr; }));
  EXPECT_FALSE(runs_while_frozen);
  ServeHlsSegment(client);
  EXPECT_TRUE(base::test::RunUntil([&] { return read; }));
}
#endif

TEST_F(ParcWebMediaPlayerImplTest, ParcSetPageHiddenOverridesDelegatePage) {
  InitializeWebMediaPlayerImpl();
  HidePlayerPage();
  ASSERT_TRUE(IsPageHidden());

  {
    testing::InSequence sequence;
    base::RunLoop loop;
    EXPECT_CALL(*compositor_, SetIsPageVisible(true));
    EXPECT_CALL(*compositor_, SetIsPageVisible(false))
        .WillOnce(RunClosure(loop.QuitClosure()));

    wmpi_->ParcSetPageHidden(false);
    EXPECT_FALSE(IsPageHidden());

    delegate_.SetPageHiddenForTesting(false);
    wmpi_->OnPageShown();
    delegate_.SetPageHiddenForTesting(true);
    wmpi_->OnPageHidden();
    EXPECT_FALSE(IsPageHidden());

    wmpi_->ParcSetPageHidden(false);
    wmpi_->ParcSetPageHidden(true);
    EXPECT_TRUE(IsPageHidden());
    loop.Run();
    testing::Mock::VerifyAndClearExpectations(compositor_);
  }

  base::RunLoop loop;
  EXPECT_CALL(*compositor_, SetIsPageVisible(true))
      .WillOnce(RunClosure(loop.QuitClosure()));
  delegate_.SetPageHiddenForTesting(false);
  wmpi_->ParcSetPageHidden(std::nullopt);
  EXPECT_FALSE(IsPageHidden());
  loop.Run();
  testing::Mock::VerifyAndClearExpectations(compositor_);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcMoveToFrameMovesPlayerAndReportsState) {
  ON_CALL(*client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  wmpi_->SetRate(1.0);
  EXPECT_CALL(*client_, DidPlayerMediaPositionStateChange(
                           0.0, kAudioOnlyTestFileDuration, base::TimeDelta(),
                           false));
  wmpi_->OnTimeUpdate();
  testing::Mock::VerifyAndClearExpectations(client_.Get());

  auto new_sink =
      base::MakeRefCounted<NiceMock<media::MockAudioRendererSink>>();
  moved_to_url_index_ = std::make_unique<UrlIndex>(
      &moved_to_fetch_context_, media_thread_.task_runner());
  moved_to_view_helper_.Initialize();
  bool factories_moved = false;
  bool media_log_moved = false;
  ParcWebMediaPlayerExtension::ParcFrameServices services;
  services.frame = moved_to_view_helper_.LocalMainFrame();
  services.delegate = &moved_to_delegate_;
  services.url_index = moved_to_url_index_.get();
  services.audio_sink = new_sink;
  services.move_factories = blink::BindOnce(
      [](bool* moved, media::RendererFactorySelector&) { *moved = true; },
      Unretained(&factories_moved));
  services.move_media_log = blink::BindOnce(
      [](bool* moved, media::MediaLog&) { *moved = true; },
      Unretained(&media_log_moved));
  EXPECT_CALL(*audio_sink_, Stop());
  EXPECT_TRUE(wmpi_->ParcMoveToFrame(std::move(services)));
  EXPECT_TRUE(factories_moved);
  EXPECT_TRUE(media_log_moved);
  EXPECT_FALSE(delegate_.has_observer());
  EXPECT_TRUE(moved_to_delegate_.has_observer());
  media_thread_.FlushForTesting();
  media_thread_.FlushForTesting();
  testing::Mock::VerifyAndClearExpectations(audio_sink_.get());
  EXPECT_TRUE(new_sink->callback());
  EXPECT_FALSE(IsSuspended());

  EXPECT_CALL(*client_,
              ParcReportMediaMetadata(true, false,
                                      _));
  EXPECT_CALL(*client_, DidPlayerMutedStatusChange(false));
  EXPECT_CALL(*client_, DidPlayerStartPlaying()).Times(0);
  EXPECT_CALL(*client_, DidPlayerMediaPositionStateChange(
                           0.0, kAudioOnlyTestFileDuration, base::TimeDelta(),
                           false));
  wmpi_->ParcReportStateToClient();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcMoveToFrameKeepsChromeIdentityPlayer) {
  InitializeWebMediaPlayerImpl();
  moved_to_view_helper_.Initialize();
  ParcWebMediaPlayerExtension::ParcFrameServices services;
  services.frame = moved_to_view_helper_.LocalMainFrame();
  services.delegate = &moved_to_delegate_;
  services.url_index = url_index_.get();
  EXPECT_FALSE(wmpi_->ParcMoveToFrame(std::move(services)));
  EXPECT_TRUE(delegate_.has_observer());
  EXPECT_FALSE(moved_to_delegate_.has_observer());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcSafariMediaSourceBufferedSeek) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(true);

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(2);
  AppendParcMediaSource(base::TimeDelta(), media::kInfiniteDuration);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());
  parc_demuxer_->MarkEndOfStream(media::PIPELINE_OK);
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());

  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  wmpi_->Seek(1.0);
  EXPECT_TRUE(wmpi_->Seeking());
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcSafariMediaSourceUnbufferedSeek) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(true);

  EXPECT_CALL(*client_, ReadyStateChanged());
  AppendParcMediaSource(base::TimeDelta(), base::Seconds(1));
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  EXPECT_CALL(*client_, ReadyStateChanged());
  wmpi_->Seek(2.0);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());

  EXPECT_CALL(*client_, ReadyStateChanged());
  AppendParcMediaSource(base::Seconds(2), base::Seconds(2.5));
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  EXPECT_CALL(*client_, ReadyStateChanged());
  AppendParcMediaSource(base::Seconds(2.5), media::kInfiniteDuration);
  parc_demuxer_->MarkEndOfStream(media::PIPELINE_OK);
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcSafariMediaSourceLateSourceBuffer) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(true);
  parc_demuxer_->ParcAllowSourceBuffersAfterInit(base::DoNothing());

  EXPECT_CALL(*client_, ReadyStateChanged());
  AppendParcMediaSource(base::TimeDelta(), media::kInfiniteDuration);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  ASSERT_EQ(parc_demuxer_->AddId("audio2", "audio/webm", "vorbis"),
            media::ChunkDemuxer::kOk);
  parc_demuxer_->SetTracksWatcher("audio2", base::DoNothing());
  EXPECT_CALL(*client_, ReadyStateChanged()).Times(0);
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  EXPECT_CALL(*client_, ReadyStateChanged());
  AppendParcMediaSource(base::Seconds(10), media::kInfiniteDuration, "audio2");
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());

  EXPECT_CALL(*client_, ReadyStateChanged());
  AppendParcMediaSource(base::TimeDelta(), base::Seconds(1), "audio2");
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  EXPECT_CALL(*client_, ReadyStateChanged());
  AppendParcMediaSource(base::Seconds(1), media::kInfiniteDuration, "audio2");
  parc_demuxer_->MarkEndOfStream(media::PIPELINE_OK);
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcChromeMediaSourceSeekUnchanged) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(false);

  AppendParcMediaSource(base::TimeDelta(), media::kInfiniteDuration);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());
  SetReadyState(WebMediaPlayer::kReadyStateHaveEnoughData);

  EXPECT_CALL(*client_, ReadyStateChanged());
  wmpi_->Seek(1.0);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());
}

class ParcWebMediaPlayerImplBackgroundBehaviorTest
    : public ParcWebMediaPlayerImplTest,
      public WebAudioSourceProviderClient,
      public ::testing::WithParamInterface<
          std::tuple<bool, int, int, bool, bool, bool, bool, bool, bool>> {
 public:
  static const int kIsMediaSuspendEnabled = 0;
  static const int kDurationSec = 1;
  static const int kAverageKeyframeDistanceSec = 2;
  static const int kIsResumeBackgroundVideoEnabled = 3;
  static const int kIsPictureInPictureEnabled = 4;
  static const int kIsBackgroundVideoPlaybackEnabled = 5;
  static const int kIsVideoBeingCaptured = 6;
  static const int kShouldHidePage = 7;
  static const int kShouldPauseWhenFrameIsHidden = 8;

  void SetUp() override {
    ParcWebMediaPlayerImplTest::SetUp();
    SetUpMediaSuspend(IsMediaSuspendOn());
    SetUpBackgroundVideoPlayback(IsBackgroundVideoPlaybackEnabled());

    std::string enabled_features;
    std::string disabled_features;

    if (IsResumeBackgroundVideoEnabled()) {
      if (!enabled_features.empty())
        enabled_features += ",";
      enabled_features += media::kResumeBackgroundVideo.name;
    } else {
      if (!disabled_features.empty())
        disabled_features += ",";
      disabled_features += media::kResumeBackgroundVideo.name;
    }

    feature_list_.InitFromCommandLine(enabled_features, disabled_features);

    if (std::get<kShouldHidePage>(GetParam())) {
      background_type_ = BackgroundBehaviorType::Page;
    } else {
      background_type_ = BackgroundBehaviorType::Frame;
    }

    InitializeWebMediaPlayerImpl();

    SetLoadType(WebMediaPlayer::kLoadTypeURL);

    SetVideoKeyframeDistanceAverage(
        base::Seconds(GetAverageKeyframeDistanceSec()));
    SetDuration(base::Seconds(GetDurationSec()));

    if (IsPictureInPictureOn()) {
      SetPiPExpectations();
      wmpi_->OnSurfaceIdUpdated(surface_id_);
    }

    if (IsVideoBeingCaptured())
      wmpi_->GetCurrentFrameThenUpdate();

    wmpi_->SetShouldPauseWhenFrameIsHidden(GetShouldPauseWhenFrameIsHidden());

    BackgroundPlayer(background_type_);
  }

  void SetVideoKeyframeDistanceAverage(base::TimeDelta value) {
    media::PipelineStatistics statistics;
    statistics.video_keyframe_distance_average = value;
    wmpi_->SetPipelineStatisticsForTest(statistics);
  }

  void SetPiPExpectations() {
    if (!IsPictureInPictureOn())
      return;
    EXPECT_CALL(*client_, GetDisplayType())
        .WillRepeatedly(
            Return(WebMediaPlayer::DisplayType::kVideoPictureInPicture));
  }

  bool IsMediaSuspendOn() {
    return std::get<kIsMediaSuspendEnabled>(GetParam());
  }

  bool IsResumeBackgroundVideoEnabled() {
    return std::get<kIsResumeBackgroundVideoEnabled>(GetParam());
  }

  bool IsPictureInPictureOn() {
    return std::get<kIsPictureInPictureEnabled>(GetParam());
  }

  bool IsBackgroundVideoPlaybackEnabled() {
    return std::get<kIsBackgroundVideoPlaybackEnabled>(GetParam());
  }

  bool IsVideoBeingCaptured() {
    return std::get<kIsVideoBeingCaptured>(GetParam());
  }

  bool GetShouldPauseWhenFrameIsHidden() const {
    return std::get<kShouldPauseWhenFrameIsHidden>(GetParam());
  }

  int GetDurationSec() const { return std::get<kDurationSec>(GetParam()); }

  int GetAverageKeyframeDistanceSec() const {
    return std::get<kAverageKeyframeDistanceSec>(GetParam());
  }

  int GetMaxKeyframeDistanceSec() const {
    return WebMediaPlayerImpl::kMaxKeyframeDistanceToDisableBackgroundVideo
        .InSeconds();
  }

  bool ShouldDisableVideoWhenHidden() const {
    return wmpi_->ShouldDisableVideoWhenHidden();
  }

  bool ShouldPausePlaybackWhenHidden() const {
    return wmpi_->ShouldPausePlaybackWhenHidden();
  }

  void SetVolume(double volume) { wmpi_->SetVolume(volume); }

  bool IsFrameHiddenAndShouldPauseWhenHidden() const {
    return background_type_ == BackgroundBehaviorType::Frame &&
           GetShouldPauseWhenFrameIsHidden();
  }

  std::string PrintValues() {
    std::stringstream stream;
    stream << "is_media_suspend_enabled=" << IsMediaSuspendOn()
           << ", duration_sec=" << GetDurationSec()
           << ", average_keyframe_distance_sec="
           << GetAverageKeyframeDistanceSec()
           << ", is_resume_background_video_enabled="
           << IsResumeBackgroundVideoEnabled()
           << ", is_picture_in_picture=" << IsPictureInPictureOn()
           << ", is_background_video_playback_enabled="
           << IsBackgroundVideoPlaybackEnabled()
           << ", is_video_being_captured=" << IsVideoBeingCaptured()
           << ", should_pause_when_frame_is_hidden="
           << GetShouldPauseWhenFrameIsHidden() << ", should_hide_page="
           << (background_type_ == BackgroundBehaviorType::Page);
    return stream.str();
  }

  MOCK_METHOD2(SetFormat, void(uint32_t numberOfChannels, float sampleRate));

 protected:
  BackgroundBehaviorType background_type_;

 private:
  base::test::ScopedFeatureList feature_list_;
};

TEST_P(ParcWebMediaPlayerImplBackgroundBehaviorTest,
       SafariIdentity_KeepsBackgroundVideoTrackSelected) {
  EXPECT_CALL(*client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  SetMetadata(true, true);
  for (auto load_type : {WebMediaPlayer::kLoadTypeURL,
                         WebMediaPlayer::kLoadTypeMediaSource}) {
    SetLoadType(load_type);
    EXPECT_FALSE(ShouldDisableVideoWhenHidden());
  }
}

TEST_P(ParcWebMediaPlayerImplBackgroundBehaviorTest,
       ChromeIdentity_PreservesBackgroundVideoOptimization) {
  EXPECT_CALL(*client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(false));
  SetMetadata(true, true);
  const bool eligible =
      !IsPictureInPictureOn() && !IsVideoBeingCaptured() &&
      (GetDurationSec() < GetMaxKeyframeDistanceSec() ||
       GetAverageKeyframeDistanceSec() < GetMaxKeyframeDistanceSec());
  for (auto load_type : {WebMediaPlayer::kLoadTypeURL,
                         WebMediaPlayer::kLoadTypeMediaSource}) {
    SetLoadType(load_type);
    EXPECT_EQ(eligible, ShouldDisableVideoWhenHidden());
  }
}

TEST_P(ParcWebMediaPlayerImplBackgroundBehaviorTest, SafariIdentity_AudioOnly) {
  base::test::ScopedFeatureList scoped_background_audio_flag{
      media::kPauseMutedBackgroundAudio};
  SCOPED_TRACE(testing::Message() << PrintValues());
  EXPECT_CALL(*client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(*client_, WasAlwaysMuted()).WillRepeatedly(Return(true));
  SetMetadata(true, false);
  SetVolume(0.);
  EXPECT_EQ(IsFrameHiddenAndShouldPauseWhenHidden() ||
                !IsBackgroundVideoPlaybackEnabled(),
            ShouldPausePlaybackWhenHidden());
}

TEST_P(ParcWebMediaPlayerImplBackgroundBehaviorTest, SafariIdentity_VideoOnly) {
  SCOPED_TRACE(testing::Message() << PrintValues());
  EXPECT_CALL(*client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(*client_, WasAlwaysMuted()).WillRepeatedly(Return(true));
  SetMetadata(false, true);
  EXPECT_EQ(
      IsFrameHiddenAndShouldPauseWhenHidden() ||
          (!IsBackgroundVideoPlaybackEnabled() && !IsPictureInPictureOn()),
      ShouldPausePlaybackWhenHidden());
}

TEST_P(ParcWebMediaPlayerImplBackgroundBehaviorTest, SafariIdentity_AudioVideo) {
  base::test::ScopedFeatureList scoped_background_audio_flag{
      media::kPauseMutedBackgroundAudio};
  SCOPED_TRACE(testing::Message() << PrintValues());
  const bool should_pause =
      IsFrameHiddenAndShouldPauseWhenHidden() ||
      (!IsBackgroundVideoPlaybackEnabled() && !IsPictureInPictureOn());
  EXPECT_CALL(*client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(*client_, WasAlwaysMuted()).WillRepeatedly(Return(true));
  SetMetadata(true, true);
  EXPECT_EQ(should_pause, ShouldPausePlaybackWhenHidden());
  SetVolume(0.);
  EXPECT_EQ(should_pause, ShouldPausePlaybackWhenHidden());

  EXPECT_CALL(*client_, WasAlwaysMuted()).WillRepeatedly(Return(false));
  SetVolume(1.);
  EXPECT_EQ(should_pause, ShouldPausePlaybackWhenHidden());
}

INSTANTIATE_TEST_SUITE_P(
    BackgroundBehaviorTestInstances,
    ParcWebMediaPlayerImplBackgroundBehaviorTest,
    ::testing::Combine(
        ::testing::Bool(),
        ::testing::Values(
            WebMediaPlayerImpl::kMaxKeyframeDistanceToDisableBackgroundVideo
                    .InSeconds() -
                1,
            300),
        ::testing::Values(
            WebMediaPlayerImpl::kMaxKeyframeDistanceToDisableBackgroundVideo
                    .InSeconds() -
                1,
            100),
        ::testing::Bool(),
        ::testing::Bool(),
        ::testing::Bool(),
        ::testing::Bool(),
        ::testing::Bool(),
        ::testing::Bool()));

}
