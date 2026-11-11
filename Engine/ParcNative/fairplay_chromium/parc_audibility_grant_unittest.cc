// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //content/browser/media/parc_audibility_grant_unittest.cc.
//
// The audibility grants Parc's FairPlay host gives each FairPlay Renderer and
// native HLS player (AudibilityBypassTracker::AddPlayerGrant), which keep the
// player in the tab's speaker indicator.
#include "content/browser/media/media_web_contents_observer.h"

#include "content/public/browser/render_frame_host.h"
#include "content/public/test/test_renderer_host.h"
#include "content/test/test_render_view_host.h"
#include "content/test/test_web_contents.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace content {
namespace {

using ParcAudibilityGrantTest = RenderViewHostImplTestHarness;

// Two players whose renderers were made in one order and who claim in the
// other each hold their own grant, so closing the first player's renderer
// leaves the second audible. From a shared pool the second held the first's
// grant and lost it.
TEST_F(ParcAudibilityGrantTest, ClosingOnePlayersRendererKeepsTheOthers) {
  RenderFrameHost* frame = contents()->GetPrimaryMainFrame();
  const MediaPlayerId first(frame->GetGlobalId(), 1);
  const MediaPlayerId second(frame->GetGlobalId(), 2);
  auto first_grant =
      AudibilityBypassTracker::AddPlayerGrant(frame, first.player_id);
  auto second_grant =
      AudibilityBypassTracker::AddPlayerGrant(frame, second.player_id);

  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(second));
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(first));
  first_grant.RunAndReset();

  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(second));
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(first));
}

TEST_F(ParcAudibilityGrantTest, OnlyItsPlayerClaimsAGrant) {
  RenderFrameHost* frame = contents()->GetPrimaryMainFrame();
  auto grant = AudibilityBypassTracker::AddPlayerGrant(frame, 1);

  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(
      MediaPlayerId(frame->GetGlobalId(), 2)));
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(
      MediaPlayerId(frame->GetGlobalId(), 1)));
}

// A player holds two renderers while one hands off to the other; when the
// first goes, the second's grant keeps the player audible.
TEST_F(ParcAudibilityGrantTest, SecondRendererGrantTakesOverForItsPlayer) {
  RenderFrameHost* frame = contents()->GetPrimaryMainFrame();
  const MediaPlayerId player(frame->GetGlobalId(), 4);
  auto first_grant = AudibilityBypassTracker::AddPlayerGrant(frame, 4);
  auto second_grant = AudibilityBypassTracker::AddPlayerGrant(frame, 4);

  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(player));
  first_grant.RunAndReset();
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(player));
  second_grant.RunAndReset();
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(player));
}

// A Safari-identity page moved a player that had claimed its grant: the old
// registration's release hands the grant to the new one.
TEST_F(ParcAudibilityGrantTest, ClaimedGrantFollowsItsMovedPlayer) {
  RenderFrameHost* main_frame = contents()->GetPrimaryMainFrame();
  RenderFrameHostTester::For(main_frame)->InitializeRenderFrameIfNeeded();
  RenderFrameHost* child_frame =
      RenderFrameHostTester::For(main_frame)->AppendChild("child");
  ASSERT_NE(child_frame, nullptr);
  ASSERT_EQ(main_frame->GetProcess(), child_frame->GetProcess());
  auto grant = AudibilityBypassTracker::AddPlayerGrant(main_frame, 5);
  const MediaPlayerId before(main_frame->GetGlobalId(), 5);
  const MediaPlayerId after(child_frame->GetGlobalId(), 5);

  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(before));
  AudibilityBypassTracker::ReleaseGrant(before);
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(after));
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(before));
  grant.RunAndReset();
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(after));
}

// A Safari-identity page moved the player to another frame before it claimed
// its renderer's grant; the grant follows it there.
TEST_F(ParcAudibilityGrantTest, UnclaimedGrantFollowsItsMovedPlayer) {
  RenderFrameHost* main_frame = contents()->GetPrimaryMainFrame();
  RenderFrameHostTester::For(main_frame)->InitializeRenderFrameIfNeeded();
  RenderFrameHost* child_frame =
      RenderFrameHostTester::For(main_frame)->AppendChild("child");
  ASSERT_NE(child_frame, nullptr);
  ASSERT_EQ(main_frame->GetProcess(), child_frame->GetProcess());
  auto grant = AudibilityBypassTracker::AddPlayerGrant(main_frame, 3);

  const MediaPlayerId moved(child_frame->GetGlobalId(), 3);
  EXPECT_TRUE(AudibilityBypassTracker::ClaimGrant(moved));
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(
      MediaPlayerId(main_frame->GetGlobalId(), 3)));
  grant.RunAndReset();
  AudibilityBypassTracker::ReleaseGrant(moved);
  EXPECT_FALSE(AudibilityBypassTracker::ClaimGrant(moved));
}

}  // namespace
}  // namespace content
