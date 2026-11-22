#import "PrivateSessionLedgerTestsSupport.h"

using namespace PrivateSessionLedgerTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_PrivateSessionLedgerTestsTeardownTests")))
@interface PrivateSessionLedgerTestsTeardownTests : ParcNativeTestCase
@end

@implementation PrivateSessionLedgerTestsTeardownTests

- (void)testDestroyedCreatorsReleaseTheirClaims {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  int calls = 0;
  {
    auto creator = std::make_shared<int>(0);
    std::weak_ptr<int> weak = creator;
    world.Prepare(1, [&calls, weak](bool) {
      ++calls;
      if (auto alive = weak.lock()) {
        ++*alive;
      }
    });
  }
  Check(world.ledger.Claims(1) == 1, "the request outlives its creator");
  world.Quiesce();
  Check(calls == 1, "the orphaned request completes once");
  Check(world.ledger.Idle(), "its claim is released");
  world.CheckSettled();
  Check(world.slots.empty(), "no window and no session");
}

- (void)testAParentCannotBeRemovedWhileItsRequestIsWaiting {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  int outcomes = 0;
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  Check(!world.CanRemoveParent(1), "removal waits for the request");
  world.disabled[1] = true;
  world.Quiesce();
  Check(world.CanRemoveParent(1), "removal can proceed afterwards");
  world.CheckSettled();
}

- (void)testAParentDisabledWhileWaitingOpensNoWindow {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  int outcomes = 0;
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  world.disabled[1] = true;
  world.Quiesce();
  Check(outcomes == 1, "the request completes once");
  Check(world.slots.empty(), "a disabled profile opens nothing");
  world.CheckSettled();
}

- (void)testOperationsKeepTheSessionUntilTheyEnd {
  World world;
  Check(world.Begin(1), "first window opens");
  world.AcquireOperation(1);
  world.CloseWindow(1);
  world.RunAll();
  Check(world.Current(1) && !world.Current(1)->dying,
        "an operation keeps the session after the last window");
  world.ReleaseOperation(1);
  world.RunAll();
  Check(world.teardowns == 1, "the session ends when the operation ends");
  world.Quiesce();
  world.CheckSettled();
}

- (void)testClaimDuringRetryKeepsTheSession {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  {
    Claim held = world.ledger.Acquire(1);
    world.CloseWindow(1);
    Check(world.ledger.Pending(1), "the deferred teardown is pending");
    world.RunAll();
    Check(world.teardowns == 0, "a retry while claimed keeps the session");
  }
  world.RunAll();
  Check(world.teardowns == 1, "releasing the claim retries the teardown");
  world.Quiesce();
  world.CheckSettled();
}

- (void)testClaimTakenByATeardownObserverDuringRetry {
  World world;
  Check(!world.Routed(1, Failure::kBeforeSession), "the first orphan is left behind");
  Check(!world.Routed(2, Failure::kBeforeSession), "the second orphan is left behind");
  Claim taken;
  world.on_teardown = [&](const SessionPtr& session) {
    if (session->parent == 1) {
      taken = world.ledger.Acquire(2);
    }
  };
  world.RunAll();
  Check(!world.Current(1), "the first orphan ends");
  Check(world.Current(2) && !world.Current(2)->dying,
        "a claim taken mid-retry keeps the other session");
  world.on_teardown = nullptr;
  taken.Reset();
  world.Quiesce();
  world.CheckSettled();
  Check(world.slots.empty(), "releasing that claim ends the other session too");
}

- (void)testSpuriousEndKeepsWaiting {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  int outcomes = 0;
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  world.ledger.Ended(1);
  world.ledger.Ended(2);
  Check(outcomes == 0, "an early end notice cannot release a waiter");
  world.Quiesce();
  Check(outcomes == 1, "the real end releases it once");
  world.CheckSettled();
}

- (void)testAwaitWhileQuittingFailsAtOnce {
  World world;
  world.ledger.SetClosing(true);
  int calls = 0;
  world.ledger.Await(world.ledger.Acquire(1), [&](bool settled) {
    ++calls;
    Check(!settled, "a wait that starts while quitting is never ready");
    Check(world.ledger.Claims(1) == 1, "it still runs under its claim");
  });
  Check(calls == 1, "it completes at once, exactly once");
  Check(world.ledger.Idle(), "its claim is released");
  world.ledger.SetClosing(false);
}

- (void)testSessionClosedOutsideParcWhileWaiting {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  int outcomes = 0;
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  world.RenderersExit(1);
  Check(!world.Current(1), "the old session is gone");
  SessionPtr next = world.GetOrCreate(1);
  next->renderers = 1;
  world.ForceTeardown(next);
  world.RunAll();
  Check(outcomes == 0, "the end notice finds another closing session and keeps waiting");
  world.RenderersExit(1);
  world.RunAll();
  Check(outcomes == 1, "the waiter completes once that session ends too");
  world.Quiesce();
  world.CheckSettled();
}

- (void)testRandomized {
  std::mt19937 random(20261116);
  const int kScenarios = 4000;
  const int kSteps = 80;
  for (int scenario = 0; scenario < kScenarios; ++scenario) {
    World world;
    int requests = 0;
    int completions = 0;
    int operations_held[3] = {0, 0, 0};
    for (int step = 0; step < kSteps; ++step) {
      const int parent = 1 + static_cast<int>(random() % 2);
      const Failure failure = static_cast<Failure>(random() % 4);
      switch (random() % 13) {
        case 0:
          ++requests;
          world.PrivateWindow(parent, failure, &completions);
          break;
        case 1:
          world.Begin(parent, failure);
          break;
        case 2:
          world.Begin(parent, failure, [&] {
            const int other = 1 + static_cast<int>(random() % 2);
            switch (random() % 4) {
              case 0:
                world.CloseWindow(other);
                break;
              case 1:
                world.Begin(other, static_cast<Failure>(random() % 4));
                break;
              case 2:
                world.RunAll();
                break;
              case 3:
                world.RenderersExit(other);
                break;
            }
          });
          break;
        case 3:
          world.Routed(parent, failure, random() % 2 == 0);
          break;
        case 4:
          ++requests;
          world.DelegateOpen(parent, &completions);
          break;
        case 5:
        case 6:
          world.CloseWindow(parent);
          break;
        case 7:
          world.RenderersExit(parent);
          break;
        case 8:
          world.RunAll();
          world.CheckPromptTeardown();
          break;
        case 9:
          if (world.Current(parent) && !world.Current(parent)->dying) {
            world.AcquireOperation(parent);
            ++operations_held[parent];
          }
          break;
        case 10:
          if (operations_held[parent]) {
            world.ReleaseOperation(parent);
            --operations_held[parent];
          }
          break;
        case 11:
          world.ledger.SetClosing(random() % 4 == 0);
          break;
        case 12:
          world.disabled[parent] = random() % 3 == 0;
          break;
      }
    }
    world.ledger.SetClosing(false);
    world.RunAll();
    world.CheckPromptTeardown();
    world.Quiesce();
    world.CheckSettled();
    Check(completions == requests, "every request completes exactly once");
    Check(world.ledger.Idle(), "no claim survives the scenario");
    for (int parent = 1; parent <= 2; ++parent) {
      while (operations_held[parent]) {
        world.ReleaseOperation(parent);
        --operations_held[parent];
      }
      while (world.CloseWindow(parent)) {
      }
    }
    world.Quiesce();
    world.CheckSettled();
    Check(world.slots.empty(),
          "after every window and operation ends, no private session survives");
  }
}

@end
