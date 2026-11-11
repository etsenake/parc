// Copyright 2026 Parc contributors.
// Fixture support is derived from Chromium tests (Chromium Authors; BSD-style
// license in Chromium's LICENSE); this file contains only Parc regressions.

#include <map>
#include <memory>
#include <string>

#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/run_loop.h"
#include "base/strings/utf_string_conversions.h"
#include "base/test/scoped_feature_list.h"
#include "base/time/time.h"
#include "content/browser/media/parc_fairplay_hooks.h"
#include "content/browser/media/session/media_session_impl.h"
#include "content/browser/media/session/mock_media_session_service_impl.h"
#include "content/browser/renderer_host/render_frame_host_impl.h"
#include "content/public/browser/media_session_player_observer.h"
#include "content/public/test/navigation_simulator.h"
#include "content/public/test/test_media_session_client.h"
#include "content/test/test_render_view_host.h"
#include "content/test/test_web_contents.h"
#include "media/base/media_content_type.h"
#include "media/base/picture_in_picture_events_info.h"
#include "services/media_session/public/cpp/media_metadata.h"
#include "services/media_session/public/cpp/test/mock_media_session.h"
#include "services/media_session/public/mojom/constants.mojom.h"
#include "third_party/blink/public/common/features.h"
#include "third_party/blink/public/mojom/mediasession/media_session.mojom.h"
#include "ui/gfx/geometry/size.h"

using ::testing::_;
using ::testing::AnyNumber;
using ::testing::Eq;
using ::testing::InvokeWithoutArgs;
using ::testing::NiceMock;

using media_session::mojom::MediaAudioVideoState;
using media_session::mojom::MediaSessionAction;
using media_session::mojom::MediaSessionImageType;

namespace {
std::u16string hidden_metadata_placeholder_title = u"placeholder_title";
std::u16string hidden_metadata_placeholder_source_title =
    u"placeholder_source_title";
std::u16string hidden_metadata_placeholder_artist = u"placeholder_artist";
std::u16string hidden_metadata_placeholder_album = u"placeholder_album";
}  // namespace

namespace content {

namespace {

constexpr base::TimeDelta kDefaultSeekTime =
    base::Seconds(media_session::mojom::kDefaultSeekTimeSeconds);

static const int kPlayerId = 0;

class MockMediaSessionPlayerObserver : public MediaSessionPlayerObserver {
 public:
  MockMediaSessionPlayerObserver(RenderFrameHost* rfh,
                                 MediaAudioVideoState audio_video_state,
                                 media::MediaContentType media_content_type)
      : render_frame_host_(rfh),
        audio_video_state_(audio_video_state),
        media_content_type_(media_content_type) {}

  ~MockMediaSessionPlayerObserver() override = default;

  MOCK_METHOD2(OnSuspend, void(int player_id, bool triggered_by_user));
  MOCK_METHOD2(OnResume, void(int player_id, bool triggered_by_user));
  MOCK_METHOD2(OnSeekForward, void(int player_id, base::TimeDelta seek_time));
  MOCK_METHOD2(OnSeekBackward, void(int player_id, base::TimeDelta seek_time));
  base::WeakPtr<MediaSessionPlayerObserver> GetPlaybackControlsWeakPtr() override {
    return weak_factory_.GetWeakPtr();
  }
  MOCK_METHOD(void, OnHandlePlaybackControlsAction,
              (int, media_session::mojom::PlaybackControlsAction, base::TimeDelta),
              (override));
  MOCK_METHOD2(OnSeekTo, void(int player_id, base::TimeDelta seek_time));
  MOCK_METHOD2(OnSetVolumeMultiplier,
               void(int player_id, double volume_multiplier));
  MOCK_METHOD2(OnEnterPictureInPicture,
               void(int player_id, const std::optional<gfx::Size>& min_size));
  MOCK_METHOD2(OnSetAudioSinkId,
               void(int player_id, const std::string& raw_device_id));
  MOCK_METHOD2(OnSetMute, void(int player_id, bool mute));
  MOCK_METHOD(void, OnRequestMediaRemoting, (int player_id), (override));
  MOCK_METHOD(void,
              OnRequestVisibility,
              (int player_id,
               RequestVisibilityCallback request_visibility_callback),
              (override));
  MOCK_METHOD(void,
              OnAutoPictureInPictureInfoChanged,
              (int player_id,
               const media::PictureInPictureEventsInfo::AutoPipInfo&
                   auto_picture_in_picture_info),
              (override));
  MOCK_METHOD(void, OnSaveVideoFrame, (int player_id), (override));

  std::optional<media_session::MediaPosition> GetPosition(
      int player_id) const override {
    return position_;
  }

  void SetPosition(
      const std::optional<media_session::MediaPosition>& position) {
    position_ = position;
  }

  bool IsPictureInPictureAvailable(int player_id) const override {
    return false;
  }

  bool HasSufficientlyVisibleVideo(int player_id) const override {
    return false;
  }

  bool IsVideoFrameAvailable(int player_id) const override { return false; }

  bool HasAudio(int player_id) const override {
    return audio_video_state_ == MediaAudioVideoState::kAudioOnly ||
           audio_video_state_ == MediaAudioVideoState::kAudioVideo;
  }

  bool HasVideo(int player_id) const override {
    return audio_video_state_ == MediaAudioVideoState::kVideoOnly ||
           audio_video_state_ == MediaAudioVideoState::kAudioVideo;
  }

  bool IsPaused(int player_id) const override { return false; }

  std::string GetAudioOutputSinkId(int player_id) const override { return ""; }

  bool SupportsAudioOutputDeviceSwitching(int player_id) const override {
    return false;
  }

  media::MediaContentType GetMediaContentType() const override {
    return media_content_type_;
  }

  RenderFrameHost* render_frame_host() const override {
    return render_frame_host_;
  }

 private:
  raw_ptr<RenderFrameHost> render_frame_host_;

  const media_session::mojom::MediaAudioVideoState audio_video_state_;

  media::MediaContentType media_content_type_;

  std::optional<media_session::MediaPosition> position_;
  base::WeakPtrFactory<MockMediaSessionPlayerObserver> weak_factory_{this};
};

}  // anonymous namespace

class ParcMediaSessionImplServiceRoutingTest
    : public RenderViewHostImplTestHarness {
 public:
  ParcMediaSessionImplServiceRoutingTest() {
    actions_.insert(MediaSessionAction::kPlay);
    actions_.insert(MediaSessionAction::kPause);
    actions_.insert(MediaSessionAction::kStop);
    actions_.insert(MediaSessionAction::kSeekTo);
    actions_.insert(MediaSessionAction::kScrubTo);
    actions_.insert(MediaSessionAction::kSeekForward);
    actions_.insert(MediaSessionAction::kSeekBackward);
  }

  ~ParcMediaSessionImplServiceRoutingTest() override = default;

  void SetUp() override {
    RenderViewHostImplTestHarness::SetUp();

    contents()->GetPrimaryMainFrame()->InitializeRenderFrameIfNeeded();
    contents()->NavigateAndCommit(GURL("http://www.example.com"));

    main_frame_ = contents()->GetPrimaryMainFrame();
    sub_frame_ = main_frame_->AppendChild("sub_frame");

    empty_metadata_.title = contents()->GetTitle();
    empty_metadata_.source_title = u"example.com";

    GetMediaSession()->SetShouldThrottleDurationUpdateForTest(false);

    SetupMediaSessionClient();
  }

  void TearDown() override {
    services_.clear();
    players_.clear();
    sub_frame_ = nullptr;
    main_frame_ = nullptr;

    RenderViewHostImplTestHarness::TearDown();
  }

 protected:
  void SetupMediaSessionClient() {
    client_.SetTitlePlaceholder(hidden_metadata_placeholder_title);
    client_.SetSourceTitlePlaceholder(hidden_metadata_placeholder_source_title);
    client_.SetArtistPlaceholder(hidden_metadata_placeholder_artist);
    client_.SetAlbumPlaceholder(hidden_metadata_placeholder_album);
  }

  void CreateServiceForFrame(TestRenderFrameHost* frame) {
    services_[frame] =
        std::make_unique<NiceMock<MockMediaSessionServiceImpl>>(frame);
  }

  void DestroyServiceForFrame(TestRenderFrameHost* frame) {
    services_.erase(frame);
  }

  MockMediaSessionClient* GetClientForFrame(TestRenderFrameHost* frame) {
    auto iter = services_.find(frame);
    return (iter != services_.end()) ? &iter->second.get()->mock_client()
                                     : nullptr;
  }

  void StartPlayerForFrame(TestRenderFrameHost* frame,
                           MediaAudioVideoState audio_video_state =
                               MediaAudioVideoState::kAudioOnly) {
    StartPlayerForFrame(frame, media::MediaContentType::kPersistent,
                        audio_video_state);
  }

  void StartPlayerForFrame(TestRenderFrameHost* frame,
                           media::MediaContentType type,
                           MediaAudioVideoState audio_video_state =
                               MediaAudioVideoState::kAudioOnly) {
    players_[frame] =
        std::make_unique<NiceMock<MockMediaSessionPlayerObserver>>(
            frame, audio_video_state, type);
    MediaSessionImpl::Get(contents())
        ->AddPlayer(players_[frame].get(), kPlayerId);
  }

  void ClearPlayersForFrame(TestRenderFrameHost* frame) {
    if (!players_.count(frame))
      return;

    MediaSessionImpl::Get(contents())
        ->RemovePlayer(players_[frame].get(), kPlayerId);
  }

  MockMediaSessionPlayerObserver* GetPlayerForFrame(
      TestRenderFrameHost* frame) {
    auto iter = players_.find(frame);
    return (iter != players_.end()) ? iter->second.get() : nullptr;
  }

  MediaSessionServiceImpl* ComputeServiceForRouting() {
    auto* frame = static_cast<TestRenderFrameHost*>(
        MediaSessionImpl::Get(contents())
            ->ComputeFrameForRouting(/*ensure_service=*/true));
    return services_.find(frame) != services_.end() ? services_[frame].get()
                                                    : nullptr;
  }

  MediaSessionImpl* GetMediaSession() {
    return MediaSessionImpl::Get(contents());
  }

  std::set<MediaSessionAction> GetDefaultActionsWithExtra(
      MediaSessionAction action) const {
    std::set<MediaSessionAction> actions(actions_.begin(), actions_.end());
    actions.insert(action);
    return actions;
  }

  const std::set<MediaSessionAction>& default_actions() const {
    return actions_;
  }

  const media_session::MediaMetadata& empty_metadata() const {
    return empty_metadata_;
  }

  const std::u16string& GetSourceTitleForNonEmptyMetadata() const {
    return empty_metadata_.source_title;
  }

  raw_ptr<TestRenderFrameHost> main_frame_;
  raw_ptr<TestRenderFrameHost> sub_frame_;

  using ServiceMap = std::map<TestRenderFrameHost*,
                              std::unique_ptr<MockMediaSessionServiceImpl>>;
  ServiceMap services_;

  using PlayerMap = std::map<TestRenderFrameHost*,
                             std::unique_ptr<MockMediaSessionPlayerObserver>>;
  PlayerMap players_;

  TestMediaSessionClient client_;

 private:
  media_session::MediaMetadata empty_metadata_;

  std::set<MediaSessionAction> actions_;
};

TEST_F(ParcMediaSessionImplServiceRoutingTest, SafariScrubKeepsPausedRecipients) {
  using Action = media_session::mojom::PlaybackControlsAction;
  parc::fairplay::SetSafariIdentityQuery(base::BindRepeating(
      [](RenderFrameHost*) { return true; }));
  base::ScopedClosureRunner reset(base::BindOnce([] {
    parc::fairplay::SetSafariIdentityQuery({});
  }));
  StartPlayerForFrame(main_frame_);
  StartPlayerForFrame(sub_frame_);
  auto* session = MediaSessionImpl::Get(contents());
  for (auto* frame : {main_frame_.get(), sub_frame_.get()})
    EXPECT_CALL(*GetPlayerForFrame(frame),
                OnHandlePlaybackControlsAction(kPlayerId, Action::kBeginScrubbing, _));
  session->HandlePlaybackControlsAction(Action::kBeginScrubbing, {});
  session->OnPlayerPaused(GetPlayerForFrame(main_frame_), kPlayerId);
  for (auto* frame : {main_frame_.get(), sub_frame_.get()})
    EXPECT_CALL(*GetPlayerForFrame(frame),
                OnHandlePlaybackControlsAction(kPlayerId, Action::kEndScrubbing, _));
  session->HandlePlaybackControlsAction(Action::kEndScrubbing, {});
}

TEST_F(ParcMediaSessionImplServiceRoutingTest, ChromePlaybackControlsKeepSeekRouting) {
  StartPlayerForFrame(main_frame_);
  EXPECT_CALL(*GetPlayerForFrame(main_frame_), OnSeekTo(kPlayerId, base::Seconds(3)));
  MediaSessionImpl::Get(contents())->HandlePlaybackControlsAction(
      media_session::mojom::PlaybackControlsAction::kSeekTo, base::Seconds(3));
}

}  // namespace content
