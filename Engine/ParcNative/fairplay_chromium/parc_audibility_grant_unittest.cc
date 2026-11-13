// Copyright 2026 Parc contributors.
#include "content/browser/media/media_web_contents_observer.h"

#include "content/browser/media/parc_media_routing.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/test/test_renderer_host.h"
#include "content/test/test_render_view_host.h"
#include "content/test/test_web_contents.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace content {
namespace {

using ParcAudibilityGrantTest = RenderViewHostImplTestHarness;

TEST_F(ParcAudibilityGrantTest, ClosingOnePlayersRendererKeepsTheOthers) {
  RenderFrameHost* frame = contents()->GetPrimaryMainFrame();
  const MediaPlayerId first(frame->GetGlobalId(), 1);
  const MediaPlayerId second(frame->GetGlobalId(), 2);
  auto first_grant = ParcAddPlayerGrant(frame, first.player_id);
  auto second_grant = ParcAddPlayerGrant(frame, second.player_id);

  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(second));
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(first));
  first_grant.RunAndReset();

  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(second));
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(first));
}

TEST_F(ParcAudibilityGrantTest, OnlyItsPlayerClaimsAGrant) {
  RenderFrameHost* frame = contents()->GetPrimaryMainFrame();
  auto grant = ParcAddPlayerGrant(frame, 1);

  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(
      MediaPlayerId(frame->GetGlobalId(), 2)));
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(
      MediaPlayerId(frame->GetGlobalId(), 1)));
}

TEST_F(ParcAudibilityGrantTest, SecondRendererGrantTakesOverForItsPlayer) {
  RenderFrameHost* frame = contents()->GetPrimaryMainFrame();
  const MediaPlayerId player(frame->GetGlobalId(), 4);
  auto first_grant = ParcAddPlayerGrant(frame, 4);
  auto second_grant = ParcAddPlayerGrant(frame, 4);

  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(player));
  first_grant.RunAndReset();
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(player));
  second_grant.RunAndReset();
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(player));
}

TEST_F(ParcAudibilityGrantTest, ClaimedGrantFollowsItsMovedPlayer) {
  RenderFrameHost* main_frame = contents()->GetPrimaryMainFrame();
  RenderFrameHostTester::For(main_frame)->InitializeRenderFrameIfNeeded();
  RenderFrameHost* child_frame =
      RenderFrameHostTester::For(main_frame)->AppendChild("child");
  ASSERT_NE(child_frame, nullptr);
  ASSERT_EQ(main_frame->GetProcess(), child_frame->GetProcess());
  auto grant = ParcAddPlayerGrant(main_frame, 5);
  const MediaPlayerId before(main_frame->GetGlobalId(), 5);
  const MediaPlayerId after(child_frame->GetGlobalId(), 5);

  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(before));
  AudibilityBypassTracker::ReleaseGrant(before);
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(after));
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(before));
  grant.RunAndReset();
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(after));
}

TEST_F(ParcAudibilityGrantTest, UnclaimedGrantFollowsItsMovedPlayer) {
  RenderFrameHost* main_frame = contents()->GetPrimaryMainFrame();
  RenderFrameHostTester::For(main_frame)->InitializeRenderFrameIfNeeded();
  RenderFrameHost* child_frame =
      RenderFrameHostTester::For(main_frame)->AppendChild("child");
  ASSERT_NE(child_frame, nullptr);
  ASSERT_EQ(main_frame->GetProcess(), child_frame->GetProcess());
  auto grant = ParcAddPlayerGrant(main_frame, 3);

  const MediaPlayerId moved(child_frame->GetGlobalId(), 3);
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(moved));
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(
      MediaPlayerId(main_frame->GetGlobalId(), 3)));
  grant.RunAndReset();
  AudibilityBypassTracker::ReleaseGrant(moved);
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(moved));
}

}
}
