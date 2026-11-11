// Copyright 2026 Parc contributors.
// Fixture support is derived from Chromium tests (Chromium Authors; BSD-style
// license in Chromium's LICENSE); this file contains only Parc regressions.

#include "content/browser/media/session/media_session_controller.h"

#include <memory>
#include <optional>
#include <tuple>

#include "base/memory/raw_ptr.h"
#include "base/time/time.h"
#include "content/browser/media/media_web_contents_observer.h"
#include "content/browser/media/session/audio_focus_delegate.h"
#include "content/browser/media/session/media_session_impl.h"
#include "content/public/browser/media_device_id.h"
#include "content/test/mock_agent_scheduling_group_host.h"
#include "content/test/test_render_view_host.h"
#include "content/test/test_web_contents.h"
#include "media/audio/audio_device_description.h"
#include "media/base/picture_in_picture_events_info.h"
#include "media/mojo/mojom/media_player.mojom.h"
#include "mojo/public/cpp/bindings/associated_receiver.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "mojo/public/cpp/bindings/pending_associated_remote.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "ui/gfx/geometry/size.h"

namespace content {

class ParcFakeAudioFocusDelegate : public content::AudioFocusDelegate {
 public:
  void set_audio_focus_result(AudioFocusResult result) {
    audio_focus_result_ = result;
  }

  // content::AudioFocusDelegate:
  AudioFocusResult RequestAudioFocus(
      media_session::mojom::AudioFocusType audio_focus_type) override {
    audio_focus_type_ = audio_focus_type;
    return audio_focus_result_;
  }
  void AbandonAudioFocus() override { audio_focus_type_.reset(); }
  std::optional<media_session::mojom::AudioFocusType> GetCurrentFocusType()
      const override {
    return audio_focus_type_;
  }
  void MediaSessionInfoChanged(
      const media_session::mojom::MediaSessionInfoPtr&) override {}
  const base::UnguessableToken& request_id() const override {
    return base::UnguessableToken::Null();
  }
  void ReleaseRequestId() override {}

 private:
  std::optional<media_session::mojom::AudioFocusType> audio_focus_type_;
  AudioFocusResult audio_focus_result_ = AudioFocusResult::kSuccess;
};

// Helper class that provides an implementation of the media::mojom::MediaPlayer
// mojo interface to allow checking that messages sent over mojo are received
// with the right values in the other end.
//
// Note this relies on MediaSessionController::BindMediaPlayer() to provide the
// MediaSessionController instance owned by the test with a valid mojo remote,
// that will be bound to the mojo receiver provided by this class instead of the
// real one used in production which would be owned by HTMLMediaElement instead.
class ParcTestMediaPlayer : public media::mojom::MediaPlayer {
 public:
  enum class PauseRequestType {
    kNone,
    kTriggeredByUser,
    kNotTriggeredByUser,
  };

  ParcTestMediaPlayer(MediaWebContentsObserver* media_web_contents_observer,
                  const MediaPlayerId& player_id) {
    // Bind the remote to the receiver, so that we can intercept incoming
    // MediaPlayer messages sent via the different methods that use the remote.
    // MediaPlayerObserver messages will not be used.
    mojo::AssociatedRemote<media::mojom::MediaPlayerHost> player_host;
    media_web_contents_observer->BindMediaPlayerHost(
        player_id.frame_routing_id,
        player_host.BindNewEndpointAndPassDedicatedReceiver());

    mojo::PendingAssociatedRemote<media::mojom::MediaPlayer> player;
    receiver_.Bind(player.InitWithNewEndpointAndPassReceiver());

    mojo::PendingAssociatedRemote<media::mojom::MediaPlayerObserver>
        dummy_player_observer;
    player_host->OnMediaPlayerAdded(
        std::move(player),
        dummy_player_observer.InitWithNewEndpointAndPassReceiver(),
        player_id.player_id);
    player_host.FlushForTesting();
  }

  // Needs to be called from tests after invoking a method related playback
  // from the MediaPlayer mojo interface, so that we have enough time to
  // process the message.
  void WaitUntilReceivedMessage() {
    run_loop_ = std::make_unique<base::RunLoop>();
    run_loop_->Run();
    run_loop_.reset();
  }

  // Needs to be called from tests after invoking SetVolumeMultiplier method
  // from the MediaPlayer mojo interface, so that we have enough time to
  // process the message.
  void WaitUntilVolumeChanged() {
    run_loop_for_volume_ = std::make_unique<base::RunLoop>();
    run_loop_for_volume_->Run();
    run_loop_for_volume_.reset();
  }

  // media::mojom::MediaPlayer implementation.
  void RequestPlay(bool triggered_by_user) override {
    received_play_ = true;
    received_play_triggered_by_user_ = triggered_by_user;
    run_loop_->Quit();
  }

  void RequestPause(bool triggered_by_user) override {
    received_pause_type_ = triggered_by_user
                               ? PauseRequestType::kTriggeredByUser
                               : PauseRequestType::kNotTriggeredByUser;
    run_loop_->Quit();
  }

  void RequestSeekForward(base::TimeDelta seek_time) override {
    received_seek_forward_time_ = seek_time;
    run_loop_->Quit();
  }

  void RequestSeekBackward(base::TimeDelta seek_time) override {
    received_seek_backward_time_ = seek_time;
    run_loop_->Quit();
  }

  void RequestHandlePlaybackControlsAction(
      media_session::mojom::PlaybackControlsAction action,
      base::TimeDelta seek_time) override {
    received_playback_controls_action_ = action;
    received_seek_to_time_ = seek_time;
    run_loop_->Quit();
  }
  std::optional<media_session::mojom::PlaybackControlsAction>
  received_playback_controls_action_;
  void RequestSeekTo(base::TimeDelta seek_time) override {
    received_seek_to_time_ = seek_time;
    run_loop_->Quit();
  }

  void RequestEnterPictureInPicture(
      const std::optional<gfx::Size>& min_size) override {}

  void RequestMute(bool mute) override {}

  void SetVolumeMultiplier(double multiplier) override {
    received_volume_multiplier_ = multiplier;
    if (run_loop_for_volume_)
      run_loop_for_volume_->Quit();
  }

  void SetPersistentState(bool persistent) override {}

  void SetPowerExperimentState(bool enabled) override {}

  void SetAudioSinkId(const std::string& sink_id) override {
    received_set_audio_sink_id_ = sink_id;
    run_loop_->Quit();
  }

  void SuspendForFrameClosed() override {}

  void RequestMediaRemoting() override {}
  void RequestSaveVideoFrame() override {}
  void ParcSetPlaybackTargetAvailability(bool available) override {}
  void ParcSetPlaybackTarget(const std::string& output_context_id,
                             const std::string& device_name,
                             bool should_play,
                             uint32_t tint_argb,
                             uint32_t tint_on_light_argb) override {}
  void ParcPlaybackTargetPickerDismissed() override {}

  void RequestVisibility(
      RequestVisibilityCallback request_visibility_callback) override {
    std::move(request_visibility_callback).Run(expected_visibility_);
    if (run_loop_) {
      run_loop_->Quit();
    }
  }

  // Helper method to set expected video visibility, which is later used as an
  // argument for the `RequestVisibility` method callback
  // (`RequestVisibilityCallback`).
  void SetExpectedVisibility(bool expected_visibility) {
    expected_visibility_ = expected_visibility;
  }

  void RecordAutoPictureInPictureInfo(
      const media::PictureInPictureEventsInfo::AutoPipInfo&
          auto_picture_in_picture_info) override {
    auto_picture_in_picture_info_ = auto_picture_in_picture_info;
    run_loop_->Quit();
  }

  // Getters used from ParcMediaSessionControllerTest.
  bool received_play() const { return received_play_; }
  bool received_play_triggered_by_user() const {
    return received_play_triggered_by_user_;
  }

  PauseRequestType received_pause() const { return received_pause_type_; }

  const base::TimeDelta& received_seek_forward_time() const {
    return received_seek_forward_time_;
  }

  const base::TimeDelta& received_seek_backward_time() const {
    return received_seek_backward_time_;
  }

  const base::TimeDelta& received_seek_to_time() const {
    return received_seek_to_time_;
  }

  double received_volume_multiplier() const {
    return received_volume_multiplier_;
  }

  const std::string& received_set_audio_sink_id() const {
    return received_set_audio_sink_id_;
  }

  const media::PictureInPictureEventsInfo::AutoPipInfo&
  received_auto_picture_in_picture_info() const {
    return auto_picture_in_picture_info_;
  }

 private:
  std::unique_ptr<base::RunLoop> run_loop_;
  std::unique_ptr<base::RunLoop> run_loop_for_volume_;
  mojo::AssociatedReceiver<media::mojom::MediaPlayer> receiver_{this};

  bool received_play_{false};
  bool received_play_triggered_by_user_{false};
  double received_volume_multiplier_{0};
  PauseRequestType received_pause_type_{PauseRequestType::kNone};
  base::TimeDelta received_seek_forward_time_;
  base::TimeDelta received_seek_backward_time_;
  base::TimeDelta received_seek_to_time_;
  std::string received_set_audio_sink_id_;
  bool expected_visibility_ = false;
  media::PictureInPictureEventsInfo::AutoPipInfo auto_picture_in_picture_info_;
};

// Helper class to mock `RequestVisibility` callbacks.
class ParcRequestVisibilityWaiter {
 public:
  ParcRequestVisibilityWaiter() = default;

  ParcRequestVisibilityWaiter(const ParcRequestVisibilityWaiter&) = delete;
  ParcRequestVisibilityWaiter(ParcRequestVisibilityWaiter&&) = delete;
  ParcRequestVisibilityWaiter& operator=(const ParcRequestVisibilityWaiter&) = delete;

  ParcTestMediaPlayer::RequestVisibilityCallback VisibilityCallback() {
    meets_visibility_ = std::nullopt;
    // base::Unretained() is safe since no further tasks can run after
    // RunLoop::Run() returns.
    return base::BindOnce(&ParcRequestVisibilityWaiter::RequestVisibility,
                          base::Unretained(this));
  }

  void WaitUntilDone() {
    if (meets_visibility_) {
      return;
    }
    run_loop_ = std::make_unique<base::RunLoop>();
    run_loop_->Run();
  }

  bool MeetsVisibility() {
    DCHECK(meets_visibility_);
    return meets_visibility_.value();
  }

 private:
  void RequestVisibility(bool meets_visibility) {
    meets_visibility_ = meets_visibility;
    if (run_loop_) {
      run_loop_->Quit();
    }
  }

  std::unique_ptr<base::RunLoop> run_loop_;
  std::optional<bool> meets_visibility_;
};

class ParcMediaSessionControllerTest : public RenderViewHostImplTestHarness {
 public:
  void SetUp() override {
    RenderViewHostImplTestHarness::SetUp();

    id_ = MediaPlayerId(contents()->GetPrimaryMainFrame()->GetGlobalId(), 0);
    controller_ = CreateController();
    media_player_ = CreateMediaPlayer(controller_.get());

    auto delegate = std::make_unique<ParcFakeAudioFocusDelegate>();
    audio_focus_delegate_ = delegate.get();
    media_session()->SetDelegateForTests(std::move(delegate));
  }

  void TearDown() override {
    audio_focus_delegate_ = nullptr;
    // Destruct the controller prior to any other teardown to avoid out of order
    // destruction relative to the MediaSession instance.
    controller_.reset();
    media_player_.reset();

    RenderViewHostImplTestHarness::TearDown();
  }

 protected:
  std::unique_ptr<MediaSessionController> CreateController() {
    return std::make_unique<MediaSessionController>(id_, contents());
  }

  std::unique_ptr<ParcTestMediaPlayer> CreateMediaPlayer(
      MediaSessionController* controller) {
    MediaWebContentsObserver* media_web_contents_observer =
        contents()->media_web_contents_observer();
    DCHECK(media_web_contents_observer);
    return std::make_unique<ParcTestMediaPlayer>(media_web_contents_observer, id_);
  }

  MediaSessionImpl* media_session() {
    return MediaSessionImpl::Get(contents());
  }

  void Suspend(bool triggered_by_user = true) {
    controller_->OnSuspend(controller_->get_player_id_for_testing(),
                           triggered_by_user);
    media_player_->WaitUntilReceivedMessage();
  }

  void Resume(bool triggered_by_user = true) {
    controller_->OnResume(controller_->get_player_id_for_testing(),
                          triggered_by_user);
    media_player_->WaitUntilReceivedMessage();
  }

  void SeekForward(base::TimeDelta seek_time) {
    controller_->OnSeekForward(controller_->get_player_id_for_testing(),
                               seek_time);
    media_player_->WaitUntilReceivedMessage();
  }

  void SeekBackward(base::TimeDelta seek_time) {
    controller_->OnSeekBackward(controller_->get_player_id_for_testing(),
                                seek_time);
    media_player_->WaitUntilReceivedMessage();
  }

  void SeekTo(base::TimeDelta seek_time) {
    controller_->OnSeekTo(controller_->get_player_id_for_testing(), seek_time);
    media_player_->WaitUntilReceivedMessage();
  }

  void SetVolumeMultiplier(double multiplier) {
    controller_->OnSetVolumeMultiplier(controller_->get_player_id_for_testing(),
                                       multiplier);
    media_player_->WaitUntilVolumeChanged();
  }

  void RequestVisibility(
      ParcTestMediaPlayer::RequestVisibilityCallback request_visibility_callback) {
    controller_->OnRequestVisibility(controller_->get_player_id_for_testing(),
                                     std::move(request_visibility_callback));
    media_player_->WaitUntilReceivedMessage();
  }

  // Helpers to check the results of using the basic controls.
  bool ReceivedMessagePlay(bool triggered_by_user) {
    return media_player_->received_play() &&
           media_player_->received_play_triggered_by_user() ==
               triggered_by_user;
  }

  bool ReceivedMessagePause(bool triggered_by_user) {
    ParcTestMediaPlayer::PauseRequestType expected_pause_request =
        triggered_by_user
            ? ParcTestMediaPlayer::PauseRequestType::kTriggeredByUser
            : ParcTestMediaPlayer::PauseRequestType::kNotTriggeredByUser;
    return media_player_->received_pause() == expected_pause_request;
  }

  bool ReceivedMessageSeekForward(base::TimeDelta expected_seek_time) {
    return expected_seek_time == media_player_->received_seek_forward_time();
  }

  bool ReceivedMessageSeekBackward(base::TimeDelta expected_seek_time) {
    return expected_seek_time == media_player_->received_seek_backward_time();
  }

  bool ReceivedMessageSeekTo(base::TimeDelta expected_seek_time) {
    return expected_seek_time == media_player_->received_seek_to_time();
  }

  bool ReceivedMessageVolume(double expected_volume_multiplier) {
    return expected_volume_multiplier ==
           media_player_->received_volume_multiplier();
  }

  // Helper method to set the expected visibility that will be used by the
  // `RequestVisibilityCallback`.
  void SetExpectedVisibility(bool expected_visibility) {
    media_player_->SetExpectedVisibility(expected_visibility);
  }

  MediaPlayerId id_ = MediaPlayerId::CreateMediaPlayerIdForTests();
  std::unique_ptr<MediaSessionController> controller_;
  std::unique_ptr<ParcTestMediaPlayer> media_player_;
  raw_ptr<ParcFakeAudioFocusDelegate> audio_focus_delegate_ = nullptr;
};

TEST_F(ParcMediaSessionControllerTest, PlaybackControlsRetainOriginAndBoundaries) {
  using Action = media_session::mojom::PlaybackControlsAction;
  for (auto action : {Action::kBeginScrubbing, Action::kSeekTo,
                      Action::kEndScrubbing, Action::kPauseForDragging,
                      Action::kResumeForDragging}) {
    controller_->OnHandlePlaybackControlsAction(
        controller_->get_player_id_for_testing(), action, base::Seconds(3));
    media_player_->WaitUntilReceivedMessage();
    EXPECT_EQ(action, media_player_->received_playback_controls_action_);
    EXPECT_TRUE(ReceivedMessageSeekTo(base::Seconds(3)));
  }
}

}  // namespace content
