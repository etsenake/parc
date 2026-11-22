#import "PrivateSessionLedgerTestsSupport.h"

namespace PrivateSessionLedgerTestsSupport {

parc::PrivateSessionUse Host::Use(const Session& session) {
  SessionPtr state = session.lock();
  if (!state || !state->alive) {
    return parc::PrivateSessionUse::kGone;
  }
  if (state->dying) {
    return parc::PrivateSessionUse::kDying;
  }
  return state->browsers ? parc::PrivateSessionUse::kOpen
                         : parc::PrivateSessionUse::kIdle;
}

bool Host::HasOperations(const Session& session) {
  SessionPtr state = session.lock();
  return state && state->operations > 0;
}

void Host::Destroy(const Session& session) {
  if (SessionPtr state = session.lock()) {
    Check(world->ledger.Claims(state->parent) == 0 && state->operations == 0,
          "the ledger never asks to end a claimed or busy session");
    world->DestroyUnused(state);
  }
}

void Host::ScheduleRetry() {
  if (world->retry_posted) {
    return;
  }
  world->retry_posted = true;
  World* target = world;
  world->Post([target] {
    target->retry_posted = false;
    target->ledger.Retry();
  });
}

bool Host::Dying(Key parent) {
  SessionPtr session = world->Current(parent);
  return session && session->dying;
}

void Host::WatchEnd(Key parent) {
  if (SessionPtr session = world->Current(parent)) {
    session->watched = true;
    return;
  }
  World* target = world;
  world->Post([target, parent] { target->ledger.Ended(parent); });
}

void FailedCreationAfterLastWindowClosed(Failure failure) {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  Check(!world.Begin(1, failure, [&] { world.CloseWindow(1); }),
        "the overlapping creation fails");
  world.RunAll();
  Check(world.teardowns == 1,
        "the session is torn down once the failed creation lets go");
  world.Quiesce();
  Check(!world.Current(1), "nothing survives a failed creation after the last close");
  world.CheckSettled();
}

void FailureAtEachStep(bool window_open, Failure failure) {
  World world;
  if (window_open) {
    Check(world.Begin(1), "an existing window opens");
  }
  int outcomes = 0;
  world.PrivateWindow(1, failure, &outcomes);
  Check(outcomes == 1, "the failed request completes once");
  Check(!world.Routed(1, failure) || window_open,
        "a failed routed request opens nothing new");
  world.Quiesce();
  world.CheckSettled();
  Check(world.ledger.Idle(), "no claim leaks from a failure");
  if (window_open) {
    Check(world.Current(1) && world.Current(1)->browsers >= 1,
          "an existing window keeps its session");
  } else {
    Check(world.slots.empty(), "a failure leaves no session behind");
  }
}

}
