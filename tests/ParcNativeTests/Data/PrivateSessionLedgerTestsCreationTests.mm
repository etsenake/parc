#import "PrivateSessionLedgerTestsSupport.h"

using namespace PrivateSessionLedgerTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_PrivateSessionLedgerTestsCreationTests")))
@interface PrivateSessionLedgerTestsCreationTests : ParcNativeTestCase
@end

@implementation PrivateSessionLedgerTestsCreationTests

- (void)testLastWindowClosesBeforeCreation {
  World world;
  Check(world.Begin(1), "first window opens");
  const int first_id = world.Current(1)->id;
  world.RunAll();
  world.CloseWindow(1);
  Check(world.Current(1)->dying, "the old session is being torn down");
  Check(!world.Begin(1), "a direct begin refuses the dying session");
  int outcomes = 0;
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  Check(outcomes == 0, "New Private Window waits for the old session to end");
  Check(world.ledger.Claims(1) == 1, "the waiting request holds one claim");
  Check(!world.CanRemoveParent(1), "the profile cannot be removed while a request waits");
  world.RunAll();
  Check(outcomes == 0, "it keeps waiting while the old session is still dying");
  world.RenderersExit(1);
  world.RunAll();
  Check(outcomes == 1, "the waiting request completes exactly once");
  Check(world.Current(1) && world.Current(1)->id != first_id,
        "the new window gets a fresh session");
  Check(world.Current(1)->browsers == 1, "the new window opened");
  world.Quiesce();
  world.CheckSettled();
}

- (void)testChromiumOpensDuringTeardown {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  Check(!world.Routed(1), "an extension window is refused, never placed on the dying session");
  world.RunAll();
  int outcomes = 0;
  world.DelegateOpen(1, &outcomes);
  Check(outcomes == 0, "the page menu's private open waits for the old session");
  world.Quiesce();
  Check(outcomes == 1, "the page menu's private open completes once");
  Check(world.Current(1) && world.Current(1)->browsers == 1,
        "the link opens in a fresh private window");
  world.CloseWindow(1);
  world.Quiesce();
  world.CheckSettled();
  Check(world.slots.empty(), "no session survives");
}

- (void)testChromiumOpensAPrivateWindowWhenNoneExist {
  World world;
  int outcomes = 0;
  world.DelegateOpen(1, &outcomes);
  Check(outcomes == 1 && world.Current(1)->browsers == 1,
        "with no private window, the link opens a new one");
  world.Quiesce();
  world.CheckSettled();
}

- (void)testChromiumOpensInTheExistingPrivateSession {
  World world;
  int outcomes = 0;
  world.DelegateOpen(1, &outcomes);
  Check(outcomes == 1 && world.Current(1)->browsers == 1,
        "with no private window, the link opens a new one");
  world.DelegateOpen(1, &outcomes);
  Check(world.created == 1 && world.Current(1)->browsers == 2,
        "with a private window, the link joins its session");
  world.Quiesce();
  world.CheckSettled();
}

- (void)testChromiumKeepsDifferentProfilesInDifferentPrivateSessions {
  World world;
  int outcomes = 0;
  world.DelegateOpen(1, &outcomes);
  Check(outcomes == 1 && world.Current(1)->browsers == 1,
        "with no private window, the link opens a new one");
  world.DelegateOpen(1, &outcomes);
  Check(world.created == 1 && world.Current(1)->browsers == 2,
        "with a private window, the link joins its session");
  world.DelegateOpen(2, &outcomes);
  Check(world.created == 2 && world.Current(1)->browsers == 2,
        "another profile's link never lands in this profile's session");
  world.Quiesce();
  world.CheckSettled();
}

- (void)testChromiumErrorsBeforeAskingForAWindow {
  World world;
  Check(!world.Routed(1, Failure::kBeforeSession), "the extension request fails early");
  Check(world.Current(1) != nullptr, "Chromium left a session behind");
  world.RunAll();
  Check(world.teardowns == 1, "the orphaned session is torn down");
  world.Quiesce();
  world.CheckSettled();
  Check(world.slots.empty(), "no orphan survives");
}

- (void)testBeforeSessionFailurePreservesTheOpenWindow {
  FailureAtEachStep(true, Failure::kBeforeSession);
}

- (void)testBeforeSessionFailureLeavesNoPrivateSession {
  FailureAtEachStep(false, Failure::kBeforeSession);
}

- (void)testAfterSessionFailurePreservesTheOpenWindow {
  FailureAtEachStep(true, Failure::kAfterSession);
}

- (void)testAfterSessionFailureLeavesNoPrivateSession {
  FailureAtEachStep(false, Failure::kAfterSession);
}

- (void)testAdmissionFailurePreservesTheOpenWindow {
  FailureAtEachStep(true, Failure::kAdmission);
}

- (void)testAdmissionFailureLeavesNoPrivateSession {
  FailureAtEachStep(false, Failure::kAdmission);
}

@end
