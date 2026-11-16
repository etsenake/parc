// Copyright 2026 Parc contributors.
#include <memory>

#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_destroyer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/test/base/testing_profile.h"
#include "content/public/test/browser_task_environment.h"
#include "content/public/test/mock_render_process_host.h"
#include "native_browser.h"
#include "native_host_route.h"
#include "parc/chromium_hooks.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace parc {
namespace {

class ParcPrivateSessionsTest : public testing::Test {
 protected:
  void SetUp() override {
    parc_hooks::SetOTRProfileDestructionDeferral(
        &DeferNativeOTRProfileDestruction);
    RegisterNativeRoute(parent_);
  }

  void TearDown() override {
    Settle();
    EXPECT_TRUE(NativePrivateSessionsIdle());
    parc_hooks::SetOTRProfileDestructionDeferral(nullptr);
  }

  Profile* Session() { return parent_.GetPrimaryOTRProfile(true); }
  bool HasSession() { return parent_.HasPrimaryOTRProfile(); }
  void Settle() { task_environment_.RunUntilIdle(); }

  content::BrowserTaskEnvironment task_environment_;
  TestingProfile parent_;
};

TEST_F(ParcPrivateSessionsTest, UnclaimedLastWindowEndsTheSessionAtOnce) {
  Profile* session = Session();
  EXPECT_FALSE(DeferNativeOTRProfileDestruction(*session));
  parc_hooks::DestroyUnusedOTRProfile(*session);
  EXPECT_FALSE(HasSession());
}

TEST_F(ParcPrivateSessionsTest, LastWindowTeardownWaitsForEveryClaim) {
  Profile* session = Session();
  NativePrivateSessionClaim first = ClaimNativePrivateSession(parent_);
  NativePrivateSessionClaim second = ClaimNativePrivateSession(parent_);
  EXPECT_FALSE(NativePrivateSessionsIdle());
  EXPECT_TRUE(DeferNativeOTRProfileDestruction(*session));
  parc_hooks::DestroyUnusedOTRProfile(*session);
  EXPECT_TRUE(HasSession());
  first.Reset();
  Settle();
  EXPECT_TRUE(HasSession());
  EXPECT_FALSE(session->ShutdownStarted());
  second.Reset();
  EXPECT_TRUE(HasSession());
  Settle();
  EXPECT_FALSE(HasSession());
}

TEST_F(ParcPrivateSessionsTest, AbandonedSessionEndsOnTheNextTask) {
  NominateNativePrivateSession(*Session());
  EXPECT_TRUE(HasSession());
  Settle();
  EXPECT_FALSE(HasSession());
}

TEST_F(ParcPrivateSessionsTest, AbandonedSessionWaitsForItsClaim) {
  Profile* session = Session();
  {
    NativePrivateSessionClaim claim = ClaimNativePrivateSession(parent_);
    NominateNativePrivateSession(*session);
    Settle();
    EXPECT_TRUE(HasSession());
  }
  Settle();
  EXPECT_FALSE(HasSession());
}

TEST_F(ParcPrivateSessionsTest, ClaimsBelongToTheirOwnProfile) {
  TestingProfile other;
  Profile* session = Session();
  NativePrivateSessionClaim claim = ClaimNativePrivateSession(other);
  EXPECT_FALSE(DeferNativeOTRProfileDestruction(*session));
  NominateNativePrivateSession(*session);
  Settle();
  EXPECT_FALSE(HasSession());
}

TEST_F(ParcPrivateSessionsTest, OtherPrivateProfilesAreLeftToTheirOwners) {
  const Profile::OTRProfileID id =
      Profile::OTRProfileID::CreateUniqueForTesting();
  Profile* other = parent_.GetOffTheRecordProfile(id, true);
  NominateNativePrivateSession(*other);
  Settle();
  EXPECT_TRUE(parent_.HasOffTheRecordProfile(id));
}

TEST_F(ParcPrivateSessionsTest, HostReportsTheSessionState) {
  NativePrivateSessionHost host;
  EXPECT_FALSE(host.Dying(&parent_));
  Profile* session = Session();
  const base::WeakPtr<Profile> weak = session->GetWeakPtr();
  EXPECT_EQ(host.Use(weak), PrivateSessionUse::kIdle);
  EXPECT_FALSE(host.HasOperations(weak));
  auto renderer = std::make_unique<content::MockRenderProcessHost>(session);
  ProfileDestroyer::DestroyOTRProfileWhenAppropriate(session);
  ASSERT_TRUE(weak);
  EXPECT_TRUE(host.Dying(&parent_));
  EXPECT_EQ(host.Use(weak), PrivateSessionUse::kDying);
  host.WatchEnd(&parent_);
  renderer.reset();
  Settle();
  EXPECT_FALSE(weak);
  EXPECT_FALSE(HasSession());
  EXPECT_FALSE(host.Dying(&parent_));
  EXPECT_EQ(host.Use(weak), PrivateSessionUse::kGone);
}

TEST_F(ParcPrivateSessionsTest, NoWindowOpensOnASessionThatIsClosing) {
  Profile* session = Session();
  RegisterNativeRoute(*session);
  auto renderer = std::make_unique<content::MockRenderProcessHost>(session);
  parc_hooks::DestroyUnusedOTRProfile(*session);
  ASSERT_TRUE(session->ShutdownStarted());
  BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL,
                                   *session, true);
  EXPECT_FALSE(PrepareNativeBrowserWindow(params));
  EXPECT_TRUE(NativePrivateSessionsIdle());
  renderer.reset();
  Settle();
  EXPECT_FALSE(HasSession());
}

TEST_F(ParcPrivateSessionsTest, RefusedPrivateWindowLeavesNoSessionBehind) {
  Profile* session = Session();
  BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL,
                                   *session, true);
  EXPECT_FALSE(PrepareNativeBrowserWindow(params));
  EXPECT_TRUE(NativePrivateSessionsIdle());
  EXPECT_TRUE(HasSession());
  Settle();
  EXPECT_FALSE(HasSession());
}

}
}
