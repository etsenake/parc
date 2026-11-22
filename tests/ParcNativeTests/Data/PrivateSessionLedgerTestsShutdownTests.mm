#import "PrivateSessionLedgerTestsSupport.h"

using namespace PrivateSessionLedgerTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_PrivateSessionLedgerTestsShutdownTests")))
@interface PrivateSessionLedgerTestsShutdownTests : ParcNativeTestCase
@end

@implementation PrivateSessionLedgerTestsShutdownTests

- (void)testQuitDuringCreation {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  int first = 0;
  int second = 0;
  world.PrivateWindow(1, Failure::kNone, &first);
  world.Prepare(1, [&](bool ready) {
    ++second;
    Check(!ready, "a waiting request fails once quitting goes ahead");
    world.ledger.SetClosing(true);
  });
  world.ledger.SetClosing(true);
  Check(first == 0 && second == 0,
        "starting a quit keeps waiting requests parked in case it is cancelled");
  int late = 0;
  world.PrivateWindow(1, Failure::kNone, &late);
  Check(late == 1, "a request made during a quit completes at once");
  world.Quiesce();
  Check(first == 1 && second == 1, "each waiting request completes once");
  Check(world.ledger.Idle(), "quitting releases every claim");
  world.CheckSettled();
  Check(world.slots.empty(), "quitting leaves no session");
  world.ledger.SetClosing(false);
  Check(world.Begin(1), "a cancelled quit allows private windows again");
}

- (void)testCancelledQuitKeepsTheRequest {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  int outcomes = 0;
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  world.ledger.SetClosing(true);
  world.ledger.SetClosing(false);
  world.Quiesce();
  Check(outcomes == 1, "the request survives a cancelled quit and completes once");
  Check(world.Current(1) && world.Current(1)->browsers == 1,
        "the private window still opens after the quit is cancelled");
  world.CheckSettled();
}

- (void)testQuitCancelledTooLateReportsNotReady {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  int outcomes = 0;
  bool ready = true;
  world.Prepare(1, [&](bool value) {
    ++outcomes;
    ready = value;
  });
  world.ledger.SetClosing(true);
  world.Quiesce();
  world.ledger.SetClosing(false);
  Check(outcomes == 1 && !ready,
        "a request whose old session ended during the quit completes once, as failed");
  Check(world.ledger.Idle(), "its claim is released");
  world.CheckSettled();
}

- (void)testWaitingOnAnAbandonedSessionThatIsClosing {
  World world;
  Check(!world.Routed(1, Failure::kBeforeSession, true),
        "Chromium leaves a session with live renderers behind");
  world.RunAll();
  Check(world.Current(1) && world.Current(1)->dying,
        "the abandoned session starts closing");
  int outcomes = 0;
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  Check(outcomes == 0, "New Private Window waits for it");
  Check(!world.CanRemoveParent(1), "removal waits for the request's lease");
  world.Quiesce();
  Check(outcomes == 1 && world.Current(1)->browsers == 1,
        "the window opens on a fresh session");
  world.CheckSettled();
}

- (void)testQuitWhileSettlingReportsNotSettled {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  std::vector<bool> results;
  world.Prepare(1, [&](bool ready) {
    results.push_back(ready);
    world.ledger.SetClosing(true);
  });
  world.Prepare(1, [&](bool ready) { results.push_back(ready); });
  world.Quiesce();
  Check(results.size() == 2, "both waiters complete once");
  Check(results[0] && !results[1],
        "a waiter settled after quitting starts is told it is not ready");
  world.CheckSettled();
}

@end
