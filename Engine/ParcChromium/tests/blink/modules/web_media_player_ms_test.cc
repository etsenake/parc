// Copyright 2026 Parc contributors.
// This fixture is derived from Chromium's web_media_player_ms_test.cc
// (Chromium Authors; BSD-style license in Chromium's LICENSE) and contains
// only Parc regressions.

#include "third_party/blink/public/web/modules/mediastream/web_media_player_ms.h"

#include <memory>
#include <tuple>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "base/run_loop.h"
#include "media/base/media_content_type.h"
#include "media/base/media_util.h"
#include "third_party/blink/public/platform/scheduler/test/renderer_scheduler_test_support.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/renderer/platform/media/media_player_client.h"
#include "third_party/blink/renderer/platform/media/parc_media_player_client.h"
#include "third_party/blink/renderer/platform/testing/task_environment.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace blink {
namespace {

class FakeWebMediaPlayerDelegate : public WebMediaPlayerDelegate {
 public:
  FakeWebMediaPlayerDelegate() = default;
  FakeWebMediaPlayerDelegate(const FakeWebMediaPlayerDelegate&) = delete;
  FakeWebMediaPlayerDelegate& operator=(const FakeWebMediaPlayerDelegate&) =
      delete;

  ~FakeWebMediaPlayerDelegate() override {
    DCHECK(!observer_);
    DCHECK(is_gone_);
  }

  int AddObserver(Observer* observer) override {
    observer_ = observer;
    return delegate_id_;
  }

  void RemoveObserver(int delegate_id) override {
    EXPECT_EQ(delegate_id_, delegate_id);
    observer_ = nullptr;
  }

  void DidMediaMetadataChange(int delegate_id,
                              bool has_audio,
                              bool has_video,
                              media::MediaContentType type) override {
    EXPECT_EQ(delegate_id_, delegate_id);
  }

  void DidPlay(int delegate_id) override {
    EXPECT_EQ(delegate_id_, delegate_id);
    is_gone_ = false;
  }

  void DidPause(int delegate_id, bool reached_end_of_stream) override {
    EXPECT_EQ(delegate_id_, delegate_id);
    EXPECT_FALSE(reached_end_of_stream);
    EXPECT_FALSE(is_gone_);
  }

  void PlayerGone(int delegate_id) override {
    EXPECT_EQ(delegate_id_, delegate_id);
    is_gone_ = true;
  }

  void SetIdle(int delegate_id, bool is_idle) override {
    EXPECT_EQ(delegate_id_, delegate_id);
    is_idle_ = is_idle;
  }

  bool IsIdle(int delegate_id) override {
    EXPECT_EQ(delegate_id_, delegate_id);
    return is_idle_;
  }

  void ClearStaleFlag(int delegate_id) override {
    EXPECT_EQ(delegate_id_, delegate_id);
  }

  bool IsStale(int delegate_id) override {
    EXPECT_EQ(delegate_id_, delegate_id);
    return false;
  }

  bool IsPageHidden() override { return false; }
  bool has_observer() const { return observer_; }

 private:
  int delegate_id_ = 1234;
  raw_ptr<Observer> observer_ = nullptr;
  bool is_gone_ = true;
  bool is_idle_ = false;
};

class ParcWebMediaPlayerMSTest
    : public testing::TestWithParam<std::tuple<bool, bool>>,
      public MediaPlayerClient,
      public ParcMediaPlayerClient {
 public:
  ~ParcWebMediaPlayerMSTest() override {
    if (!player_) {
      return;
    }
    player_->Shutdown();
    player_.reset();
    base::RunLoop().RunUntilIdle();
  }

 protected:
  void InitializeWebMediaPlayerMS() {
    auto task_runner = scheduler::GetSingleThreadTaskRunnerForTesting();
    player_ = std::make_unique<WebMediaPlayerMS>(
        nullptr, this, &delegate_, std::make_unique<media::NullMediaLog>(),
        task_runner, task_runner, task_runner, task_runner, task_runner,
        /*gpu_factories=*/nullptr, WebString(), CreateSurfaceLayerBridgeCB(),
        /*submitter=*/nullptr);
  }

  void NetworkStateChanged() override {}
  void ReadyStateChanged() override {}
  void TimeChanged() override {}
  void Repaint() override {}
  void DurationChanged() override {}
  void SizeChanged() override {}
  void SetCcLayer(cc::Layer* layer) override {}
  void OnFirstFrame(base::TimeTicks, size_t) override {}
  void OnPictureInPictureStateChange() override {}
  void RemoveTrack(const media::MediaTrack&) override {}
  void AddTrack(const media::MediaTrack&) override {}
  void SetTrackState(const media::MediaTrack&,
                     media::MediaTrack::State) override {}
  void MediaSourceOpened(std::unique_ptr<WebMediaSource>) override {}
  void RemotePlaybackCompatibilityChanged(const KURL& url,
                                          bool is_compatible) override {}
  bool WasAlwaysMuted() override { return false; }
  bool HasSelectedVideoTrack() override { return false; }
  WebMediaPlayer::TrackId GetSelectedVideoTrackId() override {
    return WebMediaPlayer::TrackId();
  }
  bool HasNativeControls() override { return false; }
  bool IsAudioElement() override { return false; }
  bool IsInAutoPIP() const override { return false; }
  void MediaRemotingStarted(
      const WebString& remote_device_friendly_name) override {}
  void MediaRemotingStopped(int error_code) override {}
  void ResumePlayback() override {}
  void PausePlayback(WebMediaPlayer::PauseReason) override {}
  void DidPlayerStartPlaying() override {}
  void DidPlayerPaused(bool) override {}
  void DidPlayerMutedStatusChange(bool muted) override {}
  void DidMediaMetadataChange(bool has_audio,
                              bool has_video,
                              media::AudioCodec audio_codec,
                              media::VideoCodec video_codec,
                              media::MediaContentType media_content_type,
                              bool is_encrypted_media) override {}
  void DidPlayerMediaPositionStateChange(double playback_rate,
                                         base::TimeDelta duration,
                                         base::TimeDelta position,
                                         bool end_of_media) override {}
  void DidDisableAudioOutputSinkChanges() override {}
  void DidUseAudioServiceChange(bool uses_audio_service) override {}
  void DidPlayerSizeChange(const gfx::Size& size) override {}
  void OnRemotePlaybackDisabled(bool disabled) override {}
  WebMediaPlayer::DisplayType GetDisplayType() const override {
    return WebMediaPlayer::DisplayType::kInline;
  }
  bool CouldPlayIfEnoughData() const override { return false; }
  void OnRequestVideoFrameCallback() override {}
  int GetElementId() override { return 0; }
  ParcMediaPlayerClient* ParcClient() override { return this; }
  bool PresentsParcSafariIdentity() const override {
    return parc_safari_identity_;
  }

  base::test::TaskEnvironment task_environment_;
  FakeWebMediaPlayerDelegate delegate_;
  bool parc_safari_identity_ = false;
  FakeWebMediaPlayerDelegate moved_to_delegate_;
  std::unique_ptr<WebMediaPlayerMS> player_;
};

// A Chrome-identity page's player stays with the frame that made it.
TEST_P(ParcWebMediaPlayerMSTest, ParcMoveToFrameKeepsChromeIdentityPlayer) {
  InitializeWebMediaPlayerMS();
  ParcWebMediaPlayerExtension::ParcFrameServices services;
  services.delegate = &moved_to_delegate_;
  EXPECT_FALSE(player_->ParcMoveToFrame(std::move(services)));
  EXPECT_TRUE(delegate_.has_observer());
}

INSTANTIATE_TEST_SUITE_P(All,
                         ParcWebMediaPlayerMSTest,
                         ::testing::Combine(::testing::Bool(),
                                            ::testing::Bool()));

}  // namespace
}  // namespace blink
