// Copyright 2026 Parc contributors.
// Installed at //content/browser/media/parc_tests/back_forward_cache_impl_test.cc.
// The fixture is derived from Chromium's matching unittest (Chromium Authors;
// BSD-style license in Chromium's LICENSE).

#include "content/browser/back_forward_cache/back_forward_cache_impl.h"

#include <optional>
#include <string>
#include <utility>

#include "base/functional/callback_helpers.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_number_conversions.h"
#include "base/test/bind.h"
#include "base/test/scoped_feature_list.h"
#include "base/test/test_mock_time_task_runner.h"
#include "base/time/time.h"
#include "content/browser/media/media_web_contents_observer.h"
#include "content/browser/media/parc_fairplay_hooks.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/test/navigation_simulator.h"
#include "content/test/test_render_frame_host.h"
#include "content/test/test_render_view_host.h"
#include "content/test/test_web_contents.h"
#include "media/mojo/mojom/media_player.mojom.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "mojo/public/cpp/bindings/pending_associated_receiver.h"
#include "mojo/public/cpp/bindings/pending_associated_remote.h"
#include "services/media_session/public/mojom/media_session.mojom.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "url/gurl.h"

namespace content {
namespace {

GURL GetNextUrl() {
  static int counter = 0;
  return GURL("http://" + base::NumberToString(counter++) + ".com");
}

}  // namespace

class ParcBackForwardCacheImplTest : public RenderViewHostImplTestHarness {
 public:
  void SetUp() override {
    RenderViewHostImplTestHarness::SetUp();
    scoped_feature_list_.InitAndDisableFeature(
        kAllowCrossOriginNotRestoredReasons);
  }

 private:
  base::test::ScopedFeatureList scoped_feature_list_;
};

// Parc: a Safari-identity page stays as long as WebKit keeps one
// (BackForwardCacheExpirationInterval); other pages keep Chromium's time.
TEST_F(ParcBackForwardCacheImplTest, ParcSafariIdentityPageStaysThirtyMinutes) {
  auto task_runner = base::MakeRefCounted<base::TestMockTimeTaskRunner>();
  contents()->GetController().GetBackForwardCache().SetTaskRunnerForTesting(
      task_runner);
  RenderFrameHost* safari_frame = nullptr;
  parc::fairplay::SetSafariIdentityQuery(base::BindLambdaForTesting(
      [&](RenderFrameHost* frame) { return frame == safari_frame; }));
  base::ScopedClosureRunner reset_query(base::BindOnce(
      [] { parc::fairplay::SetSafariIdentityQuery({}); }));

  NavigationSimulator::NavigateAndCommitFromBrowser(contents(), GetNextUrl());
  base::WeakPtr<RenderFrameHostImpl> safari =
      contents()->GetPrimaryMainFrame()->GetWeakPtr();
  safari_frame = safari.get();
  NavigationSimulator::NavigateAndCommitFromBrowser(contents(), GetNextUrl());
  base::WeakPtr<RenderFrameHostImpl> chrome =
      contents()->GetPrimaryMainFrame()->GetWeakPtr();
  NavigationSimulator::NavigateAndCommitFromBrowser(contents(), GetNextUrl());
  ASSERT_TRUE(safari && safari->IsInBackForwardCache());
  ASSERT_TRUE(chrome && chrome->IsInBackForwardCache());

  task_runner->FastForwardBy(base::Minutes(11));
  EXPECT_TRUE(!chrome || chrome->is_evicted_from_back_forward_cache());
  ASSERT_TRUE(safari);
  EXPECT_FALSE(safari->is_evicted_from_back_forward_cache());

  task_runner->FastForwardBy(base::Minutes(20));
  EXPECT_TRUE(!safari || safari->is_evicted_from_back_forward_cache());
}

// Parc: a player in a frame, telling the browser whether it casts.
class ParcCastingPlayer {
 public:
  ParcCastingPlayer(MediaWebContentsObserver* observer, RenderFrameHost* frame) {
    observer->BindMediaPlayerHost(
        frame->GetGlobalId(),
        player_host_.BindNewEndpointAndPassDedicatedReceiver());
    mojo::PendingAssociatedRemote<media::mojom::MediaPlayer> player;
    player_receiver_ = player.InitWithNewEndpointAndPassReceiver();
    player_host_->OnMediaPlayerAdded(std::move(player),
                                     observer_.BindNewEndpointAndPassReceiver(),
                                     /*player_id=*/1);
    player_host_.FlushForTesting();
  }

  void SetCasting(bool started) {
    observer_->OnRemotePlaybackMetadataChange(
        media_session::mojom::RemotePlaybackMetadata::New(
            "vp8", "opus", /*remote_playback_disabled=*/false, started,
            std::nullopt, /*is_encrypted_media=*/false));
    observer_.FlushForTesting();
  }

 private:
  mojo::AssociatedRemote<media::mojom::MediaPlayerHost> player_host_;
  mojo::PendingAssociatedReceiver<media::mojom::MediaPlayer> player_receiver_;
  mojo::AssociatedRemote<media::mojom::MediaPlayerObserver> observer_;
};

// Parc: a page casting a video stays as long as WebKit keeps its AirPlay
// route after the video stopped (an hour); other pages keep their time.
TEST_F(ParcBackForwardCacheImplTest, ParcCastingPageStaysAnHour) {
  auto task_runner = base::MakeRefCounted<base::TestMockTimeTaskRunner>();
  contents()->GetController().GetBackForwardCache().SetTaskRunnerForTesting(
      task_runner);

  NavigationSimulator::NavigateAndCommitFromBrowser(contents(), GetNextUrl());
  base::WeakPtr<RenderFrameHostImpl> casting =
      contents()->GetPrimaryMainFrame()->GetWeakPtr();
  ParcCastingPlayer player(contents()->media_web_contents_observer(),
                           casting.get());
  player.SetCasting(true);
  NavigationSimulator::NavigateAndCommitFromBrowser(contents(), GetNextUrl());
  base::WeakPtr<RenderFrameHostImpl> other =
      contents()->GetPrimaryMainFrame()->GetWeakPtr();
  NavigationSimulator::NavigateAndCommitFromBrowser(contents(), GetNextUrl());
  ASSERT_TRUE(casting && casting->IsInBackForwardCache());
  ASSERT_TRUE(other && other->IsInBackForwardCache());

  task_runner->FastForwardBy(base::Minutes(11));
  EXPECT_TRUE(!other || other->is_evicted_from_back_forward_cache());
  task_runner->FastForwardBy(base::Minutes(48));
  ASSERT_TRUE(casting);
  EXPECT_FALSE(casting->is_evicted_from_back_forward_cache());

  task_runner->FastForwardBy(base::Minutes(2));
  EXPECT_TRUE(!casting || casting->is_evicted_from_back_forward_cache());
}

TEST_F(ParcBackForwardCacheImplTest, ParcPageWhoseCastEndedKeepsItsTime) {
  auto task_runner = base::MakeRefCounted<base::TestMockTimeTaskRunner>();
  contents()->GetController().GetBackForwardCache().SetTaskRunnerForTesting(
      task_runner);

  NavigationSimulator::NavigateAndCommitFromBrowser(contents(), GetNextUrl());
  base::WeakPtr<RenderFrameHostImpl> page =
      contents()->GetPrimaryMainFrame()->GetWeakPtr();
  ParcCastingPlayer player(contents()->media_web_contents_observer(),
                           page.get());
  player.SetCasting(true);
  NavigationSimulator::NavigateAndCommitFromBrowser(contents(), GetNextUrl());
  ASSERT_TRUE(page && page->IsInBackForwardCache());

  // The user ends the cast while the page is cached.
  player.SetCasting(false);

  task_runner->FastForwardBy(base::Minutes(11));
  EXPECT_TRUE(!page || page->is_evicted_from_back_forward_cache());
}

}  // namespace content
