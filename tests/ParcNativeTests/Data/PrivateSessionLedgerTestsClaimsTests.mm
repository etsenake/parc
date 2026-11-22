#import "PrivateSessionLedgerTestsSupport.h"

using namespace PrivateSessionLedgerTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_PrivateSessionLedgerTestsClaimsTests")))
@interface PrivateSessionLedgerTestsClaimsTests : ParcNativeTestCase
@end

@implementation PrivateSessionLedgerTestsClaimsTests

- (void)testADefaultClaimHoldsNothing {
  Claim empty;
  Check(!empty, "a default claim holds nothing");
  empty.Reset();
}

- (void)testMovingAClaimTransfersItsSingleCount {
  World world;
  Claim first = world.ledger.Acquire(1);
  Check(world.ledger.Claims(1) == 1, "acquiring counts one claim");
  Claim second = std::move(first);
  Check(!first && second, "moving a claim transfers it");
  Check(world.ledger.Claims(1) == 1, "moving a claim does not add a count");
}

- (void)testAssigningAClaimToItselfKeepsItsCount {
  World world;
  Claim second = world.ledger.Acquire(1);
  Claim& alias = second;
  second = std::move(alias);
  Check(second && world.ledger.Claims(1) == 1, "self-assignment keeps exactly one claim");
}

- (void)testMoveAssignmentReleasesTheOverwrittenClaim {
  World world;
  Claim second = world.ledger.Acquire(1);
  Claim third = world.ledger.Acquire(1);
  Check(world.ledger.Claims(1) == 2, "claims are counted");
  third = std::move(second);
  Check(world.ledger.Claims(1) == 1, "assigning over a claim releases the overwritten one");
}

- (void)testRepeatedlyResettingAClaimReleasesItOnlyOnce {
  World world;
  Claim third = world.ledger.Acquire(1);
  third.Reset();
  third.Reset();
  Check(world.ledger.Claims(1) == 0, "reset releases once and only once");
  Check(world.ledger.Idle(), "every claim is gone after its scope");
}

- (void)testOverlappingCreationsShareOneSession {
  World world;
  int outcomes = 0;
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  Check(outcomes == 2, "both requests complete");
  Check(world.created == 1, "overlapping requests share one private session");
  Check(world.Current(1)->browsers == 2, "both windows opened");
  world.RunAll();
  world.CheckPromptTeardown();
  world.CloseWindow(1);
  world.RunAll();
  Check(world.Current(1) && !world.Current(1)->dying,
        "closing one of two windows keeps the session");
  world.CloseWindow(1);
  world.Quiesce();
  Check(!world.Current(1), "closing the last window ends the session");
  world.CheckSettled();
}

- (void)testCreationClaimsBeforeLastWindowCloses {
  World world;
  Check(world.Begin(1), "first window opens");
  const int first_id = world.Current(1)->id;
  world.RunAll();
  bool closed = false;
  Check(world.Begin(1, Failure::kNone, [&] {
          closed = world.CloseWindow(1);
          world.RunAll();
        }),
        "a creation overlapping the last close still opens");
  Check(closed, "the last window really closed mid-creation");
  Check(world.teardowns == 0, "the claimed session was never torn down");
  Check(world.Current(1)->id == first_id,
        "the new window joined the session it claimed");
  world.Quiesce();
  Check(world.Current(1) && world.Current(1)->browsers == 1,
        "the session survives with its new window");
  world.CheckSettled();
}

- (void)testFailingAfterSessionAfterLastWindowCloseReleasesTheSession {
  FailedCreationAfterLastWindowClosed(Failure::kAfterSession);
}

- (void)testFailingAdmissionAfterLastWindowCloseReleasesTheSession {
  FailedCreationAfterLastWindowClosed(Failure::kAdmission);
}

- (void)testReentrantCreationNeitherDoubleClaimsNorReleasesEarly {
  World world;
  size_t inner_claims = 0;
  size_t after_inner = 0;
  Check(world.Begin(1, Failure::kNone, [&] {
          Check(world.ledger.Claims(1) == 1, "the outer creation holds one claim");
          Check(world.Begin(1, Failure::kAdmission, [&] {
                  inner_claims = world.ledger.Claims(1);
                }) == false,
                "the reentrant creation fails");
          after_inner = world.ledger.Claims(1);
          world.RunAll();
        }),
        "the outer creation still opens");
  Check(inner_claims == 2, "the reentrant creation adds exactly its own claim");
  Check(after_inner == 1, "the reentrant failure releases only its own claim");
  Check(world.teardowns == 0, "the reentrant failure never tore the session down");
  Check(world.ledger.Claims(1) == 0, "both claims are released");
  world.Quiesce();
  world.CheckSettled();
  Check(world.Current(1)->browsers == 1, "exactly one window opened");
}

- (void)testReentrantWaitersAndTeardownObservers {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  int observed = 0;
  int nested = 0;
  world.on_teardown = [&](const SessionPtr&) {
    world.on_teardown = nullptr;
    world.Prepare(1, [&](bool ready) {
      ++observed;
      if (ready) {
        world.Prepare(1, [&](bool again) {
          ++nested;
          Check(again, "a waiter can start another request while it runs");
          Check(world.ledger.Claims(1) == 2, "the outer waiter still holds its claim");
          world.Begin(1);
        });
      }
    });
  };
  world.CloseWindow(1);
  Check(observed == 0, "a request made during teardown waits");
  world.Quiesce();
  Check(observed == 1 && nested == 1, "each request completes exactly once");
  Check(world.Current(1) && world.Current(1)->browsers == 1,
        "the nested request opened a fresh window");
  world.CheckSettled();
}

@end
