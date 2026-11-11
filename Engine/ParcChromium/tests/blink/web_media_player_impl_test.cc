// Copyright 2026 Parc contributors.
// Installed at
// //third_party/blink/renderer/parc_tests/blink/web_media_player_impl_test.cc.
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
#include "base/test/simple_test_tick_clock.h"
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
#include "media/base/memory_dump_provider_proxy.h"
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
#include "third_party/blink/public/platform/web_fullscreen_video_status.h"
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

class MockWebMediaPlayerClient : public MediaPlayerClient,
                                 public ParcMediaPlayerClient {
 public:
  MockWebMediaPlayerClient() = default;

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
// A CDM whose sessions have key requests for `requested_keys` ("skd" init
// data), answering ParcHasSessionForInitData as the FairPlay CDM does.
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

  // Delivers the deferred answers in order, as MojoCdm does.
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
  // Answers as each was when asked, but later (MojoCdm's round trip).
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
#endif  // BUILDFLAG(IS_MAC)

#if BUILDFLAG(IS_MAC)
// Parc: a FairPlay CDM whose sessions already asked for every key the init
// data names.
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
#endif  // BUILDFLAG(IS_MAC)

class MockWebMediaPlayerDelegate : public WebMediaPlayerDelegate {
 public:
  MockWebMediaPlayerDelegate() = default;
  ~MockWebMediaPlayerDelegate() override = default;

  // WebMediaPlayerDelegate implementation.
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

  void SetIdleForTesting(bool is_idle) { is_idle_ = is_idle; }

  void SetStaleForTesting(bool is_stale) {
    is_idle_ |= is_stale;
    is_stale_ = is_stale;
  }

  // Returns true if the player does in fact expire.
  bool ExpireForTesting() {
    if (is_idle_ && !is_stale_) {
      is_stale_ = true;
      observer_->OnIdleTimeout();
    }

    return is_stale_;
  }

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

  // MOCK_METHOD doesn't like OnceCallback.
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

}  // namespace

class ParcWebMediaPlayerImplTest
    : public testing::Test,
      private WebTestingSupport::WebScopedMockScrollbars {
 public:
  base::test::ScopedCommandLine av1_command_line_;

  ParcWebMediaPlayerImplTest()
      : media_thread_("MediaThreadForTest"),
        context_provider_(viz::TestContextProvider::CreateGLES()),
        audio_parameters_(media::TestAudioParameters::Normal()),
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

    EXPECT_CALL(client_, SetCcLayer(_)).Times(0);
    ON_CALL(*surface_layer_bridge_ptr_, GetSurfaceId())
        .WillByDefault(ReturnRef(surface_id_));
  }

  ParcWebMediaPlayerImplTest(const ParcWebMediaPlayerImplTest&) = delete;
  ParcWebMediaPlayerImplTest& operator=(const ParcWebMediaPlayerImplTest&) = delete;

  ~ParcWebMediaPlayerImplTest() override {
    if (!wmpi_)
      return;
    EXPECT_CALL(client_, SetCcLayer(nullptr));
    EXPECT_CALL(client_, MediaRemotingStopped(_));

    // Destruct WebMediaPlayerImpl and pump the message loop to ensure that
    // objects passed to the message loop for destruction are released.
    //
    // NOTE: This should be done before any other member variables are
    // destructed since WMPI may reference them during destruction.
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
    // We want to avoid the "Uninteresting mock function call" warning.
    EXPECT_CALL(*this, IsShuttingDown())
        .Times(AnyNumber())
        .WillRepeatedly(Return(false));

    auto media_log = std::make_unique<NiceMock<media::MockMediaLog>>();
    InitializeSurfaceLayerBridge();

    // Retain a raw pointer to |media_log| for use by tests. Meanwhile, give its
    // ownership to |wmpi_|. Reject attempts to reinitialize to prevent orphaned
    // expectations on previous |media_log_|.
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

    // Initialize provider since none of the tests below actually go through the
    // full loading/pipeline initialize phase. If this ever changes the provider
    // will start DCHECK failing.
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
    wmpi_ = std::make_unique<WebMediaPlayerImpl>(
        GetWebLocalFrame(), &client_, &encrypted_client_, &delegate_,
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
    EXPECT_CALL(client_, NetworkStateChanged());
    wmpi_->SetNetworkState(state);
  }

  void SetReadyState(WebMediaPlayer::ReadyState state) {
    EXPECT_CALL(client_, ReadyStateChanged());
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
  void SetEnded(bool is_ended) { wmpi_->ended_ = is_ended; }
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
        /*repaint_duplicate_frame=*/false);
  }
  void SetTickClock(const base::TickClock* clock) {
    wmpi_->SetTickClockForTest(clock);
  }
  void SetWasSuspendedForFrameClosed(bool is_suspended) {
    wmpi_->was_suspended_for_frame_closed_or_frozen_ = is_suspended;
  }

  void SetFullscreen(bool is_fullscreen) {
    wmpi_->overlay_enabled_ = is_fullscreen;
    wmpi_->overlay_info_.is_fullscreen = is_fullscreen;
  }

  void SetMetadata(bool has_audio, bool has_video) {
    wmpi_->SetNetworkState(WebMediaPlayer::kNetworkStateLoaded);

    EXPECT_CALL(client_, ReadyStateChanged());
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

  void SetError(media::PipelineStatus status = media::PIPELINE_ERROR_DECODE) {
    wmpi_->OnError(status);
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
  // Parc: a clear file's move between routes (ParcSwitchRoute).
  bool ParcFileOnNativeRoute() const {
    return wmpi_->parc_->file_on_native_route_;
  }
  bool ParcSwitchingRoute() const {
    return wmpi_->parc_->route_switch_.has_value();
  }
  bool HasDataSource() const {
    return wmpi_->demuxer_manager_->HasDataSource();
  }
  // What the restarting pipeline reports, without expecting the element to
  // hear it.
  void ParcReportReadyState(WebMediaPlayer::ReadyState state) {
    wmpi_->SetReadyState(state);
  }
  void ParcReportDurationChange() { wmpi_->OnDurationChange(); }
  void ParcReportNativeReadyState(media::ParcNativeHlsReadyState state) {
    wmpi_->ParcNativeHlsReadyStateChanged(state);
  }
  // The fixture serves files from file:// URLs; the native route loads only
  // HTTP(S).
  void ParcServeOverHttps() {
    wmpi_->demuxer_manager_->SetLoadedUrl(
        GURL("https://example.com/episode.mp3"));
    wmpi_->ParcCheckFileTargetSupport();
  }
  // A live stream that supports a target, loaded again from `url` by a route
  // switch.
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

  // Parc: setMediaKeys with `parc_cdm_context_` behind `web_cdm_`.
  void ParcSetKeyRequestCdm() {
    DCHECK(web_cdm_);
    EXPECT_CALL(*mock_cdm_, GetCdmContext())
        .WillRepeatedly(Return(&parc_cdm_context_));
    wmpi_->SetCdmInternal(web_cdm_.get());
    CycleThreads();
  }

  // Attaches `parc_cdm_context_` as a completed SetCdm would.
  void ParcAttachCdm() { ParcAttachCdm(&parc_cdm_context_); }
  void ParcAttachCdm(media::CdmContext* cdm_context) {
    wmpi_->pending_cdm_context_ref_ =
        std::make_unique<ParcCdmContextRef>(cdm_context);
    wmpi_->OnCdmAttached(true);
  }
#endif  // BUILDFLAG(IS_MAC)

  void OnVideoNaturalSizeChange(const gfx::Size& size) {
    wmpi_->OnVideoNaturalSizeChange(size);
  }

  void OnVideoConfigChange(const media::VideoDecoderConfig& config) {
    wmpi_->OnVideoConfigChange(config);
  }

#if BUILDFLAG(IS_MAC)
  // Parc: reports a late SourceBuffer's streams to a paused player at
  // HAVE_ENOUGH and expects readyState to drop to HAVE_METADATA without the
  // pipeline restarting (no suspend and resume) to play them.
  void ParcAddStreamsWithoutRestart(
      const media::PipelineMetadata& added,
      const std::vector<media::ChunkDemuxer::ParcAddedTrack>& tracks) {
    ASSERT_EQ(wmpi_->GetReadyState(),
              WebMediaPlayer::kReadyStateHaveEnoughData);
    ASSERT_TRUE(wmpi_->Paused());
    EXPECT_CALL(client_, ReadyStateChanged());
    wmpi_->ParcOnSourceBufferStreamsAdded(added, tracks);
    EXPECT_EQ(wmpi_->GetReadyState(), WebMediaPlayer::kReadyStateHaveMetadata);
    EXPECT_FALSE(wmpi_->pending_suspend_resume_cycle_);
    testing::Mock::VerifyAndClearExpectations(&client_);
    EXPECT_CALL(client_, ReadyStateChanged()).Times(AnyNumber());
    CycleThreads();
    EXPECT_FALSE(IsSuspended());
    EXPECT_FALSE(wmpi_->pending_suspend_resume_cycle_);
    EXPECT_TRUE(wmpi_->Paused());
  }

  // Parc: as ParcAddStreamsWithoutRestart(), but the pipeline restarts into
  // a renderer made with every stream, whose buffering raises readyState
  // again; the player stays paused and isn't suspended.
  void ParcAddStreamsAndWaitForRestart(
      const media::PipelineMetadata& added,
      const std::vector<media::ChunkDemuxer::ParcAddedTrack>& tracks) {
    ASSERT_EQ(wmpi_->GetReadyState(),
              WebMediaPlayer::kReadyStateHaveEnoughData);
    ASSERT_TRUE(wmpi_->Paused());
    EXPECT_CALL(client_, ReadyStateChanged());
    wmpi_->ParcOnSourceBufferStreamsAdded(added, tracks);
    EXPECT_EQ(wmpi_->GetReadyState(), WebMediaPlayer::kReadyStateHaveMetadata);
    EXPECT_TRUE(wmpi_->pending_suspend_resume_cycle_);
    testing::Mock::VerifyAndClearExpectations(&client_);

    while (wmpi_->GetReadyState() <
           WebMediaPlayer::kReadyStateHaveEnoughData) {
      base::RunLoop loop;
      EXPECT_CALL(client_, ReadyStateChanged())
          .WillRepeatedly(RunClosure(loop.QuitClosure()));
      loop.Run();
      testing::Mock::VerifyAndClearExpectations(&client_);
    }
    EXPECT_CALL(client_, ReadyStateChanged()).Times(AnyNumber());
    CycleThreads();
    EXPECT_FALSE(IsSuspended());
    EXPECT_TRUE(wmpi_->Paused());
  }

  bool ParcAwaitsAddedStreamsRenderer() const {
    return wmpi_->parc_->awaits_added_streams_renderer_;
  }

  // Parc: a FairPlay CDM being set, as SetCdmInternal() leaves it.
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
#endif  // BUILDFLAG(IS_MAC)

  WebMediaPlayerImpl::PlayState ComputePlayState() {
    return wmpi_->UpdatePlayState_ComputePlayState(false, true, false, false,
                                                   false);
  }

  WebMediaPlayerImpl::PlayState ComputePlayState_FrameHidden() {
    return wmpi_->UpdatePlayState_ComputePlayState(false, true, false, true,
                                                   false);
  }

  WebMediaPlayerImpl::PlayState ComputePlayState_Suspended() {
    return wmpi_->UpdatePlayState_ComputePlayState(false, true, true, false,
                                                   false);
  }

  WebMediaPlayerImpl::PlayState ComputePlayState_Flinging() {
    return wmpi_->UpdatePlayState_ComputePlayState(true, true, false, false,
                                                   false);
  }

  WebMediaPlayerImpl::PlayState ComputePlayState_BackgroundedStreaming() {
    return wmpi_->UpdatePlayState_ComputePlayState(false, false, false, true,
                                                   false);
  }

  WebMediaPlayerImpl::PlayState ComputePlayState_FrameHiddenPictureInPicture() {
    return wmpi_->UpdatePlayState_ComputePlayState(false, true, false, true,
                                                   true);
  }

  bool IsSuspended() { return wmpi_->pipeline_controller_->IsSuspended(); }

  bool IsPipelineStable() { return wmpi_->pipeline_controller_->IsStable(); }

  bool IsPipelineSuspended() {
    return wmpi_->pipeline_controller_->IsPipelineSuspended();
  }

  // Freezes the page's task queues, as the back/forward cache does. Only a
  // hidden page is frozen.
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

  // As SwitchToRemoteRenderer() leaves the player, without restarting the
  // test's pipeline.
  void SetRemoteRenderingWithoutRestart() {
    wmpi_->ParcSetRemoteRendering(true);
    wmpi_->disable_pipeline_auto_suspend_ = true;
  }

#if BUILDFLAG(ENABLE_HLS_DEMUXER)
  // The provider GetHlsDataSourceProvider() makes, used on this thread.
  std::unique_ptr<media::HlsDataSourceProviderImpl> CreateHlsProvider() {
    return std::make_unique<media::HlsDataSourceProviderImpl>(
        wmpi_->CreateHlsDataSourceFactory());
  }

  // Reads https://example.com/segment.ts through `provider`; `client` is its
  // load's once it starts.
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

  void AddBufferedRanges() {
    wmpi_->buffered_data_source_host_->AddBufferedByteRange(0, 1);
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

  bool IsBackgroundVideoPlaybackAllowed() const {
    return wmpi_->allow_background_video_playback_;
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

    // Clear the mock so it doesn't have a stale QuitClosure.
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

    // Clear the mock so it doesn't have a stale QuitClosure.
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

  void ScheduleIdlePauseTimer() { wmpi_->ScheduleIdlePauseTimer(); }
  void FireIdlePauseTimer() { wmpi_->background_pause_timer_.FireNow(); }

  bool IsIdlePauseTimerRunning() {
    return wmpi_->background_pause_timer_.IsRunning();
  }

  void SetSuspendState(bool is_suspended) {
    wmpi_->SetSuspendState(is_suspended);
  }

  void SetLoadType(WebMediaPlayer::LoadType load_type) {
    wmpi_->load_type_ = load_type;
  }

  bool IsVideoTrackDisabled() const { return wmpi_->video_track_disabled_; }

  bool IsPageHidden() const { return wmpi_->IsPageHidden(); }

  bool IsDisableVideoTrackPending() const {
    return !wmpi_->is_background_status_change_cancelled_;
  }

  gfx::Size GetNaturalSize() const {
    return wmpi_->pipeline_metadata_.natural_size;
  }

  bool ShouldCancelUponDefer() const {
    auto* ds = wmpi_->demuxer_manager_->GetDataSourceForTesting();
    CHECK_NE(ds, nullptr);
    // TODO(crbug.com/40243452): Can we add |cancel_on_defer_for_testing| to
    // CrossOriginDataSource? We can't do a |GetAsMultiBufferDataSource| since
    // MBDS is in blink, and we can't import that into media.
    return static_cast<const MultiBufferDataSource*>(ds)
        ->cancel_on_defer_for_testing();
  }

  MultiBufferDataSource* GetMultiBufferDataSource() {
    auto* ds = wmpi_->demuxer_manager_->GetDataSourceForTesting();
    CHECK_NE(ds, nullptr);
    // See comment in |ShouldCancelUponDefer|.
    return static_cast<MultiBufferDataSource*>(ds);
  }

  bool IsDataSourceMarkedAsPlaying() const {
    auto* ds = wmpi_->demuxer_manager_->GetDataSourceForTesting();
    CHECK_NE(ds, nullptr);
    // See comment in |ShouldCancelUponDefer|.
    return static_cast<const MultiBufferDataSource*>(ds)->media_has_played();
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

    // The URL is used by MultiBufferDataSource to determine if it should assume
    // the resource is fully buffered locally. We can use a fake one here since
    // we're injecting the response artificially. It's value is unknown to the
    // underlying demuxer.
    const KURL kTestURL(
        String::FromUtf8(std::string(is_streaming ? "http" : "file") +
                         "://example.com/sample.webm"));

    // This block sets up a fetch context which ultimately provides us a pointer
    // to the WebAssociatedURLLoaderClient handed out by the DataSource after it
    // requests loading of a resource. We then use that client as if we are the
    // network stack and "serve" an in memory file to the DataSource.
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
                /*is_cache_disabled=*/false);

    base::RunLoop().RunUntilIdle();
    if (!should_have_client) {
      return;
    }
    EXPECT_TRUE(client);

    // Load a real media file into memory.
    scoped_refptr<media::DecoderBuffer> data =
        media::ReadTestDataFile(data_file);

    // "Serve" the file to the DataSource. Note: We respond with 200 okay, which
    // will prevent range requests or partial responses from being used. For
    // streaming responses, we'll pretend we don't know the content length.
    WebURLResponse response(kTestURL);
    response.SetHttpHeaderField(
        WebString("Content-Length"),
        WebString::FromUtf8(is_streaming ? "-1"
                                         : base::NumberToString(data->size())));
    response.SetExpectedContentLength(is_streaming ? -1 : data->size());
    response.SetHttpStatusCode(200);
    client->DidReceiveResponse(response);

    // Copy over the file data.
    client->DidReceiveData(base::as_chars(base::span(*data)));

    // If we're pretending to be a streaming resource, don't complete the load;
    // otherwise the DataSource will not be marked as streaming.
    if (!is_streaming)
      client->DidFinishLoading();
  }

  // This runs until we reach the |ready_state_|. Attempting to wait for ready
  // states < kReadyStateHaveCurrentData in non-startup-suspend test cases is
  // unreliable due to asynchronous execution of tasks on the
  // base::test:TaskEnvironment.
  void LoadAndWaitForReadyState(std::string data_file,
                                WebMediaPlayer::ReadyState ready_state) {
    Load(data_file);
    while (wmpi_->GetReadyState() < ready_state) {
      base::RunLoop loop;
      EXPECT_CALL(client_, ReadyStateChanged())
          .WillRepeatedly(RunClosure(loop.QuitClosure()));
      loop.Run();

      // Clear the mock so it doesn't have a stale QuitClosure.
      testing::Mock::VerifyAndClearExpectations(&client_);
    }

    // Verify we made it through pipeline startup.
    EXPECT_TRUE(HasDataSource());
    EXPECT_TRUE(wmpi_->demuxer_manager_->HasDemuxer());

    if (ready_state > WebMediaPlayer::kReadyStateHaveCurrentData)
      EXPECT_FALSE(wmpi_->seeking_);
  }

  void LoadAndWaitForCurrentData(std::string data_file) {
    LoadAndWaitForReadyState(data_file,
                             WebMediaPlayer::kReadyStateHaveCurrentData);
  }

  void WaitForReadyStateHaveCurrentData() {
    // This runs until we reach the have current data state. Attempting to wait
    // for states < kReadyStateHaveCurrentData is unreliable due to asynchronous
    // execution of tasks on the base::test:TaskEnvironment.
    while (wmpi_->GetReadyState() <
           WebMediaPlayer::kReadyStateHaveCurrentData) {
      base::RunLoop loop;
      EXPECT_CALL(client_, ReadyStateChanged())
          .WillRepeatedly(RunClosure(loop.QuitClosure()));
      loop.Run();

      // Clear the mock so it doesn't have a stale QuitClosure.
      testing::Mock::VerifyAndClearExpectations(&client_);
    }
  }

  void CycleThreads() {
    // Ensure any tasks waiting to be posted to the media thread are posted.
    base::RunLoop().RunUntilIdle();

    // Flush all media tasks.
    media_thread_.FlushForTesting();

    // Cycle anything that was posted back from the media thread.
    base::RunLoop().RunUntilIdle();
  }

  void OnProgress() { wmpi_->OnProgress(); }

  // Parc: a paused audio Media Source element at HAVE_METADATA over a
  // ChunkDemuxer the test appends to.
  void StartParcMediaSource(bool safari_identity) {
    ON_CALL(client_, PresentsParcSafariIdentity())
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
    SetMetadata(/*has_audio=*/true, /*has_video=*/false);
    SetPaused(true);
  }

  // Appends the part of a 2.7 s audio file in [start, end) to SourceBuffer
  // |id|, as an append reports progress.
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
    // Must use a supported key system on a secure context.
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
  // Parc: a Media Source element of a Safari-identity page gets FairPlay
  // MediaKeys (setMediaKeys).
  void ParcSetFairPlayCdmOnSafariMediaSource() {
    DCHECK(web_cdm_);
    ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
    wmpi_->load_type_ = WebMediaPlayer::kLoadTypeMediaSource;
    EXPECT_CALL(*mock_cdm_, GetCdmContext())
        .WillRepeatedly(Return(&parc_fairplay_cdm_context_));
    wmpi_->SetCdmInternal(web_cdm_.get());
    CycleThreads();
  }

  // Parc: an init segment's FairPlay sinf for a protected track.
  void ParcAppendSinf() {
    wmpi_->OnEncryptedMediaInitData(media::EmeInitDataType::SINF,
                                    std::vector<uint8_t>{1, 2, 3});
    CycleThreads();
  }
#endif  // BUILDFLAG(IS_MAC)

  media::MemoryDumpProviderProxy* GetMainThreadMemDumper() {
    return wmpi_->main_thread_mem_dumper_.get();
  }
  media::MemoryDumpProviderProxy* GetMediaThreadMemDumper() {
    return wmpi_->media_thread_mem_dumper_.get();
  }

  test::TaskEnvironment task_environment_;

  // "Media" thread. This is necessary because WMPI destruction waits on a
  // WaitableEvent.
  base::Thread media_thread_;

  // Blink state.
  frame_test_helpers::WebViewHelper web_view_helper_;

  scoped_refptr<viz::TestContextProvider> context_provider_;
  raw_ptr<NiceMock<MockVideoFrameCompositor>,
          UnprotectedInRelease | DanglingUntriaged>
      compositor_;

  scoped_refptr<NiceMock<media::MockAudioRendererSink>> audio_sink_;
  MockResourceFetchContext mock_resource_fetch_context_;
  std::unique_ptr<UrlIndex> url_index_;

  // Audio hardware configuration.
  media::AudioParameters audio_parameters_;

  bool is_background_suspend_enabled_ = false;
  bool is_background_video_playback_enabled_ = true;

  // The client interface used by |wmpi_|.
  NiceMock<MockWebMediaPlayerClient> client_;
  MockWebMediaPlayerEncryptedMediaClient encrypted_client_;

  std::unique_ptr<media::KeySystemsImpl> key_systems_;

  // Used to create the media::MockCdm to test encrypted playback.
  scoped_refptr<media::MockCdm> mock_cdm_ =
      base::MakeRefCounted<media::MockCdm>();
  media::MockCdmFactory mock_cdm_factory_{mock_cdm_};
  std::unique_ptr<WebContentDecryptionModule> web_cdm_;
  media::MockCdmContext mock_cdm_context_;
#if BUILDFLAG(IS_MAC)
  ParcFairPlayCdmContext parc_fairplay_cdm_context_;
  ParcKeyRequestCdmContext parc_cdm_context_;
#endif  // BUILDFLAG(IS_MAC)

  viz::FrameSinkId frame_sink_id_ = viz::FrameSinkId(1, 1);
  viz::LocalSurfaceId local_surface_id_ = viz::LocalSurfaceId(
      11,
      base::UnguessableToken::CreateForTesting(0x111111, 0));
  viz::SurfaceId surface_id_ =
      viz::SurfaceId(frame_sink_id_, local_surface_id_);

  NiceMock<MockWebMediaPlayerDelegate> delegate_;
  // Parc: the delegate and media cache of the frame ParcMoveToFrame() moves
  // |wmpi_| to.
  NiceMock<MockWebMediaPlayerDelegate> moved_to_delegate_;
  StrictMock<MockResourceFetchContext> moved_to_fetch_context_;
  std::unique_ptr<UrlIndex> moved_to_url_index_;
  frame_test_helpers::WebViewHelper moved_to_view_helper_;

  // Use NiceMock since most tests do not care about this.
  std::unique_ptr<NiceMock<MockSurfaceLayerBridge>> surface_layer_bridge_;
  raw_ptr<NiceMock<MockSurfaceLayerBridge>,
          UnprotectedInRelease | DanglingUntriaged>
      surface_layer_bridge_ptr_ = nullptr;

  // Only valid once set by InitializeWebMediaPlayerImpl(), this is for
  // verifying a subset of potential media logs.
  raw_ptr<NiceMock<media::MockMediaLog>,
          UnprotectedInRelease | DanglingUntriaged>
      media_log_ = nullptr;

  // Raw pointer of the media::RendererFactorySelector owned by |wmpi_|.
  raw_ptr<media::RendererFactorySelector,
          UnprotectedInRelease | DanglingUntriaged>
      renderer_factory_selector_ = nullptr;

  // default decoder factory for WMPI
  std::unique_ptr<media::DecoderFactory> decoder_factory_;

  // The WebMediaPlayerImpl's media observer.
  NiceMock<MockMediaObserver> mock_observer_;

  // Parc: see StartParcMediaSource(); outlives |wmpi_|, which points at it.
  NiceMock<media::MockMediaLog> parc_media_log_;
  NiceMock<media::MockDemuxerHost> parc_demuxer_host_;
  std::unique_ptr<media::ChunkDemuxer> parc_demuxer_;

  // The WebMediaPlayerImpl instance under test.
  std::unique_ptr<WebMediaPlayerImpl> wmpi_;

  std::unique_ptr<base::trace_event::MemoryDumpManager> memory_dump_manager_;
};

TEST_F(ParcWebMediaPlayerImplTest, ParcSafariRefusesUndeclaredAV1WithoutHardware) {
  InitializeWebMediaPlayerImpl();
  av1_command_line_.GetProcessCommandLine()->AppendSwitchASCII(
      media::kParcAV1HardwareDecoder, "0");
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  media::PipelineMetadata metadata;
  metadata.has_video = true;
  metadata.video_decoder_config = TestVideoConfig::Normal(media::VideoCodec::kAV1);
  EXPECT_CALL(client_, NetworkStateChanged());
  OnMetadata(metadata);
  EXPECT_EQ(wmpi_->GetNetworkState(), WebMediaPlayer::kNetworkStateFormatError);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcChromeTakesUndeclaredAV1WithoutHardware) {
  InitializeWebMediaPlayerImpl();
  av1_command_line_.GetProcessCommandLine()->AppendSwitchASCII(
      media::kParcAV1HardwareDecoder, "0");
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(false));
  media::PipelineMetadata metadata;
  metadata.has_video = true;
  metadata.video_decoder_config = TestVideoConfig::Normal(media::VideoCodec::kAV1);
  OnMetadata(metadata);
  EXPECT_NE(wmpi_->GetNetworkState(), WebMediaPlayer::kNetworkStateFormatError);
}


// Verify LoadAndWaitForCurrentData() functions without issue.

// Verify LoadAndWaitForCurrentData() functions without issue.

// Verify that preload=metadata suspend works properly.

// Verify that Play() before kReadyStateHaveEnough doesn't increase buffer size.

// Verify that preload=metadata suspend works properly for streaming sources.

// Verify that lazy load for preload=metadata works properly.

// Verify that lazy load is skipped when rVFC has been requested.

// Verify that preload=metadata suspend video w/ poster uses zero video memory.

// Verify that preload=metadata suspend is aborted if we know the element will
// play as soon as we reach kReadyStateHaveFutureData.


// Ensure memory reporting is not running after an error.


// Parc: playing backward (only Safari-identity pages do), the player ends at
// the start, as WebKit's MediaPlayerPrivateAVFoundation::didEnd; the element
// hears it, and the time stays the player's, not the duration.
TEST_F(ParcWebMediaPlayerImplTest, ParcBackwardEndKeepsTheTime) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  wmpi_->SetRate(-1.0);

  EXPECT_CALL(client_, TimeChanged());
  OnEnded();
  EXPECT_FALSE(wmpi_->IsEnded());
  EXPECT_EQ(0, wmpi_->CurrentTime());
}

// The element reads CurrentTime() for currentTime and timeupdate; Now Playing
// must use the same renderer clock, including when a receiver cannot reverse.
class ParcWebMediaPlayerImplReverseRouteTest
    : public ParcWebMediaPlayerImplTest,
      public testing::WithParamInterface<media::RendererType> {};

TEST_P(ParcWebMediaPlayerImplReverseRouteTest, FrozenRouteReportsItsActualRate) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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

  EXPECT_CALL(client_, DidPlayerMediaPositionStateChange(
                           0.0, kAudioOnlyTestFileDuration, base::Seconds(1),
                           /*end_of_media=*/false));
  wmpi_->OnTimeUpdate();
  EXPECT_EQ(1.0, wmpi_->CurrentTime());
  testing::Mock::VerifyAndClearExpectations(&client_);
  EXPECT_CALL(client_, DidPlayerMediaPositionStateChange(_, _, _, _)).Times(0);
  CycleThreads();
  wmpi_->OnTimeUpdate();
  EXPECT_EQ(1.0, wmpi_->CurrentTime());
  testing::Mock::VerifyAndClearExpectations(&client_);

  // A new receiver position (including a backward seek) reaches both clocks.
  time->store(500000);
  EXPECT_CALL(client_, DidPlayerMediaPositionStateChange(
                           0.0, kAudioOnlyTestFileDuration, base::Seconds(0.5),
                           /*end_of_media=*/false));
  wmpi_->OnTimeUpdate();
  EXPECT_EQ(0.5, wmpi_->CurrentTime());
  testing::Mock::VerifyAndClearExpectations(&client_);

  // Forward playback resumes on the same route.
  EXPECT_CALL(*renderer, SetPlaybackRate(1.0));
  wmpi_->SetRate(1.0);
  CycleThreads();
  EXPECT_CALL(client_, DidPlayerMediaPositionStateChange(
                           1.0, kAudioOnlyTestFileDuration, base::Seconds(0.5),
                           /*end_of_media=*/false));
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
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  wmpi_->SetRate(-1.0);
  Play();
  ParcPlayChromiumRenderer();
  EXPECT_CALL(client_, DidPlayerMediaPositionStateChange(
                           -1.0, kAudioOnlyTestFileDuration, base::TimeDelta(),
                           /*end_of_media=*/false));
  wmpi_->OnTimeUpdate();
  testing::Mock::VerifyAndClearExpectations(&client_);
  ParcPlayNativeHls();
  // A rate change must still be reported by native HLS.
  wmpi_->SetRate(-2.0);
  EXPECT_CALL(client_, DidPlayerMediaPositionStateChange(
                           -2.0, kAudioOnlyTestFileDuration, base::TimeDelta(),
                           /*end_of_media=*/false));
  wmpi_->OnTimeUpdate();
}
#endif


// On a Safari-identity page the end reaches the element while paused too, as
// WebKit's player reports it (HTMLMediaElement::handlePlaybackPositionChanged).
TEST_F(ParcWebMediaPlayerImplTest, SafariIdentity_EndedWhilePausedTellsClient) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  ASSERT_TRUE(IsPaused());
  EXPECT_CALL(client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(client_, TimeChanged());
  OnEnded();
  EXPECT_TRUE(wmpi_->IsEnded());
}

TEST_F(ParcWebMediaPlayerImplTest, EndedWhilePausedDoesNotTellClient) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  ASSERT_TRUE(IsPaused());
  EXPECT_CALL(client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(false));
  EXPECT_CALL(client_, TimeChanged()).Times(0);
  OnEnded();
  EXPECT_TRUE(wmpi_->IsEnded());
}


// It's possible for current time to be infinite if the page seeks to
// |media::kInfiniteDuration| (2**64 - 1) when duration is infinite.

// A src= player whose first 10% (1s) is buffered, at HAVE_ENOUGH_DATA.
class ParcWebMediaPlayerImplUrlSeekTest : public ParcWebMediaPlayerImplTest {
 protected:
  void SetUpPlayer(bool safari_identity,
                   bool has_video,
                   bool has_first_frame = true) {
    InitializeWebMediaPlayerImpl();
    ON_CALL(client_, PresentsParcSafariIdentity())
        .WillByDefault(Return(safari_identity));
    SetMetadata(/*has_audio=*/true, has_video);
    SetDuration(base::Seconds(10));
    SetBufferedBytes(100, 1000);
    SetReadyState(WebMediaPlayer::kReadyStateHaveEnoughData);
    if (has_first_frame) {
      SetHasFirstFrame();
    }
    testing::Mock::VerifyAndClearExpectations(&client_);
  }
};

// Safari keeps readyState through a seek into buffered media and ends it at
// the target's first frame: no waiting, canplay, playing or canplaythrough.
TEST_F(ParcWebMediaPlayerImplUrlSeekTest,
       SafariSeekIntoBufferedKeepsReadyState) {
  SetUpPlayer(/*safari_identity=*/true, /*has_video=*/true);

  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
  EXPECT_TRUE(wmpi_->Seeking());

  // The pipeline's seek alone doesn't end the element's (no TimeChanged()):
  // the target's frame isn't up.
  OnPipelineSeeked(/*time_updated=*/true);
  CycleThreads();
  EXPECT_FALSE(wmpi_->Seeking());
  testing::Mock::VerifyAndClearExpectations(&client_);

  // Its first frame does, before the renderer reports HAVE_ENOUGH.
  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(client_, TimeChanged());
  PaintFrame();
  CycleThreads();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
  testing::Mock::VerifyAndClearExpectations(&client_);

  // Once.
  EXPECT_CALL(client_, TimeChanged()).Times(0);
  PaintFrame();
  CycleThreads();
}

TEST_F(ParcWebMediaPlayerImplUrlSeekTest, SafariAudioSeekEndsWithPipelineSeek) {
  SetUpPlayer(/*safari_identity=*/true, /*has_video=*/false);

  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  testing::Mock::VerifyAndClearExpectations(&client_);

  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(client_, TimeChanged());
  OnPipelineSeeked(/*time_updated=*/true);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
}

// A frame of an earlier seek doesn't end a later one.
TEST_F(ParcWebMediaPlayerImplUrlSeekTest, SafariSeekIgnoresEarlierSeeksFrame) {
  SetUpPlayer(/*safari_identity=*/true, /*has_video=*/true);

  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  OnPipelineSeeked(/*time_updated=*/true);
  CycleThreads();
  wmpi_->Seek(0.7);
  // The first seek's frame reaches the main thread only after the second
  // seek's pipeline part is done.
  PaintFrame();
  media_thread_.FlushForTesting();
  OnPipelineSeeked(/*time_updated=*/true);
  CycleThreads();
  testing::Mock::VerifyAndClearExpectations(&client_);

  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(client_, TimeChanged());
  PaintFrame();
  CycleThreads();
}

// Before the first frame the compositor's callback is OnFirstFrame()'s, so a
// frame doesn't end the seek (the renderer's HAVE_ENOUGH does); readyState is
// still kept.
TEST_F(ParcWebMediaPlayerImplUrlSeekTest, SafariSeekBeforeFirstFrameWaits) {
  SetUpPlayer(/*safari_identity=*/true, /*has_video=*/true,
              /*has_first_frame=*/false);

  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  OnPipelineSeeked(/*time_updated=*/true);
  CycleThreads();
  PaintFrame();
  CycleThreads();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
  EXPECT_TRUE(ShouldNotifyTimeChanged());
}

TEST_F(ParcWebMediaPlayerImplUrlSeekTest,
       SafariSeekOutsideBufferedLowersReadyState) {
  SetUpPlayer(/*safari_identity=*/true, /*has_video=*/true);

  EXPECT_CALL(client_, ReadyStateChanged());
  EXPECT_CALL(client_, TimeChanged()).Times(0);
  wmpi_->Seek(5);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());
  OnPipelineSeeked(/*time_updated=*/true);
  PaintFrame();
  CycleThreads();
}

TEST_F(ParcWebMediaPlayerImplUrlSeekTest, ChromeSeekLowersReadyState) {
  SetUpPlayer(/*safari_identity=*/false, /*has_video=*/true);

  EXPECT_CALL(client_, ReadyStateChanged());
  EXPECT_CALL(client_, TimeChanged()).Times(0);
  wmpi_->Seek(0.5);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());
  OnPipelineSeeked(/*time_updated=*/true);
  PaintFrame();
  CycleThreads();
}

#if BUILDFLAG(IS_MAC)
// Parc: a clear MP3 served over HTTPS, paused at 2s at HAVE_ENOUGH_DATA in
// Chromium's pipeline (NATIVE_HLS.md, AirPlay).
class ParcWebMediaPlayerImplFileAirPlayTest : public ParcWebMediaPlayerImplTest {
 protected:
  void LoadFile(bool safari_identity) {
    InitializeWebMediaPlayerImpl();
    ON_CALL(client_, PresentsParcSafariIdentity())
        .WillByDefault(Return(safari_identity));
    wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
    LoadAndWaitForReadyState("bear-audio-10s-CBR-has-TOC.mp3",
                             WebMediaPlayer::kReadyStateHaveEnoughData);
    ParcServeOverHttps();
    EXPECT_CALL(client_, ReadyStateChanged()).Times(AnyNumber());
    EXPECT_CALL(client_, TimeChanged()).Times(AnyNumber());
    wmpi_->Seek(2);
    for (int i = 0; i < 100 && wmpi_->Seeking(); ++i) {
      CycleThreads();
    }
    ASSERT_FALSE(wmpi_->Seeking());
    testing::Mock::VerifyAndClearExpectations(&client_);
  }
  void SwitchLiveStream(std::optional<double> seek_during_switch);
};

// Parc: the file, paused at 2s, as a live stream played to a target; the
// native route AVFoundation can't open here sends it back to Chromium's
// pipeline on a new connection.
void ParcWebMediaPlayerImplFileAirPlayTest::SwitchLiveStream(
    std::optional<double> seek_during_switch) {
  LoadFile(/*safari_identity=*/true);
  const GURL file_url = LoadedUrl();
  ParcServeOverHttps();
  ParcMakeLive(file_url);
  wmpi_->ParcSetPlaybackTarget("context", /*should_play=*/true);
  ASSERT_TRUE(ParcSwitchingRoute());
  if (seek_during_switch) {
    // The element's seek completes.
    EXPECT_CALL(client_, TimeChanged()).Times(testing::AtLeast(1));
    wmpi_->Seek(*seek_during_switch);
  }
  for (int i = 0; i < 200 && ParcSwitchingRoute(); ++i) {
    CycleThreads();
  }
  ASSERT_FALSE(ParcSwitchingRoute());
  EXPECT_FALSE(ParcFileOnNativeRoute());
}

// Safari's AVPlayer plays the file, so it supports a target, as the native
// HLS player does; the element reports it at HAVE_METADATA.
TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, SafariFileSupportsTarget) {
  LoadFile(/*safari_identity=*/true);
  EXPECT_TRUE(wmpi_->ParcSupportsPlaybackTarget());
}

TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, ChromeFileKeepsItsPipeline) {
  LoadFile(/*safari_identity=*/false);
  EXPECT_FALSE(wmpi_->ParcSupportsPlaybackTarget());
  wmpi_->ParcSetPlaybackTarget("context", /*should_play=*/true);
  EXPECT_FALSE(ParcFileOnNativeRoute());
  EXPECT_FALSE(ParcSwitchingRoute());
  EXPECT_TRUE(HasDataSource());
}

// A target the element doesn't play to, or none, moves nothing.
TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, NotPlayingToTargetStays) {
  LoadFile(/*safari_identity=*/true);
  wmpi_->ParcSetPlaybackTarget("context", /*should_play=*/false);
  wmpi_->ParcSetPlaybackTarget("", /*should_play=*/true);
  EXPECT_FALSE(ParcFileOnNativeRoute());
  EXPECT_FALSE(ParcSwitchingRoute());
  EXPECT_FALSE(wmpi_->Seeking());
  EXPECT_TRUE(HasDataSource());
}

// A finite stream without byte ranges couldn't resume where the element is.
TEST_F(ParcWebMediaPlayerImplTest, ParcFiniteStreamDoesNotSupportTarget) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  // Over http; larger than the MultiBuffer block size, so the data source
  // initializes.
  Load("bear_192kHz.wav", LoadType::kStreaming);
  while (wmpi_->GetReadyState() < WebMediaPlayer::kReadyStateHaveMetadata) {
    base::RunLoop loop;
    EXPECT_CALL(client_, ReadyStateChanged())
        .WillRepeatedly(RunClosure(loop.QuitClosure()));
    loop.Run();
    testing::Mock::VerifyAndClearExpectations(&client_);
  }
  ASSERT_TRUE(IsStreaming());
  EXPECT_FALSE(wmpi_->ParcSupportsPlaybackTarget());
}

// Played to the target, the file moves to the native route: the element
// sees the same time, duration and readyState, and nothing the restarting
// pipeline reports, until the new route has seeked there; Chromium's
// pipeline, coming back, then reports its own, never lowered to
// HAVE_METADATA.
TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, SwitchHoldsWhatTheElementSees) {
  LoadFile(/*safari_identity=*/true);
  const double duration = wmpi_->Duration();
  const WebMediaPlayer::ReadyState ready_state = wmpi_->GetReadyState();

  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  EXPECT_CALL(client_, DurationChanged()).Times(0);
  EXPECT_CALL(client_, TimeChanged()).Times(0);
  wmpi_->ParcSetPlaybackTarget("context", /*should_play=*/true);
  EXPECT_TRUE(ParcFileOnNativeRoute());
  ASSERT_TRUE(ParcSwitchingRoute());
  EXPECT_FALSE(HasDataSource());
  ParcReportReadyState(WebMediaPlayer::kReadyStateHaveMetadata);
  ParcReportDurationChange();
  EXPECT_NEAR(wmpi_->CurrentTime(), 2, 0.05);
  EXPECT_EQ(wmpi_->Duration(), duration);
  EXPECT_EQ(wmpi_->GetReadyState(), ready_state);
  testing::Mock::VerifyAndClearExpectations(&client_);

  // Only a higher readyState than the held one is told at the seek's end.
  ParcReportReadyState(WebMediaPlayer::kReadyStateHaveMetadata);
  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  OnPipelineSeeked(/*time_updated=*/false);
  EXPECT_FALSE(ParcSwitchingRoute());
  EXPECT_EQ(wmpi_->GetReadyState(), ready_state);
  testing::Mock::VerifyAndClearExpectations(&client_);
  // The switch ends once: later states are the pipeline's own.
  EXPECT_CALL(client_, ReadyStateChanged());
  ParcReportReadyState(WebMediaPlayer::kReadyStateHaveCurrentData);
}

// A live stream's new connection starts its own timeline at 0; the element's
// time goes on from where it was, as Safari's single connection's does.
TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, LiveStreamKeepsItsTime) {
  SwitchLiveStream(/*seek_during_switch=*/std::nullopt);
  ASSERT_LT(PipelineTime(), base::Seconds(0.5));
  EXPECT_NEAR(wmpi_->CurrentTime(), 2, 0.05);
  ASSERT_FALSE(wmpi_->Buffered().empty());
  EXPECT_NEAR(wmpi_->Buffered()[0].start, 2, 0.05);
}

// A seek while it reconnects lands where the page asked, the new
// connection's start taking that time.
TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, LiveStreamSeekDuringSwitch) {
  SwitchLiveStream(/*seek_during_switch=*/5);
  ASSERT_LT(PipelineTime(), base::Seconds(0.5));
  EXPECT_FALSE(wmpi_->Seeking());
  EXPECT_NEAR(wmpi_->CurrentTime(), 5, 0.05);
}

// The element's audio and video choices go to the native route's player by
// position among Chromium's audio and video tracks, every enabled audio
// track (Safari's AVPlayer plays them all) and the selected video track.
TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, TrackChoicesByPosition) {
  LoadFile(/*safari_identity=*/true);
  // The MP3's own audio track is "1".
  media::MediaTracks tracks;
  tracks
      .AddAudioTrack(TestAudioConfig::Normal(), /*enabled=*/false, 2,
                     media::MediaTrack::Kind("main"),
                     media::MediaTrack::Label(""),
                     media::MediaTrack::Language("fr"))
      ->set_id(media::MediaTrack::Id("2"));
  tracks
      .AddVideoTrack(TestVideoConfig::Normal(), /*enabled=*/true, 3,
                     media::MediaTrack::Kind("main"),
                     media::MediaTrack::Label(""),
                     media::MediaTrack::Language(""))
      ->set_id(media::MediaTrack::Id("3"));
  tracks
      .AddVideoTrack(TestVideoConfig::Normal(), /*enabled=*/false, 4,
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

// On the native route the element takes AVPlayer's readyState from the
// seek's end, as for native HLS; its HAVE_METADATA lowers nothing.
TEST_F(ParcWebMediaPlayerImplFileAirPlayTest, NativeRouteTakesAVPlayerState) {
  LoadFile(/*safari_identity=*/true);
  wmpi_->ParcSetPlaybackTarget("context", /*should_play=*/true);
  ASSERT_TRUE(ParcSwitchingRoute());
  ParcPlayNativeHls();

  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  OnPipelineSeeked(/*time_updated=*/false);
  EXPECT_FALSE(ParcSwitchingRoute());
  EXPECT_EQ(wmpi_->GetReadyState(), WebMediaPlayer::kReadyStateHaveEnoughData);
  testing::Mock::VerifyAndClearExpectations(&client_);

  EXPECT_CALL(client_, ReadyStateChanged());
  ParcReportNativeReadyState(media::ParcNativeHlsReadyState::kHaveCurrentData);
  EXPECT_EQ(wmpi_->GetReadyState(), WebMediaPlayer::kReadyStateHaveCurrentData);
}
#endif  // BUILDFLAG(IS_MAC)


#if BUILDFLAG(IS_MAC)
// Parc: setMediaKeys(null) on a Safari-identity page detaches its FairPlay
// MediaKeys, as WebKit's HTMLMediaElement::setMediaKeys does
// (cdmInstanceDetached): a protected track's init data then finds no CDM, so
// the element hears `encrypted` and waits for a key, as WebKit's renderer
// without one answers setInitData, until the same MediaKeys come back.
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

// Parc: a page without Safari's identity still can't clear its MediaKeys,
// FairPlay's included, as Chromium refuses.
TEST_F(ParcWebMediaPlayerImplTest, ParcChromeMediaKeysNullStillRefused) {
  InitializeWebMediaPlayerImpl();
  CreateCdm();
  ParcSetFairPlayCdmOnSafariMediaSource();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(false));

  Persistent<ParcCdmResult> result = MakeGarbageCollected<ParcCdmResult>();
  wmpi_->SetContentDecryptionModule(nullptr, result->Result());
  CycleThreads();
  EXPECT_TRUE(result->failed);
}
#endif  // BUILDFLAG(IS_MAC)

#if BUILDFLAG(IS_MAC)
// WebKit's native HLS player stops waiting only once a session has a request
// for the key it waits on, not for another key becoming usable.
TEST_F(ParcWebMediaPlayerImplTest, ParcStalledKeyWaitEndsOnlyForThatKey) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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

// The native HLS player stalls only for a request made while it held no CDM,
// so the element waits even when a CDM attached here since, as WebKit's
// player sets waiting at the request; a session that already has a request
// for the key then ends the wait, as WebKit's setMediaKeys does
// (attemptToResumePlaybackIfNecessary). One for a key no session asked for
// stays waiting.
TEST_F(ParcWebMediaPlayerImplTest, ParcStallAfterItsKeyArrivedWaitsThenResumes) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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

// WebKit's setMediaKeys ends the wait when a session already asked for the
// key (attemptToResumePlaybackIfNecessary).
TEST_F(ParcWebMediaPlayerImplTest, ParcStalledKeyWaitEndsOnAttachWithItsKey) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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

// A key event while the stall's own check is on its way asks again, and only
// that later answer decides.
TEST_F(ParcWebMediaPlayerImplTest, ParcKeyEventDuringStallCheckDecides) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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

// WebKit's cdmInstanceDetached: a stall whose key check was on its way to
// MediaKeys the page then clears has no CDM, so it waits, whatever that
// check answers.
TEST_F(ParcWebMediaPlayerImplTest, ParcStallCheckingDetachedCdmWaits) {
  InitializeWebMediaPlayerImpl();
  CreateCdm();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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

// src= decryptor stalls with an attached CDM are not waiting-for-key.
TEST_F(ParcWebMediaPlayerImplTest, ParcSrcAttachedCdmDoesNotWait) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  ParcAttachCdm();
  EXPECT_CALL(encrypted_client_, DidBlockPlaybackWaitingForKey()).Times(0);
  EXPECT_CALL(encrypted_client_, DidResumePlaybackBlockedForKey()).Times(0);
  OnWaiting(media::WaitingReason::kNoDecryptionKey);
  parc_cdm_context_.NotifyStatusesChanged();
  base::RunLoop().RunUntilIdle();
}

TEST_F(ParcWebMediaPlayerImplTest, ParcMediaSourceWaitsForEverySourceBuffer) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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

// Parc: Safari's Media Source reports a SAMPLE-AES TS stream's "mpts" init
// data as it reports sinf (SourceBufferPrivateAVFObjC): `encrypted` with it
// and a wait until a session has a request for it; a Chrome page's element
// hears it as before.
TEST_F(ParcWebMediaPlayerImplTest, ParcMediaSourceReportsMptsInitData) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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

  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(false));
  EXPECT_CALL(encrypted_client_, Encrypted(media::EmeInitDataType::MPTS, _));
  OnEncryptedMediaInitData(media::EmeInitDataType::MPTS, mpts);
}

TEST_F(ParcWebMediaPlayerImplTest, ParcRemovedSourceDoesNotHoldWaitOrAcceptOldCheck) {
  InitializeWebMediaPlayerImpl();
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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
#endif  // BUILDFLAG(IS_MAC)

#if BUILDFLAG(IS_WIN)

// Tests that for encrypted media, when a CDM is attached that requires
// MediaFoundationRenderer, the pipeline will fallback to create a new Renderer
// for RendererType::kMediaFoundation.

// Tests that when PIPELINE_ERROR_HARDWARE_CONTEXT_RESET happens, the pipeline
// will suspend/resume the pipeline, which will create a new Renderer.

// Same as above, but tests that when PIPELINE_ERROR_HARDWARE_CONTEXT_RESET
// happens twice, the pipeline will suspend/resume the pipeline only for the
// first one, which will create a new Renderer. For the second one, we will
// stop and fail with PIPELINE_ERROR_HARDWARE_CONTEXT_RESET error code. See
// https://crbug.com/40272221 for the context.


// Test the case where a hardware context reset happens first, the video is
// playing, and the video is not recovered by a subsequent error after resuming
// from the hardware context reset. Steps: a) A hardware context reset happens
// -> b) Playing video -> c) A pipeline decode error happens -> d) The video is
// not recovered and terminated.

// Test the case where a hardware context reset happens first, the video is
// playing, and the video is recovered without any subsequent errors after
// resuming from the hardware context reset. Steps: a) A hardware context reset
// happens -> b) Playing video -> c) The video is recovered and terminated.

// Test the case where a hardware context reset happens first, the video is not
// recovered by a subsequent hardware context reset after resuming from the
// hardware context reset while the video is paused, and then terminated without
// any additional error. Steps: a) A hardware context reset happens
// -> b) Paused video -> c) Another hardware context reset happens (we can't
// conclude whether it is failed to recover or not since the video is paused) ->
// d) The video is not recovered but terminated.

// Test the case where a hardware context reset happens first, the video is not
// recovered by a subsequent hardware context reset after resuming from the
// hardware context reset while the video is paused, and then the video is
// playing (only 1 ms advanced) but another hardware context reset happens.
// Steps: a) A hardware context reset happens -> b) Paused video -> c) Another
// hardware context reset happens (we can't conclude whether it is failed to
// recover or not since the video is paused) -> d) The video is playing (only 1
// ms advanced) -> e) Another hardware context reset happens -> f) The video is
// not recovered but terminated.
#endif  // BUILDFLAG(IS_WIN)


#if BUILDFLAG(IS_MAC)
// Parc: a SourceBuffer added after the renderer was made enables a stream of a
// new type (ChunkDemuxer::ParcAllowSourceBuffersAfterInit()). readyState drops
// to HAVE_METADATA (WebKit's MediaSource::sourceBufferActiveTrackFlagChanged),
// and the stream joins RendererImpl through the pipeline's track change, as
// WebKit adds a renderer to its synchronizer, instead of a restart into a new
// renderer that decodes again from a keyframe.
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

// Parc: a second audio track, which WebKit mixes with the first, joins
// RendererImpl, which mixes it too (RendererImpl::ParcSyncMixedAudio()).
TEST_F(ParcWebMediaPlayerImplTest, ParcStreamsAddedMixingAudioJoinsRendererImpl) {
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveEnoughData);

  ParcAddStreamsWithoutRestart(
      media::PipelineMetadata(),
      {{media::DemuxerStream::AUDIO, media::MediaTrack::Id("2")}});
  EXPECT_TRUE(ParcAwaitsAddedStreamsRenderer());
}

// Parc: so does an encrypted stream: RendererImpl's decoders take the CDM
// when it's set, the clock waiting for it there, as WebKit's renderer waits
// for samples it can't decrypt yet, instead of a restart (a rebuffer).
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

// Parc: one encrypted for the FairPlay CDM, which only the FairPlay Renderer
// decrypts, restarts into a renderer made with every stream.
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

// Parc: Safari's renderer plays VP9 (profiles 0 and 2, VideoToolbox's) and
// Vorbis beside Dolby Vision, so on a Safari-identity Media Source the
// FairPlay Renderer takes them over from Chromium's renderer instead of
// failing at a switch into Dolby Vision, and changeType() on its players
// switches to them, and to AV1. A Chrome-identity page, or a file, still
// keeps them on Chromium's renderer.
TEST_F(ParcWebMediaPlayerImplTest, ParcSafariFairPlayPlaysVp9AndVorbis) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(/*safari_identity=*/true);
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

  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(false));
  EXPECT_FALSE(ParcFairPlayPlays(dolby_vision, vorbis));
  EXPECT_FALSE(ParcFairPlayPlays(vp9_profile2, aac));
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
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
#endif  // BUILDFLAG(IS_MAC)

#if BUILDFLAG(IS_MAC)
// Parc: a FairPlay Renderer takes FairPlay MediaKeys in place, after playing
// without any (a clear start, or clear Dolby Vision) and when the page
// replaces them: new renderers join the key session on the same clock
// (FairPlayRenderer::SetCdm), as Safari attaches keys to samples at any time,
// instead of a restart that stops playback for a moment.
// Parc: a move to the FairPlay Renderer asked for during a seek waits for
// it, rather than restarting now, which would stop playback a second time.
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
#endif  // BUILDFLAG(IS_MAC)


class ParcWebMediaPlayerImplHiddenVideoTest
    : public ParcWebMediaPlayerImplTest,
      public ::testing::WithParamInterface<bool> {
 protected:
  bool PresentsSafariIdentity() const { return GetParam(); }

  // A playing video-only player on a desktop renderer's defaults.
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

    ON_CALL(client_, PresentsParcSafariIdentity())
        .WillByDefault(Return(PresentsSafariIdentity()));
    SetReadyState(WebMediaPlayer::kReadyStateHaveFutureData);
    SetSeeking(false);
    Play();
  }
};

// Safari doesn't pause a video for its page being hidden, so the page sees no
// `pause` and no auto-resume when shown; Chrome pages still pause and resume.
TEST_P(ParcWebMediaPlayerImplHiddenVideoTest, PageHidden) {
  PlayVideoOnly();

  EXPECT_CALL(client_, PausePlayback(WebMediaPlayer::PauseReason::kPageHidden))
      .Times(PresentsSafariIdentity() ? 0 : 1);
  BackgroundPlayer(BackgroundBehaviorType::Page);
  EXPECT_EQ(!PresentsSafariIdentity(), IsPausedBecausePageHidden());

  EXPECT_CALL(client_, ResumePlayback())
      .Times(PresentsSafariIdentity() ? 0 : 1);
  ForegroundPlayer(BackgroundBehaviorType::Page);
  EXPECT_FALSE(IsPausedBecausePageHidden());
}

// The media-playback-while-not-visible policy still pauses a hidden frame.
TEST_P(ParcWebMediaPlayerImplHiddenVideoTest, FrameHiddenWithPolicy) {
  PlayVideoOnly();
  wmpi_->SetShouldPauseWhenFrameIsHidden(true);

  EXPECT_CALL(client_,
              PausePlayback(WebMediaPlayer::PauseReason::kFrameHidden));
  BackgroundPlayer(BackgroundBehaviorType::Frame);
  EXPECT_TRUE(IsPausedBecauseFrameHidden());
}

INSTANTIATE_TEST_SUITE_P(SafariIdentity,
                         ParcWebMediaPlayerImplHiddenVideoTest,
                         ::testing::Bool());

// When `WebMediaPlayerImpl::should_pause_when_frame_is_hidden` is false, frame
// visibility changes should not affect the playback state.


TEST_F(ParcWebMediaPlayerImplTest, ParcOnFrozenWhileRemotingKeepsPipeline) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SwitchToRemoteRenderer("TV");
  ASSERT_FALSE(IsSuspended());

  // The observer keeps a session casting this element.
  EXPECT_CALL(mock_observer_, OnFrozen());
  wmpi_->OnFrozen();
  EXPECT_FALSE(IsSuspended());
}

TEST_F(ParcWebMediaPlayerImplTest, ParcOnFrozenWhileRemotingKeepsStreamingReader) {
  InitializeWebMediaPlayerImpl();
  wmpi_->SetPreload(WebMediaPlayer::kPreloadAuto);
  // Larger than the MultiBuffer block size, so the data source initializes.
  Load("bear_192kHz.wav", LoadType::kStreaming);
  while (wmpi_->GetReadyState() < WebMediaPlayer::kReadyStateHaveMetadata) {
    base::RunLoop loop;
    EXPECT_CALL(client_, ReadyStateChanged())
        .WillRepeatedly(RunClosure(loop.QuitClosure()));
    loop.Run();
    testing::Mock::VerifyAndClearExpectations(&client_);
  }
  EXPECT_CALL(client_, ReadyStateChanged()).Times(AnyNumber());
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

// A cast whose session starts after the page went into the back/forward cache
// restarts the pipeline on the receiver's renderer, paused.
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

// Casting takes a suspend already waiting on the frozen page with it.
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

// A player that isn't casting stays frozen with its page.
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

// A casting player's source keeps its reader in a frozen frame, and loads on
// for the receiver.
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

// A cast that starts after the page was frozen preloads for the receiver
// again, and its source reads while the page stays frozen.
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

  // Without a reader, the read waits for the source's task.
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

// A frozen player that isn't casting reads only once its page runs again.
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

// A cast still connecting keeps its source's reader in the back/forward cache,
// until its request ends.
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

  // The connection failed.
  wmpi_->ParcCastRequestChanged(false);
  wmpi_->ParcOnFrozenInBackForwardCache();
  EXPECT_TRUE(ShouldCancelUponDefer());
}

#if BUILDFLAG(ENABLE_HLS_DEMUXER)
// Parc: Chromium's HLS player reads a segment while casting from a frozen
// page, and only once the page runs again otherwise.
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
#endif  // BUILDFLAG(ENABLE_HLS_DEMUXER)


TEST_F(ParcWebMediaPlayerImplTest, SafariIdentityHasNoBackgroundIdlePauseTimer) {
  base::test::ScopedFeatureList feature_list;
  feature_list.InitAndEnableFeature(media::kPauseBackgroundTimer);
  InitializeWebMediaPlayerImpl();
  SetSuspendState(true);
  SetPaused(false);
  SetMetadata(true, true);
  ASSERT_TRUE(IsSuspended());

  EXPECT_CALL(client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  ScheduleIdlePauseTimer();
  EXPECT_FALSE(IsIdlePauseTimerRunning());

  EXPECT_CALL(client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(false));
  ScheduleIdlePauseTimer();
  EXPECT_TRUE(IsIdlePauseTimerRunning());
}

// A player told its element's page visibility follows that page, and its
// compositor keeps drawing while that page is visible, whatever the page of
// the frame that made it does; std::nullopt follows that frame's page again.
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

// A Safari-identity element that takes its player to another frame
// (HTMLMediaElement::ParcMovePlayerToFrame) makes it that frame's, keeping its
// pipeline: the frame's delegate tracks it, its audio plays out of the sink
// made for the frame and its factories are handed the frame's; then the player
// tells its client again what it told it so far.
TEST_F(ParcWebMediaPlayerImplTest, ParcMoveToFrameMovesPlayerAndReportsState) {
  ON_CALL(client_, PresentsParcSafariIdentity()).WillByDefault(Return(true));
  InitializeWebMediaPlayerImpl();
  LoadAndWaitForReadyState(kAudioOnlyTestFile,
                           WebMediaPlayer::kReadyStateHaveFutureData);
  wmpi_->SetRate(1.0);
  EXPECT_CALL(client_, DidPlayerMediaPositionStateChange(
                           0.0, kAudioOnlyTestFileDuration, base::TimeDelta(),
                           /*end_of_media=*/false));
  wmpi_->OnTimeUpdate();
  testing::Mock::VerifyAndClearExpectations(&client_);

  auto new_sink =
      base::MakeRefCounted<NiceMock<media::MockAudioRendererSink>>();
  // The test file's server has no ranges, so its load stays with the old
  // index (MultiBufferDataSource::ParcMoveToUrlIndex).
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
  // The switch, then the new sink's authorization answer.
  media_thread_.FlushForTesting();
  media_thread_.FlushForTesting();
  testing::Mock::VerifyAndClearExpectations(audio_sink_.get());
  EXPECT_TRUE(new_sink->callback());
  EXPECT_FALSE(IsSuspended());

  EXPECT_CALL(client_,
              ParcReportMediaMetadata(/*has_audio=*/true, /*has_video=*/false,
                                      _));
  EXPECT_CALL(client_, DidPlayerMutedStatusChange(false));
  EXPECT_CALL(client_, DidPlayerStartPlaying()).Times(0);
  EXPECT_CALL(client_, DidPlayerMediaPositionStateChange(
                           0.0, kAudioOnlyTestFileDuration, base::TimeDelta(),
                           /*end_of_media=*/false));
  wmpi_->ParcReportStateToClient();
}

// A player made for a Chrome-identity page stays with its frame.
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

// Verifies that an infinite duration doesn't muck up GetCurrentTimeInternal.


// Tests that updating the surface id calls OnPictureInPictureStateChange.

// Test that OnPictureInPictureStateChange is not called for audio elements.
// This test explicitly sets display type to picture in picture, for an audio
// element, for testing purposes only (See crbug.com/40251587 for reference).


// Verify that a demuxer override is used when specified.
// TODO(crbug.com/40131757): This test is flaky.


// Parc: Safari's Media Source element takes readyState from the buffered
// ranges (WebKit's MediaSource::monitorSourceBuffers): canplay before
// canplaythrough, and a seek into buffered data keeps HAVE_ENOUGH_DATA, so
// the element fires no waiting, canplay or playing.
TEST_F(ParcWebMediaPlayerImplTest, ParcSafariMediaSourceBufferedSeek) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(/*safari_identity=*/true);

  EXPECT_CALL(client_, ReadyStateChanged()).Times(2);
  AppendParcMediaSource(base::TimeDelta(), media::kInfiniteDuration);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());
  parc_demuxer_->MarkEndOfStream(media::PIPELINE_OK);
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());

  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  wmpi_->Seek(1.0);
  EXPECT_TRUE(wmpi_->Seeking());
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
}

// Parc: a seek with no data at its target drops to HAVE_METADATA (waiting)
// and rises through HAVE_FUTURE_DATA to HAVE_ENOUGH_DATA as data comes.
TEST_F(ParcWebMediaPlayerImplTest, ParcSafariMediaSourceUnbufferedSeek) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(/*safari_identity=*/true);

  EXPECT_CALL(client_, ReadyStateChanged());
  AppendParcMediaSource(base::TimeDelta(), base::Seconds(1));
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  EXPECT_CALL(client_, ReadyStateChanged());
  wmpi_->Seek(2.0);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());

  EXPECT_CALL(client_, ReadyStateChanged());
  AppendParcMediaSource(base::Seconds(2), base::Seconds(2.5));
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  EXPECT_CALL(client_, ReadyStateChanged());
  AppendParcMediaSource(base::Seconds(2.5), media::kInfiniteDuration);
  parc_demuxer_->MarkEndOfStream(media::PIPELINE_OK);
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
}

// Parc: a SourceBuffer added after the others initialized joins the buffered
// ranges with its first init segment, so a second audio language drops
// readyState to HAVE_METADATA and it rises through HAVE_FUTURE_DATA to
// HAVE_ENOUGH_DATA as that SourceBuffer's data comes.
TEST_F(ParcWebMediaPlayerImplTest, ParcSafariMediaSourceLateSourceBuffer) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(/*safari_identity=*/true);
  parc_demuxer_->ParcAllowSourceBuffersAfterInit(base::DoNothing());

  EXPECT_CALL(client_, ReadyStateChanged());
  AppendParcMediaSource(base::TimeDelta(), media::kInfiniteDuration);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  ASSERT_EQ(parc_demuxer_->AddId("audio2", "audio/webm", "vorbis"),
            media::ChunkDemuxer::kOk);
  parc_demuxer_->SetTracksWatcher("audio2", base::DoNothing());
  EXPECT_CALL(client_, ReadyStateChanged()).Times(0);
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  // Its init segment alone: every frame is outside the append window.
  EXPECT_CALL(client_, ReadyStateChanged());
  AppendParcMediaSource(base::Seconds(10), media::kInfiniteDuration, "audio2");
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());

  EXPECT_CALL(client_, ReadyStateChanged());
  AppendParcMediaSource(base::TimeDelta(), base::Seconds(1), "audio2");
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveFutureData, wmpi_->GetReadyState());

  EXPECT_CALL(client_, ReadyStateChanged());
  AppendParcMediaSource(base::Seconds(1), media::kInfiniteDuration, "audio2");
  parc_demuxer_->MarkEndOfStream(media::PIPELINE_OK);
  OnProgress();
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveEnoughData, wmpi_->GetReadyState());
}

// Parc: Chrome's identity keeps Chromium's readyState: appends alone don't
// raise it, and a seek drops it to HAVE_METADATA.
TEST_F(ParcWebMediaPlayerImplTest, ParcChromeMediaSourceSeekUnchanged) {
  InitializeWebMediaPlayerImpl();
  StartParcMediaSource(/*safari_identity=*/false);

  AppendParcMediaSource(base::TimeDelta(), media::kInfiniteDuration);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());
  SetReadyState(WebMediaPlayer::kReadyStateHaveEnoughData);

  EXPECT_CALL(client_, ReadyStateChanged());
  wmpi_->Seek(1.0);
  EXPECT_EQ(WebMediaPlayer::kReadyStateHaveMetadata, wmpi_->GetReadyState());
}

class ParcWebMediaPlayerImplBackgroundBehaviorTest
    : public ParcWebMediaPlayerImplTest,
      public WebAudioSourceProviderClient,
      public ::testing::WithParamInterface<
          std::tuple<bool, int, int, bool, bool, bool, bool, bool, bool>> {
 public:
  // Indices of the tuple parameters.
  static const int kIsMediaSuspendEnabled = 0;
  static const int kDurationSec = 1;
  static const int kAverageKeyframeDistanceSec = 2;
  static const int kIsResumeBackgroundVideoEnabled = 3;
  static const int kIsPictureInPictureEnabled = 4;
  static const int kIsBackgroundVideoPlaybackEnabled = 5;
  static const int kIsVideoBeingCaptured = 6;
  // If true, the player's page is hidden. Otherwise, the player's frame is
  // hidden.
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

    // MSE or SRC doesn't matter since we artificially inject pipeline stats.
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
    EXPECT_CALL(client_, GetDisplayType())
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

  // We should pause media playback if the media-playback-while-not-visible
  // permission policy is not enabled and the player's frame is hidden.
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


// Exercise both load types: the optimization runs above renderer selection.
TEST_P(ParcWebMediaPlayerImplBackgroundBehaviorTest,
       SafariIdentity_KeepsBackgroundVideoTrackSelected) {
  EXPECT_CALL(client_, PresentsParcSafariIdentity())
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
  EXPECT_CALL(client_, PresentsParcSafariIdentity())
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

// On a Safari-identity page a hidden player pauses only for the
// media-playback-while-not-visible policy or an embedder that disables
// background video playback, whatever its tracks, volume or suspend flags.
TEST_P(ParcWebMediaPlayerImplBackgroundBehaviorTest, SafariIdentity_AudioOnly) {
  base::test::ScopedFeatureList scoped_background_audio_flag{
      media::kPauseMutedBackgroundAudio};
  SCOPED_TRACE(testing::Message() << PrintValues());
  EXPECT_CALL(client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(client_, WasAlwaysMuted()).WillRepeatedly(Return(true));
  SetMetadata(true, false);
  SetVolume(0.);
  EXPECT_EQ(IsFrameHiddenAndShouldPauseWhenHidden() ||
                !IsBackgroundVideoPlaybackEnabled(),
            ShouldPausePlaybackWhenHidden());
}

TEST_P(ParcWebMediaPlayerImplBackgroundBehaviorTest, SafariIdentity_VideoOnly) {
  SCOPED_TRACE(testing::Message() << PrintValues());
  EXPECT_CALL(client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(client_, WasAlwaysMuted()).WillRepeatedly(Return(true));
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
  EXPECT_CALL(client_, PresentsParcSafariIdentity())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(client_, WasAlwaysMuted()).WillRepeatedly(Return(true));
  SetMetadata(true, true);
  EXPECT_EQ(should_pause, ShouldPausePlaybackWhenHidden());
  SetVolume(0.);
  EXPECT_EQ(should_pause, ShouldPausePlaybackWhenHidden());

  EXPECT_CALL(client_, WasAlwaysMuted()).WillRepeatedly(Return(false));
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

}  // namespace blink
