// Copyright 2026 Parc contributors.
// Fixture support is derived from Chromium tests (Chromium Authors; BSD-style
// license in Chromium's LICENSE); this file contains only Parc regressions.

#include "content/browser/media/media_web_contents_observer.h"

#include <memory>
#include <optional>

#include "base/run_loop.h"
#include "content/test/test_render_view_host.h"
#include "content/test/test_web_contents.h"
#include "media/base/media_content_type.h"
#include "media/mojo/mojom/media_player.mojom.h"
#include "mojo/public/cpp/bindings/associated_receiver.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "ui/gfx/geometry/size.h"

namespace content {
namespace {

constexpr auto kContentType = media::MediaContentType::kPersistent;

class TestMediaPlayer final : public media::mojom::MediaPlayer {
 public:
  mojo::AssociatedReceiver<media::mojom::MediaPlayer>& receiver() {
    return receiver_;
  }

  // media::mojom::MediaPlayer implementation.
  void RequestPlay(bool triggered_by_user) override {}
  void RequestPause(bool triggered_by_user) override {}
  void RequestSeekForward(base::TimeDelta seek_time) override {}
  void RequestSeekBackward(base::TimeDelta seek_time) override {}
  void RequestHandlePlaybackControlsAction(
      media_session::mojom::PlaybackControlsAction action,
      base::TimeDelta seek_time) override {}
  void RequestSeekTo(base::TimeDelta seek_time) override {}
  void RequestEnterPictureInPicture(
      const std::optional<gfx::Size>& min_size) override {}
  void RequestMute(bool mute) override {}
  void SetVolumeMultiplier(double multiplier) override {}
  void SetPersistentState(bool persistent) override {}
  void SetPowerExperimentState(bool enabled) override {}
  void SetAudioSinkId(const std::string& sink_id) override {}
  void SuspendForFrameClosed() override {}
  void RequestMediaRemoting() override {}
  void RequestVisibility(
      RequestVisibilityCallback request_visibility_callback) override {}
  void RecordAutoPictureInPictureInfo(
      const media::PictureInPictureEventsInfo::AutoPipInfo&
          auto_picture_in_picture_info) override {}
  void RequestSaveVideoFrame() override {}
  void ParcSetPlaybackTargetAvailability(bool available) override {}
  void ParcSetPlaybackTarget(const std::string& output_context_id,
                             const std::string& device_name,
                             bool should_play,
                             uint32_t tint_argb,
                             uint32_t tint_on_light_argb) override {}
  void ParcPlaybackTargetPickerDismissed() override {}

 private:
  mojo::AssociatedReceiver<media::mojom::MediaPlayer> receiver_{this};
};

class ParcMediaWebContentsObserverTest : public RenderViewHostImplTestHarness {
 public:
  struct PlayerSetup {
    std::unique_ptr<TestMediaPlayer> player;
    mojo::AssociatedRemote<media::mojom::MediaPlayerObserver> observer;
    int32_t player_id;
  };

 protected:
  mojo::AssociatedRemote<media::mojom::MediaPlayerHost> SetupPlayerHost() {
    mojo::AssociatedRemote<media::mojom::MediaPlayerHost> player_host;
    contents()->media_web_contents_observer()->BindMediaPlayerHost(
        contents()->GetPrimaryMainFrame()->GetGlobalId(),
        player_host.BindNewEndpointAndPassDedicatedReceiver());
    return player_host;
  }

  auto CreateAndAddPlayer(
      mojo::AssociatedRemote<media::mojom::MediaPlayerHost>& player_host,
      int32_t player_id) -> PlayerSetup {
    PlayerSetup setup{.player = std::make_unique<TestMediaPlayer>(),
                      .player_id = player_id};
    player_host->OnMediaPlayerAdded(
        setup.player->receiver().BindNewEndpointAndPassRemote(),
        setup.observer.BindNewEndpointAndPassReceiver(), player_id);
    player_host.FlushForTesting();
    return setup;
  }

  // Overload for tests that do not care about specific IDs.
  auto CreateAndAddPlayer(
      mojo::AssociatedRemote<media::mojom::MediaPlayerHost>& player_host)
      -> PlayerSetup {
    return CreateAndAddPlayer(player_host, next_player_id_++);
  }

  void SetMediaMetadata(
      mojo::AssociatedRemote<media::mojom::MediaPlayerObserver>& observer,
      bool has_audio,
      bool has_video) {
    observer->OnMediaMetadataChanged(has_audio, has_video, kContentType);
    observer.FlushForTesting();
  }

  void PlayMedia(
      mojo::AssociatedRemote<media::mojom::MediaPlayerObserver>& observer) {
    observer->OnMediaPlaying();
    observer.FlushForTesting();
  }

  void PauseMedia(
      mojo::AssociatedRemote<media::mojom::MediaPlayerObserver>& observer,
      bool stream_ended = false) {
    observer->OnMediaPaused(stream_ended);
    observer.FlushForTesting();
  }

  void SetFullscreenStatus(
      mojo::AssociatedRemote<media::mojom::MediaPlayerObserver>& observer,
      blink::WebFullscreenVideoStatus status) {
    observer->OnMediaEffectivelyFullscreenChanged(status);
    observer.FlushForTesting();
  }

  void SetUseAudioService(
      mojo::AssociatedRemote<media::mojom::MediaPlayerObserver>& observer,
      bool uses_audio_service) {
    observer->OnUseAudioServiceChanged(uses_audio_service);
    observer.FlushForTesting();
  }

  bool IsWebContentsAudible() { return contents()->IsCurrentlyAudible(); }

  MediaPlayerId CreatePlayerId(int32_t player_id) {
    return MediaPlayerId(contents()->GetPrimaryMainFrame()->GetGlobalId(),
                         player_id);
  }

  MediaWebContentsObserver& media_web_contents_observer() {
    return *contents()->media_web_contents_observer();
  }

 private:
  int32_t next_player_id_ = 0;
};


// Parc: a Safari-identity page moving an element to another frame registers its
// player there under the same id (HTMLMediaElement::ParcMovePlayerToFrame).
class ParcMediaWebContentsObserverMovedPlayerTest
    : public ParcMediaWebContentsObserverTest {
 protected:
  void SetUp() override {
    ParcMediaWebContentsObserverTest::SetUp();
    RenderFrameHost* main_rfh = contents()->GetPrimaryMainFrame();
    RenderFrameHostTester::For(main_rfh)->InitializeRenderFrameIfNeeded();
    child_rfh_ = RenderFrameHostTester::For(main_rfh)->AppendChild("child");
    RenderFrameHostTester::For(child_rfh_)->InitializeRenderFrameIfNeeded();
    main_player_host_ = SetupPlayerHost();
    media_web_contents_observer().BindMediaPlayerHost(
        child_rfh_->GetGlobalId(),
        child_player_host_.BindNewEndpointAndPassDedicatedReceiver());
  }

  void TearDown() override {
    main_player_host_.reset();
    child_player_host_.reset();
    ParcMediaWebContentsObserverTest::TearDown();
  }

  void BypassAudioService(PlayerSetup& player) {
    SetMediaMetadata(player.observer, /*has_audio=*/true, /*has_video=*/false);
    SetUseAudioService(player.observer, false);
  }

  void EndRegistration(PlayerSetup& player) {
    player.observer.reset();
    player.player.reset();
    base::RunLoop().RunUntilIdle();
  }

  raw_ptr<RenderFrameHost> child_rfh_ = nullptr;
  mojo::AssociatedRemote<media::mojom::MediaPlayerHost> main_player_host_;
  mojo::AssociatedRemote<media::mojom::MediaPlayerHost> child_player_host_;
};

// The grant follows the player when its old registration ends first, and its
// revocation reaches it in the new frame.
TEST_F(ParcMediaWebContentsObserverMovedPlayerTest, GrantFollowsAndIsRevoked) {
  auto grant =
      AudibilityBypassTracker::AddGrant(contents()->GetPrimaryMainFrame());
  auto player = CreateAndAddPlayer(main_player_host_, /*player_id=*/7);
  BypassAudioService(player);
  PlayMedia(player.observer);
  ASSERT_TRUE(IsWebContentsAudible());

  EndRegistration(player);
  auto moved = CreateAndAddPlayer(child_player_host_, /*player_id=*/7);
  BypassAudioService(moved);
  PlayMedia(moved.observer);
  EXPECT_TRUE(IsWebContentsAudible());

  grant.RunAndReset();
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(IsWebContentsAudible());
}

// A paused player's grant follows it when the new registration plays before
// the old one ends, and no other player of the new frame gets it.
TEST_F(ParcMediaWebContentsObserverMovedPlayerTest,
       PausedPlayersGrantFollowsWhenOldRegistrationEndsLast) {
  auto grant =
      AudibilityBypassTracker::AddGrant(contents()->GetPrimaryMainFrame());
  auto player = CreateAndAddPlayer(main_player_host_, /*player_id=*/7);
  BypassAudioService(player);
  ASSERT_FALSE(IsWebContentsAudible());

  auto moved = CreateAndAddPlayer(child_player_host_, /*player_id=*/7);
  BypassAudioService(moved);
  PlayMedia(moved.observer);
  EXPECT_FALSE(IsWebContentsAudible());
  EndRegistration(player);
  EXPECT_TRUE(IsWebContentsAudible());

  auto other = CreateAndAddPlayer(child_player_host_, /*player_id=*/8);
  PauseMedia(moved.observer);
  BypassAudioService(other);
  PlayMedia(other.observer);
  EXPECT_FALSE(IsWebContentsAudible());
}

// A paused moved player takes its grant when its old registration ends, so
// the grant stays its own after the old frame goes.
TEST_F(ParcMediaWebContentsObserverMovedPlayerTest,
       PausedMovedPlayerKeepsGrantAfterOldFrameGoes) {
  auto grant = AudibilityBypassTracker::AddGrant(child_rfh_);
  auto player = CreateAndAddPlayer(child_player_host_, /*player_id=*/7);
  BypassAudioService(player);

  auto moved = CreateAndAddPlayer(main_player_host_, /*player_id=*/7);
  BypassAudioService(moved);
  EndRegistration(player);
  RenderFrameHostTester::For(child_rfh_.ExtractAsDangling())->Detach();
  base::RunLoop().RunUntilIdle();

  PlayMedia(moved.observer);
  EXPECT_TRUE(IsWebContentsAudible());

  grant.RunAndReset();
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(IsWebContentsAudible());
}

}  // namespace
}  // namespace content
