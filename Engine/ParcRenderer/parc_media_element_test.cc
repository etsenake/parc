// Copyright 2026 Parc contributors.

#include "third_party/blink/renderer/core/html/media/parc_media_element.h"

#include "third_party/blink/renderer/core/html/media/html_media_element.h"

#include <cmath>

#include "base/memory/raw_ptr.h"
#include "base/run_loop.h"
#include "base/test/gtest_util.h"
#include "base/time/time_override.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/media_content_type.h"
#include "media/base/media_switches.h"
#include "media/base/media_track.h"
#include "media/base/video_decoder_config.h"
#include "media/mojo/mojom/media_player.mojom-blink.h"
#include "services/media_session/public/mojom/media_session.mojom-blink.h"
#include "services/network/public/cpp/permissions_policy/permissions_policy.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "third_party/blink/public/mojom/autoplay/autoplay.mojom-blink.h"
#include "third_party/blink/public/platform/parc_web_media_player_extension.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/public/platform/web_media_player_source.h"
#include "third_party/blink/public/platform/web_media_source.h"
#include "third_party/blink/public/platform/web_source_buffer.h"
#include "third_party/blink/renderer/bindings/core/v8/script_promise_tester.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_dom_exception.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_text_track_kind.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_text_track_mode.h"
#include "third_party/blink/renderer/core/css/css_default_style_sheets.h"
#include "third_party/blink/renderer/core/dom/dom_exception.h"
#include "third_party/blink/renderer/core/dom/dom_implementation.h"
#include "third_party/blink/renderer/core/dom/element.h"
#include "third_party/blink/renderer/core/dom/events/event.h"
#include "third_party/blink/renderer/core/dom/events/native_event_listener.h"
#include "third_party/blink/renderer/core/dom/shadow_root.h"
#include "third_party/blink/renderer/core/execution_context/agent.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/picture_in_picture_controller.h"
#include "third_party/blink/renderer/core/frame/settings.h"
#include "third_party/blink/renderer/core/fullscreen/fullscreen.h"
#include "third_party/blink/renderer/core/html/html_document.h"
#include "third_party/blink/renderer/core/html/html_head_element.h"
#include "third_party/blink/renderer/core/html/html_source_element.h"
#include "third_party/blink/renderer/core/html/html_template_element.h"
#include "third_party/blink/renderer/core/html/media/html_audio_element.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/html/media/media_error.h"
#include "third_party/blink/renderer/core/html/media/media_source_attachment.h"
#include "third_party/blink/renderer/core/html/media/media_video_visibility_tracker.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element_air_play.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element_names.h"
#include "third_party/blink/renderer/core/html/media/parc_media_player_move.h"
#include "third_party/blink/renderer/core/html/time_ranges.h"
#include "third_party/blink/renderer/core/html/track/audio_track_list.h"
#include "third_party/blink/renderer/core/html/track/text_track.h"
#include "third_party/blink/renderer/core/html/track/text_track_list.h"
#include "third_party/blink/renderer/core/html/track/video_track_list.h"
#include "third_party/blink/renderer/core/html/track/vtt/vtt_cue.h"
#include "third_party/blink/renderer/core/loader/empty_clients.h"
#include "third_party/blink/renderer/core/testing/dummy_page_holder.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/thread_state_scopes.h"
#include "third_party/blink/renderer/platform/mediastream/media_stream_descriptor.h"
#include "third_party/blink/renderer/platform/network/network_state_notifier.h"
#include "third_party/blink/renderer/platform/scheduler/public/event_loop.h"
#include "third_party/blink/renderer/platform/testing/empty_web_media_player.h"
#include "third_party/blink/renderer/platform/testing/runtime_enabled_features_test_helpers.h"
#include "third_party/blink/renderer/platform/testing/task_environment.h"
#include "third_party/blink/renderer/platform/testing/unit_test_helpers.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"
#include "third_party/blink/renderer/platform/wtf/vector.h"
#include "ui/gfx/geometry/size.h"

using ::testing::_;
using ::testing::AnyNumber;
using ::testing::Return;

namespace blink {

namespace {

enum class TestURLScheme {
  kHttp,
  kHttps,
  kFtp,
  kFile,
  kData,
  kBlob,
};

AtomicString SrcSchemeToURL(TestURLScheme scheme) {
  switch (scheme) {
    case TestURLScheme::kHttp:
      return AtomicString("http://example.com/foo.mp4");
    case TestURLScheme::kHttps:
      return AtomicString("https://example.com/foo.mp4");
    case TestURLScheme::kFtp:
      return AtomicString("ftp://example.com/foo.mp4");
    case TestURLScheme::kFile:
      return AtomicString("file:///foo/bar.mp4");
    case TestURLScheme::kData:
      return AtomicString("data:video/mp4;base64,XXXXXXX");
    case TestURLScheme::kBlob:
      return AtomicString(
          "blob:http://example.com/00000000-0000-0000-0000-000000000000");
    default:
      NOTREACHED();
  }
}

class StubMediaSourceAttachment : public MediaSourceAttachment {
 public:
  StubMediaSourceAttachment() = default;
  void Unregister() override {}
  MediaSourceTracer* StartAttachingToMediaElement(HTMLMediaElement*,
                                                  bool* success) override {
    *success = true;
    return nullptr;
  }
  void CompleteAttachingToMediaElement(
      MediaSourceTracer* tracer,
      std::unique_ptr<WebMediaSource>) override {}
  void Close(MediaSourceTracer* tracer) override {}
  WebTimeRanges BufferedInternal(MediaSourceTracer* tracer) const override {
    return {};
  }
  WebTimeRanges SeekableInternal(MediaSourceTracer* tracer) const override {
    return {};
  }
  void OnTrackChanged(MediaSourceTracer* tracer, TrackBase*) override {}
  void OnElementTimeUpdate(double time) override {}
  void OnElementError() override {}
  void OnElementContextDestroyed() override {}
};

class ManagedMediaSourceAttachment final : public StubMediaSourceAttachment {
 public:
  ManagedMediaSourceAttachment() { parc_managed_ = true; }
  void CompleteAttachingToMediaElement(
      MediaSourceTracer*,
      std::unique_ptr<WebMediaSource>) override {
    ++opens_;
  }
  int opens() const { return opens_; }

 private:
  int opens_ = 0;
};

class StubWebMediaSource final : public WebMediaSource {
 public:
  std::unique_ptr<WebSourceBuffer> AddSourceBuffer(const WebString&,
                                                   const WebString&,
                                                   AddStatus&) override {
    return nullptr;
  }
  std::unique_ptr<WebSourceBuffer> AddSourceBuffer(
      std::unique_ptr<media::AudioDecoderConfig>,
      AddStatus&) override {
    return nullptr;
  }
  std::unique_ptr<WebSourceBuffer> AddSourceBuffer(
      std::unique_ptr<media::VideoDecoderConfig>,
      AddStatus&) override {
    return nullptr;
  }
  double Duration() override { return 0; }
  void SetDuration(double) override {}
  void MarkEndOfStream(EndOfStreamStatus) override {}
  void UnmarkEndOfStream() override {}
};

class MockWebMediaPlayer : public EmptyWebMediaPlayer,
                           public ParcWebMediaPlayerExtension {
 public:
  ParcWebMediaPlayerExtension* GetParcExtension() override { return this; }
  MOCK_METHOD0(Play, void());
  MOCK_METHOD0(UnlockBackgroundPlayback, void());
  MOCK_METHOD1(Pause, void(PauseReason));
  MOCK_METHOD0(OnTimeUpdate, void());
  MOCK_CONST_METHOD0(Paused, bool());
  MOCK_CONST_METHOD0(Seekable, WebTimeRanges());
  MOCK_CONST_METHOD0(Buffered, WebTimeRanges());
  MOCK_METHOD0(OnFrozen, void());
  MOCK_METHOD0(ParcOnFrozenInBackForwardCache, void());
  MOCK_METHOD1(ParcSetPageHidden, void(std::optional<bool>));
  MOCK_METHOD(bool, ParcMoveToFrame, (ParcFrameServices), (override));
  MOCK_METHOD(void, ParcReportStateToClient, (), (override));
  MOCK_CONST_METHOD0(HasAudio, bool());
  MOCK_CONST_METHOD0(HasVideo, bool());
  MOCK_CONST_METHOD0(Duration, double());
  MOCK_CONST_METHOD0(CurrentTime, double());
  MOCK_CONST_METHOD0(IsEnded, bool());
  MOCK_METHOD0(DidLoadingProgress, bool());
  MOCK_CONST_METHOD0(GetNetworkState, NetworkState());
  MOCK_CONST_METHOD0(GetReadyState, ReadyState());
  MOCK_CONST_METHOD0(WouldTaintOrigin, bool());
  MOCK_METHOD1(SetLatencyHint, void(double));
  MOCK_METHOD1(SetWasPlayedWithUserActivationAndHighMediaEngagement,
               void(bool));
  MOCK_METHOD1(EnabledAudioTracksChanged, void(std::optional<TrackId>));
  MOCK_METHOD1(ParcEnabledAudioTracksChanged,
               void(const std::vector<TrackId>&));
  MOCK_METHOD1(SelectedVideoTrackChanged, void(std::optional<TrackId>));
  MOCK_METHOD4(
      Load,
      WebMediaPlayer::LoadTiming(LoadType load_type,
                                 const blink::WebMediaPlayerSource& source,
                                 CorsMode cors_mode,
                                 bool is_cache_disabled));
  MOCK_CONST_METHOD0(DidLazyLoad, bool());

  MOCK_METHOD0(GetSrcAfterRedirects, GURL());

  MOCK_CONST_METHOD0(HasAvailableVideoFrame, bool());
  MOCK_CONST_METHOD0(HasReadableVideoFrame, bool());
  MOCK_METHOD1(SetVolume, void(double));
  MOCK_METHOD1(SetShouldPauseWhenFrameIsHidden, void(bool));
  MOCK_METHOD1(Seek, void(double));
  MOCK_METHOD1(SetRate, void(double));
  MOCK_METHOD0(OnFrameHidden, void());
  MOCK_METHOD0(OnFrameShown, void());
  MOCK_METHOD1(SetPreload, void(Preload));
  MOCK_CONST_METHOD0(GetErrorMessage, WebString());
  MOCK_METHOD2(ParcFastSeek, void(double, double));
  MOCK_METHOD2(ParcSetPlaybackTarget, void(std::string_view, bool));
  MOCK_METHOD1(ParcSetWirelessVideoPlaybackDisabled, void(bool));
  MOCK_CONST_METHOD0(ParcSupportsPlaybackTarget, bool());
};

class WebMediaStubLocalFrameClient : public EmptyLocalFrameClient {
 public:
  explicit WebMediaStubLocalFrameClient(std::unique_ptr<WebMediaPlayer> player)
      : player_(std::move(player)) {}

  std::unique_ptr<WebMediaPlayer> CreateWebMediaPlayer(
      HTMLMediaElement&,
      const WebMediaPlayerSource&,
      WebMediaPlayerClient* client) override {
    DCHECK(player_) << " Empty injected player - already used?";
    return std::move(player_);
  }

  void SetPlayer(std::unique_ptr<WebMediaPlayer> player) {
    player_ = std::move(player);
  }
  String UserAgent() override { return user_agent_; }
  void set_user_agent(const String& user_agent) { user_agent_ = user_agent; }

 private:
  std::unique_ptr<WebMediaPlayer> player_;
  String user_agent_;
};

bool MoveStubWebMediaPlayer(HTMLMediaElement& element) {
  ParcWebMediaPlayerExtension* parc =
      element.GetWebMediaPlayer()->GetParcExtension();
  return parc && parc->ParcMoveToFrame(
                     ParcWebMediaPlayerExtension::ParcFrameServices());
}

class FullscreenMockChromeClient : public EmptyChromeClient {
 public:
  void EnterFullscreen(LocalFrame& frame,
                       const FullscreenOptions*,
                       FullscreenRequestType) override {
    Fullscreen::DidResolveEnterFullscreenRequest(*frame.GetDocument(),
                                                 true);
  }
  void ExitFullscreen(LocalFrame& frame) override {
    Fullscreen::DidExitFullscreen(*frame.GetDocument());
  }
};

class TestMediaPlayerObserver final
    : public media::mojom::blink::MediaPlayerObserver {
 public:
  struct OnMetadataChangedResult {
    bool has_audio;
    bool has_video;
    media::MediaContentType media_content_type;
  };

  void WaitUntilReceivedMessage() {
    run_loop_ = std::make_unique<base::RunLoop>();
    run_loop_->Run();
    run_loop_.reset();
  }

  void OnMediaPlaying() override {
    received_media_playing_ = true;
    run_loop_->Quit();
  }

  void OnMediaPaused(bool stream_ended) override {
    received_media_paused_stream_ended_ = stream_ended;
    run_loop_->Quit();
  }

  void OnMutedStatusChanged(bool muted) override {
    received_muted_status_type_ = muted;
    run_loop_->Quit();
  }

  void OnMediaMetadataChanged(bool has_audio,
                              bool has_video,
                              media::MediaContentType content_type) override {
    received_metadata_changed_result_ =
        OnMetadataChangedResult{has_audio, has_video, content_type};
    run_loop_->Quit();
  }

  void OnMediaPositionStateChanged(
      ::media_session::mojom::blink::MediaPositionPtr) override {}

  void OnMediaEffectivelyFullscreenChanged(
      blink::WebFullscreenVideoStatus status) override {}

  void OnMediaSizeChanged(const gfx::Size& size) override {
    received_media_size_ = size;
    run_loop_->Quit();
  }

  void OnPictureInPictureAvailabilityChanged(bool available) override {}

  void OnAudioOutputSinkChanged(const String& hashed_device_id) override {}

  void OnUseAudioServiceChanged(bool uses_audio_service) override {
    received_uses_audio_service_ = uses_audio_service;
    run_loop_->Quit();
  }

  void OnAudioOutputSinkChangingDisabled() override {}

  void OnRemotePlaybackMetadataChange(
      media_session::mojom::blink::RemotePlaybackMetadataPtr
          remote_playback_metadata) override {
    received_remote_playback_metadata_ = std::move(remote_playback_metadata);
    run_loop_->Quit();
  }

  void OnVideoVisibilityChanged(bool meets_visibility_threshold) override {}

  void OnVideoFrameAvailabilityChanged(bool available) override {
    received_video_frame_availability_ = available;
    if (run_loop_) {
      run_loop_->Quit();
    }
  }

  struct PlaybackTargetState {
    bool requires_monitoring;
    bool supports_target;
    bool plays_to_target;
    bool wireless;
  };
  void OnParcPlaybackTargetStateChanged(bool requires_monitoring,
                                        bool supports_target,
                                        bool plays_to_target,
                                        bool wireless) override {
    received_playback_target_state_ = PlaybackTargetState{
        requires_monitoring, supports_target, plays_to_target, wireless};
    if (run_loop_) {
      run_loop_->Quit();
    }
  }

  void OnParcShowPlaybackTargetPicker(const gfx::Point& position) override {
    ++received_playback_target_pickers_;
    if (run_loop_) {
      run_loop_->Quit();
    }
  }

  const std::optional<PlaybackTargetState>& received_playback_target_state()
      const {
    return received_playback_target_state_;
  }
  int received_playback_target_pickers() const {
    return received_playback_target_pickers_;
  }

  void WaitForVideoFrameAvailability() {
    if (received_video_frame_availability_.has_value()) {
      return;
    }
    run_loop_ = std::make_unique<base::RunLoop>();
    run_loop_->Run();
  }

  const std::optional<bool>& received_video_frame_availability() const {
    return received_video_frame_availability_;
  }

  void ClearVideoFrameAvailability() {
    received_video_frame_availability_.reset();
  }

  bool received_media_playing() const { return received_media_playing_; }

  const std::optional<bool>& received_media_paused_stream_ended() const {
    return received_media_paused_stream_ended_;
  }

  const std::optional<bool>& received_muted_status() const {
    return received_muted_status_type_;
  }

  const std::optional<OnMetadataChangedResult>&
  received_metadata_changed_result() const {
    return received_metadata_changed_result_;
  }

  gfx::Size received_media_size() const { return received_media_size_; }

  bool received_use_audio_service_changed(bool uses_audio_service) const {
    return received_uses_audio_service_.value() == uses_audio_service;
  }

  bool received_remote_playback_metadata(
      media_session::mojom::blink::RemotePlaybackMetadataPtr
          remote_playback_metadata) const {
    return received_remote_playback_metadata_ == remote_playback_metadata;
  }

 private:
  std::unique_ptr<base::RunLoop> run_loop_;
  bool received_media_playing_{false};
  std::optional<bool> received_media_paused_stream_ended_;
  std::optional<bool> received_muted_status_type_;
  std::optional<OnMetadataChangedResult> received_metadata_changed_result_;
  gfx::Size received_media_size_{0, 0};
  std::optional<bool> received_uses_audio_service_;
  std::optional<bool> received_video_frame_availability_;
  std::optional<PlaybackTargetState> received_playback_target_state_;
  int received_playback_target_pickers_ = 0;
  media_session::mojom::blink::RemotePlaybackMetadataPtr
      received_remote_playback_metadata_;
};

class TestMediaPlayerHost final : public media::mojom::blink::MediaPlayerHost {
 public:
  void WaitForPlayer() { run_loop_.Run(); }

  void OnMediaPlayerAdded(
      mojo::PendingAssociatedRemote<media::mojom::blink::MediaPlayer>
          media_player,
      mojo::PendingAssociatedReceiver<media::mojom::blink::MediaPlayerObserver>
          media_player_observer,
      int32_t) override {
    media_player_.reset();
    media_player_.Bind(std::move(media_player));
    receiver_.reset();
    receiver_.Bind(std::move(media_player_observer));
    run_loop_.Quit();
  }

  TestMediaPlayerObserver& observer() { return observer_; }
  bool HasConnectedPlayer() const {
    return media_player_.is_bound() && media_player_.is_connected();
  }

 private:
  mojo::AssociatedRemote<media::mojom::blink::MediaPlayer> media_player_;
  TestMediaPlayerObserver observer_;
  mojo::AssociatedReceiver<media::mojom::blink::MediaPlayerObserver> receiver_{
      &observer_};
  base::RunLoop run_loop_;
};

class EventCountingListener final : public NativeEventListener {
 public:
  void Invoke(ExecutionContext*, Event*) override { ++count_; }
  int count() const { return count_; }

 private:
  int count_ = 0;
};

enum class MediaTestParam { kAudio, kVideo };

}

class ParcMediaElementTest : public testing::TestWithParam<MediaTestParam> {
 public:
  explicit ParcMediaElementTest(
      test::TaskEnvironment::TimeSource time_source =
          test::TaskEnvironment::TimeSource::SYSTEM_TIME)
      : task_environment_(time_source) {}

 protected:
  void SetUp() override {
    previous_move_web_media_player_ =
        parc_hooks::SetMoveWebMediaPlayer(&MoveStubWebMediaPlayer);
    auto mock_media_player =
        std::make_unique<testing::NiceMock<MockWebMediaPlayer>>();
    media_player_weak_ = mock_media_player->AsWeakPtr();
    media_player_ = mock_media_player.get();

    EXPECT_CALL(*mock_media_player, Seekable())
        .WillRepeatedly(Return(WebTimeRanges()));
    EXPECT_CALL(*mock_media_player, HasAudio()).WillRepeatedly(Return(true));
    EXPECT_CALL(*mock_media_player, HasVideo()).WillRepeatedly(Return(true));
    EXPECT_CALL(*mock_media_player, Duration()).WillRepeatedly(Return(1.0));
    EXPECT_CALL(*mock_media_player, CurrentTime()).WillRepeatedly(Return(0));
    EXPECT_CALL(*mock_media_player, Load(_, _, _, _))
        .Times(AnyNumber())
        .WillRepeatedly(Return(WebMediaPlayer::LoadTiming::kImmediate));
    EXPECT_CALL(*mock_media_player, DidLazyLoad).WillRepeatedly(Return(false));
    EXPECT_CALL(*mock_media_player, WouldTaintOrigin)
        .WillRepeatedly(Return(true));
    EXPECT_CALL(*mock_media_player, GetNetworkState)
        .WillRepeatedly(Return(WebMediaPlayer::kNetworkStateIdle));
    EXPECT_CALL(*mock_media_player, SetLatencyHint(_)).Times(AnyNumber());

    chrome_client_ = MakeGarbageCollected<FullscreenMockChromeClient>();
    dummy_page_holder_ = std::make_unique<DummyPageHolder>(
        gfx::Size(), chrome_client_,
        MakeGarbageCollected<WebMediaStubLocalFrameClient>(
            std::move(mock_media_player)));

    if (GetParam() == MediaTestParam::kAudio) {
      media_ = MakeGarbageCollected<HTMLAudioElement>(
          dummy_page_holder_->GetDocument());
    } else {
      media_ = MakeGarbageCollected<HTMLVideoElement>(
          dummy_page_holder_->GetDocument());
    }

    media_->SetMediaPlayerHostForTesting(
        media_player_host_receiver_.BindNewEndpointAndPassDedicatedRemote());

    UpdateLifecyclePhases();
  }

  void TearDown() override {
    parc_hooks::SetMoveWebMediaPlayer(previous_move_web_media_player_);
  }

  void UpdateLifecyclePhases() {
    dummy_page_holder_->GetFrameView().UpdateAllLifecyclePhasesForTest();
  }

  void WaitForPlayer() {
    Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
    Media()->Play();
    media_player_host_.WaitForPlayer();
  }

  HTMLMediaElement* Media() const { return media_.Get(); }
  void SetUserAgent(const char* user_agent) {
    static_cast<WebMediaStubLocalFrameClient*>(
        dummy_page_holder_->GetFrame().Client())
        ->set_user_agent(String(user_agent));
  }

  MockWebMediaPlayer* MockMediaPlayer() { return media_player_; }

  bool CouldPlayIfEnoughData() { return Media()->CouldPlayIfEnoughData(); }

  bool PotentiallyPlaying() { return Media()->PotentiallyPlaying(); }

  void ParcStopAtEndAtRateZero() {
    WebTimeRanges seekable;
    seekable.Add(0, 1.0);
    EXPECT_CALL(*MockMediaPlayer(), Seekable())
        .WillRepeatedly(Return(seekable));
    EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(1.0));
    EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
    Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
    test::RunPendingTasks();
    ASSERT_TRUE(Media()->GetWebMediaPlayer());
    SetReadyState(HTMLMediaElement::kHaveEnoughData);
    Media()->setPlaybackRate(0);
    test::RunPendingTasks();
    ASSERT_TRUE(Media()->paused());
  }

  bool ShouldDelayLoadEvent() { return Media()->should_delay_load_event_; }

  bool ParcCompletelyLoaded() {
    return ParcMediaElement::From(*Media()).completely_loaded_;
  }

  void SetNetworkState(WebMediaPlayer::NetworkState state) {
    Media()->SetNetworkState(state);
  }

  void NetworkStateChanged() { Media()->NetworkStateChanged(); }

  void SetReadyState(HTMLMediaElement::ReadyState state) {
    Media()->SetReadyState(state);
  }

  void ReadyStateChanged() { Media()->ReadyStateChanged(); }

  void ParcSetPlaybackTarget(const String& output_context_id,
                             const String& device_name,
                             bool should_play,
                             uint32_t tint_argb = 0,
                             uint32_t tint_on_light_argb = 0) {
    Media()->ParcSetPlaybackTarget(output_context_id, device_name, should_play,
                                   tint_argb, tint_on_light_argb);
  }
  void ParcPlaybackTargetIsWirelessChanged(bool wireless) {
    ParcMediaElementAirPlay::From(*Media()).PlaybackTargetIsWirelessChanged(
        wireless);
  }

  TestMediaPlayerObserver& media_player_observer() {
    return media_player_host_.observer();
  }
  TestMediaPlayerHost& media_player_host() { return media_player_host_; }

  bool MediaIsPlaying() const { return Media()->playing_; }

  void SetLazyMediaLoadStateToDeferredForTesting() {
    Media()->lazy_media_load_state_ =
        decltype(Media()->lazy_media_load_state_)::kDeferred;
  }

  bool HasParcLazyLoadResumeTask() const {
    return ParcMediaElement::From(*Media()).lazy_load_resume_task_.IsActive();
  }

  ExecutionContext* GetExecutionContext() const {
    return dummy_page_holder_->GetFrame().DomWindow();
  }

  void SetPageVisibility(mojom::blink::PageVisibilityState visibility) {
    dummy_page_holder_->GetPage().SetVisibilityState(
        visibility, false);
  }

  LocalDOMWindow* GetDomWindow() const {
    return dummy_page_holder_->GetFrame().DomWindow();
  }

  bool HasHiddenAutoplayGrant() const {
    return ParcMediaElement::From(*Media()).hidden_autoplay_granted_;
  }

  void PrepareReplacementPlayer() {
    auto player = std::make_unique<testing::NiceMock<MockWebMediaPlayer>>();
    media_player_ = player.get();
    media_player_weak_ = player->AsWeakPtr();
    ON_CALL(*player, HasAudio()).WillByDefault(Return(true));
    ON_CALL(*player, HasVideo()).WillByDefault(Return(true));
    ON_CALL(*player, Duration()).WillByDefault(Return(60.0));
    ON_CALL(*player, Load(_, _, _, _))
        .WillByDefault(Return(WebMediaPlayer::LoadTiming::kImmediate));
    static_cast<WebMediaStubLocalFrameClient*>(
        dummy_page_holder_->GetFrame().Client())
        ->SetPlayer(std::move(player));
  }

  void AddAudioTrack() {
    Media()->AddTrack(media::MediaTrack::CreateAudioTrack(
        "audio", media::MediaTrack::AudioKind::kMain, "audio", "en", true));
  }
  AudioTrack* ParcAddTwoAudioTracks() {
    Media()->AddTrack(media::MediaTrack::CreateAudioTrack(
        "audio1", media::MediaTrack::AudioKind::kMain, "audio1", "", true));
    Media()->AddTrack(media::MediaTrack::CreateAudioTrack(
        "audio2", media::MediaTrack::AudioKind::kMain, "audio2", "", false));
    AudioTrack* track = Media()->audioTracks().getTrackById("audio2");
    CHECK(track);
    return track;
  }
  void TimeChanged() { Media()->TimeChanged(); }

  void ParcPlayerTimeChanged() {
    ParcMediaElement::From(*Media()).ParcPlayerTimeChanged();
  }

  void SetPreviousProgressTime() {
    Media()->previous_progress_time_ = base::ElapsedTimer();
  }

  void CallProgressEventTimerFired() { Media()->ProgressEventTimerFired(); }

  void CallPlaybackProgressTimerFired() {
    Media()->PlaybackProgressTimerFired();
  }

  bool LoadIsDeferred() const { return Media()->LoadIsDeferred(); }

  bool ParcPreparesToPlay() const {
    return ParcMediaElement::From(*Media()).ParcPreparesToPlay();
  }

  void PlaybackControls(
      media_session::mojom::blink::PlaybackControlsAction action,
      double time = 0) {
    Media()->RequestHandlePlaybackControlsAction(action, base::Seconds(time));
  }
  bool PlaybackControlsPausedInternally() const {
    return ParcMediaElement::From(*Media()).scrubbing_playback_controls_;
  }
  void RequestSeekTo(double time) {
    Media()->RequestSeekTo(base::Seconds(time));
  }
  void RequestSeekForward(double seconds) {
    Media()->RequestSeekForward(base::Seconds(seconds));
  }
  void RequestSeekBackward(double seconds) {
    Media()->RequestSeekBackward(base::Seconds(seconds));
  }
  void RequestPause() { Media()->RequestPause(true); }
  std::optional<base::TimeDelta> ParcRemoteScrubEndsIn() const {
    ParcMediaElement& parc = ParcMediaElement::From(*Media());
    if (!parc.remote_scrub_end_timer_.IsActive()) {
      return std::nullopt;
    }
    return parc.remote_scrub_end_timer_.NextFireInterval();
  }
  void EndParcRemoteScrub() {
    ParcMediaElement& parc = ParcMediaElement::From(*Media());
    parc.remote_scrub_end_timer_.Stop();
    parc.RemoteScrubEndTimerFired(nullptr);
  }

  void SetMediaSourceAttachment(
      scoped_refptr<MediaSourceAttachment> attachment) {
    Media()->media_source_attachment_ = std::move(attachment);
  }

  void MediaSourceOpened() {
    Media()->MediaSourceOpened(std::make_unique<StubWebMediaSource>());
  }

  void AppendSource(const AtomicString& src) {
    auto* source =
        MakeGarbageCollected<HTMLSourceElement>(Media()->GetDocument());
    source->setAttribute(html_names::kSrcAttr, src);
    Media()->AppendChild(source);
  }

  void CheckParcPlaybackTargetCompatibility() {
    ParcMediaElementAirPlay& air_play = ParcMediaElementAirPlay::From(*Media());
    air_play.check_playback_target_compatibility_timer_.Stop();
    air_play.CheckPlaybackTargetCompatibility(nullptr);
  }

  size_t PendingPlayPromiseCount() const {
    return Media()->play_promise_resolvers_.size();
  }

  void PauseForInvisibleAutoplay() {
    Media()->PauseInternal(WebMediaPlayer::PauseReason::kAutoplayAutoPause);
    Media()->can_autoplay_ = true;
  }

  bool CanAutoplay() const { return Media()->can_autoplay_; }

 protected:
  void NotifyMediaMetadataChanged(bool has_audio,
                                  bool has_video,
                                  media::AudioCodec audio_codec,
                                  media::VideoCodec video_codec,
                                  media::MediaContentType media_content_type,
                                  bool is_encrypted_media) {
    media_->DidMediaMetadataChange(has_audio, has_video, audio_codec,
                                   video_codec, media_content_type,
                                   is_encrypted_media);
    media_player_observer().WaitUntilReceivedMessage();
    media_player_observer().WaitUntilReceivedMessage();
  }

  bool WasPlayerDestroyed() const { return !media_player_weak_; }

  std::unique_ptr<DummyPageHolder> CreatePageWithSecurityOrigin(
      const char* origin,
      bool is_picture_in_picture,
      bool with_mock_player = false) {
    std::unique_ptr<WebMediaPlayer> player;
    if (with_mock_player) {
      auto mock_player =
          std::make_unique<testing::NiceMock<MockWebMediaPlayer>>();
      EXPECT_CALL(*mock_player, Seekable())
          .WillRepeatedly(Return(WebTimeRanges()));
      EXPECT_CALL(*mock_player, HasAudio()).WillRepeatedly(Return(true));
      EXPECT_CALL(*mock_player, HasVideo()).WillRepeatedly(Return(true));
      EXPECT_CALL(*mock_player, Duration()).WillRepeatedly(Return(1.0));
      EXPECT_CALL(*mock_player, CurrentTime()).WillRepeatedly(Return(0));
      EXPECT_CALL(*mock_player, Load(_, _, _, _))
          .Times(AnyNumber())
          .WillRepeatedly(Return(WebMediaPlayer::LoadTiming::kImmediate));
      EXPECT_CALL(*mock_player, DidLazyLoad).WillRepeatedly(Return(false));
      EXPECT_CALL(*mock_player, WouldTaintOrigin).WillRepeatedly(Return(true));
      EXPECT_CALL(*mock_player, GetNetworkState)
          .WillRepeatedly(Return(WebMediaPlayer::kNetworkStateIdle));
      EXPECT_CALL(*mock_player, SetLatencyHint(_)).Times(AnyNumber());
      player = std::move(mock_player);
    }

    auto dummy_page_holder = std::make_unique<DummyPageHolder>(
        gfx::Size(), nullptr,
        MakeGarbageCollected<WebMediaStubLocalFrameClient>(std::move(player)));
    Document& document = dummy_page_holder->GetDocument();
    document.domWindow()->GetSecurityContext().SetSecurityOriginForTesting(
        SecurityOrigin::CreateFromString(origin));
    document.domWindow()->set_is_picture_in_picture_window_for_testing(
        is_picture_in_picture);

    return dummy_page_holder;
  }

  static void PresentSafariIdentity(Document& document) {
    static_cast<WebMediaStubLocalFrameClient*>(document.GetFrame()->Client())
        ->set_user_agent(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 "
            "Safari/605.1.15");
  }

  void SetSecurityOrigin(const char* origin) {
    Media()
        ->GetDocument()
        .domWindow()
        ->GetSecurityContext()
        .SetSecurityOriginForTesting(SecurityOrigin::CreateFromString(origin));
  }

  void ExpectDocumentMoveReloads(bool old_safari,
                                 bool new_safari,
                                 const char* new_origin) {
    ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
    SetSecurityOrigin("https://a.com");
    if (old_safari) {
      PresentSafariIdentity(Media()->GetDocument());
    }
    Media()->GetDocument().body()->AppendChild(Media());
    WaitForPlayer();
    test::RunPendingTasks();

    auto* emptied = MakeGarbageCollected<EventCountingListener>();
    Media()->addEventListener(event_type_names::kEmptied, emptied);
    auto new_page = CreatePageWithSecurityOrigin(
        new_origin, false, true);
    if (new_safari) {
      PresentSafariIdentity(new_page->GetDocument());
    }
    new_page->GetDocument().body()->AppendChild(Media());
    test::RunPendingTasks();

    EXPECT_TRUE(WasPlayerDestroyed());
    EXPECT_EQ(new_page->GetDocument().GetFrame(),
              Media()->LocalFrameForPlayer());
    EXPECT_EQ(emptied->count(), 1);
  }

  test::TaskEnvironment task_environment_;
  CSSDefaultStyleSheets::TestingScope ua_style_sheets_scope_;
  std::unique_ptr<DummyPageHolder> dummy_page_holder_;
  parc_hooks::MoveWebMediaPlayer previous_move_web_media_player_ = nullptr;

 private:
  Persistent<HTMLMediaElement> media_;
  Persistent<FullscreenMockChromeClient> chrome_client_;

  raw_ptr<MockWebMediaPlayer, UnprotectedInRelease | DanglingUntriaged>
      media_player_;
  base::WeakPtr<WebMediaPlayer> media_player_weak_;

  TestMediaPlayerHost media_player_host_;
  mojo::AssociatedReceiver<media::mojom::blink::MediaPlayerHost>
      media_player_host_receiver_{&media_player_host_};
};

INSTANTIATE_TEST_SUITE_P(Audio,
                         ParcMediaElementTest,
                         testing::Values(MediaTestParam::kAudio));
INSTANTIATE_TEST_SUITE_P(Video,
                         ParcMediaElementTest,
                         testing::Values(MediaTestParam::kVideo));

TEST_P(ParcMediaElementTest, SafariIdentityDocumentMoveKeepsPlayer) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  Document& original_document = Media()->GetDocument();
  PresentSafariIdentity(original_document);
  original_document.body()->AppendChild(Media());
  WaitForPlayer();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());

  auto* reload_listener = MakeGarbageCollected<EventCountingListener>();
  for (const AtomicString& type :
       {event_type_names::kAbort, event_type_names::kEmptied,
        event_type_names::kLoadstart, event_type_names::kPause}) {
    Media()->addEventListener(type, reload_listener);
  }

  auto second_page =
      CreatePageWithSecurityOrigin(origin, false);
  PresentSafariIdentity(second_page->GetDocument());
  second_page->GetDocument().body()->AppendChild(Media());
  ASSERT_FALSE(WasPlayerDestroyed());
  test::RunPendingTasks();
  EXPECT_EQ(original_document.GetFrame(), Media()->LocalFrameForPlayer());

  auto third_page =
      CreatePageWithSecurityOrigin(origin, false);
  PresentSafariIdentity(third_page->GetDocument());
  third_page->GetDocument().body()->AppendChild(Media());
  ASSERT_FALSE(WasPlayerDestroyed());
  test::RunPendingTasks();
  EXPECT_EQ(original_document.GetFrame(), Media()->LocalFrameForPlayer());

  original_document.body()->AppendChild(Media());
  ASSERT_FALSE(WasPlayerDestroyed());
  test::RunPendingTasks();
  EXPECT_EQ(original_document.GetFrame(), Media()->LocalFrameForPlayer());
  EXPECT_FALSE(Media()->paused());
  EXPECT_EQ(reload_listener->count(), 0);
}

TEST_P(ParcMediaElementTest, SafariIdentityMovedPlayerBelongsToNewFrame) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  PresentSafariIdentity(Media()->GetDocument());
  Media()->GetDocument().body()->AppendChild(Media());
  WaitForPlayer();
  test::RunPendingTasks();
  ASSERT_TRUE(media_player_host().HasConnectedPlayer());

  auto new_page = CreatePageWithSecurityOrigin(
      origin, false, true);
  Document& new_document = new_page->GetDocument();
  PresentSafariIdentity(new_document);
  TestMediaPlayerHost new_host;
  mojo::AssociatedReceiver<media::mojom::blink::MediaPlayerHost>
      new_host_receiver(&new_host);
  new_document.GetFrame()
      ->GetRemoteNavigationAssociatedInterfaces()
      ->OverrideBinderForTesting(
          media::mojom::blink::MediaPlayerHost::Name_,
          BindRepeating(
              [](mojo::AssociatedReceiver<media::mojom::blink::MediaPlayerHost>*
                     receiver,
                 mojo::ScopedInterfaceEndpointHandle handle) {
                receiver->Bind(mojo::PendingAssociatedReceiver<
                               media::mojom::blink::MediaPlayerHost>(
                    std::move(handle)));
              },
              Unretained(&new_host_receiver)));

  {
    testing::InSequence sequence;
    EXPECT_CALL(*MockMediaPlayer(), ParcMoveToFrame(_)).WillOnce(Return(true));
    EXPECT_CALL(*MockMediaPlayer(), ParcReportStateToClient());
  }
  new_document.body()->AppendChild(Media());
  new_host.WaitForPlayer();
  new_host.observer().WaitUntilReceivedMessage();
  test::RunPendingTasks();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
  EXPECT_FALSE(WasPlayerDestroyed());
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(new_host.HasConnectedPlayer());
  EXPECT_FALSE(media_player_host().HasConnectedPlayer());
  EXPECT_TRUE(new_host.observer().received_remote_playback_metadata(
      media_session::mojom::blink::RemotePlaybackMetadata::New(
          "unknown", "unknown", false, false, String(), false)));
  EXPECT_EQ(new_document.GetFrame(), Media()->LocalFrameForPlayer());

  auto* reload_listener = MakeGarbageCollected<EventCountingListener>();
  for (const AtomicString& type :
       {event_type_names::kAbort, event_type_names::kEmptied,
        event_type_names::kLoadstart, event_type_names::kPause}) {
    Media()->addEventListener(type, reload_listener);
  }
  GetDomWindow()->FrameDestroyed();
  test::RunPendingTasks();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
  EXPECT_FALSE(WasPlayerDestroyed());
  EXPECT_FALSE(Media()->paused());
  EXPECT_EQ(reload_listener->count(), 0);
}

TEST_P(ParcMediaElementTest, ChromeIdentityDocumentMoveReloads) {
  ExpectDocumentMoveReloads(false, false,
                            "https://a.com");
}

TEST_P(ParcMediaElementTest, SafariToChromeIdentityDocumentMoveReloads) {
  ExpectDocumentMoveReloads(true, false,
                            "https://a.com");
}

TEST_P(ParcMediaElementTest, SafariIdentityCrossOriginDocumentMoveReloads) {
  ExpectDocumentMoveReloads(true, true,
                            "https://b.com");
}

TEST_P(ParcMediaElementTest, SafariIdentityMovedElementReloadsWhenFrameGoes) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  PresentSafariIdentity(Media()->GetDocument());
  Media()->GetDocument().body()->AppendChild(Media());
  WaitForPlayer();
  test::RunPendingTasks();

  auto new_page = CreatePageWithSecurityOrigin(
      origin, false, true);
  PresentSafariIdentity(new_page->GetDocument());
  new_page->GetDocument().body()->AppendChild(Media());
  test::RunPendingTasks();
  ASSERT_FALSE(WasPlayerDestroyed());

  auto* emptied_listener = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEmptied, emptied_listener);
  GetDomWindow()->FrameDestroyed();
  EXPECT_TRUE(WasPlayerDestroyed());
  EXPECT_EQ(new_page->GetDocument().GetFrame(), Media()->LocalFrameForPlayer());
  test::RunPendingTasks();
  EXPECT_EQ(emptied_listener->count(), 1);
}

TEST_P(ParcMediaElementTest,
       SafariIdentityMoveOutOfPictureInPictureWindowKeepsPlayer) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(true);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  Document& original_document = Media()->GetDocument();
  PresentSafariIdentity(original_document);
  original_document.domWindow()->set_is_picture_in_picture_window_for_testing(
      true);
  WaitForPlayer();

  auto new_page =
      CreatePageWithSecurityOrigin(origin, false);
  PresentSafariIdentity(new_page->GetDocument());
  new_page->GetDocument().adoptNode(Media(), ASSERT_NO_EXCEPTION);
  EXPECT_FALSE(WasPlayerDestroyed());
  EXPECT_EQ(original_document.GetFrame(), Media()->LocalFrameForPlayer());
}

TEST_P(ParcMediaElementTest, SafariIdentityDeferredLoadMoveUsesNewFrame) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  PresentSafariIdentity(Media()->GetDocument());
  Media()->setAttribute(html_names::kPreloadAttr, AtomicString("none"));
  Media()->GetDocument().body()->AppendChild(Media());
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->GetWebMediaPlayer());
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);

  auto* reload_listener = MakeGarbageCollected<EventCountingListener>();
  for (const AtomicString& type :
       {event_type_names::kAbort, event_type_names::kEmptied,
        event_type_names::kLoadstart}) {
    Media()->addEventListener(type, reload_listener);
  }
  auto new_page = CreatePageWithSecurityOrigin(
      origin, false, true);
  PresentSafariIdentity(new_page->GetDocument());
  new_page->GetDocument().body()->AppendChild(Media());
  test::RunPendingTasks();

  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
  EXPECT_EQ(reload_listener->count(), 0);
  EXPECT_EQ(new_page->GetDocument().GetFrame(), Media()->LocalFrameForPlayer());
}

TEST_P(ParcMediaElementTest, SafariIdentityMoveThroughFramelessDocument) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  SetSecurityOrigin("https://a.com");
  Document& document = Media()->GetDocument();
  PresentSafariIdentity(document);
  document.body()->AppendChild(Media());
  WaitForPlayer();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());

  auto* reload_listener = MakeGarbageCollected<EventCountingListener>();
  for (const AtomicString& type :
       {event_type_names::kAbort, event_type_names::kEmptied,
        event_type_names::kLoadstart, event_type_names::kPause}) {
    Media()->addEventListener(type, reload_listener);
  }
  document.implementation().createHTMLDocument("")->body()->AppendChild(
      Media());
  test::RunPendingTasks();
  EXPECT_FALSE(WasPlayerDestroyed());
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(media_player_host().HasConnectedPlayer());

  document.body()->AppendChild(Media());
  test::RunPendingTasks();
  EXPECT_FALSE(WasPlayerDestroyed());
  EXPECT_FALSE(Media()->paused());
  EXPECT_EQ(document.GetFrame(), Media()->LocalFrameForPlayer());
  EXPECT_TRUE(media_player_host().HasConnectedPlayer());
  EXPECT_EQ(reload_listener->count(), 0);
}

TEST_P(ParcMediaElementTest, SafariIdentityMoveThroughTemplateContent) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  Document& document = Media()->GetDocument();
  PresentSafariIdentity(document);
  document.body()->AppendChild(Media());
  WaitForPlayer();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());

  auto* reload_listener = MakeGarbageCollected<EventCountingListener>();
  for (const AtomicString& type :
       {event_type_names::kAbort, event_type_names::kEmptied,
        event_type_names::kLoadstart}) {
    Media()->addEventListener(type, reload_listener);
  }
  auto* template_element = To<HTMLTemplateElement>(
      document.CreateRawElement(html_names::kTemplateTag));
  template_element->content()->AppendChild(Media());
  test::RunPendingTasks();
  EXPECT_FALSE(WasPlayerDestroyed());
  EXPECT_TRUE(Media()->paused());

  auto new_page =
      CreatePageWithSecurityOrigin(origin, false);
  PresentSafariIdentity(new_page->GetDocument());
  new_page->GetDocument().body()->AppendChild(Media());
  test::RunPendingTasks();
  EXPECT_FALSE(WasPlayerDestroyed());
  EXPECT_EQ(reload_listener->count(), 0);
}

TEST_P(ParcMediaElementTest,
       SafariIdentityDeferredLoadFailsInFramelessDocument) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  SetSecurityOrigin("https://a.com");
  Document& document = Media()->GetDocument();
  PresentSafariIdentity(document);
  Media()->setAttribute(html_names::kPreloadAttr, AtomicString("none"));
  document.body()->AppendChild(Media());
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);

  document.implementation().createHTMLDocument("")->body()->AppendChild(
      Media());
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
  Media()->Play();
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->GetWebMediaPlayer());
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrSrcNotSupported);
}

TEST_P(ParcMediaElementTest, ChromeIdentityMoveIntoFramelessDocumentReloads) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  SetSecurityOrigin("https://a.com");
  Document& document = Media()->GetDocument();
  document.body()->AppendChild(Media());
  WaitForPlayer();
  test::RunPendingTasks();

  auto* emptied = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEmptied, emptied);
  document.implementation().createHTMLDocument("")->body()->AppendChild(
      Media());
  test::RunPendingTasks();
  EXPECT_TRUE(WasPlayerDestroyed());
  EXPECT_EQ(emptied->count(), 1);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrSrcNotSupported);
}

TEST_P(ParcMediaElementTest,
       SafariIdentityPictureInPictureMoveBeforeLoadUsesOpenerFrame) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(true);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  PresentSafariIdentity(Media()->GetDocument());
  auto new_page =
      CreatePageWithSecurityOrigin(origin, true);
  PresentSafariIdentity(new_page->GetDocument());
  LocalFrame* old_frame = Media()->GetDocument().GetFrame();
  new_page->GetDocument().GetFrame()->SetOpener(old_frame);
  new_page->GetDocument().adoptNode(Media(), ASSERT_NO_EXCEPTION);
  EXPECT_EQ(old_frame, Media()->LocalFrameForPlayer());
}

TEST_P(ParcMediaElementTest, SafariIdentityKeptPlayerLearnsFrameVisibility) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  PresentSafariIdentity(Media()->GetDocument());
  dummy_page_holder_->GetFrame().OnFrameVisibilityChangedForMediaPlayback(
      false);
  Media()->GetDocument().body()->AppendChild(Media());
  WaitForPlayer();

  auto new_page =
      CreatePageWithSecurityOrigin(origin, false);
  PresentSafariIdentity(new_page->GetDocument());
  new_page->GetFrame().OnFrameVisibilityChangedForMediaPlayback(
      true);
  EXPECT_CALL(*MockMediaPlayer(), OnFrameHidden());
  new_page->GetDocument().body()->AppendChild(Media());
  EXPECT_FALSE(WasPlayerDestroyed());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
}

TEST_P(ParcMediaElementTest, SafariIdentityKeptPlayerFollowsElementPage) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  Document& original_document = Media()->GetDocument();
  PresentSafariIdentity(original_document);
  original_document.body()->AppendChild(Media());
  WaitForPlayer();
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);

  auto new_page =
      CreatePageWithSecurityOrigin(origin, false);
  PresentSafariIdentity(new_page->GetDocument());
  {
    testing::InSequence sequence;
    EXPECT_CALL(*MockMediaPlayer(),
                ParcSetPageHidden(std::optional<bool>(false)))
        .Times(testing::AtLeast(1));
    EXPECT_CALL(*MockMediaPlayer(),
                ParcSetPageHidden(std::optional<bool>(true)));
    EXPECT_CALL(*MockMediaPlayer(), ParcSetPageHidden(std::optional<bool>()));
  }
  new_page->GetDocument().body()->AppendChild(Media());
  ASSERT_FALSE(WasPlayerDestroyed());
  ASSERT_EQ(original_document.GetFrame(), Media()->LocalFrameForPlayer());

  SetPageVisibility(mojom::blink::PageVisibilityState::kVisible);
  new_page->GetPage().SetVisibilityState(
      mojom::blink::PageVisibilityState::kHiddenButPainting,
      false);
  new_page->GetPage().SetVisibilityState(
      mojom::blink::PageVisibilityState::kHidden, false);

  original_document.body()->AppendChild(Media());
  ASSERT_FALSE(WasPlayerDestroyed());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
}

TEST_P(ParcMediaElementTest,
       SafariIdentityPlayerMadeAfterMoveFollowsElementPage) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(true);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  PresentSafariIdentity(Media()->GetDocument());
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);
  auto new_page =
      CreatePageWithSecurityOrigin(origin, true);
  PresentSafariIdentity(new_page->GetDocument());
  LocalFrame* old_frame = Media()->GetDocument().GetFrame();
  new_page->GetDocument().GetFrame()->SetOpener(old_frame);
  new_page->GetDocument().adoptNode(Media(), ASSERT_NO_EXCEPTION);
  ASSERT_EQ(old_frame, Media()->LocalFrameForPlayer());

  EXPECT_CALL(*MockMediaPlayer(),
              ParcSetPageHidden(std::optional<bool>(false)));
  WaitForPlayer();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
}

TEST_P(ParcMediaElementTest,
       ChromeIdentityPictureInPicturePlayerKeepsOpenerPage) {
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(true);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  WaitForPlayer();
  auto new_page =
      CreatePageWithSecurityOrigin(origin, true);
  new_page->GetDocument().GetFrame()->SetOpener(
      Media()->GetDocument().GetFrame());

  EXPECT_CALL(*MockMediaPlayer(), ParcSetPageHidden(_)).Times(0);
  new_page->GetDocument().adoptNode(Media(), ASSERT_NO_EXCEPTION);
  ASSERT_FALSE(WasPlayerDestroyed());
  new_page->GetPage().SetVisibilityState(
      mojom::blink::PageVisibilityState::kHidden, false);
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
}

constexpr char kParcSafariUserAgent[] =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/27.2 Safari/605.1.15";
constexpr char kParcChromeUserAgent[] =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";

TEST_P(ParcMediaElementTest, ParcSafariCurrentTimeFollowsPlayerWhilePlaying) {
  SetUserAgent(kParcSafariUserAgent);
  double now = 0;
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime())
      .WillRepeatedly(testing::ReturnPointee(&now));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  GetExecutionContext()->GetAgent()->event_loop()->PerformMicrotaskCheckpoint();
  ASSERT_FALSE(Media()->paused());

  now = 0.25;
  EXPECT_EQ(Media()->currentTime(), 0.25);
  now = 0.5;
  EXPECT_EQ(Media()->currentTime(), 0.5);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  now = 0.75;
  EXPECT_EQ(Media()->currentTime(), 0.75);
  now = 1.5;
  EXPECT_EQ(Media()->currentTime(), 1.0);

  now = 0.5;
  Media()->pause();
  now = 0.75;
  EXPECT_EQ(Media()->currentTime(), 0.5);
}

TEST_P(ParcMediaElementTest, ParcSafariHandsPlayerEveryEnabledAudioTrack) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  AudioTrack* second = ParcAddTwoAudioTracks();

  EXPECT_CALL(*MockMediaPlayer(), EnabledAudioTracksChanged(_)).Times(0);
  EXPECT_CALL(*MockMediaPlayer(),
              ParcEnabledAudioTracksChanged(
                  testing::ElementsAre(WebMediaPlayer::TrackId("audio1"),
                                       WebMediaPlayer::TrackId("audio2"))));
  second->setEnabled(true);
  test::RunPendingTasks();
}

TEST_P(ParcMediaElementTest, ParcChromeHandsPlayerOneAudioTrack) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  AudioTrack* second = ParcAddTwoAudioTracks();

  EXPECT_CALL(*MockMediaPlayer(), ParcEnabledAudioTracksChanged(_)).Times(0);
  EXPECT_CALL(*MockMediaPlayer(), EnabledAudioTracksChanged(testing::Optional(
                                      WebMediaPlayer::TrackId("audio1"))));
  second->setEnabled(true);
  test::RunPendingTasks();
}

bool ParcPictureInPictureCardFollowsCues(HTMLMediaElement& media) {
  media.SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  TextTrack* track =
      media.addTextTrack(V8TextTrackKind(V8TextTrackKind::Enum::kCaptions),
                         g_empty_atom, g_empty_atom, ASSERT_NO_EXCEPTION);
  track->setMode(V8TextTrackMode(V8TextTrackMode::Enum::kShowing));
  test::RunPendingTasks();
  To<HTMLVideoElement>(media).OnEnteredPictureInPicture();
  bool cues = false;
  for (Node* child = media.UserAgentShadowRoot()->firstChild(); child;
       child = child->nextSibling()) {
    if (child->IsPictureInPictureInterstitial()) {
      Node* next = child->nextSibling();
      EXPECT_TRUE(cues || (next && next->IsTextTrackContainer()));
      return cues;
    }
    cues |= child->IsTextTrackContainer();
  }
  ADD_FAILURE() << "No picture in picture interstitial";
  return false;
}

TEST_P(ParcMediaElementTest, ParcSafariPictureInPictureCardCoversCues) {
  if (GetParam() != MediaTestParam::kVideo) {
    return;
  }
  SetUserAgent(kParcSafariUserAgent);
  EXPECT_TRUE(ParcPictureInPictureCardFollowsCues(*Media()));
}

TEST_P(ParcMediaElementTest, ParcChromePictureInPictureCuesOverCard) {
  if (GetParam() != MediaTestParam::kVideo) {
    return;
  }
  SetUserAgent(kParcChromeUserAgent);
  EXPECT_FALSE(ParcPictureInPictureCardFollowsCues(*Media()));
}

TEST_P(ParcMediaElementTest, ParcChromeCurrentTimeHeldUntilMicrotask) {
  SetUserAgent(kParcChromeUserAgent);
  double now = 0;
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime())
      .WillRepeatedly(testing::ReturnPointee(&now));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  GetExecutionContext()->GetAgent()->event_loop()->PerformMicrotaskCheckpoint();
  ASSERT_FALSE(Media()->paused());

  now = 0.25;
  EXPECT_EQ(Media()->currentTime(), 0.25);
  now = 0.5;
  EXPECT_EQ(Media()->currentTime(), 0.25);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  GetExecutionContext()->GetAgent()->event_loop()->PerformMicrotaskCheckpoint();
  now = 0.75;
  EXPECT_EQ(Media()->currentTime(), 0.5);
}

TEST_P(ParcMediaElementTest, ParcSafariAcceptsAnyPlaybackRate) {
  SetUserAgent(kParcSafariUserAgent);
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(0.5));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  test::RunPendingTasks();
  ASSERT_TRUE(PotentiallyPlaying());
  auto* ratechange = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kRatechange, ratechange);

  {
    testing::InSequence sequence;
    EXPECT_CALL(*MockMediaPlayer(), SetRate(32.0));
    EXPECT_CALL(*MockMediaPlayer(), SetRate(-1.0));
    EXPECT_CALL(*MockMediaPlayer(), SetRate(0.01));
  }
  for (const double rate : {32.0, -1.0, 0.01}) {
    DummyExceptionStateForTesting exception_state;
    Media()->setPlaybackRate(rate, exception_state);
    EXPECT_FALSE(exception_state.HadException());
    EXPECT_EQ(Media()->playbackRate(), rate);
  }
  EXPECT_TRUE(PotentiallyPlaying());
  Media()->setDefaultPlaybackRate(-2);
  EXPECT_EQ(Media()->defaultPlaybackRate(), -2.0);
  test::RunPendingTasks();
  EXPECT_EQ(ratechange->count(), 4);
}

TEST_P(ParcMediaElementTest, ParcChromeRejectsUnsupportedPlaybackRate) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  test::RunPendingTasks();
  auto* ratechange = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kRatechange, ratechange);

  EXPECT_CALL(*MockMediaPlayer(), SetRate(_)).Times(0);
  for (const double rate : {32.0, -1.0, 0.01}) {
    DummyExceptionStateForTesting exception_state;
    Media()->setPlaybackRate(rate, exception_state);
    EXPECT_EQ(exception_state.CodeAs<DOMExceptionCode>(),
              DOMExceptionCode::kNotSupportedError);
    EXPECT_EQ(Media()->playbackRate(), 1.0);
  }
  Media()->setDefaultPlaybackRate(-2);
  EXPECT_EQ(Media()->defaultPlaybackRate(), 1.0);
  test::RunPendingTasks();
  EXPECT_EQ(ratechange->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariNotEndedAtRateZero) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(1.0));
  EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
  EXPECT_TRUE(Media()->ended());

  Media()->setPlaybackRate(0);
  EXPECT_FALSE(Media()->ended());
}

TEST_P(ParcMediaElementTest, ParcChromeEndedAtRateZero) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(1.0));
  EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
  EXPECT_TRUE(Media()->ended());

  Media()->setPlaybackRate(0);
  EXPECT_TRUE(Media()->ended());
}

TEST_P(ParcMediaElementTest, ParcSafariPlayAtEndAtRateZeroDoesNotSeek) {
  SetUserAgent(kParcSafariUserAgent);
  ASSERT_NO_FATAL_FAILURE(ParcStopAtEndAtRateZero());

  EXPECT_CALL(*MockMediaPlayer(), Seek(_)).Times(0);
  Media()->Play();
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->paused());
  EXPECT_FALSE(Media()->seeking());
  EXPECT_TRUE(CouldPlayIfEnoughData());
}

TEST_P(ParcMediaElementTest, ParcChromePlayAtEndAtRateZeroSeeksToStart) {
  SetUserAgent(kParcChromeUserAgent);
  ASSERT_NO_FATAL_FAILURE(ParcStopAtEndAtRateZero());

  EXPECT_CALL(*MockMediaPlayer(), Seek(0.0));
  Media()->Play();
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(Media()->seeking());
}

TEST_P(ParcMediaElementTest, ParcSafariNoEndedAtEndAtRateZero) {
  SetUserAgent(kParcSafariUserAgent);
  ASSERT_NO_FATAL_FAILURE(ParcStopAtEndAtRateZero());
  Media()->Play();
  test::RunPendingTasks();
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPause, pause);

  TimeChanged();
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->paused());
  EXPECT_EQ(ended->count(), 0);
  EXPECT_EQ(pause->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariRateAboveZeroAtEndEnds) {
  SetUserAgent(kParcSafariUserAgent);
  ASSERT_NO_FATAL_FAILURE(ParcStopAtEndAtRateZero());
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);

  Media()->setPlaybackRate(1);
  EXPECT_FALSE(Media()->paused());
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());
  EXPECT_TRUE(Media()->ended());
  EXPECT_EQ(ended->count(), 1);
}

TEST_P(ParcMediaElementTest, ParcSafariRateAboveZeroAtEndLoops) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetBooleanAttribute(html_names::kLoopAttr, true);
  ASSERT_NO_FATAL_FAILURE(ParcStopAtEndAtRateZero());
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());

  EXPECT_CALL(*MockMediaPlayer(), Seek(0.0));
  Media()->setPlaybackRate(1);
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(Media()->seeking());
}

TEST_P(ParcMediaElementTest, ParcChromeEndedAtEndAtRateZero) {
  SetUserAgent(kParcChromeUserAgent);
  double now = 0.5;
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime())
      .WillRepeatedly(testing::ReturnPointee(&now));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->setPlaybackRate(0);
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);

  now = 1.0;
  EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());
  EXPECT_EQ(ended->count(), 1);
}

TEST_P(ParcMediaElementTest,
       ParcLoadKeepsSafariDefaultRateAfterIdentityChange) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->setDefaultPlaybackRate(32);
  SetUserAgent(kParcChromeUserAgent);

  EXPECT_CALL(*MockMediaPlayer(), Paused()).WillRepeatedly(Return(true));
  EXPECT_CALL(*MockMediaPlayer(), SetRate(32.0)).Times(0);
  EXPECT_CALL(*MockMediaPlayer(), SetRate(HTMLMediaElement::kMaxPlaybackRate))
      .Times(testing::AtLeast(1));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  EXPECT_EQ(Media()->playbackRate(), 32.0);
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_TRUE(PotentiallyPlaying());
}

TEST_P(ParcMediaElementTest, ParcSafariBackwardPlaybackEndsAtStart) {
  SetUserAgent(kParcSafariUserAgent);
  double now = 0.5;
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime())
      .WillRepeatedly(testing::ReturnPointee(&now));
  WebTimeRanges seekable;
  seekable.Add(0, 1.0);
  EXPECT_CALL(*MockMediaPlayer(), Seekable()).WillRepeatedly(Return(seekable));
  Media()->SetBooleanAttribute(html_names::kLoopAttr, true);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  DummyExceptionStateForTesting exception_state;
  Media()->setPlaybackRate(-1, exception_state);
  ASSERT_FALSE(exception_state.HadException());
  test::RunPendingTasks();
  ASSERT_TRUE(PotentiallyPlaying());
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);

  EXPECT_CALL(*MockMediaPlayer(), Seek(_)).Times(0);
  now = 0;
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());
  EXPECT_FALSE(Media()->ended());
  EXPECT_EQ(ended->count(), 1);
}

TEST_P(ParcMediaElementTest, ParcSafariMutedAttributeLatchesOnInsertion) {
  ScopedMediaElementMutedDefaultStateForTest scoped_muted_default(false);
  SetUserAgent(kParcSafariUserAgent);
  auto* volumechange = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kVolumechange, volumechange);

  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  EXPECT_TRUE(Media()->muted());
  Media()->removeAttribute(html_names::kMutedAttr);
  EXPECT_FALSE(Media()->muted());
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  EXPECT_TRUE(Media()->muted());
  Media()->GetDocument().body()->AppendChild(Media());
  Media()->removeAttribute(html_names::kMutedAttr);
  EXPECT_TRUE(Media()->muted());

  EXPECT_CALL(*MockMediaPlayer(), SetVolume(testing::Ne(0.0))).Times(0);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_TRUE(Media()->muted());
  EXPECT_EQ(volumechange->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcChromeCreatedMutedAttributeLatchesInSafari) {
  ScopedMediaElementMutedDefaultStateForTest scoped_muted_default(false);
  SetUserAgent(kParcChromeUserAgent);
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  EXPECT_FALSE(Media()->muted());
  auto* volumechange = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kVolumechange, volumechange);

  auto destination = CreatePageWithSecurityOrigin("https://example.com", false);
  PresentSafariIdentity(destination->GetDocument());
  destination->GetDocument().adoptNode(Media(), ASSERT_NO_EXCEPTION);
  EXPECT_FALSE(Media()->isConnected());
  EXPECT_TRUE(Media()->muted());
  destination->GetDocument().body()->AppendChild(Media());
  Media()->removeAttribute(html_names::kMutedAttr);
  EXPECT_TRUE(Media()->muted());
  test::RunPendingTasks();
  EXPECT_EQ(volumechange->count(), 0);
}

TEST_P(ParcMediaElementTest,
       ParcSafariCreatedMutedAttributeStaysChromeInChrome) {
  ScopedMediaElementMutedDefaultStateForTest scoped_muted_default(false);
  SetUserAgent(kParcSafariUserAgent);
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  EXPECT_TRUE(Media()->muted());

  auto destination = CreatePageWithSecurityOrigin("https://example.com", false);
  static_cast<WebMediaStubLocalFrameClient*>(destination->GetFrame().Client())
      ->set_user_agent(String(kParcChromeUserAgent));
  destination->GetDocument().body()->AppendChild(Media());
  EXPECT_EQ(&Media()->GetDocument(), &destination->GetDocument());
  EXPECT_FALSE(Media()->muted());
  Media()->removeAttribute(html_names::kMutedAttr);
  EXPECT_FALSE(Media()->muted());
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  EXPECT_FALSE(Media()->muted());
}

TEST_P(ParcMediaElementTest,
       ParcMutedAttributeLatchedBeforeDocumentMoveIsKept) {
  ScopedMediaElementMutedDefaultStateForTest scoped_muted_default(false);
  SetUserAgent(kParcSafariUserAgent);
  Document& original = Media()->GetDocument();
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  original.body()->AppendChild(Media());
  EXPECT_TRUE(Media()->muted());

  auto destination = CreatePageWithSecurityOrigin("https://example.com", false);
  static_cast<WebMediaStubLocalFrameClient*>(destination->GetFrame().Client())
      ->set_user_agent(String(kParcChromeUserAgent));
  destination->GetDocument().body()->AppendChild(Media());
  Media()->removeAttribute(html_names::kMutedAttr);
  EXPECT_TRUE(Media()->muted());
  original.body()->AppendChild(Media());
  EXPECT_TRUE(Media()->muted());

  Media()->setMuted(false);
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  destination->GetDocument().body()->AppendChild(Media());
  original.body()->AppendChild(Media());
  EXPECT_FALSE(Media()->muted());
}

TEST_P(ParcMediaElementTest, ParcSafariMutedAttributeLatchesOnLoad) {
  ScopedMediaElementMutedDefaultStateForTest scoped_muted_default(false);
  SetUserAgent(kParcSafariUserAgent);
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);

  EXPECT_CALL(*MockMediaPlayer(), SetVolume(testing::Ne(0.0))).Times(0);
  EXPECT_CALL(*MockMediaPlayer(), SetVolume(0.0)).Times(testing::AtLeast(1));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  Media()->removeAttribute(html_names::kMutedAttr);
  Media()->GetDocument().body()->AppendChild(Media());
  EXPECT_TRUE(Media()->muted());
}

TEST_P(ParcMediaElementTest, ParcSafariScriptMutedBeforeAttributeIsKept) {
  ScopedMediaElementMutedDefaultStateForTest scoped_muted_default(false);
  SetUserAgent(kParcSafariUserAgent);
  auto* volumechange = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kVolumechange, volumechange);

  Media()->setMuted(false);
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  Media()->GetDocument().body()->AppendChild(Media());
  EXPECT_FALSE(Media()->muted());
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->muted());
  EXPECT_EQ(volumechange->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariVolumechangeBeforeMutedIsLatched) {
  ScopedMediaElementMutedDefaultStateForTest scoped_muted_default(false);
  SetUserAgent(kParcSafariUserAgent);
  auto* volumechange = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kVolumechange, volumechange);
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  Media()->setMuted(true);
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->muted());
  EXPECT_EQ(volumechange->count(), 1);

  auto* other = MakeGarbageCollected<HTMLAudioElement>(Media()->GetDocument());
  auto* other_volumechange = MakeGarbageCollected<EventCountingListener>();
  other->addEventListener(event_type_names::kVolumechange, other_volumechange);
  other->setAttribute(html_names::kMutedAttr, g_empty_atom);
  other->setMuted(false);
  test::RunPendingTasks();
  EXPECT_FALSE(other->muted());
  EXPECT_EQ(other_volumechange->count(), 0);
  other->GetDocument().body()->AppendChild(other);
  EXPECT_FALSE(other->muted());
}

TEST_P(ParcMediaElementTest, ParcChromeMutedAttributeOnlyFromParser) {
  ScopedMediaElementMutedDefaultStateForTest scoped_muted_default(false);
  SetUserAgent(kParcChromeUserAgent);
  auto* volumechange = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kVolumechange, volumechange);
  Media()->setAttribute(html_names::kMutedAttr, g_empty_atom);
  EXPECT_FALSE(Media()->muted());
  Media()->GetDocument().body()->AppendChild(Media());
  EXPECT_FALSE(Media()->muted());
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->muted());

  Media()->setMuted(true);
  Media()->setMuted(true);
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->muted());
  EXPECT_EQ(volumechange->count(), 1);
}

class EventOrderListener final : public NativeEventListener {
 public:
  void Invoke(ExecutionContext*, Event* event) override {
    types_.push_back(event->type().Utf8());
  }
  std::vector<std::string> Only(std::initializer_list<std::string> types) {
    std::vector<std::string> result;
    for (const std::string& type : types_) {
      if (std::ranges::find(types, type) != types.end()) {
        result.push_back(type);
      }
    }
    return result;
  }

 private:
  std::vector<std::string> types_;
};

class ParcMediaElementSeekTest : public ParcMediaElementTest {
 protected:
  void Prepare(const char* user_agent,
               double start,
               double end,
               HTMLMediaElement::ReadyState ready_state =
                   HTMLMediaElement::kHaveEnoughData,
               double duration = 10.0) {
    SetUserAgent(user_agent);
    WebTimeRanges seekable;
    if (end > start) {
      seekable.Add(start, end);
    }
    EXPECT_CALL(*MockMediaPlayer(), Seekable).WillRepeatedly(Return(seekable));
    EXPECT_CALL(*MockMediaPlayer(), Duration).WillRepeatedly(Return(duration));
    EXPECT_CALL(*MockMediaPlayer(), Seek(_))
        .WillRepeatedly([this](double time) { seeks_.push_back(time); });
    Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
    test::RunPendingTasks();
    SetReadyState(ready_state);
    RunTasks();
    events_ = MakeGarbageCollected<EventOrderListener>();
    for (const AtomicString& type :
         {event_type_names::kSeeking, event_type_names::kSeeked,
          event_type_names::kTimeupdate, event_type_names::kEnded,
          event_type_names::kPlaying, event_type_names::kPlay,
          event_type_names::kPause}) {
      Media()->addEventListener(type, events_);
    }
  }

  void SetCurrentTime(double time) {
    Media()->setCurrentTimeForBindings(time, ASSERT_NO_EXCEPTION);
  }

  void RunTasks() { test::RunPendingTasks(); }

  std::vector<std::string> Events() {
    return events_->Only(
        {"seeking", "seeked", "timeupdate", "ended", "playing"});
  }

  std::vector<double> seeks_;
  Persistent<EventOrderListener> events_;
};

INSTANTIATE_TEST_SUITE_P(Video,
                         ParcMediaElementSeekTest,
                         testing::Values(MediaTestParam::kVideo));

TEST_P(ParcMediaElementSeekTest, ParcSafariSeekContinuesInTask) {
  Prepare(kParcSafariUserAgent, 2, 8);
  SetCurrentTime(20);
  EXPECT_TRUE(Media()->seeking());
  EXPECT_EQ(Media()->currentTime(), 10);
  SetCurrentTime(1);
  EXPECT_EQ(Media()->currentTime(), 1);
  EXPECT_TRUE(seeks_.empty());

  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(2));
  EXPECT_EQ(Media()->currentTime(), 2);
  EXPECT_TRUE(Media()->seeking());
  EXPECT_THAT(Events(), testing::ElementsAre("seeking"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariReplacedSeekKeepsItsStart) {
  Prepare(kParcSafariUserAgent, 0, 10);
  SetCurrentTime(5);
  SetCurrentTime(0);
  RunTasks();
  EXPECT_TRUE(seeks_.empty());
  EXPECT_FALSE(Media()->seeking());
  EXPECT_THAT(Events(),
              testing::ElementsAre("seeking", "timeupdate", "seeked"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariNearestTieGoesToEarliest) {
  Prepare(kParcSafariUserAgent, 0, 10);
  WebTimeRanges seekable;
  seekable.Add(0, 2);
  seekable.Add(8, 10);
  EXPECT_CALL(*MockMediaPlayer(), Seekable).WillRepeatedly(Return(seekable));
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(9.0));
  SetCurrentTime(9);
  RunTasks();
  TimeChanged();
  ASSERT_EQ(Media()->currentTime(), 9);
  SetCurrentTime(5);
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(9, 2));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariEarlierSeekFinishesFirst) {
  Prepare(kParcSafariUserAgent, 0, 10);
  SetCurrentTime(3);
  RunTasks();
  SetCurrentTime(6);
  TimeChanged();
  EXPECT_FALSE(Media()->seeking());
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(3, 6));
  EXPECT_TRUE(Media()->seeking());
  EXPECT_THAT(Events(), testing::ElementsAre("seeking", "timeupdate", "seeked",
                                             "seeking"));
}

TEST_P(ParcMediaElementSeekTest, ParcChromeSeekRunsAtOnce) {
  Prepare(kParcChromeUserAgent, 2, 8);
  SetCurrentTime(20);
  EXPECT_EQ(Media()->currentTime(), 8);
  SetCurrentTime(1);
  EXPECT_THAT(seeks_, testing::ElementsAre(8, 2));
  RunTasks();
  EXPECT_THAT(Events(), testing::ElementsAre("seeking", "seeking"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariFastSeekContinuesInTask) {
  Prepare(kParcSafariUserAgent, 0, 10);
  testing::MockFunction<void()> task;
  {
    testing::InSequence sequence;
    EXPECT_CALL(task, Call());
    EXPECT_CALL(*MockMediaPlayer(), ParcFastSeek(5.0, 5.0));
  }
  Media()->fastSeek(5);
  EXPECT_EQ(Media()->currentTime(), 5);
  task.Call();
  RunTasks();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
}

TEST_P(ParcMediaElementSeekTest, ParcSafariSeekToCurrentTimeSkipsPlayer) {
  Prepare(kParcSafariUserAgent, 0, 10);
  SetCurrentTime(0);
  RunTasks();
  EXPECT_TRUE(seeks_.empty());
  EXPECT_FALSE(Media()->seeking());
  EXPECT_THAT(Events(),
              testing::ElementsAre("seeking", "timeupdate", "seeked"));
}

TEST_P(ParcMediaElementSeekTest, ParcChromeSeekToCurrentTimeSeeksPlayer) {
  Prepare(kParcChromeUserAgent, 0, 10);
  SetCurrentTime(0);
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(0));
  EXPECT_TRUE(Media()->seeking());
  EXPECT_THAT(Events(), testing::ElementsAre("seeking"));
}

TEST_P(ParcMediaElementSeekTest,
       ParcSafariCurrentTimeSeekAtRateZeroKeepsEndedLatch) {
  Prepare(kParcSafariUserAgent, 0, 10);
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(10.0));
  SetCurrentTime(10);
  RunTasks();
  TimeChanged();
  RunTasks();
  ASSERT_EQ(Media()->currentTime(), 10);
  ASSERT_THAT(events_->Only({"ended"}), testing::ElementsAre("ended"));
  const auto initial_seeks = seeks_.size();

  for (double target : {10.0, 20.0}) {
    Media()->setPlaybackRate(0);
    Media()->Play();
    RunTasks();
    ASSERT_FALSE(Media()->paused());
    ASSERT_FALSE(Media()->ended());
    const auto initial_events = Events().size();
    SetCurrentTime(target);
    ASSERT_TRUE(Media()->seeking());
    RunTasks();
    EXPECT_FALSE(Media()->seeking());
    EXPECT_EQ(seeks_.size(), initial_seeks);
    auto events = Events();
    EXPECT_THAT(
        std::vector<std::string>(events.begin() + initial_events, events.end()),
        testing::ElementsAre("seeking", "timeupdate", "seeked"));
    Media()->setPlaybackRate(1);
    RunTasks();
    EXPECT_TRUE(Media()->paused());
    EXPECT_THAT(events_->Only({"ended"}), testing::ElementsAre("ended"));
  }
}

TEST_P(ParcMediaElementSeekTest,
       ParcChromeCurrentTimeSeekAtEndStillSeeksAndEndsAgain) {
  Prepare(kParcChromeUserAgent, 0, 10);
  EXPECT_CALL(*MockMediaPlayer(), IsEnded).WillRepeatedly(Return(true));
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(10.0));
  SetCurrentTime(10);
  TimeChanged();
  RunTasks();
  ASSERT_THAT(events_->Only({"ended"}), testing::ElementsAre("ended"));
  const auto initial_seeks = seeks_.size();
  SetCurrentTime(10);
  EXPECT_EQ(seeks_.size(), initial_seeks + 1);
  TimeChanged();
  RunTasks();
  EXPECT_FALSE(Media()->seeking());
  EXPECT_THAT(events_->Only({"ended"}), testing::ElementsAre("ended", "ended"));
}

class SeekableMediaSourceAttachment final : public StubMediaSourceAttachment {
 public:
  WebTimeRanges SeekableInternal(MediaSourceTracer*) const override {
    WebTimeRanges seekable;
    seekable.Add(0, 10);
    return seekable;
  }
};

TEST_P(ParcMediaElementSeekTest,
       ParcSafariSeekToCurrentTimeWithMediaSourceSeeksPlayer) {
  Prepare(kParcSafariUserAgent, 0, 0);
  SetMediaSourceAttachment(
      base::MakeRefCounted<SeekableMediaSourceAttachment>());
  SetCurrentTime(0);
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(0));
  EXPECT_THAT(Events(), testing::ElementsAre("seeking"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariSeekWithNothingSeekable) {
  Prepare(kParcSafariUserAgent, 0, 0);
  SetCurrentTime(0);
  RunTasks();
  EXPECT_THAT(Events(),
              testing::ElementsAre("seeking", "timeupdate", "seeked"));
  SetCurrentTime(5);
  EXPECT_TRUE(Media()->seeking());
  RunTasks();
  EXPECT_FALSE(Media()->seeking());
  EXPECT_EQ(Events().size(), 3u);
  EXPECT_TRUE(seeks_.empty());
}

TEST_P(ParcMediaElementSeekTest, ParcChromeSeekWithNothingSeekable) {
  Prepare(kParcChromeUserAgent, 0, 0);
  SetCurrentTime(0);
  RunTasks();
  EXPECT_FALSE(Media()->seeking());
  EXPECT_TRUE(Events().empty());
  EXPECT_TRUE(seeks_.empty());
}

TEST_P(ParcMediaElementSeekTest, ParcSafariEndedOnceUntilPlaybackLeaves) {
  Prepare(kParcSafariUserAgent, 0, 10);
  EXPECT_CALL(*MockMediaPlayer(), IsEnded).WillRepeatedly(Return(true));
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(10.0));
  TimeChanged();
  ASSERT_EQ(Media()->currentTime(), 0);
  SetCurrentTime(10);
  RunTasks();
  TimeChanged();
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(10));
  EXPECT_THAT(events_->Only({"ended"}), testing::ElementsAre("ended"));

  EXPECT_CALL(*MockMediaPlayer(), IsEnded).WillRepeatedly(Return(false));
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(5.0));
  SetCurrentTime(5);
  RunTasks();
  TimeChanged();
  EXPECT_CALL(*MockMediaPlayer(), IsEnded).WillRepeatedly(Return(true));
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(10.0));
  SetCurrentTime(10);
  RunTasks();
  TimeChanged();
  RunTasks();
  EXPECT_THAT(events_->Only({"ended"}), testing::ElementsAre("ended", "ended"));
}

TEST_P(ParcMediaElementSeekTest, ParcChromeEndedAfterEachSeekToTheEnd) {
  Prepare(kParcChromeUserAgent, 0, 10);
  EXPECT_CALL(*MockMediaPlayer(), IsEnded).WillRepeatedly(Return(true));
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(10.0));
  TimeChanged();
  SetCurrentTime(10);
  TimeChanged();
  RunTasks();
  EXPECT_THAT(events_->Only({"ended"}), testing::ElementsAre("ended", "ended"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariPlayingWaitsForSeeked) {
  Prepare(kParcSafariUserAgent, 0, 10, HTMLMediaElement::kHaveCurrentData);
  Media()->Play();
  RunTasks();
  SetCurrentTime(5);
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(5));
  EXPECT_THAT(events_->Only({"seeking", "seeked", "playing"}),
              testing::ElementsAre("seeking"));

  TimeChanged();
  RunTasks();
  EXPECT_THAT(events_->Only({"seeking", "seeked", "playing"}),
              testing::ElementsAre("seeking", "seeked", "playing"));
}

TEST_P(ParcMediaElementSeekTest, ParcChromeReadyStateFinishesSeek) {
  Prepare(kParcChromeUserAgent, 0, 10, HTMLMediaElement::kHaveCurrentData);
  Media()->Play();
  RunTasks();
  SetCurrentTime(5);
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  RunTasks();
  EXPECT_THAT(events_->Only({"seeking", "seeked", "playing"}),
              testing::ElementsAre("seeking", "seeked", "playing"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariKeptReadyStateChangeDoesNotEndSeek) {
  Prepare(kParcSafariUserAgent, 0, 10, HTMLMediaElement::kHaveFutureData);
  SetCurrentTime(5);
  RunTasks();
  ASSERT_THAT(seeks_, testing::ElementsAre(5));
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  RunTasks();
  EXPECT_TRUE(Media()->seeking());
  EXPECT_THAT(events_->Only({"seeking", "seeked"}),
              testing::ElementsAre("seeking"));

  TimeChanged();
  RunTasks();
  EXPECT_FALSE(Media()->seeking());
  EXPECT_THAT(events_->Only({"seeking", "seeked"}),
              testing::ElementsAre("seeking", "seeked"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariLoweredReadyStateRiseEndsSeek) {
  Prepare(kParcSafariUserAgent, 0, 10, HTMLMediaElement::kHaveFutureData);
  SetCurrentTime(5);
  RunTasks();
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  EXPECT_TRUE(Media()->seeking());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_FALSE(Media()->seeking());
  RunTasks();
  EXPECT_THAT(events_->Only({"seeking", "seeked"}),
              testing::ElementsAre("seeking", "seeked"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariSeekPreparesToPlay) {
  Media()->setAttribute(html_names::kPreloadAttr, AtomicString("metadata"));
  Prepare(kParcSafariUserAgent, 0, 10, HTMLMediaElement::kHaveMetadata);
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(_)).Times(AnyNumber());
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadAuto));
  SetCurrentTime(5);
  RunTasks();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
}

TEST_P(ParcMediaElementSeekTest, ParcSafariSeekWithFutureDataKeepsPreload) {
  Media()->setAttribute(html_names::kPreloadAttr, AtomicString("metadata"));
  Prepare(kParcSafariUserAgent, 0, 10, HTMLMediaElement::kHaveFutureData,
          std::numeric_limits<double>::infinity());
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(_)).Times(AnyNumber());
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadAuto))
      .Times(0);
  SetCurrentTime(5);
  RunTasks();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
  EXPECT_EQ(WebMediaPlayer::kPreloadMetaData, Media()->EffectivePreloadType());
}

TEST_P(ParcMediaElementSeekTest,
       ParcSafariSeekAtPreloadMetadataPreparesWhateverBuffered) {
  Media()->setAttribute(html_names::kPreloadAttr, AtomicString("metadata"));
  Prepare(kParcSafariUserAgent, 0, 10, HTMLMediaElement::kHaveEnoughData);
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(_)).Times(AnyNumber());
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadAuto))
      .Times(testing::AtLeast(1));
  SetCurrentTime(5);
  RunTasks();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
  EXPECT_EQ(WebMediaPlayer::kPreloadAuto, Media()->EffectivePreloadType());
}

TEST_P(ParcMediaElementSeekTest, ParcChromeSeekKeepsPreload) {
  Media()->setAttribute(html_names::kPreloadAttr, AtomicString("metadata"));
  Prepare(kParcChromeUserAgent, 0, 10, HTMLMediaElement::kHaveMetadata);
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(_)).Times(AnyNumber());
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadAuto))
      .Times(0);
  SetCurrentTime(5);
  RunTasks();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
}

TEST_P(ParcMediaElementSeekTest, ParcSafariPlaybackControlsScrubIsSilent) {
  using Action = media_session::mojom::blink::PlaybackControlsAction;
  Prepare(kParcSafariUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  EXPECT_CALL(*MockMediaPlayer(),
              Pause(WebMediaPlayer::PauseReason::kPauseRequestedInternally));
  PlaybackControls(Action::kBeginScrubbing);
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(PlaybackControlsPausedInternally());
  PlaybackControls(Action::kSeekTo, 3);
  PlaybackControls(Action::kSeekTo, 4);
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(4));
  EXPECT_FALSE(ParcRemoteScrubEndsIn());
  TimeChanged();
  EXPECT_CALL(*MockMediaPlayer(), Paused()).WillRepeatedly(Return(true));
  EXPECT_CALL(*MockMediaPlayer(), Play());
  PlaybackControls(Action::kEndScrubbing);
  RunTasks();
  EXPECT_FALSE(Media()->paused());
  EXPECT_FALSE(PlaybackControlsPausedInternally());
  EXPECT_THAT(events_->Only({"play", "playing", "pause", "seeking", "seeked"}),
              testing::ElementsAre("play", "playing", "seeking", "seeked"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariPlaybackControlsAtEndStayPaused) {
  using Action = media_session::mojom::blink::PlaybackControlsAction;
  Prepare(kParcSafariUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(10.0));
  ASSERT_FALSE(Media()->paused());
  PlaybackControls(Action::kBeginScrubbing);
  EXPECT_TRUE(Media()->paused());
  EXPECT_FALSE(PlaybackControlsPausedInternally());
  PlaybackControls(Action::kSeekTo, 3);
  RunTasks();
  TimeChanged();
  PlaybackControls(Action::kEndScrubbing);
  RunTasks();
  EXPECT_TRUE(Media()->paused());
  EXPECT_THAT(events_->Only({"play", "playing", "pause"}),
              testing::ElementsAre("play", "playing", "pause"));
}

TEST_P(ParcMediaElementSeekTest,
       ParcSafariToolbarDragDoesNotOverridePagePause) {
  using Action = media_session::mojom::blink::PlaybackControlsAction;
  Prepare(kParcSafariUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  PlaybackControls(Action::kPauseForDragging);
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(PlaybackControlsPausedInternally());
  Media()->pause();
  PlaybackControls(Action::kSeekTo, 3);
  RunTasks();
  TimeChanged();
  PlaybackControls(Action::kResumeForDragging);
  RunTasks();
  EXPECT_TRUE(Media()->paused());
  EXPECT_FALSE(PlaybackControlsPausedInternally());
  EXPECT_THAT(events_->Only({"play", "playing", "pause"}),
              testing::ElementsAre("play", "playing", "pause"));
}

TEST_P(ParcMediaElementSeekTest, ParcChromePlaybackControlsKeepLegacyBehavior) {
  using Action = media_session::mojom::blink::PlaybackControlsAction;
  Prepare(kParcChromeUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  PlaybackControls(Action::kBeginScrubbing);
  PlaybackControls(Action::kSeekTo, 3);
  EXPECT_FALSE(PlaybackControlsPausedInternally());
  EXPECT_THAT(seeks_, testing::ElementsAre(3));
  EXPECT_FALSE(Media()->paused());
  PlaybackControls(Action::kPauseForDragging);
  EXPECT_TRUE(Media()->paused());
  PlaybackControls(Action::kResumeForDragging);
  RunTasks();
  EXPECT_FALSE(Media()->paused());
}

TEST_P(ParcMediaElementSeekTest, ParcSafariRemoteScrubPausesUntilSeeked) {
  Prepare(kParcSafariUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  RequestSeekTo(3);
  EXPECT_TRUE(Media()->paused());
  EXPECT_TRUE(seeks_.empty());
  RequestSeekTo(4);
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(4));
  EXPECT_TRUE(Media()->paused());

  TimeChanged();
  RunTasks();
  EXPECT_FALSE(Media()->paused());
  EXPECT_THAT(events_->Only({"play", "playing", "pause", "seeking", "seeked"}),
              testing::ElementsAre("play", "playing", "pause", "seeking",
                                   "seeked", "play", "playing"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariRemoteScrubPlayingOnceAfterClimb) {
  Prepare(kParcSafariUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  RequestSeekTo(3);
  RunTasks();
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  RunTasks();
  EXPECT_FALSE(Media()->seeking());
  EXPECT_FALSE(Media()->paused());
  EXPECT_THAT(events_->Only({"play", "playing", "pause", "seeking", "seeked"}),
              testing::ElementsAre("play", "playing", "pause", "seeking",
                                   "seeked", "play", "playing"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariRemoteScrubEndsAfterHalfSecond) {
  static thread_local base::TimeTicks mock_time_ticks;
  mock_time_ticks = base::TimeTicks::Now();
  base::subtle::ScopedTimeClockOverrides time_override(
      nullptr, []() { return mock_time_ticks; }, nullptr);
  Prepare(kParcSafariUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  RequestSeekTo(3);
  EXPECT_EQ(ParcRemoteScrubEndsIn(), base::Milliseconds(500));
  RunTasks();
  TimeChanged();
  RunTasks();
  ASSERT_FALSE(Media()->paused());

  mock_time_ticks += base::Milliseconds(300);
  EXPECT_EQ(ParcRemoteScrubEndsIn(), base::Milliseconds(200));
  RequestSeekTo(5);
  EXPECT_FALSE(Media()->paused());
  EXPECT_EQ(ParcRemoteScrubEndsIn(), base::Milliseconds(500));

  EndParcRemoteScrub();
  RequestSeekTo(6);
  EXPECT_TRUE(Media()->paused());
}

TEST_P(ParcMediaElementSeekTest, ParcSafariRemoteSkipPausesUntilSeeked) {
  Prepare(kParcSafariUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  RequestSeekForward(4);
  EXPECT_TRUE(Media()->paused());
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(4));
  TimeChanged();
  RunTasks();
  EXPECT_FALSE(Media()->paused());
}

TEST_P(ParcMediaElementSeekTest, ParcSafariRemoteSkipBackPausesUntilSeeked) {
  Prepare(kParcSafariUserAgent, 0, 10);
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(6.0));
  SetCurrentTime(6);
  RunTasks();
  TimeChanged();
  ASSERT_EQ(Media()->currentTime(), 6);
  Media()->Play();
  RunTasks();
  RequestSeekBackward(10);
  EXPECT_TRUE(Media()->paused());
  EXPECT_EQ(Media()->currentTime(), 0);
  RunTasks();
  EXPECT_THAT(seeks_, testing::ElementsAre(6, 0));
  TimeChanged();
  RunTasks();
  EXPECT_FALSE(Media()->paused());
}

TEST_P(ParcMediaElementSeekTest, ParcSafariPauseDuringRemoteScrubHolds) {
  Prepare(kParcSafariUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  RequestSeekTo(3);
  ASSERT_TRUE(Media()->paused());
  RequestPause();
  RunTasks();
  TimeChanged();
  RunTasks();
  EXPECT_TRUE(Media()->paused());

  EndParcRemoteScrub();
  Media()->Play();
  RunTasks();
  RequestSeekTo(5);
  ASSERT_TRUE(Media()->paused());
  Media()->pause();
  RunTasks();
  TimeChanged();
  RunTasks();
  EXPECT_TRUE(Media()->paused());
}

TEST_P(ParcMediaElementSeekTest, ParcSafariRemoteSeekToCurrentTimeHolds) {
  Prepare(kParcSafariUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  RequestSeekTo(0);
  RunTasks();
  EXPECT_TRUE(seeks_.empty());
  EXPECT_FALSE(Media()->seeking());
  EXPECT_TRUE(Media()->paused());

  SetCurrentTime(5);
  RunTasks();
  TimeChanged();
  RunTasks();
  EXPECT_TRUE(Media()->paused());
}

TEST_P(ParcMediaElementSeekTest, ParcChromeRemoteSeekKeepsPlaying) {
  Prepare(kParcChromeUserAgent, 0, 10);
  Media()->Play();
  RunTasks();
  RequestSeekTo(3);
  EXPECT_FALSE(Media()->paused());
  EXPECT_THAT(seeks_, testing::ElementsAre(3));
  EXPECT_FALSE(ParcRemoteScrubEndsIn());
  RunTasks();
  EXPECT_THAT(events_->Only({"pause"}), testing::IsEmpty());
}

class ClosingMediaSourceAttachment final : public StubMediaSourceAttachment {
 public:
  void Close(MediaSourceTracer*) override { ++closes_; }
  int closes() const { return closes_; }

 private:
  int closes_ = 0;
};

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceDetachAbortsLoad) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  ASSERT_NE(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  ASSERT_TRUE(ShouldDelayLoadEvent());
  ASSERT_TRUE(
      ParcMediaElement::From(*Media()).CancelsLoadWhenMediaSourceDetaches());
  auto attachment = base::MakeRefCounted<ClosingMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);
  auto* events = MakeGarbageCollected<EventOrderListener>();
  for (const AtomicString& type :
       {event_type_names::kAbort, event_type_names::kEmptied,
        event_type_names::kError}) {
    Media()->addEventListener(type, events);
  }

  ParcMediaElement::From(*Media()).MediaSourceWasDetached();
  EXPECT_FALSE(Media()->GetWebMediaPlayer());
  EXPECT_EQ(attachment->closes(), 1);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrAborted);
  EXPECT_EQ(Media()->error()->message(), "Load was aborted");
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  EXPECT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveNothing);
  EXPECT_FALSE(ShouldDelayLoadEvent());
  test::RunPendingTasks();
  EXPECT_THAT(events->Only({"abort", "emptied", "error"}),
              testing::ElementsAre("abort", "emptied"));
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceDetachWithControlsStays) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  Media()->GetDocument().body()->AppendChild(Media());
  Media()->SetBooleanAttribute(html_names::kControlsAttr, true);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  ASSERT_TRUE(Media()->GetMediaControls());
  auto* events = MakeGarbageCollected<EventOrderListener>();
  for (const AtomicString& type :
       {event_type_names::kAbort, event_type_names::kEmptied,
        event_type_names::kLoadstart, event_type_names::kPause}) {
    Media()->addEventListener(type, events);
  }

  ParcMediaElement::From(*Media()).MediaSourceWasDetached();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrAborted);
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);

  Media()->SetBooleanAttribute(html_names::kControlsAttr, false);
  Media()->SetBooleanAttribute(html_names::kControlsAttr, true);
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  EXPECT_THAT(events->Only({"abort", "emptied", "loadstart", "pause"}),
              testing::ElementsAre("abort", "emptied"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariMediaSourceDetachAfterMetadata) {
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(2.0));
  Prepare(kParcSafariUserAgent, 2, 8);
  ASSERT_EQ(Media()->duration(), 10);
  ASSERT_EQ(Media()->currentTime(), 2);
  for (const AtomicString& type :
       {event_type_names::kAbort, event_type_names::kEmptied,
        event_type_names::kError}) {
    Media()->addEventListener(type, events_);
  }

  ParcMediaElement::From(*Media()).MediaSourceWasDetached();
  EXPECT_FALSE(Media()->GetWebMediaPlayer());
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrAborted);
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
  EXPECT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveNothing);
  EXPECT_TRUE(std::isnan(Media()->duration()));
  EXPECT_EQ(Media()->currentTime(), 0);
  RunTasks();
  EXPECT_THAT(events_->Only({"abort", "emptied", "error"}),
              testing::ElementsAre("abort"));
}

TEST_P(ParcMediaElementSeekTest, ParcSafariMediaSourceDetachDropsSeek) {
  Prepare(kParcSafariUserAgent, 0, 10);
  SetCurrentTime(5);
  ASSERT_TRUE(Media()->seeking());
  ASSERT_EQ(Media()->currentTime(), 5);

  ParcMediaElement::From(*Media()).MediaSourceWasDetached();
  RunTasks();
  EXPECT_TRUE(seeks_.empty());
  EXPECT_TRUE(Media()->seeking());
  EXPECT_EQ(Media()->currentTime(), 0);
  EXPECT_THAT(events_->Only({"seeking", "seeked"}), testing::IsEmpty());
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceDetachAfterEndOfStreamKeeps) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetMediaSourceAttachment(base::MakeRefCounted<StubMediaSourceAttachment>());
  const auto network_state = Media()->getNetworkState();

  ParcMediaElement::From(*Media()).MediaSourceEnded();
  ParcMediaElement::From(*Media()).MediaSourceWasDetached();
  EXPECT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_FALSE(Media()->error());
  EXPECT_EQ(Media()->getNetworkState(), network_state);

  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
  ParcMediaElement::From(*Media()).MediaSourceWasDetached();
  EXPECT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_FALSE(Media()->error());
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);

  ASSERT_TRUE(ParcCompletelyLoaded());
  Media()->load();
  EXPECT_FALSE(ParcCompletelyLoaded());
}

TEST_P(ParcMediaElementTest, ParcChromeMediaSourceDetachKeepsLoad) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_FALSE(
      ParcMediaElement::From(*Media()).CancelsLoadWhenMediaSourceDetaches());
  const auto network_state = Media()->getNetworkState();

  ParcMediaElement::From(*Media()).MediaSourceWasDetached();
  EXPECT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_FALSE(Media()->error());
  EXPECT_EQ(Media()->getNetworkState(), network_state);
}

TEST_P(ParcMediaElementTest, ParcSafariSrcNotSupportedMessages) {
  SetUserAgent(kParcSafariUserAgent);
  EXPECT_CALL(*MockMediaPlayer(), WouldTaintOrigin())
      .WillRepeatedly(Return(false));
  EXPECT_CALL(*MockMediaPlayer(), GetErrorMessage())
      .WillRepeatedly(
          Return(WebString::FromUtf8("DEMUXER_ERROR_COULD_NOT_OPEN: test")));

  Media()->setAttribute(html_names::kSrcAttr, g_empty_atom);
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrSrcNotSupported);
  EXPECT_EQ(Media()->error()->message(), "");

  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetNetworkState(WebMediaPlayer::kNetworkStateFormatError);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrSrcNotSupported);
  EXPECT_EQ(Media()->error()->message(), "");

  auto* frameless = MakeGarbageCollected<HTMLAudioElement>(
      *Media()->GetDocument().implementation().createHTMLDocument(""));
  frameless->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(frameless->error());
  EXPECT_EQ(frameless->error()->code(), MediaError::kMediaErrSrcNotSupported);
  EXPECT_EQ(frameless->error()->message(), "Unsupported source type");
}

TEST_P(ParcMediaElementTest, ParcChromeSrcNotSupportedMessages) {
  SetUserAgent(kParcChromeUserAgent);
  EXPECT_CALL(*MockMediaPlayer(), WouldTaintOrigin())
      .WillRepeatedly(Return(false));
  EXPECT_CALL(*MockMediaPlayer(), GetErrorMessage())
      .WillRepeatedly(
          Return(WebString::FromUtf8("DEMUXER_ERROR_COULD_NOT_OPEN: test")));

  Media()->setAttribute(html_names::kSrcAttr, g_empty_atom);
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->message(),
            "MEDIA_ELEMENT_ERROR: Empty src attribute");

  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetNetworkState(WebMediaPlayer::kNetworkStateFormatError);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->message(), "DEMUXER_ERROR_COULD_NOT_OPEN: test");

  auto* frameless = MakeGarbageCollected<HTMLAudioElement>(
      *Media()->GetDocument().implementation().createHTMLDocument(""));
  frameless->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(frameless->error());
  EXPECT_EQ(frameless->error()->message(),
            "MEDIA_ELEMENT_ERROR: Media load rejected by URL safety check");
}

TEST_P(ParcMediaElementTest, ParcSafariMediaEngineErrorMessages) {
  SetUserAgent(kParcSafariUserAgent);
  EXPECT_CALL(*MockMediaPlayer(), GetErrorMessage())
      .WillRepeatedly(
          Return(WebString::FromUtf8("PIPELINE_ERROR_DECODE: test")));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveMetadata);

  SetNetworkState(WebMediaPlayer::kNetworkStateNetworkError);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrNetwork);
  EXPECT_EQ(Media()->error()->message(), "Media failed to load");

  SetNetworkState(WebMediaPlayer::kNetworkStateDecodeError);
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrDecode);
  EXPECT_EQ(Media()->error()->message(), "Media failed to decode");
}

TEST_P(ParcMediaElementTest, ParcChromeMediaEngineErrorMessages) {
  SetUserAgent(kParcChromeUserAgent);
  EXPECT_CALL(*MockMediaPlayer(), GetErrorMessage())
      .WillRepeatedly(
          Return(WebString::FromUtf8("PIPELINE_ERROR_DECODE: test")));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveMetadata);

  SetNetworkState(WebMediaPlayer::kNetworkStateNetworkError);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->message(), "PIPELINE_ERROR_DECODE: test");
  SetNetworkState(WebMediaPlayer::kNetworkStateDecodeError);
  EXPECT_EQ(Media()->error()->message(), "PIPELINE_ERROR_DECODE: test");
}

namespace {

struct ParcPlayRejectionMessages {
  const char* not_allowed;
  const char* paused;
  const char* new_load;
  const char* failed_source;
  const char* no_source;
};

DOMException* ParcPlayRejection(ScriptState* script_state,
                                ScriptPromise<IDLUndefined> promise) {
  ScriptPromiseTester tester(script_state, promise);
  tester.WaitUntilSettled();
  if (!tester.IsRejected()) {
    return nullptr;
  }
  return V8DOMException::ToWrappable(script_state->GetIsolate(),
                                     tester.Value().V8Value());
}

void ExpectParcPlayRejection(ScriptState* script_state,
                             ScriptPromise<IDLUndefined> promise,
                             const char* name,
                             const char* message) {
  DOMException* exception = ParcPlayRejection(script_state, promise);
  ASSERT_TRUE(exception);
  EXPECT_EQ(exception->name(), name);
  EXPECT_EQ(exception->message(), message);
}

void ExpectParcPlayRejectionMessages(
    HTMLMediaElement* media,
    ScriptState* script_state,
    const ParcPlayRejectionMessages& expected) {
  Settings* settings = media->GetDocument().GetSettings();
  settings->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  ExpectParcPlayRejection(script_state, media->playForBindings(script_state),
                          "NotAllowedError", expected.not_allowed);
  settings->SetAutoplayPolicy(AutoplayPolicy::Type::kNoUserGestureRequired);

  auto paused = media->playForBindings(script_state);
  media->pause();
  ExpectParcPlayRejection(script_state, paused, "AbortError", expected.paused);

  media->setAttribute(html_names::kSrcAttr, g_empty_atom);
  auto reloaded = media->playForBindings(script_state);
  media->load();
  auto failed = media->playForBindings(script_state);
  ExpectParcPlayRejection(script_state, reloaded, "AbortError",
                          expected.new_load);
  ExpectParcPlayRejection(script_state, failed, "NotSupportedError",
                          expected.failed_source);

  ASSERT_TRUE(media->error());
  EXPECT_EQ(media->error()->code(), MediaError::kMediaErrSrcNotSupported);
  ExpectParcPlayRejection(script_state, media->playForBindings(script_state),
                          "NotSupportedError", expected.no_source);
}

}

TEST_P(ParcMediaElementTest, ParcSafariPlayRejectionMessages) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ScriptState* script_state =
      ToScriptStateForMainWorld(&dummy_page_holder_->GetFrame());
  ScriptState::Scope scope(script_state);
  ExpectParcPlayRejectionMessages(
      Media(), script_state,
      {.not_allowed =
           "The request is not allowed by the user agent or the platform in "
           "the current context, possibly because the user denied "
           "permission.",
       .paused = "The operation was aborted.",
       .new_load = "The operation was aborted.",
       .failed_source = "The operation is not supported.",
       .no_source = "The operation is not supported."});
}

TEST_P(ParcMediaElementTest, ParcChromePlayRejectionMessages) {
  SetUserAgent(kParcChromeUserAgent);
  ScriptState* script_state =
      ToScriptStateForMainWorld(&dummy_page_holder_->GetFrame());
  ScriptState::Scope scope(script_state);
  ExpectParcPlayRejectionMessages(
      Media(), script_state,
      {.not_allowed = "play() failed because the user didn't interact with "
                      "the document first. https://goo.gl/xX8pDD",
       .paused = "The play() request was interrupted by a call to pause(). "
                 "https://goo.gl/LdLk22",
       .new_load = "The play() request was interrupted by a new load "
                   "request. https://goo.gl/LdLk22",
       .failed_source = "Failed to load because no supported source was found.",
       .no_source = "The element has no supported sources."});
}

namespace {

void ParcStickyActivationOnly(HTMLMediaElement* media) {
  media->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  LocalFrame* frame = media->GetDocument().GetFrame();
  LocalFrame::NotifyUserActivation(
      frame, mojom::UserActivationNotificationType::kTest);
  LocalFrame::ConsumeTransientUserActivation(frame);
}

}

TEST_P(ParcMediaElementTest, ParcSafariAudiblePlayNeedsGestureOnElement) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  EXPECT_EQ(Media()->Play(), DOMExceptionCode::kNotAllowedError);

  LocalFrame* frame = Media()->GetDocument().GetFrame();
  LocalFrame::NotifyUserActivation(
      frame, mojom::UserActivationNotificationType::kTest);
  EXPECT_FALSE(Media()->Play().has_value());
  Media()->pause();
  LocalFrame::ConsumeTransientUserActivation(frame);
  EXPECT_FALSE(Media()->Play().has_value());
}

TEST_P(ParcMediaElementTest, ParcChromeAudiblePlayAfterAnyGesture) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  EXPECT_FALSE(Media()->Play().has_value());
}

TEST_P(ParcMediaElementTest, ParcSafariSilentPlayNeedsNoGesture) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();

  Media()->setMuted(true);
  EXPECT_FALSE(Media()->Play().has_value());
  Media()->pause();
  Media()->setMuted(false);
  Media()->setVolume(0, ASSERT_NO_EXCEPTION);
  EXPECT_FALSE(Media()->Play().has_value());
  Media()->pause();
  Media()->setVolume(1, ASSERT_NO_EXCEPTION);

  EXPECT_CALL(*MockMediaPlayer(), HasAudio()).WillRepeatedly(Return(false));
  EXPECT_EQ(Media()->Play().has_value(), GetParam() == MediaTestParam::kAudio);
}

TEST_P(ParcMediaElementTest, ParcChromeSilentPlay) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();

  Media()->setMuted(true);
  EXPECT_EQ(Media()->Play().has_value(), GetParam() == MediaTestParam::kAudio);
  Media()->pause();
  Media()->setMuted(false);
  EXPECT_CALL(*MockMediaPlayer(), HasAudio()).WillRepeatedly(Return(false));
  EXPECT_EQ(Media()->Play(), DOMExceptionCode::kNotAllowedError);
}

TEST_P(ParcMediaElementTest, ParcSafariBecomingAudiblePauses) {
  SetUserAgent(kParcSafariUserAgent);
  ScriptState* script_state =
      ToScriptStateForMainWorld(&dummy_page_holder_->GetFrame());
  ScriptState::Scope scope(script_state);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());

  Media()->setMuted(true);
  auto promise = Media()->playForBindings(script_state);
  ASSERT_FALSE(Media()->paused());
  Media()->setMuted(false);
  EXPECT_TRUE(Media()->paused());
  ExpectParcPlayRejection(script_state, promise, "AbortError",
                          "The operation was aborted.");

  Media()->setVolume(0, ASSERT_NO_EXCEPTION);
  Media()->Play();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  ASSERT_TRUE(MediaIsPlaying());
  Media()->setVolume(1, ASSERT_NO_EXCEPTION);
  EXPECT_TRUE(Media()->paused());
}

TEST_P(ParcMediaElementTest, ParcChromeBecomingAudibleAfterAnyGesture) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());

  Media()->setMuted(true);
  Media()->Play();
  Media()->setMuted(false);
  EXPECT_FALSE(Media()->paused());
}

TEST_P(ParcMediaElementTest, ParcSafariAudioFoundAtMetadataRefusesPlay) {
  if (GetParam() == MediaTestParam::kAudio) {
    GTEST_SKIP();
  }
  SetUserAgent(kParcSafariUserAgent);
  ScriptState* script_state =
      ToScriptStateForMainWorld(&dummy_page_holder_->GetFrame());
  ScriptState::Scope scope(script_state);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  EXPECT_CALL(*MockMediaPlayer(), HasAudio()).WillRepeatedly(Return(false));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();

  auto promise = Media()->playForBindings(script_state);
  ASSERT_FALSE(Media()->paused());
  EXPECT_CALL(*MockMediaPlayer(), HasAudio()).WillRepeatedly(Return(true));
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  EXPECT_TRUE(Media()->paused());
  ExpectParcPlayRejection(
      script_state, promise, "NotAllowedError",
      "The request is not allowed by the user agent or the platform in the "
      "current context, possibly because the user denied permission.");
}

TEST_P(ParcMediaElementTest, ParcSafariMutingStartsRefusedAutoplay) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  Media()->SetBooleanAttribute(html_names::kAutoplayAttr, true);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_TRUE(Media()->paused());

  Media()->setMuted(true);
  EXPECT_FALSE(Media()->paused());
}

TEST_P(ParcMediaElementTest, ParcChromeMutingLeavesAutoplayAlone) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  Media()->SetBooleanAttribute(html_names::kAutoplayAttr, true);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->setMuted(true);
  EXPECT_TRUE(Media()->paused());
}

TEST_P(ParcMediaElementTest, ParcSafariGestureReachesOtherMedia) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  Document& document = Media()->GetDocument();
  auto* other = MakeGarbageCollected<HTMLAudioElement>(document);

  LocalFrame* frame = document.GetFrame();
  LocalFrame::NotifyUserActivation(
      frame, mojom::UserActivationNotificationType::kTest);
  auto* created_in_gesture = MakeGarbageCollected<HTMLAudioElement>(document);
  Media()->Play();
  LocalFrame::ConsumeTransientUserActivation(frame);

  EXPECT_FALSE(created_in_gesture->Play().has_value());
  EXPECT_EQ(other->Play(), DOMExceptionCode::kNotAllowedError);
  Media()->DispatchEvent(*Event::Create(event_type_names::kEnded));
  EXPECT_FALSE(other->Play().has_value());
  EXPECT_TRUE(ParcMediaElement::From(*other).HadMediaUserGesture());
}

TEST_P(ParcMediaElementTest, ParcSafariFirstMutedSetInGestureUnlocks) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  LocalFrame* frame = Media()->GetDocument().GetFrame();
  LocalFrame::NotifyUserActivation(
      frame, mojom::UserActivationNotificationType::kTest);
  Media()->setMuted(false);
  EXPECT_TRUE(ParcMediaElement::From(*Media()).HadMediaUserGesture());
  LocalFrame::ConsumeTransientUserActivation(frame);

  Media()->SetBooleanAttribute(html_names::kAutoplayAttr, true);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_FALSE(Media()->paused());
}

TEST_P(ParcMediaElementTest, ParcSafariAudioFoundLaterPauses) {
  if (GetParam() == MediaTestParam::kAudio) {
    GTEST_SKIP();
  }
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  EXPECT_CALL(*MockMediaPlayer(), HasAudio()).WillRepeatedly(Return(false));
  WaitForPlayer();
  ASSERT_FALSE(Media()->paused());

  EXPECT_CALL(*MockMediaPlayer(), HasAudio()).WillRepeatedly(Return(true));
  NotifyMediaMetadataChanged(true, true, media::AudioCodec::kAAC,
                             media::VideoCodec::kH264,
                             media::MediaContentType::kPersistent, false);
  EXPECT_TRUE(Media()->paused());
}

TEST_P(ParcMediaElementTest, ParcSafariBackForwardCacheStopsAndResumesQuietly) {
  SetUserAgent(kParcSafariUserAgent);
  ON_CALL(*MockMediaPlayer(), Paused()).WillByDefault(Return(true));
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPause, pause);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  ASSERT_TRUE(MediaIsPlaying());
  WebMediaPlayer* player = Media()->GetWebMediaPlayer();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), OnFrozen()).Times(0);
  EXPECT_CALL(*MockMediaPlayer(), Play()).Times(0);
  EXPECT_CALL(*MockMediaPlayer(), ParcOnFrozenInBackForwardCache());
  EXPECT_CALL(*MockMediaPlayer(),
              Pause(WebMediaPlayer::PauseReason::kFrameFrozen));
  GetExecutionContext()->SetIsInBackForwardCache(true);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kFrozen);
  EXPECT_FALSE(Media()->paused());
  EXPECT_FALSE(MediaIsPlaying());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_FALSE(MediaIsPlaying());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), Play()).Times(testing::AtLeast(1));
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kRunning);
  GetExecutionContext()->SetIsInBackForwardCache(false);
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(MediaIsPlaying());
  EXPECT_EQ(Media()->GetWebMediaPlayer(), player);
  test::RunPendingTasks();
  EXPECT_EQ(pause->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariOtherFreezeLeavesPlaybackAlone) {
  SetUserAgent(kParcSafariUserAgent);
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPause, pause);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  ASSERT_TRUE(MediaIsPlaying());

  EXPECT_CALL(*MockMediaPlayer(), OnFrozen()).Times(0);
  EXPECT_CALL(*MockMediaPlayer(), Pause(_)).Times(0);
  EXPECT_CALL(*MockMediaPlayer(), ParcOnFrozenInBackForwardCache()).Times(0);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kFrozen);
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(MediaIsPlaying());
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kRunning);
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(MediaIsPlaying());
  test::RunPendingTasks();
  EXPECT_EQ(pause->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcChromeBackForwardCacheFreezePauses) {
  SetUserAgent(kParcChromeUserAgent);
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPause, pause);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  ASSERT_TRUE(MediaIsPlaying());

  EXPECT_CALL(*MockMediaPlayer(), OnFrozen());
  EXPECT_CALL(*MockMediaPlayer(), ParcOnFrozenInBackForwardCache()).Times(0);
  GetExecutionContext()->SetIsInBackForwardCache(true);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kFrozen);
  EXPECT_TRUE(Media()->paused());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kRunning);
  GetExecutionContext()->SetIsInBackForwardCache(false);
  EXPECT_TRUE(Media()->paused());
  EXPECT_FALSE(MediaIsPlaying());
  test::RunPendingTasks();
  EXPECT_EQ(pause->count(), 1);
}

TEST_P(ParcMediaElementTest, ParcSafariBackForwardCacheRestoreHeldUntilShown) {
  SetUserAgent(kParcSafariUserAgent);
  ON_CALL(*MockMediaPlayer(), Paused()).WillByDefault(Return(true));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  test::RunPendingTasks();
  ASSERT_TRUE(MediaIsPlaying());
  auto* play = MakeGarbageCollected<EventCountingListener>();
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPlay, play);
  Media()->addEventListener(event_type_names::kPause, pause);

  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(false);
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);
  GetExecutionContext()->SetIsInBackForwardCache(true);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kFrozen);
  ASSERT_FALSE(MediaIsPlaying());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), Play()).Times(0);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kRunning);
  GetExecutionContext()->SetIsInBackForwardCache(false);
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->paused());
  EXPECT_FALSE(MediaIsPlaying());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_FALSE(MediaIsPlaying());
  SetPageVisibility(mojom::blink::PageVisibilityState::kHiddenButPainting);
  EXPECT_FALSE(MediaIsPlaying());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), Play()).Times(testing::AtLeast(1));
  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(true);
  SetPageVisibility(mojom::blink::PageVisibilityState::kVisible);
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(MediaIsPlaying());
  test::RunPendingTasks();
  EXPECT_EQ(play->count(), 0);
  EXPECT_EQ(pause->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariBackForwardCacheRestoreVisibleResumes) {
  SetUserAgent(kParcSafariUserAgent);
  ON_CALL(*MockMediaPlayer(), Paused()).WillByDefault(Return(true));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  test::RunPendingTasks();
  ASSERT_TRUE(MediaIsPlaying());
  auto* play = MakeGarbageCollected<EventCountingListener>();
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPlay, play);
  Media()->addEventListener(event_type_names::kPause, pause);

  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(false);
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);
  GetExecutionContext()->SetIsInBackForwardCache(true);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kFrozen);
  ASSERT_FALSE(MediaIsPlaying());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), Play()).Times(testing::AtLeast(1));
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kRunning);
  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(true);
  SetPageVisibility(mojom::blink::PageVisibilityState::kVisible);
  GetExecutionContext()->SetIsInBackForwardCache(false);
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(MediaIsPlaying());
  test::RunPendingTasks();
  EXPECT_EQ(play->count(), 0);
  EXPECT_EQ(pause->count(), 0);
}

TEST_P(ParcMediaElementTest,
       ParcChromeBackForwardCacheHiddenRestoreStaysPaused) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  test::RunPendingTasks();
  ASSERT_TRUE(MediaIsPlaying());
  auto* play = MakeGarbageCollected<EventCountingListener>();
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPlay, play);
  Media()->addEventListener(event_type_names::kPause, pause);

  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(false);
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);
  EXPECT_CALL(*MockMediaPlayer(), OnFrozen());
  GetExecutionContext()->SetIsInBackForwardCache(true);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kFrozen);
  EXPECT_TRUE(Media()->paused());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), Play()).Times(0);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kRunning);
  GetExecutionContext()->SetIsInBackForwardCache(false);
  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(true);
  SetPageVisibility(mojom::blink::PageVisibilityState::kVisible);
  EXPECT_TRUE(Media()->paused());
  EXPECT_FALSE(MediaIsPlaying());
  test::RunPendingTasks();
  EXPECT_EQ(play->count(), 0);
  EXPECT_EQ(pause->count(), 1);
}

TEST_P(ParcMediaElementTest,
       ParcSafariBackForwardCacheCoveredTabResumesWhenAttached) {
  SetUserAgent(kParcSafariUserAgent);
  ON_CALL(*MockMediaPlayer(), Paused()).WillByDefault(Return(true));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  test::RunPendingTasks();
  ASSERT_TRUE(MediaIsPlaying());
  auto* play = MakeGarbageCollected<EventCountingListener>();
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPlay, play);
  Media()->addEventListener(event_type_names::kPause, pause);

  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(false);
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);
  GetExecutionContext()->SetIsInBackForwardCache(true);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kFrozen);
  ASSERT_FALSE(MediaIsPlaying());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), Play()).Times(0);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kRunning);
  GetExecutionContext()->SetIsInBackForwardCache(false);
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->paused());
  EXPECT_FALSE(MediaIsPlaying());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_FALSE(MediaIsPlaying());
  SetPageVisibility(mojom::blink::PageVisibilityState::kHiddenButPainting);
  EXPECT_FALSE(MediaIsPlaying());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), Play()).Times(testing::AtLeast(1));
  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(true);
  EXPECT_EQ(Media()->GetDocument().GetPage()->GetVisibilityState(),
            mojom::blink::PageVisibilityState::kHiddenButPainting);
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(MediaIsPlaying());
  test::RunPendingTasks();
  EXPECT_EQ(play->count(), 0);
  EXPECT_EQ(pause->count(), 0);
}

TEST_P(ParcMediaElementTest,
       ParcSafariBackForwardCacheMinimisedInWindowResumes) {
  SetUserAgent(kParcSafariUserAgent);
  ON_CALL(*MockMediaPlayer(), Paused()).WillByDefault(Return(true));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  test::RunPendingTasks();
  ASSERT_TRUE(MediaIsPlaying());
  auto* play = MakeGarbageCollected<EventCountingListener>();
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPlay, play);
  Media()->addEventListener(event_type_names::kPause, pause);

  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(true);
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);
  GetExecutionContext()->SetIsInBackForwardCache(true);
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kFrozen);
  ASSERT_FALSE(MediaIsPlaying());
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), Play()).Times(testing::AtLeast(1));
  GetExecutionContext()->SetLifecycleState(
      mojom::blink::FrameLifecycleState::kRunning);
  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetInWindow(true);
  EXPECT_EQ(Media()->GetDocument().GetPage()->GetVisibilityState(),
            mojom::blink::PageVisibilityState::kHidden);
  GetExecutionContext()->SetIsInBackForwardCache(false);
  EXPECT_FALSE(Media()->paused());
  EXPECT_TRUE(MediaIsPlaying());
  test::RunPendingTasks();
  EXPECT_EQ(play->count(), 0);
  EXPECT_EQ(pause->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariPausesAtEndOnPlayerTime) {
  SetUserAgent(kParcSafariUserAgent);
  double now = 0.5;
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime())
      .WillRepeatedly(testing::ReturnPointee(&now));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  GetExecutionContext()->GetAgent()->event_loop()->PerformMicrotaskCheckpoint();
  ASSERT_FALSE(Media()->paused());

  now = 1.25;
  EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
  TimeChanged();
  EXPECT_TRUE(Media()->paused());
  EXPECT_EQ(Media()->currentTime(), 1.0);
}

TEST_P(ParcMediaElementTest, ParcChromePausesAtEndOnHeldTime) {
  SetUserAgent(kParcChromeUserAgent);
  double now = 0.5;
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime())
      .WillRepeatedly(testing::ReturnPointee(&now));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  GetExecutionContext()->GetAgent()->event_loop()->PerformMicrotaskCheckpoint();
  ASSERT_FALSE(Media()->paused());

  now = 1.0;
  EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
  TimeChanged();
  EXPECT_TRUE(Media()->paused());
  EXPECT_EQ(Media()->currentTime(), 0.5);
}

TEST_P(ParcMediaElementTest, ParcSafariPreloadDefaultsToAuto) {
  SetUserAgent(kParcSafariUserAgent);
  EXPECT_EQ("auto", Media()->preload());
  Media()->setPreload(AtomicString("foo"));
  EXPECT_EQ("auto", Media()->preload());
  Media()->setPreload(AtomicString("metadata"));
  EXPECT_EQ("metadata", Media()->preload());
  Media()->setPreload(AtomicString("none"));
  EXPECT_EQ("none", Media()->preload());

  Media()->removeAttribute(html_names::kPreloadAttr);
  GetNetworkStateNotifier().SetNetworkConnectionInfoOverride(
      true, WebConnectionType::kWebConnectionTypeCellular3G,
      WebEffectiveConnectionType::kTypeUnknown, 1.0, 2.0);
  EXPECT_EQ("auto", Media()->preload());
  GetNetworkStateNotifier().ClearOverride();
}

TEST_P(ParcMediaElementTest, ParcChromePreloadDefaultsToMetadata) {
  SetUserAgent(kParcChromeUserAgent);
  EXPECT_EQ("metadata", Media()->preload());
  Media()->setPreload(AtomicString("foo"));
  EXPECT_EQ("metadata", Media()->preload());
}

TEST_P(ParcMediaElementTest, ParcSafariPlayerPreloadIsAutoByDefault) {
  SetUserAgent(kParcSafariUserAgent);
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadMetaData))
      .Times(0);
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadAuto))
      .Times(testing::AtLeast(1));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_TRUE(ParcPreparesToPlay());
}

TEST_P(ParcMediaElementTest, ParcChromePlayerPreloadIsMetadataByDefault) {
  SetUserAgent(kParcChromeUserAgent);
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadAuto))
      .Times(0);
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadMetaData))
      .Times(testing::AtLeast(1));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
}

TEST_P(ParcMediaElementTest, ParcSafariPreloadNoneStillDefersLoad) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->setPreload(AtomicString("none"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  EXPECT_TRUE(LoadIsDeferred());
  EXPECT_FALSE(Media()->GetWebMediaPlayer());
  EXPECT_FALSE(ParcPreparesToPlay());
}

TEST_P(ParcMediaElementTest, ParcSafariEffectivePreloadFollowsWebKit) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  Media()->setPreload(AtomicString("none"));
  EXPECT_EQ(WebMediaPlayer::kPreloadNone, Media()->EffectivePreloadType());
  Media()->setAttribute(html_names::kAutoplayAttr, g_empty_atom);
  EXPECT_EQ(WebMediaPlayer::kPreloadAuto, Media()->EffectivePreloadType());
  Media()->removeAttribute(html_names::kAutoplayAttr);

  Media()->setPreload(AtomicString("metadata"));
  EXPECT_EQ(WebMediaPlayer::kPreloadMetaData, Media()->EffectivePreloadType());
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kNoUserGestureRequired);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  Media()->Play();
  EXPECT_EQ(WebMediaPlayer::kPreloadAuto, Media()->EffectivePreloadType());
  EXPECT_TRUE(ParcPreparesToPlay());

  auto* other = MakeGarbageCollected<HTMLAudioElement>(Media()->GetDocument());
  other->setPreload(AtomicString("metadata"));
  other->load();
  test::RunPendingTasks();
  EXPECT_EQ(WebMediaPlayer::kPreloadAuto, other->EffectivePreloadType());
}

TEST_P(ParcMediaElementTest, ParcSafariLoadKeepsPreloadAutoForLaterLoads) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->setPreload(AtomicString("none"));
  Media()->load();
  test::RunPendingTasks();

  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadNone))
      .Times(0);
  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadAuto))
      .Times(testing::AtLeast(1));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  EXPECT_FALSE(LoadIsDeferred());
  EXPECT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_TRUE(ParcPreparesToPlay());
}

TEST_P(ParcMediaElementTest, ParcSafariNewLoadCancelsLoadPrepareToPlay) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->setPreload(AtomicString("none"));
  Media()->load();
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  EXPECT_TRUE(LoadIsDeferred());
  EXPECT_FALSE(Media()->GetWebMediaPlayer());
  EXPECT_EQ(WebMediaPlayer::kPreloadNone, Media()->EffectivePreloadType());
}

TEST_P(ParcMediaElementTest, ParcSafariPlayKeepsPreloadAutoForLaterLoads) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kNoUserGestureRequired);
  Media()->setPreload(AtomicString("metadata"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();

  Media()->SetSrc(AtomicString("http://example.com/bar.mp4"));
  EXPECT_EQ(WebMediaPlayer::kPreloadAuto, Media()->EffectivePreloadType());
  EXPECT_TRUE(ParcPreparesToPlay());
  Media()->removeAttribute(html_names::kSrcAttr);
  test::RunPendingTasks();
}

TEST_P(ParcMediaElementTest, ParcSafariPlayingAtPreloadAutoDoesNotPrepare) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kNoUserGestureRequired);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();

  Media()->setPreload(AtomicString("none"));
  Media()->SetSrc(AtomicString("http://example.com/bar.mp4"));
  EXPECT_EQ(WebMediaPlayer::kPreloadNone, Media()->EffectivePreloadType());
  EXPECT_FALSE(ParcPreparesToPlay());
  Media()->removeAttribute(html_names::kSrcAttr);
  test::RunPendingTasks();
}

TEST_P(ParcMediaElementTest, ParcSafariLoweredPreloadKeepsFutureData) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kNoUserGestureRequired);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();
  Media()->setPreload(AtomicString("none"));
  SetReadyState(HTMLMediaElement::kHaveCurrentData);

  Media()->SetSrc(AtomicString("http://example.com/bar.mp4"));
  EXPECT_EQ(WebMediaPlayer::kPreloadNone, Media()->EffectivePreloadType());
  Media()->removeAttribute(html_names::kSrcAttr);
  test::RunPendingTasks();
}

TEST_P(ParcMediaElementTest, ParcSafariRaisedPreloadCountsBufferedData) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kNoUserGestureRequired);
  Media()->setPreload(AtomicString("metadata"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->setPreload(AtomicString("auto"));
  Media()->setPreload(AtomicString("metadata"));
  Media()->Play();

  Media()->SetSrc(AtomicString("http://example.com/bar.mp4"));
  EXPECT_EQ(WebMediaPlayer::kPreloadMetaData, Media()->EffectivePreloadType());
  Media()->removeAttribute(html_names::kSrcAttr);
  test::RunPendingTasks();
}

TEST_P(ParcMediaElementTest, ParcSafariLoadSuspendsThenLoadsAtPreloadNone) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->setPreload(AtomicString("none"));
  auto* suspend = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kSuspend, suspend);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->load();
  test::RunPendingTasks();
  EXPECT_EQ(suspend->count(), 1);
  EXPECT_FALSE(LoadIsDeferred());
  EXPECT_TRUE(Media()->GetWebMediaPlayer());
}

TEST_P(ParcMediaElementTest, ParcChromeLoadLiftsPreloadNoneToMetadata) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->setPreload(AtomicString("none"));
  Media()->load();
  EXPECT_EQ(WebMediaPlayer::kPreloadMetaData, Media()->EffectivePreloadType());
}

TEST_P(ParcMediaElementTest, ParcSafariSeekAtPreloadAutoDoesNotPrepare) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  Media()->setCurrentTime(1);

  Media()->setPreload(AtomicString("none"));
  Media()->SetSrc(AtomicString("http://example.com/bar.mp4"));
  EXPECT_EQ(WebMediaPlayer::kPreloadNone, Media()->EffectivePreloadType());
  Media()->removeAttribute(html_names::kSrcAttr);
  test::RunPendingTasks();
}

TEST_P(ParcMediaElementTest, ParcSafariSeekKeepsPreloadAutoForLaterLoads) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->setPreload(AtomicString("metadata"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  EXPECT_EQ(WebMediaPlayer::kPreloadMetaData, Media()->EffectivePreloadType());
  Media()->setCurrentTime(1);

  Media()->SetSrc(AtomicString("http://example.com/bar.mp4"));
  EXPECT_EQ(WebMediaPlayer::kPreloadAuto, Media()->EffectivePreloadType());
  EXPECT_TRUE(ParcPreparesToPlay());
  Media()->removeAttribute(html_names::kSrcAttr);
  test::RunPendingTasks();
}

TEST_P(ParcMediaElementTest, ParcSafariSeekWithAutoplayKeepsPreloadAuto) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  Media()->setAttribute(html_names::kAutoplayAttr, g_empty_atom);
  Media()->setPreload(AtomicString("metadata"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  ASSERT_TRUE(Media()->paused());
  Media()->setCurrentTime(1);

  Media()->removeAttribute(html_names::kAutoplayAttr);
  Media()->SetSrc(AtomicString("http://example.com/bar.mp4"));
  EXPECT_EQ(WebMediaPlayer::kPreloadAuto, Media()->EffectivePreloadType());
  Media()->removeAttribute(html_names::kSrcAttr);
  test::RunPendingTasks();
}

TEST_P(ParcMediaElementTest, ParcSafariFragmentStartKeepsPreloadAuto) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(AtomicString("http://example.com/foo.mp4#t=2"));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveMetadata);

  Media()->setPreload(AtomicString("none"));
  Media()->SetSrc(AtomicString("http://example.com/bar.mp4"));
  EXPECT_EQ(WebMediaPlayer::kPreloadAuto, Media()->EffectivePreloadType());
  Media()->removeAttribute(html_names::kSrcAttr);
  test::RunPendingTasks();
}

TEST_P(ParcMediaElementTest, ParcSafariPlayBeforeResourceSelectionLoads) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kNoUserGestureRequired);
  Media()->setPreload(AtomicString("none"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->Play();
  test::RunPendingTasks();
  EXPECT_FALSE(LoadIsDeferred());
  EXPECT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_TRUE(ParcPreparesToPlay());
}

TEST_P(ParcMediaElementTest, ParcSafariPlayStartsDeferredLoad) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kNoUserGestureRequired);
  Media()->setPreload(AtomicString("none"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(LoadIsDeferred());
  Media()->Play();
  test::RunPendingTasks();
  EXPECT_FALSE(LoadIsDeferred());
  EXPECT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_TRUE(ParcPreparesToPlay());
}

TEST_P(ParcMediaElementTest, ParcChromeLoadDoesNotKeepPreloadForLaterLoads) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->setPreload(AtomicString("none"));
  Media()->load();
  test::RunPendingTasks();
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  EXPECT_TRUE(LoadIsDeferred());
  EXPECT_FALSE(Media()->GetWebMediaPlayer());
}

TEST_P(ParcMediaElementTest, ParcSafariAutoplayAttributeStartsDeferredLoad) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  Media()->setPreload(AtomicString("none"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(LoadIsDeferred());

  EXPECT_CALL(*MockMediaPlayer(), SetPreload(WebMediaPlayer::kPreloadAuto))
      .Times(testing::AtLeast(1));
  Media()->setAttribute(html_names::kAutoplayAttr, g_empty_atom);
  test::RunPendingTasks();
  EXPECT_FALSE(LoadIsDeferred());
  EXPECT_TRUE(Media()->GetWebMediaPlayer());
}

TEST_P(ParcMediaElementTest, ParcChromeAutoplayAttributeKeepsLoadDeferred) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kNoUserGestureRequired);
  Media()->setPreload(AtomicString("none"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(LoadIsDeferred());

  Media()->setAttribute(html_names::kAutoplayAttr, g_empty_atom);
  test::RunPendingTasks();
  EXPECT_TRUE(LoadIsDeferred());
  EXPECT_FALSE(Media()->GetWebMediaPlayer());
}

TEST_P(ParcMediaElementTest, ParcChromeEffectivePreloadUnchanged) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  Media()->setPreload(AtomicString("none"));
  Media()->setAttribute(html_names::kAutoplayAttr, g_empty_atom);
  EXPECT_EQ(WebMediaPlayer::kPreloadNone, Media()->EffectivePreloadType());
  Media()->removeAttribute(html_names::kAutoplayAttr);

  Media()->setPreload(AtomicString("metadata"));
  Media()->load();
  EXPECT_EQ(WebMediaPlayer::kPreloadMetaData, Media()->EffectivePreloadType());
}

class ParcTimeupdateTest : public ParcMediaElementTest {
 protected:
  void StartPlaying(double time) {
    WebTimeRanges seekable;
    seekable.Add(0, 10);
    EXPECT_CALL(*MockMediaPlayer(), Seekable).WillRepeatedly(Return(seekable));
    EXPECT_CALL(*MockMediaPlayer(), Duration).WillRepeatedly(Return(10.0));
    SetTime(time);
    Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
    test::RunPendingTasks();
    SetReadyState(HTMLMediaElement::kHaveFutureData);
    Media()->Play();
    test::RunPendingTasks();
    timeupdate_ = MakeGarbageCollected<EventCountingListener>();
    Media()->addEventListener(event_type_names::kTimeupdate, timeupdate_);
  }

  void SetTime(double time) {
    EXPECT_CALL(*MockMediaPlayer(), CurrentTime).WillRepeatedly(Return(time));
  }

  int Timeupdates() {
    test::RunPendingTasks();
    return timeupdate_->count();
  }

  Persistent<EventCountingListener> timeupdate_;
};

INSTANTIATE_TEST_SUITE_P(Audio,
                         ParcTimeupdateTest,
                         testing::Values(MediaTestParam::kAudio));
INSTANTIATE_TEST_SUITE_P(Video,
                         ParcTimeupdateTest,
                         testing::Values(MediaTestParam::kVideo));

TEST_P(ParcTimeupdateTest, SafariPauseAtReportedTimeFiresNone) {
  SetUserAgent(kParcSafariUserAgent);
  StartPlaying(0);
  Media()->pause();
  EXPECT_EQ(Timeupdates(), 0);

  Media()->Play();
  SetTime(1.5);
  CallPlaybackProgressTimerFired();
  EXPECT_EQ(Timeupdates(), 1);
  Media()->pause();
  EXPECT_EQ(Timeupdates(), 1);
}

TEST_P(ParcTimeupdateTest, ChromePauseAlwaysFires) {
  SetUserAgent(kParcChromeUserAgent);
  StartPlaying(0);
  Media()->pause();
  EXPECT_EQ(Timeupdates(), 1);

  Media()->Play();
  SetTime(1.5);
  CallPlaybackProgressTimerFired();
  EXPECT_EQ(Timeupdates(), 2);
  Media()->pause();
  EXPECT_EQ(Timeupdates(), 3);
}

TEST_P(ParcTimeupdateTest, SafariPeriodicThrottledSinceLastTimeupdate) {
  static thread_local base::TimeTicks mock_time_ticks;
  mock_time_ticks = base::TimeTicks::Now();
  base::subtle::ScopedTimeClockOverrides time_override(
      nullptr, []() { return mock_time_ticks; }, nullptr);
  SetUserAgent(kParcSafariUserAgent);
  StartPlaying(0);

  SetTime(1);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  EXPECT_EQ(Timeupdates(), 1);
  SetReadyState(HTMLMediaElement::kHaveFutureData);

  SetTime(1.1);
  mock_time_ticks += base::Milliseconds(100);
  CallPlaybackProgressTimerFired();
  EXPECT_EQ(Timeupdates(), 1);

  SetTime(1.3);
  mock_time_ticks += base::Milliseconds(160);
  CallPlaybackProgressTimerFired();
  EXPECT_EQ(Timeupdates(), 2);
}

TEST_P(ParcTimeupdateTest, ChromePeriodicNotThrottledByClock) {
  static thread_local base::TimeTicks mock_time_ticks;
  mock_time_ticks = base::TimeTicks::Now();
  base::subtle::ScopedTimeClockOverrides time_override(
      nullptr, []() { return mock_time_ticks; }, nullptr);
  SetUserAgent(kParcChromeUserAgent);
  StartPlaying(0);

  SetTime(1);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  EXPECT_EQ(Timeupdates(), 1);
  SetReadyState(HTMLMediaElement::kHaveFutureData);

  SetTime(1.1);
  mock_time_ticks += base::Milliseconds(100);
  CallPlaybackProgressTimerFired();
  EXPECT_EQ(Timeupdates(), 2);
}

TEST_P(ParcTimeupdateTest, SafariSeekDropsQueuedPeriodicTimeupdate) {
  SetUserAgent(kParcSafariUserAgent);
  StartPlaying(0);
  SetTime(1);
  CallPlaybackProgressTimerFired();
  Media()->setCurrentTime(0.5);
  EXPECT_EQ(Timeupdates(), 0);
  EXPECT_TRUE(Media()->seeking());
}

TEST_P(ParcTimeupdateTest, SafariSeekKeepsQueuedPauseTimeupdate) {
  SetUserAgent(kParcSafariUserAgent);
  StartPlaying(0);
  SetTime(1);
  Media()->pause();
  Media()->setCurrentTime(0.5);
  EXPECT_EQ(Timeupdates(), 1);
}

TEST_P(ParcTimeupdateTest, ChromeSeekKeepsQueuedPeriodicTimeupdate) {
  SetUserAgent(kParcChromeUserAgent);
  StartPlaying(0);
  SetTime(1);
  CallPlaybackProgressTimerFired();
  Media()->setCurrentTime(0.5);
  EXPECT_EQ(Timeupdates(), 1);
}

TEST_P(ParcTimeupdateTest, SafariSeekFinishedTimeupdateIsUnconditional) {
  SetUserAgent(kParcSafariUserAgent);
  StartPlaying(1);
  Media()->pause();
  EXPECT_EQ(Timeupdates(), 0);

  Media()->setCurrentTime(2);
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  EXPECT_FALSE(Media()->seeking());
  EXPECT_EQ(Timeupdates(), 1);
}

TEST_P(ParcTimeupdateTest, SafariLoadResetTimeupdateIsUnconditional) {
  SetUserAgent(kParcSafariUserAgent);
  StartPlaying(0);
  Media()->setCurrentTime(1);
  ASSERT_EQ(Media()->currentTime(), 1);

  Media()->removeAttribute(html_names::kSrcAttr);
  Media()->load();
  EXPECT_EQ(Timeupdates(), 1);
}

namespace {

class SeekableToOneMediaSourceAttachment final
    : public StubMediaSourceAttachment {
 public:
  WebTimeRanges SeekableInternal(MediaSourceTracer* tracer) const override {
    return WebTimeRanges(0, 1);
  }
};

}

TEST_P(ParcMediaElementTest, ParcSafariEndedByPositionFiresOnce) {
  SetUserAgent(kParcSafariUserAgent);
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPause, pause);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_CALL(*MockMediaPlayer(), Seekable())
      .WillRepeatedly(Return(WebTimeRanges(0, 1)));
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  ASSERT_TRUE(Media()->paused());
  EXPECT_FALSE(Media()->ended());

  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(1.0));
  Media()->setCurrentTime(1.0);
  TimeChanged();
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->ended());
  EXPECT_EQ(ended->count(), 1);
  EXPECT_EQ(pause->count(), 0);

  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(0.5));
  Media()->setCurrentTime(0.5);
  TimeChanged();
  EXPECT_FALSE(Media()->ended());
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(1.0));
  Media()->setCurrentTime(1.0);
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_EQ(ended->count(), 2);

  Media()->setCurrentTime(1.0);
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_EQ(ended->count(), 2);
  Media()->setCurrentTime(0.5);
  test::RunPendingTasks();
  Media()->setCurrentTime(1.0);
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_EQ(ended->count(), 3);
}

TEST_P(ParcMediaElementTest, ParcSafariEndedOnceAcrossRateZeroPlay) {
  SetUserAgent(kParcSafariUserAgent);
  double now = 0.5;
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime())
      .WillRepeatedly(testing::ReturnPointee(&now));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);
  auto* pause = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPause, pause);

  now = 1.0;
  TimeChanged();
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->paused());
  ASSERT_EQ(ended->count(), 1);
  ASSERT_EQ(pause->count(), 1);

  Media()->setPlaybackRate(0);
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());
  Media()->setPlaybackRate(1);
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());
  EXPECT_EQ(pause->count(), 2);
  EXPECT_EQ(ended->count(), 1);
}

TEST_P(ParcMediaElementTest, ParcSafariEmptyMediaEnds) {
  SetUserAgent(kParcSafariUserAgent);
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);
  EXPECT_CALL(*MockMediaPlayer(), Duration()).WillRepeatedly(Return(0.0));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());

  TimeChanged();
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());
  EXPECT_FALSE(Media()->ended());
  EXPECT_EQ(ended->count(), 1);
}

TEST_P(ParcMediaElementTest, ParcSafariEndedWhenPlayerEndsWhileWaiting) {
  SetUserAgent(kParcSafariUserAgent);
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());
  SetReadyState(HTMLMediaElement::kHaveCurrentData);

  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(1.0));
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());
  EXPECT_EQ(ended->count(), 1);
}

TEST_P(ParcMediaElementTest, ParcChromeEndedByPlayer) {
  SetUserAgent(kParcChromeUserAgent);
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_CALL(*MockMediaPlayer(), Seekable())
      .WillRepeatedly(Return(WebTimeRanges(0, 1)));
  SetReadyState(HTMLMediaElement::kHaveEnoughData);

  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(1.0));
  Media()->setCurrentTime(1.0);
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->ended());
  EXPECT_EQ(ended->count(), 0);

  EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
  TimeChanged();
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->ended());
  EXPECT_EQ(ended->count(), 2);
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceEndsOnlyOnceEnded) {
  SetUserAgent(kParcSafariUserAgent);
  auto* ended = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEnded, ended);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  auto attachment = base::MakeRefCounted<SeekableToOneMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_FALSE(Media()->paused());

  EXPECT_CALL(*MockMediaPlayer(), CurrentTime()).WillRepeatedly(Return(1.0));
  Media()->setCurrentTime(1.0);
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->ended());
  EXPECT_FALSE(Media()->paused());
  EXPECT_EQ(ended->count(), 0);

  auto* playing = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPlaying, playing);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  test::RunPendingTasks();
  EXPECT_EQ(playing->count(), 1);

  attachment->ParcSetMediaSourceEnded(true);
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());
  EXPECT_EQ(ended->count(), 1);

  attachment->ParcSetMediaSourceEnded(false);
  TimeChanged();
  attachment->ParcSetMediaSourceEnded(true);
  TimeChanged();
  test::RunPendingTasks();
  EXPECT_EQ(ended->count(), 2);
}

TEST_P(ParcMediaElementTest, ParcChromeNoPlayingWithCanplayAfterEnd) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();
  test::RunPendingTasks();
  EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
  ASSERT_FALSE(Media()->paused());

  auto* playing = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kPlaying, playing);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  test::RunPendingTasks();
  EXPECT_EQ(playing->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariWaitingOnlyAfterFutureData) {
  SetUserAgent(kParcSafariUserAgent);
  auto* waiting = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kWaiting, waiting);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  Media()->Play();
  test::RunPendingTasks();
  EXPECT_EQ(waiting->count(), 1);

  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  test::RunPendingTasks();
  EXPECT_EQ(waiting->count(), 1);

  SetReadyState(HTMLMediaElement::kHaveFutureData);
  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  test::RunPendingTasks();
  EXPECT_EQ(waiting->count(), 2);
}

TEST_P(ParcMediaElementTest, ParcChromeWaitingFromMetadata) {
  SetUserAgent(kParcChromeUserAgent);
  auto* waiting = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kWaiting, waiting);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  Media()->Play();
  test::RunPendingTasks();
  EXPECT_EQ(waiting->count(), 1);

  SetReadyState(HTMLMediaElement::kHaveCurrentData);
  test::RunPendingTasks();
  EXPECT_EQ(waiting->count(), 2);
}

TEST_P(ParcMediaElementTest, ParcSafariDetachedElementPauses) {
  SetUserAgent(kParcSafariUserAgent);
  NonThrowableExceptionState should_not_throw;

  Media()->GetDocument().body()->AppendChild(Media());
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_CALL(*MockMediaPlayer(), Seekable())
      .WillRepeatedly(Return(WebTimeRanges(0, 1)));
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();
  Media()->setCurrentTime(0.5);
  ASSERT_TRUE(Media()->seeking());
  Media()->remove(should_not_throw);
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->paused());

  TimeChanged();
  Media()->GetDocument().body()->AppendChild(Media());
  Media()->remove(should_not_throw);
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());

  Media()->setAttribute(html_names::kAutoplayAttr, g_empty_atom);
  Media()->GetDocument().body()->AppendChild(Media());
  Media()->Play();
  PauseForInvisibleAutoplay();
  Media()->remove(should_not_throw);
  test::RunPendingTasks();
  EXPECT_TRUE(CanAutoplay());
}

TEST_P(ParcMediaElementTest, ParcSafariDetachedElementWithoutResource) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().body()->AppendChild(Media());
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  ASSERT_FALSE(Media()->paused());

  NonThrowableExceptionState should_not_throw;
  Media()->remove(should_not_throw);
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->paused());
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
}

TEST_P(ParcMediaElementTest, ParcChromeDetachedElementPauses) {
  SetUserAgent(kParcChromeUserAgent);
  NonThrowableExceptionState should_not_throw;

  Media()->GetDocument().body()->AppendChild(Media());
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  Media()->remove(should_not_throw);
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());

  Media()->GetDocument().body()->AppendChild(Media());
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_CALL(*MockMediaPlayer(), Seekable())
      .WillRepeatedly(Return(WebTimeRanges(0, 1)));
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  Media()->Play();
  Media()->setCurrentTime(0.5);
  ASSERT_TRUE(Media()->seeking());
  Media()->remove(should_not_throw);
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->paused());

  Media()->setAttribute(html_names::kAutoplayAttr, g_empty_atom);
  Media()->GetDocument().body()->AppendChild(Media());
  Media()->Play();
  PauseForInvisibleAutoplay();
  Media()->remove(should_not_throw);
  test::RunPendingTasks();
  EXPECT_FALSE(CanAutoplay());
}

TEST_P(ParcMediaElementTest, ParcSafariPauseSelectsResourceOnlyIfPermitted) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  Media()->pause();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);

  LocalFrame::NotifyUserActivation(
      Media()->GetDocument().GetFrame(),
      mojom::UserActivationNotificationType::kTest);
  Media()->pause();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
}

TEST_P(ParcMediaElementTest, ParcChromePauseSelectsResource) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->GetDocument().GetSettings()->SetAutoplayPolicy(
      AutoplayPolicy::Type::kDocumentUserActivationRequired);
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  Media()->pause();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
}

namespace {

void DisallowPlaybackWhileNotVisible(LocalDOMWindow* window) {
  network::ParsedPermissionsPolicy policy;
  policy.emplace_back(
      network::mojom::PermissionsPolicyFeature::kMediaPlaybackWhileNotVisible,
      std::vector<network::OriginWithPossibleWildcards>(),
      std::nullopt,
      false,
      false);
  window->GetSecurityContext().SetPermissionsPolicy(
      network::PermissionsPolicy::CreateFromParsedPolicy(
          policy, window->GetSecurityOrigin()->ToUrlOrigin()));
  ASSERT_FALSE(window->IsFeatureEnabled(
      network::mojom::PermissionsPolicyFeature::kMediaPlaybackWhileNotVisible));
}

}

TEST_P(ParcMediaElementTest, ParcSafariPlaysWhileHiddenDespitePolicy) {
  SetUserAgent(kParcSafariUserAgent);
  DisallowPlaybackWhileNotVisible(GetDomWindow());
  EXPECT_CALL(*MockMediaPlayer(), SetShouldPauseWhenFrameIsHidden(false));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
}

TEST_P(ParcMediaElementTest, ParcChromePausesWhileHiddenUnderPolicy) {
  SetUserAgent(kParcChromeUserAgent);
  DisallowPlaybackWhileNotVisible(GetDomWindow());
  EXPECT_CALL(*MockMediaPlayer(), SetShouldPauseWhenFrameIsHidden(true));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
}

TEST_P(ParcMediaElementTest, ParcSafariWaitForKeyLowersReadyStateOnce) {
  SetUserAgent(kParcSafariUserAgent);
  WaitForPlayer();
  EXPECT_CALL(*MockMediaPlayer(), GetReadyState())
      .WillRepeatedly(Return(WebMediaPlayer::kReadyStateHaveEnoughData));
  ReadyStateChanged();
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveEnoughData);
  ASSERT_TRUE(PotentiallyPlaying());
  auto* waitingforkey = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kWaitingforkey, waitingforkey);
  auto* waiting = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kWaiting, waiting);

  EXPECT_CALL(*MockMediaPlayer(), Buffered())
      .WillRepeatedly(Return(WebTimeRanges(0, 10)));
  EXPECT_TRUE(ParcMediaElement::From(*Media()).WaitForKey());
  EXPECT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveCurrentData);
  ReadyStateChanged();
  EXPECT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveCurrentData);
  EXPECT_TRUE(ParcMediaElement::From(*Media()).WaitForKey());
  test::RunPendingTasks();
  EXPECT_EQ(waitingforkey->count(), 1);
  EXPECT_EQ(waiting->count(), 1);

  EXPECT_CALL(*MockMediaPlayer(), GetReadyState())
      .WillRepeatedly(Return(WebMediaPlayer::kReadyStateHaveFutureData));
  ReadyStateChanged();
  EXPECT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveFutureData);

  EXPECT_CALL(*MockMediaPlayer(), GetReadyState())
      .WillRepeatedly(Return(WebMediaPlayer::kReadyStateHaveEnoughData));
  EXPECT_TRUE(ParcMediaElement::From(*Media()).StopWaitingForKey());
  EXPECT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveEnoughData);

  EXPECT_CALL(*MockMediaPlayer(), Buffered())
      .WillRepeatedly(Return(WebTimeRanges()));
  EXPECT_TRUE(ParcMediaElement::From(*Media()).WaitForKey());
  EXPECT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveMetadata);
  test::RunPendingTasks();
  EXPECT_EQ(waitingforkey->count(), 2);
}

TEST_P(ParcMediaElementTest, ParcSafariWaitForKeyOnlyLowersReadyState) {
  SetUserAgent(kParcSafariUserAgent);
  WaitForPlayer();
  EXPECT_CALL(*MockMediaPlayer(), GetReadyState())
      .WillRepeatedly(Return(WebMediaPlayer::kReadyStateHaveMetadata));
  ReadyStateChanged();
  EXPECT_CALL(*MockMediaPlayer(), Buffered())
      .WillRepeatedly(Return(WebTimeRanges(0, 10)));
  EXPECT_TRUE(ParcMediaElement::From(*Media()).WaitForKey());
  EXPECT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveMetadata);
}

TEST_P(ParcMediaElementTest, ParcSafariLoadEndsTheWaitForKey) {
  SetUserAgent(kParcSafariUserAgent);
  WaitForPlayer();
  auto* waitingforkey = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kWaitingforkey, waitingforkey);
  EXPECT_TRUE(ParcMediaElement::From(*Media()).WaitForKey());
  test::RunPendingTasks();
  Media()->removeAttribute(html_names::kSrcAttr);
  Media()->load();
  EXPECT_TRUE(ParcMediaElement::From(*Media()).WaitForKey());
  test::RunPendingTasks();
  EXPECT_EQ(waitingforkey->count(), 2);
}

TEST_P(ParcMediaElementTest, ParcChromeWaitForKeyIsBlinks) {
  SetUserAgent(kParcChromeUserAgent);
  WaitForPlayer();
  EXPECT_CALL(*MockMediaPlayer(), GetReadyState())
      .WillRepeatedly(Return(WebMediaPlayer::kReadyStateHaveEnoughData));
  ReadyStateChanged();
  auto* waitingforkey = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kWaitingforkey, waitingforkey);
  EXPECT_FALSE(ParcMediaElement::From(*Media()).WaitForKey());
  EXPECT_EQ(Media()->getReadyState(), HTMLMediaElement::kHaveEnoughData);
  EXPECT_FALSE(ParcMediaElement::From(*Media()).StopWaitingForKey());
  test::RunPendingTasks();
  EXPECT_EQ(waitingforkey->count(), 0);
}

namespace {

class ParcPictureInPictureController final : public PictureInPictureController {
 public:
  explicit ParcPictureInPictureController(Document& document)
      : PictureInPictureController(document) {}

  void EnterPictureInPicture(
      HTMLVideoElement*,
      ScriptPromiseResolver<PictureInPictureWindow>*) override {}
  void EnterPictureInPictureImmersive(HTMLVideoElement&) override {}
  void ExitPictureInPicture(HTMLVideoElement*,
                            ScriptPromiseResolver<IDLUndefined>*) override {
    ++exit_count_;
  }
  Status IsElementAllowed(const HTMLVideoElement&, bool) const override {
    return Status::kEnabled;
  }
  void OnExitedPictureInPicture(ScriptPromiseResolver<IDLUndefined>*) override {
  }
  void OnPictureInPictureStateChange() override {}
  void OnMediaPositionStateChanged(
      const media_session::mojom::blink::MediaPositionPtr&) override {}
  Element* PictureInPictureElement() const override { return element_; }
  Element* PictureInPictureElement(TreeScope&) const override {
    return element_;
  }
  bool PictureInPictureEnabled() const override { return true; }
  bool IsPictureInPictureRequestTokenActive() const override { return false; }
  void ActivatePictureInPictureRequestToken() override {}
  bool ConsumePictureInPictureRequestToken() override { return false; }

  int exit_count() const { return exit_count_; }
  void set_element(Element* element) { element_ = element; }

  void Trace(Visitor* visitor) const override {
    visitor->Trace(element_);
    PictureInPictureController::Trace(visitor);
  }

 protected:
  bool IsPictureInPictureElement(const Element* element) const override {
    return IsA<HTMLVideoElement>(element);
  }
  LocalDOMWindow* GetDocumentPictureInPictureWindow() const override {
    return nullptr;
  }
  LocalDOMWindow* GetDocumentPictureInPictureOwner() const override {
    return nullptr;
  }

 private:
  int exit_count_ = 0;
  Member<Element> element_;
};

}

TEST_P(ParcMediaElementTest,
       SafariIdentityPictureInPictureVideoMovesWhenItLeaves) {
  if (!IsA<HTMLVideoElement>(Media())) {
    GTEST_SKIP();
  }
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  PresentSafariIdentity(Media()->GetDocument());
  Media()->GetDocument().body()->AppendChild(Media());
  WaitForPlayer();
  test::RunPendingTasks();
  auto* pip = MakeGarbageCollected<ParcPictureInPictureController>(
      Media()->GetDocument());
  Supplement<Document>::ProvideTo(
      Media()->GetDocument(), static_cast<PictureInPictureController*>(pip));
  pip->set_element(Media());

  auto new_page = CreatePageWithSecurityOrigin(
      origin, false, true);
  PresentSafariIdentity(new_page->GetDocument());
  EXPECT_CALL(*MockMediaPlayer(), ParcMoveToFrame(_)).Times(0);
  new_page->GetDocument().body()->AppendChild(Media());
  test::RunPendingTasks();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), ParcMoveToFrame(_)).WillOnce(Return(true));
  pip->set_element(nullptr);
  To<HTMLVideoElement>(Media())->OnExitedPictureInPicture();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
  EXPECT_FALSE(WasPlayerDestroyed());

  auto* emptied_listener = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEmptied, emptied_listener);
  EXPECT_CALL(*MockMediaPlayer(), ParcMoveToFrame(_)).Times(0);
  GetDomWindow()->FrameDestroyed();
  test::RunPendingTasks();
  EXPECT_FALSE(WasPlayerDestroyed());
  EXPECT_EQ(emptied_listener->count(), 0);
}

TEST_P(ParcMediaElementTest,
       SafariIdentityPictureInPictureVideoMovesWhenItsFrameGoes) {
  if (!IsA<HTMLVideoElement>(Media())) {
    GTEST_SKIP();
  }
  ScopedDocumentPictureInPictureAPIForTest scoped_feature(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  PresentSafariIdentity(Media()->GetDocument());
  Media()->GetDocument().body()->AppendChild(Media());
  WaitForPlayer();
  test::RunPendingTasks();
  auto* pip = MakeGarbageCollected<ParcPictureInPictureController>(
      Media()->GetDocument());
  Supplement<Document>::ProvideTo(
      Media()->GetDocument(), static_cast<PictureInPictureController*>(pip));
  pip->set_element(Media());

  auto new_page = CreatePageWithSecurityOrigin(
      origin, false, true);
  PresentSafariIdentity(new_page->GetDocument());
  new_page->GetDocument().body()->AppendChild(Media());
  test::RunPendingTasks();

  auto* emptied_listener = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kEmptied, emptied_listener);
  EXPECT_CALL(*MockMediaPlayer(), ParcMoveToFrame(_)).WillOnce(Return(true));
  GetDomWindow()->FrameDestroyed();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
  EXPECT_FALSE(WasPlayerDestroyed());
  test::RunPendingTasks();
  EXPECT_EQ(emptied_listener->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariLoadAfterPlayWithoutSourcePauses) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  ScriptState* script_state =
      ToScriptStateForMainWorld(Media()->GetDocument().GetFrame());
  ScriptState::Scope scope(script_state);
  ScriptPromiseTester play(script_state,
                           Media()->playForBindings(script_state));
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  ASSERT_FALSE(Media()->paused());
  ASSERT_EQ(PendingPlayPromiseCount(), 1u);

  Media()->load();
  ASSERT_TRUE(Media()->paused());
  ASSERT_EQ(PendingPlayPromiseCount(), 0u);
  play.WaitUntilSettled();
  EXPECT_TRUE(play.IsRejected());
}

TEST_P(ParcMediaElementTest, ParcChromeLoadAfterPlayWithoutSourceKeepsPlaying) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->Play();
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);

  Media()->load();
  EXPECT_FALSE(Media()->paused());
}

TEST_P(ParcMediaElementTest, ParcSafariSrcAfterPlayWithoutSourceRejectsPlay) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  ScriptState* script_state =
      ToScriptStateForMainWorld(Media()->GetDocument().GetFrame());
  ScriptState::Scope scope(script_state);
  auto play = Media()->playForBindings(script_state);
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  ASSERT_FALSE(Media()->paused());
  ASSERT_EQ(PendingPlayPromiseCount(), 1u);

  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  EXPECT_FALSE(Media()->paused());
  ASSERT_EQ(PendingPlayPromiseCount(), 0u);
  DOMException* exception = ParcPlayRejection(script_state, play);
  ASSERT_TRUE(exception);
  EXPECT_EQ(exception->name(), "AbortError");
}

TEST_P(ParcMediaElementTest, ParcChromeSrcAfterPlayWithoutSourceKeepsPlay) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  ScriptState* script_state =
      ToScriptStateForMainWorld(Media()->GetDocument().GetFrame());
  ScriptState::Scope scope(script_state);
  Media()->playForBindings(script_state);
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  ASSERT_FALSE(Media()->paused());
  ASSERT_EQ(PendingPlayPromiseCount(), 1u);

  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  EXPECT_FALSE(Media()->paused());
  EXPECT_EQ(PendingPlayPromiseCount(), 1u);
}

TEST_P(ParcMediaElementTest, ParcSafariLazyLoadWaitsAtNoSource) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  auto* loadstart = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kLoadstart, loadstart);
  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("lazy"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->IsLazyLoadDeferred());
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
  EXPECT_EQ(loadstart->count(), 0);

  Media()->Play();
  Media()->GetDocument().GetAgent().event_loop()->PerformMicrotaskCheckpoint();
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  EXPECT_EQ(loadstart->count(), 1);
}

TEST_P(ParcMediaElementTest, ParcChromeLazyLoadWaitsAtIdle) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  SetUserAgent(kParcChromeUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("lazy"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->IsLazyLoadDeferred());
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);

  Media()->Play();
  Media()->GetDocument().GetAgent().event_loop()->PerformMicrotaskCheckpoint();
  EXPECT_TRUE(Media()->IsLazyLoadDeferred());
}

TEST_P(ParcMediaElementTest, ParcSafariLazyLoadIgnoresAddedSource) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("lazy"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->IsLazyLoadDeferred());

  Media()->removeAttribute(html_names::kSrcAttr);
  auto* source =
      MakeGarbageCollected<HTMLSourceElement>(Media()->GetDocument());
  source->setAttribute(html_names::kSrcAttr,
                       SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->AppendChild(source);
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->IsLazyLoadDeferred());
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);

  Media()->Play();
  Media()->GetDocument().GetAgent().event_loop()->PerformMicrotaskCheckpoint();
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  EXPECT_EQ(Media()->currentSrc(), KURL(SrcSchemeToURL(TestURLScheme::kHttp)));
}

TEST_P(ParcMediaElementTest, ParcSafariPosterDeferredPlaySelects) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  SetUserAgent(kParcSafariUserAgent);
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  SetLazyMediaLoadStateToDeferredForTesting();

  Media()->Play();
  Media()->GetDocument().GetAgent().event_loop()->PerformMicrotaskCheckpoint();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
  EXPECT_TRUE(Media()->IsLazyLoadDeferred());
}

TEST_P(ParcMediaElementTest, ParcSafariPlayWaitsForQueuedSelection) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  auto* loadstart = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kLoadstart, loadstart);
  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("lazy"));
  SetLazyMediaLoadStateToDeferredForTesting();
  auto* source =
      MakeGarbageCollected<HTMLSourceElement>(Media()->GetDocument());
  source->setAttribute(html_names::kSrcAttr,
                       SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->AppendChild(source);
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);

  Media()->Play();
  Media()->GetDocument().GetAgent().event_loop()->PerformMicrotaskCheckpoint();
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->IsLazyLoadDeferred());
  EXPECT_EQ(loadstart->count(), 0);
}

TEST_P(ParcMediaElementTest,
       ParcSafariPosterDeferredElementSelectsAddedSource) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  SetUserAgent(kParcSafariUserAgent);
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  SetLazyMediaLoadStateToDeferredForTesting();

  auto* source =
      MakeGarbageCollected<HTMLSourceElement>(Media()->GetDocument());
  source->setAttribute(html_names::kSrcAttr,
                       SrcSchemeToURL(TestURLScheme::kHttp));
  Media()->AppendChild(source);
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
}

TEST_P(ParcMediaElementTest, ParcSafariLazyLoadStaysDeferredOnDocumentMove) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  ScopedDocumentPictureInPictureAPIForTest scoped_pip(false);
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("lazy"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->IsLazyLoadDeferred());

  auto* client = MakeGarbageCollected<WebMediaStubLocalFrameClient>(nullptr);
  client->set_user_agent(String(kParcSafariUserAgent));
  DummyPageHolder page(gfx::Size(), nullptr, client);
  page.GetDocument().adoptNode(Media(), ASSERT_NO_EXCEPTION);
  EXPECT_TRUE(Media()->IsLazyLoadDeferred());
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
}

TEST_P(ParcMediaElementTest, ParcSafariLazyLoadResumesAfterSameOriginMove) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  ScopedDocumentPictureInPictureAPIForTest scoped_pip(false);
  const char* origin = "https://a.com";
  SetSecurityOrigin(origin);
  PresentSafariIdentity(Media()->GetDocument());
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  Media()->GetDocument().body()->AppendChild(Media());
  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("lazy"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->IsLazyLoadDeferred());

  auto new_page = CreatePageWithSecurityOrigin(
      origin, false, true);
  PresentSafariIdentity(new_page->GetDocument());
  new_page->GetDocument().body()->AppendChild(Media());
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->IsLazyLoadDeferred());
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);

  Media()->Play();
  new_page->GetDocument().GetAgent().event_loop()->PerformMicrotaskCheckpoint();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  EXPECT_EQ(new_page->GetDocument().GetFrame(), Media()->LocalFrameForPlayer());
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  EXPECT_NE(Media()->GetWebMediaPlayer(), MockMediaPlayer());
}

TEST_P(ParcMediaElementTest, ParcSafariNothingToLoadEmptiesNetworkState) {
  SetUserAgent(kParcSafariUserAgent);
  auto* pip = MakeGarbageCollected<ParcPictureInPictureController>(
      Media()->GetDocument());
  Supplement<Document>::ProvideTo(Media()->GetDocument(), pip);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  Media()->removeAttribute(html_names::kSrcAttr);
  SetNetworkState(WebMediaPlayer::kNetworkStateEmpty);

  Media()->Play();
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkEmpty);
  EXPECT_EQ(pip->exit_count(), GetParam() == MediaTestParam::kVideo ? 1 : 0);
}

TEST_P(ParcMediaElementTest, ParcChromeNothingToLoadKeepsNetworkState) {
  SetUserAgent(kParcChromeUserAgent);
  auto* pip = MakeGarbageCollected<ParcPictureInPictureController>(
      Media()->GetDocument());
  Supplement<Document>::ProvideTo(Media()->GetDocument(), pip);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->GetWebMediaPlayer());
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  Media()->removeAttribute(html_names::kSrcAttr);
  SetNetworkState(WebMediaPlayer::kNetworkStateEmpty);

  Media()->Play();
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
  EXPECT_EQ(pip->exit_count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariPreloadNoneDefersBlob) {
  SetUserAgent(kParcSafariUserAgent);
  SetSecurityOrigin("http://example.com");
  Media()->setAttribute(html_names::kPreloadAttr, AtomicString("none"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kBlob));
  test::RunPendingTasks();
  EXPECT_FALSE(Media()->GetWebMediaPlayer());
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
}

TEST_P(ParcMediaElementTest, ParcChromePreloadNoneLoadsBlob) {
  SetUserAgent(kParcChromeUserAgent);
  SetSecurityOrigin("http://example.com");
  Media()->setAttribute(html_names::kPreloadAttr, AtomicString("none"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kBlob));
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->GetWebMediaPlayer());
}

TEST_P(ParcMediaElementTest, ParcSafariIdleFiresProgressAndSuspend) {
  SetUserAgent(kParcSafariUserAgent);
  auto* progress = MakeGarbageCollected<EventCountingListener>();
  auto* suspend = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kProgress, progress);
  Media()->addEventListener(event_type_names::kSuspend, suspend);
  EXPECT_CALL(*MockMediaPlayer(), WouldTaintOrigin())
      .WillRepeatedly(Return(false));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  ASSERT_TRUE(ShouldDelayLoadEvent());

  SetNetworkState(WebMediaPlayer::kNetworkStateIdle);
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
  EXPECT_EQ(progress->count(), 1);
  EXPECT_EQ(suspend->count(), 1);
  EXPECT_FALSE(ShouldDelayLoadEvent());
}

TEST_P(ParcMediaElementTest, ParcChromeIdleFiresSuspendOnly) {
  SetUserAgent(kParcChromeUserAgent);
  auto* progress = MakeGarbageCollected<EventCountingListener>();
  auto* suspend = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kProgress, progress);
  Media()->addEventListener(event_type_names::kSuspend, suspend);
  EXPECT_CALL(*MockMediaPlayer(), WouldTaintOrigin())
      .WillRepeatedly(Return(false));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);

  SetNetworkState(WebMediaPlayer::kNetworkStateIdle);
  test::RunPendingTasks();
  EXPECT_EQ(progress->count(), 0);
  EXPECT_EQ(suspend->count(), 1);
  EXPECT_TRUE(ShouldDelayLoadEvent());
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceProgressOnlyAtEnd) {
  SetUserAgent(kParcSafariUserAgent);
  auto* progress = MakeGarbageCollected<EventCountingListener>();
  auto* suspend = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kProgress, progress);
  Media()->addEventListener(event_type_names::kSuspend, suspend);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  SetMediaSourceAttachment(base::MakeRefCounted<StubMediaSourceAttachment>());

  SetPreviousProgressTime();
  EXPECT_CALL(*MockMediaPlayer(), DidLoadingProgress())
      .WillRepeatedly(Return(true));
  CallProgressEventTimerFired();
  test::RunPendingTasks();
  EXPECT_EQ(progress->count(), 0);

  ParcMediaElement::From(*Media()).MediaSourceEnded();
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
  EXPECT_EQ(progress->count(), 1);
  EXPECT_EQ(suspend->count(), 1);
}

TEST_P(ParcMediaElementTest, ParcChromeMediaSourceProgressWhileLoading) {
  SetUserAgent(kParcChromeUserAgent);
  auto* progress = MakeGarbageCollected<EventCountingListener>();
  auto* suspend = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kProgress, progress);
  Media()->addEventListener(event_type_names::kSuspend, suspend);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  SetMediaSourceAttachment(base::MakeRefCounted<StubMediaSourceAttachment>());

  SetPreviousProgressTime();
  EXPECT_CALL(*MockMediaPlayer(), DidLoadingProgress())
      .WillRepeatedly(Return(true));
  CallProgressEventTimerFired();
  test::RunPendingTasks();
  EXPECT_GE(progress->count(), 1);

  ParcMediaElement::From(*Media()).MediaSourceEnded();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  test::RunPendingTasks();
  EXPECT_EQ(suspend->count(), 0);
}

TEST_P(ParcTimeupdateTest, SafariCueUpdateQueuesTimeupdate) {
  SetUserAgent(kParcSafariUserAgent);
  StartPlaying(0);
  TextTrack* track = AppendConfiguredTextTrack(Media(), TextTrackMode::kHidden,
                                               TextTrack::kLoaded);
  SetTime(1);
  track->addCue(VTTCue::Create(Media()->GetDocument(), 5, 6, "cue"));
  EXPECT_EQ(Timeupdates(), 1);
}

TEST_P(ParcTimeupdateTest, ChromeCueUpdateQueuesNone) {
  SetUserAgent(kParcChromeUserAgent);
  StartPlaying(0);
  TextTrack* track = AppendConfiguredTextTrack(Media(), TextTrackMode::kHidden,
                                               TextTrack::kLoaded);
  SetTime(1);
  track->addCue(VTTCue::Create(Media()->GetDocument(), 5, 6, "cue"));
  EXPECT_EQ(Timeupdates(), 0);
}

class EventNameListener final : public NativeEventListener {
 public:
  void Invoke(ExecutionContext*, Event* event) override {
    names_.push_back(event->type());
  }
  const Vector<AtomicString>& names() const { return names_; }

 private:
  Vector<AtomicString> names_;
};

TEST_P(ParcTimeupdateTest, SafariSeekCueTimeupdateFollowsSeeked) {
  static thread_local base::TimeTicks mock_time_ticks;
  mock_time_ticks = base::TimeTicks::Now();
  base::subtle::ScopedTimeClockOverrides time_override(
      nullptr, []() { return mock_time_ticks; }, nullptr);
  SetUserAgent(kParcSafariUserAgent);
  StartPlaying(0);
  TextTrack* track = AppendConfiguredTextTrack(Media(), TextTrackMode::kHidden,
                                               TextTrack::kLoaded);
  SetTime(3);
  track->addCue(VTTCue::Create(Media()->GetDocument(), 5, 6, "cue"));
  ASSERT_EQ(Timeupdates(), 1);

  auto* events = MakeGarbageCollected<EventNameListener>();
  Media()->addEventListener(event_type_names::kTimeupdate, events);
  Media()->addEventListener(event_type_names::kSeeked, events);
  Media()->setCurrentTime(1);
  SetTime(1);
  mock_time_ticks += base::Milliseconds(300);
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  ASSERT_FALSE(Media()->seeking());
  test::RunPendingTasks();
  EXPECT_THAT(events->names(),
              testing::ElementsAre(event_type_names::kTimeupdate,
                                   event_type_names::kSeeked,
                                   event_type_names::kTimeupdate));
}

TEST_P(ParcTimeupdateTest, SafariLoopAtEndQueuesTimeupdate) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->setAttribute(html_names::kLoopAttr, g_empty_atom);
  StartPlaying(0);
  SetTime(10);
  EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
  TimeChanged();
  EXPECT_TRUE(Media()->seeking());
  EXPECT_EQ(Timeupdates(), 1);
}

TEST_P(ParcTimeupdateTest, ChromeLoopAtEndQueuesNone) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->setAttribute(html_names::kLoopAttr, g_empty_atom);
  StartPlaying(0);
  SetTime(10);
  EXPECT_CALL(*MockMediaPlayer(), IsEnded()).WillRepeatedly(Return(true));
  TimeChanged();
  EXPECT_TRUE(Media()->seeking());
  EXPECT_EQ(Timeupdates(), 0);
}

TEST_P(ParcTimeupdateTest, SafariPlayerTimeChangeQueuesTimeupdate) {
  SetUserAgent(kParcSafariUserAgent);
  StartPlaying(5);
  SetTime(2);
  ParcPlayerTimeChanged();
  EXPECT_EQ(Timeupdates(), 1);
  EXPECT_EQ(Media()->currentTime(), 2);

  Media()->setCurrentTime(8);
  SetTime(1);
  ParcPlayerTimeChanged();
  EXPECT_EQ(Timeupdates(), 1);
}

TEST_P(ParcTimeupdateTest, ChromePlayerTimeChangeQueuesNone) {
  SetUserAgent(kParcChromeUserAgent);
  StartPlaying(5);
  SetTime(2);
  ParcPlayerTimeChanged();
  EXPECT_EQ(Timeupdates(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceEndedWaitsForTask) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  SetMediaSourceAttachment(base::MakeRefCounted<StubMediaSourceAttachment>());

  ParcMediaElement::From(*Media()).MediaSourceEnded();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceEndedCancelledByLoad) {
  SetUserAgent(kParcSafariUserAgent);
  auto* suspend = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kSuspend, suspend);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  SetMediaSourceAttachment(base::MakeRefCounted<StubMediaSourceAttachment>());

  ParcMediaElement::From(*Media()).MediaSourceEnded();
  Media()->load();
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  EXPECT_EQ(suspend->count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariLazyResumeWaitsForTask) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("lazy"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->IsLazyLoadDeferred());
  ASSERT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);

  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("eager"));
  Media()->GetDocument().GetAgent().event_loop()->PerformMicrotaskCheckpoint();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
  test::RunPendingTasks();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
}

TEST_P(ParcMediaElementTest, ParcSafariLazyResumeCancelledByLoad) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  SetUserAgent(kParcSafariUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("lazy"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->IsLazyLoadDeferred());

  Media()->Play();
  ASSERT_TRUE(HasParcLazyLoadResumeTask());
  Media()->load();
  EXPECT_FALSE(HasParcLazyLoadResumeTask());
  test::RunPendingTasks();
  EXPECT_TRUE(Media()->IsLazyLoadDeferred());
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
}

TEST_P(ParcMediaElementTest, ParcChromeLazyResumeRunsInMicrotask) {
  ScopedLazyLoadVideoAndAudioForTest scoped_feature(true);
  SetUserAgent(kParcChromeUserAgent);
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("lazy"));
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ASSERT_TRUE(Media()->IsLazyLoadDeferred());

  Media()->setAttribute(html_names::kLoadingAttr, AtomicString("eager"));
  Media()->GetDocument().GetAgent().event_loop()->PerformMicrotaskCheckpoint();
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkLoading);
  EXPECT_FALSE(HasParcLazyLoadResumeTask());
}

class ParcClosingMediaSourceAttachment final
    : public StubMediaSourceAttachment {
 public:
  void Close(MediaSourceTracer* tracer) override { ++close_count_; }
  int close_count() const { return close_count_; }

 private:
  int close_count_ = 0;
};

TEST_P(ParcMediaElementTest, ParcSafariMediaEngineErrorClosesMediaSource) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  auto attachment = base::MakeRefCounted<ParcClosingMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);

  EXPECT_CALL(*MockMediaPlayer(), GetNetworkState())
      .WillRepeatedly(Return(WebMediaPlayer::kNetworkStateDecodeError));
  NetworkStateChanged();
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrDecode);
  EXPECT_EQ(attachment->close_count(), 1);
}

TEST_P(ParcMediaElementTest, ParcChromeMediaEngineErrorKeepsMediaSource) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  auto attachment = base::MakeRefCounted<ParcClosingMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);

  EXPECT_CALL(*MockMediaPlayer(), GetNetworkState())
      .WillRepeatedly(Return(WebMediaPlayer::kNetworkStateDecodeError));
  NetworkStateChanged();
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(attachment->close_count(), 0);
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceErrorFailsAtOnce) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  auto attachment = base::MakeRefCounted<ParcClosingMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);
  auto* error = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kError, error);

  ParcMediaElement::From(*Media()).MediaSourceEndedWithError(
      false);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrDecode);
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
  EXPECT_EQ(attachment->close_count(), 1);

  EXPECT_CALL(*MockMediaPlayer(), GetNetworkState())
      .WillRepeatedly(Return(WebMediaPlayer::kNetworkStateDecodeError));
  NetworkStateChanged();
  test::RunPendingTasks();
  EXPECT_EQ(error->count(), 1);
  EXPECT_EQ(attachment->close_count(), 1);
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceErrorBeforeMetadata) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  auto attachment = base::MakeRefCounted<ParcClosingMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);
  auto* error = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kError, error);

  ParcMediaElement::From(*Media()).MediaSourceEndedWithError(
      false);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrSrcNotSupported);
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkNoSource);
  EXPECT_EQ(attachment->close_count(), 1);
  test::RunPendingTasks();
  EXPECT_EQ(error->count(), 1);
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceNetworkErrorFailsAtOnce) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  auto attachment = base::MakeRefCounted<ParcClosingMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);

  ParcMediaElement::From(*Media()).MediaSourceEndedWithError(
      true);
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrNetwork);
  EXPECT_EQ(Media()->getNetworkState(), HTMLMediaElement::kNetworkIdle);
  EXPECT_EQ(attachment->close_count(), 1);
}

TEST_P(ParcMediaElementTest, ParcChromeMediaSourceErrorWaitsForPlayer) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  auto attachment = base::MakeRefCounted<ParcClosingMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);
  auto* error = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(event_type_names::kError, error);

  ParcMediaElement::From(*Media()).MediaSourceEndedWithError(
      true);
  EXPECT_FALSE(Media()->error());

  EXPECT_CALL(*MockMediaPlayer(), GetNetworkState())
      .WillRepeatedly(Return(WebMediaPlayer::kNetworkStateNetworkError));
  NetworkStateChanged();
  ASSERT_TRUE(Media()->error());
  EXPECT_EQ(Media()->error()->code(), MediaError::kMediaErrNetwork);
  test::RunPendingTasks();
  EXPECT_EQ(error->count(), 1);
  EXPECT_EQ(attachment->close_count(), 0);
}

}

namespace blink {
class ParcMediaMockTimeTest : public ParcMediaElementTest {
 public:
  ParcMediaMockTimeTest()
      : ParcMediaElementTest(test::TaskEnvironment::TimeSource::MOCK_TIME) {}
};
INSTANTIATE_TEST_SUITE_P(Audio,
                         ParcMediaMockTimeTest,
                         testing::Values(MediaTestParam::kAudio));
TEST_P(ParcMediaMockTimeTest, EndedGestureExpiresAfterOneSecond) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  auto* frame = Media()->GetDocument().GetFrame();
  LocalFrame::NotifyUserActivation(
      frame, mojom::UserActivationNotificationType::kTest);
  Media()->Play();
  LocalFrame::ConsumeTransientUserActivation(frame);
  Media()->DispatchEvent(*Event::Create(event_type_names::kEnded));
  task_environment_.AdvanceClock(base::Seconds(1));
  auto* at_boundary =
      MakeGarbageCollected<HTMLAudioElement>(Media()->GetDocument());
  EXPECT_FALSE(at_boundary->Play().has_value());
  task_environment_.AdvanceClock(base::Microseconds(1));
  auto* expired =
      MakeGarbageCollected<HTMLAudioElement>(Media()->GetDocument());
  EXPECT_EQ(expired->Play(), DOMExceptionCode::kNotAllowedError);
}

TEST_P(ParcMediaElementTest, ParcPowerRestrictedMutedPlaybackSafari) {
  SetUserAgent(kParcSafariUserAgent);
  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetMediaPowerRestricted(true);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  Media()->setMuted(true);
  bool safari_video = GetParam() == MediaTestParam::kVideo;
  EXPECT_EQ(Media()->Play().has_value(), safari_video);
  Media()->pause();
  if (safari_video) {
    ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetMediaPowerRestricted(false);
    EXPECT_FALSE(Media()->Play().has_value());
    Media()->pause();
  }
}
TEST_P(ParcMediaElementTest, ParcPowerRestrictedMutedPlaybackChrome) {
  SetUserAgent(kParcChromeUserAgent);
  ParcPageMediaState::From(*Media()->GetDocument().GetPage())
      .SetMediaPowerRestricted(true);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  Media()->setMuted(true);
  EXPECT_FALSE(Media()->Play().has_value());
  Media()->pause();
}

TEST_P(ParcMediaMockTimeTest, ParcHiddenStartDoesNotStopAdmittedPlayback) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  auto* frame = Media()->GetDocument().GetFrame();
  LocalFrame::NotifyUserActivation(
      frame, mojom::UserActivationNotificationType::kTest);
  ASSERT_FALSE(Media()->Play().has_value());
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  LocalFrame::ConsumeTransientUserActivation(frame);
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);
  EXPECT_FALSE(Media()->paused());
  Media()->pause();
  EXPECT_FALSE(Media()->Play().has_value());
  Media()->pause();
  task_environment_.AdvanceClock(base::Seconds(10) + base::Microseconds(1));
  EXPECT_EQ(Media()->Play(), DOMExceptionCode::kNotAllowedError);
  Media()->setMuted(true);
  EXPECT_FALSE(Media()->Play().has_value());
}

TEST_P(ParcMediaElementTest, ParcChromeHiddenStartKeepsElementGrant) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);
  EXPECT_FALSE(Media()->Play().has_value());
}

TEST_P(ParcMediaElementTest, ParcLiveStreamUsesDocumentAudioAllowance) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  auto* frame = Media()->GetDocument().GetFrame();
  auto* stream = MakeGarbageCollected<HTMLAudioElement>(Media()->GetDocument());
  stream->SetSrcObjectVariant(MakeGarbageCollected<MediaStreamDescriptor>(
      MediaStreamComponentVector(), MediaStreamComponentVector()));
  EXPECT_EQ(stream->Play(), DOMExceptionCode::kNotAllowedError);
  LocalFrame::NotifyUserActivation(
      frame, mojom::UserActivationNotificationType::kTest);
  Media()->Play();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  LocalFrame::ConsumeTransientUserActivation(frame);
  ASSERT_TRUE(MediaIsPlaying());
  EXPECT_FALSE(stream->Play().has_value());
}

TEST_P(ParcMediaElementTest, ParcLiveStreamUsesCaptureAllowance) {
  SetUserAgent(kParcSafariUserAgent);
  ParcStickyActivationOnly(Media());
  Media()->SetSrcObjectVariant(MakeGarbageCollected<MediaStreamDescriptor>(
      MediaStreamComponentVector(), MediaStreamComponentVector()));
  EXPECT_EQ(Media()->Play(), DOMExceptionCode::kNotAllowedError);
  Media()->GetDocument().GetFrame()->SetIsCapturingMediaCallback(
      base::BindRepeating([] { return true; }));
  EXPECT_FALSE(Media()->Play().has_value());
}

TEST_P(ParcMediaElementTest, ParcTrackAnnouncementRechecksSoundSafari) {
  if (GetParam() != MediaTestParam::kVideo)
    GTEST_SKIP();
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  EXPECT_CALL(*MockMediaPlayer(), HasAudio()).WillRepeatedly(Return(false));
  ASSERT_FALSE(Media()->Play().has_value());
  AddAudioTrack();
  EXPECT_EQ(Media()->paused(), true);
  Media()->pause();
}
TEST_P(ParcMediaElementTest, ParcTrackAnnouncementRechecksSoundChrome) {
  if (GetParam() != MediaTestParam::kVideo)
    GTEST_SKIP();
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  EXPECT_CALL(*MockMediaPlayer(), HasAudio()).WillRepeatedly(Return(false));
  ASSERT_FALSE(Media()->Play().has_value());
  AddAudioTrack();
  EXPECT_EQ(Media()->paused(), false);
  Media()->pause();
}
TEST_P(ParcMediaMockTimeTest, HiddenAutoplayLoadGrantIsSingleUse) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kHttp));
  test::RunPendingTasks();
  ParcStickyActivationOnly(Media());
  auto* frame = Media()->GetDocument().GetFrame();
  LocalFrame::NotifyUserActivation(
      frame, mojom::UserActivationNotificationType::kTest);
  Media()->Play();
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  LocalFrame::ConsumeTransientUserActivation(frame);
  Media()->SetBooleanAttribute(html_names::kAutoplayAttr, true);
  SetPageVisibility(mojom::blink::PageVisibilityState::kHidden);
  PrepareReplacementPlayer();
  Media()->SetSrc(AtomicString("https://example.org/replacement.mp4"));
  test::RunPendingTasks();
  task_environment_.AdvanceClock(base::Seconds(11));
  ASSERT_TRUE(HasHiddenAutoplayGrant());
  EXPECT_EQ(Media()->Play(), DOMExceptionCode::kNotAllowedError);
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  EXPECT_FALSE(Media()->paused());
  EXPECT_FALSE(HasHiddenAutoplayGrant());
  Media()->pause();
  task_environment_.AdvanceClock(base::Seconds(11));
  EXPECT_EQ(Media()->Play(), DOMExceptionCode::kNotAllowedError);
}

namespace {
constexpr char kParcAirPlayContextId[] = "6F1B3B57-0D0B-4B4A-9C55-3C3E2E3B1A11";
}

TEST_P(ParcMediaElementTest, ParcSafariAirPlayTargetAndWirelessEvent) {
  SetUserAgent(kParcSafariUserAgent);
  WaitForPlayer();
  base::RunLoop().RunUntilIdle();
  auto* listener = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(
      parc_media_element_names::Webkitcurrentplaybacktargetiswirelesschanged(),
      listener);
  EXPECT_CALL(
      *MockMediaPlayer(),
      ParcSetPlaybackTarget(std::string_view(kParcAirPlayContextId), true));
  ParcSetPlaybackTarget(kParcAirPlayContextId, "Living Room", true);
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  ParcPlaybackTargetIsWirelessChanged(true);
  EXPECT_FALSE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
  test::RunPendingTasks();
  EXPECT_TRUE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
  EXPECT_EQ(listener->count(), 1);

  EXPECT_CALL(*MockMediaPlayer(),
              ParcSetPlaybackTarget(std::string_view(), false));
  ParcSetPlaybackTarget(String(), String(), false);
  test::RunPendingTasks();
  EXPECT_FALSE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
  EXPECT_EQ(listener->count(), 2);
}

TEST_P(ParcMediaElementTest, ParcSafariAirPlayTintAloneLeavesThePlayer) {
  SetUserAgent(kParcSafariUserAgent);
  WaitForPlayer();
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(
      *MockMediaPlayer(),
      ParcSetPlaybackTarget(std::string_view(kParcAirPlayContextId), true));
  ParcSetPlaybackTarget(kParcAirPlayContextId, "Living Room", true, 0xFF72B6E1);
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());
  EXPECT_CALL(*MockMediaPlayer(), ParcSetPlaybackTarget(_, _)).Times(0);
  ParcSetPlaybackTarget(kParcAirPlayContextId, "Living Room", true, 0xFFBAA4E0);
  EXPECT_TRUE(
      ParcMediaElementAirPlay::From(*Media()).AirPlayTintedGlyph().contains(
          "rgba(186,164,224,1)"));
}

TEST_P(ParcMediaElementTest, ParcSafariWirelessNeedsTheTarget) {
  SetUserAgent(kParcSafariUserAgent);
  WaitForPlayer();
  base::RunLoop().RunUntilIdle();
  ParcPlaybackTargetIsWirelessChanged(true);
  test::RunPendingTasks();
  EXPECT_FALSE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
}

TEST_P(ParcMediaElementTest, ParcChromeIgnoresAirPlayTarget) {
  WaitForPlayer();
  EXPECT_CALL(*MockMediaPlayer(), ParcSetPlaybackTarget(_, _)).Times(0);
  ParcSetPlaybackTarget(kParcAirPlayContextId, "Living Room", true);
  ParcPlaybackTargetIsWirelessChanged(true);
  test::RunPendingTasks();
  EXPECT_FALSE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
}

TEST_P(ParcMediaElementTest, ParcSafariAirPlayDenyDisablesExternalPlayback) {
  SetUserAgent(kParcSafariUserAgent);
  WaitForPlayer();
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(*MockMediaPlayer(), ParcSupportsPlaybackTarget())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(*MockMediaPlayer(), ParcSetWirelessVideoPlaybackDisabled(true));
  Media()->setAttribute(parc_media_element_names::XWebkitAirplayAttr(),
                        AtomicString("deny"));
  media_player_observer().WaitUntilReceivedMessage();
  ASSERT_TRUE(media_player_observer().received_playback_target_state());
  EXPECT_FALSE(media_player_observer()
                   .received_playback_target_state()
                   ->supports_target);
  EXPECT_FALSE(media_player_observer()
                   .received_playback_target_state()
                   ->requires_monitoring);
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), ParcSupportsPlaybackTarget())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(*MockMediaPlayer(), ParcSetWirelessVideoPlaybackDisabled(false));
  Media()->setAttribute(parc_media_element_names::XWebkitAirplayAttr(),
                        AtomicString("allow"));
  media_player_observer().WaitUntilReceivedMessage();
  EXPECT_TRUE(media_player_observer()
                  .received_playback_target_state()
                  ->supports_target);
}

TEST_P(ParcMediaElementTest, ParcLegacyEmeHandlerAttributesNeedSafariIdentity) {
  Media()->GetDocument().GetSettings()->SetScriptEnabled(true);
  const struct {
    const char* attribute;
    const char* event;
  } kHandlers[] = {{"onwebkitkeyadded", "webkitkeyadded"},
                   {"onwebkitkeyerror", "webkitkeyerror"},
                   {"onwebkitkeymessage", "webkitkeymessage"},
                   {"onwebkitneedkey", "webkitneedkey"}};
  for (const char* user_agent : {kParcSafariUserAgent, kParcChromeUserAgent}) {
    SetUserAgent(user_agent);
    for (const auto& handler : kHandlers) {
      const QualifiedName attribute(AtomicString(handler.attribute));
      Media()->setAttribute(attribute, AtomicString("void 0"));
      EXPECT_EQ(
          !!Media()->GetAttributeEventListener(AtomicString(handler.event)),
          user_agent == kParcSafariUserAgent)
          << user_agent << " " << handler.attribute;
      Media()->removeAttribute(attribute);
    }
  }
}

TEST_P(ParcMediaElementTest, ParcSafariManagedMediaSourceOpensWithAlternative) {
  SetUserAgent(kParcSafariUserAgent);
  AppendSource(SrcSchemeToURL(TestURLScheme::kBlob));
  test::RunPendingTasks();
  auto attachment = base::MakeRefCounted<ManagedMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);
  MediaSourceOpened();
  EXPECT_EQ(attachment->opens(), 0);
  AppendSource(SrcSchemeToURL(TestURLScheme::kBlob));
  EXPECT_EQ(attachment->opens(), 0);
  AppendSource(AtomicString("https://example.com/stream.m3u8"));
  EXPECT_EQ(attachment->opens(), 1);
}

TEST_P(ParcMediaElementTest,
       ParcSafariManagedMediaSourceOpensWithDisableRemotePlayback) {
  SetUserAgent(kParcSafariUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kBlob));
  test::RunPendingTasks();
  auto attachment = base::MakeRefCounted<ManagedMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);
  MediaSourceOpened();
  EXPECT_EQ(attachment->opens(), 0);
  Media()->SetBooleanAttribute(html_names::kDisableremoteplaybackAttr, true);
  EXPECT_EQ(attachment->opens(), 1);
}

TEST_P(ParcMediaElementTest, ParcChromeManagedMediaSourceOpensAtOnce) {
  SetUserAgent(kParcChromeUserAgent);
  Media()->SetSrc(SrcSchemeToURL(TestURLScheme::kBlob));
  test::RunPendingTasks();
  auto attachment = base::MakeRefCounted<ManagedMediaSourceAttachment>();
  SetMediaSourceAttachment(attachment);
  MediaSourceOpened();
  EXPECT_EQ(attachment->opens(), 1);
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceSwitchesToAirPlaySource) {
  SetUserAgent(kParcSafariUserAgent);
  double now = 0;
  EXPECT_CALL(*MockMediaPlayer(), CurrentTime())
      .WillRepeatedly(testing::ReturnPointee(&now));
  const AtomicString alternative("https://example.com/stream.m3u8");
  AppendSource(SrcSchemeToURL(TestURLScheme::kBlob));
  AppendSource(alternative);
  Media()->Play();
  media_player_host().WaitForPlayer();
  base::RunLoop().RunUntilIdle();
  SetMediaSourceAttachment(base::MakeRefCounted<StubMediaSourceAttachment>());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);
  ASSERT_FALSE(Media()->paused());
  now = 0.5;
  auto* listener = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(
      parc_media_element_names::Webkitcurrentplaybacktargetiswirelesschanged(),
      listener);

  ParcSetPlaybackTarget(kParcAirPlayContextId, "Living Room", true);
  test::RunPendingTasks();
  EXPECT_TRUE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
  EXPECT_EQ(listener->count(), 1);
  base::RunLoop().RunUntilIdle();
  ASSERT_TRUE(media_player_observer().received_playback_target_state());
  EXPECT_TRUE(media_player_observer()
                  .received_playback_target_state()
                  ->supports_target);
  EXPECT_FALSE(
      media_player_observer().received_playback_target_state()->wireless);

  PrepareReplacementPlayer();
  WebTimeRanges seekable;
  seekable.Add(0, 1.0);
  EXPECT_CALL(*MockMediaPlayer(), Seekable()).WillRepeatedly(Return(seekable));
  EXPECT_CALL(*MockMediaPlayer(), ParcSupportsPlaybackTarget())
      .WillRepeatedly(Return(true));
  EXPECT_CALL(
      *MockMediaPlayer(),
      ParcSetPlaybackTarget(std::string_view(kParcAirPlayContextId), true));
  CheckParcPlaybackTargetCompatibility();
  test::RunPendingTasks();
  EXPECT_EQ(Media()->currentSrc(), KURL(alternative));
  EXPECT_FALSE(Media()->paused());
  EXPECT_FALSE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
  EXPECT_EQ(listener->count(), 2);

  EXPECT_CALL(*MockMediaPlayer(), Seek(0.5));
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  SetReadyState(HTMLMediaElement::kHaveFutureData);
  test::RunPendingTasks();
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  ParcPlaybackTargetIsWirelessChanged(true);
  test::RunPendingTasks();
  EXPECT_TRUE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
  EXPECT_EQ(listener->count(), 3);
}

TEST_P(ParcMediaElementTest, ParcSafariMediaSourceWithoutAirPlaySourceStays) {
  SetUserAgent(kParcSafariUserAgent);
  AppendSource(SrcSchemeToURL(TestURLScheme::kBlob));
  Media()->Play();
  media_player_host().WaitForPlayer();
  base::RunLoop().RunUntilIdle();
  SetMediaSourceAttachment(base::MakeRefCounted<StubMediaSourceAttachment>());
  SetReadyState(HTMLMediaElement::kHaveEnoughData);

  ParcSetPlaybackTarget(kParcAirPlayContextId, "Living Room", true);
  test::RunPendingTasks();
  ASSERT_TRUE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
  base::RunLoop().RunUntilIdle();
  ASSERT_TRUE(media_player_observer().received_playback_target_state());
  EXPECT_FALSE(media_player_observer()
                   .received_playback_target_state()
                   ->supports_target);
  EXPECT_FALSE(
      media_player_observer().received_playback_target_state()->wireless);

  CheckParcPlaybackTargetCompatibility();
  test::RunPendingTasks();
  EXPECT_FALSE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
  EXPECT_EQ(Media()->currentSrc(), KURL(SrcSchemeToURL(TestURLScheme::kBlob)));

  ParcSetPlaybackTarget(kParcAirPlayContextId, "Living Room", true);
  test::RunPendingTasks();
  EXPECT_FALSE(
      ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(*Media()));
}

TEST_P(ParcMediaElementTest, ParcSafariPlaybackTargetPickerNeedsMetadata) {
  SetUserAgent(kParcSafariUserAgent);
  WaitForPlayer();
  base::RunLoop().RunUntilIdle();
  ParcMediaElementAirPlay::webkitShowPlaybackTargetPicker(*Media());
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(media_player_observer().received_playback_target_pickers(), 0);
  SetReadyState(HTMLMediaElement::kHaveMetadata);
  ParcMediaElementAirPlay::webkitShowPlaybackTargetPicker(*Media());
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(media_player_observer().received_playback_target_pickers(), 1);
}

TEST_P(ParcMediaElementTest, ParcSafariAvailabilityListenersStartMonitoring) {
  SetUserAgent(kParcSafariUserAgent);
  WaitForPlayer();
  base::RunLoop().RunUntilIdle();
  auto* listener = MakeGarbageCollected<EventCountingListener>();
  Media()->addEventListener(
      parc_media_element_names::Webkitplaybacktargetavailabilitychanged(),
      listener);
  media_player_observer().WaitUntilReceivedMessage();
  ASSERT_TRUE(media_player_observer().received_playback_target_state());
  EXPECT_TRUE(media_player_observer()
                  .received_playback_target_state()
                  ->requires_monitoring);
  Media()->removeEventListener(
      parc_media_element_names::Webkitplaybacktargetavailabilitychanged(),
      listener,
      false);
  media_player_observer().WaitUntilReceivedMessage();
  EXPECT_FALSE(media_player_observer()
                   .received_playback_target_state()
                   ->requires_monitoring);
}

TEST_P(ParcMediaElementTest, ParcSafariWebkitWirelessVideoPlaybackDisabled) {
  auto* video = DynamicTo<HTMLVideoElement>(Media());
  if (!video) {
    GTEST_SKIP();
  }
  SetUserAgent(kParcSafariUserAgent);
  EXPECT_TRUE(
      ParcMediaElementAirPlay::webkitWirelessVideoPlaybackDisabled(*video));
  WaitForPlayer();
  EXPECT_FALSE(
      ParcMediaElementAirPlay::webkitWirelessVideoPlaybackDisabled(*video));

  EXPECT_CALL(*MockMediaPlayer(), ParcSetWirelessVideoPlaybackDisabled(true));
  ParcMediaElementAirPlay::setWebkitWirelessVideoPlaybackDisabled(*video, true);
  EXPECT_TRUE(video->FastHasAttribute(
      parc_media_element_names::WebkitwirelessvideoplaybackdisabledAttr()));
  EXPECT_TRUE(
      ParcMediaElementAirPlay::webkitWirelessVideoPlaybackDisabled(*video));
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  EXPECT_CALL(*MockMediaPlayer(), ParcSetWirelessVideoPlaybackDisabled(false));
  ParcMediaElementAirPlay::setWebkitWirelessVideoPlaybackDisabled(*video,
                                                                  false);
  EXPECT_FALSE(video->FastHasAttribute(
      parc_media_element_names::WebkitwirelessvideoplaybackdisabledAttr()));
  EXPECT_FALSE(
      ParcMediaElementAirPlay::webkitWirelessVideoPlaybackDisabled(*video));
  testing::Mock::VerifyAndClearExpectations(MockMediaPlayer());

  video->SetBooleanAttribute(html_names::kDisableremoteplaybackAttr, true);
  EXPECT_TRUE(
      ParcMediaElementAirPlay::webkitWirelessVideoPlaybackDisabled(*video));
}

}
