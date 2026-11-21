#import "ParcNativeTest.h"
#include "private_session_ledger.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <random>
#include <utility>
#include <vector>

namespace {


#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)

struct SessionState {
  int parent = 0;
  int id = 0;
  bool alive = true;
  bool dying = false;
  int browsers = 0;
  int operations = 0;
  int renderers = 0;
  bool watched = false;
};
using SessionPtr = std::shared_ptr<SessionState>;

struct World;

struct Host {
  using Key = int;
  using Session = std::weak_ptr<SessionState>;
  using Waiter = std::function<void(bool)>;

  parc::PrivateSessionUse Use(const Session& session);
  bool HasOperations(const Session& session);
  void Destroy(const Session& session);
  void ScheduleRetry();
  bool Dying(Key parent);
  void WatchEnd(Key parent);
  void Finish(Waiter waiter, bool settled) { waiter(settled); }

  World* world = nullptr;
};

using Ledger = parc::PrivateSessionLedger<Host>;
using Claim = Ledger::Claim;

enum class Failure { kNone, kBeforeSession, kAfterSession, kAdmission };

struct World {
  World() { host.world = this; }
  ~World() { tasks.clear(); }

  SessionPtr Current(int parent) {
    const auto found = slots.find(parent);
    return found == slots.end() ? nullptr : found->second;
  }

  SessionPtr GetOrCreate(int parent) {
    if (SessionPtr session = Current(parent)) {
      return session;
    }
    auto session = std::make_shared<SessionState>();
    session->parent = parent;
    session->id = next_id++;
    slots[parent] = session;
    ++created;
    Nominate(session);
    return session;
  }

  void Nominate(const SessionPtr& session) {
    if (session->alive && !session->dying) {
      ledger.Nominate(session->parent, session);
    }
  }

  void Post(std::function<void()> task) { tasks.push_back(std::move(task)); }

  void RunAll() {
    while (!tasks.empty()) {
      auto task = std::move(tasks.front());
      tasks.pop_front();
      task();
    }
  }

  void StartDestroy(const SessionPtr& session) {
    Check(session->alive && !session->dying, "a session's teardown starts once");
    Check(session->browsers == 0, "no session is torn down under an open window");
    Check(ledger.Claims(session->parent) == 0,
          "no session is torn down while a creation claims it");
    Check(session->operations == 0,
          "no session is torn down while an operation holds it");
    session->dying = true;
    ++teardowns;
    if (on_teardown) {
      auto observer = on_teardown;
      observer(session);
    }
    if (session->alive && session->dying && session->renderers == 0) {
      Finish(session);
    }
  }

  void Finish(const SessionPtr& session) {
    session->alive = false;
    session->dying = false;
    if (Current(session->parent) == session) {
      slots.erase(session->parent);
    }
    if (session->watched) {
      const int parent = session->parent;
      Post([this, parent] { ledger.Ended(parent); });
    }
  }

  void ForceTeardown(const SessionPtr& session) {
    session->dying = true;
    ++teardowns;
    if (session->renderers == 0) {
      Finish(session);
    }
  }

  void DestroyUnused(const SessionPtr& session) {
    if (ledger.Defer(session->parent, session)) {
      return;
    }
    if (!session->alive || session->dying) {
      return;
    }
    StartDestroy(session);
  }

  void AddBrowser(const SessionPtr& session) {
    Check(session->alive && !session->dying,
          "a window never opens on a session that is being torn down");
    ++session->browsers;
    session->renderers = 1;
  }

  bool CloseWindow(int parent) {
    SessionPtr session = Current(parent);
    if (!session || !session->browsers) {
      return false;
    }
    if (--session->browsers == 0) {
      DestroyUnused(session);
    }
    return true;
  }

  void RenderersExit(int parent) {
    SessionPtr session = Current(parent);
    if (!session) {
      return;
    }
    session->renderers = 0;
    if (session->dying) {
      Finish(session);
    }
  }

  void AcquireOperation(int parent) {
    if (SessionPtr session = Current(parent); session && !session->dying) {
      ++session->operations;
    }
  }

  void ReleaseOperation(int parent) {
    if (SessionPtr session = Current(parent); session && session->operations) {
      --session->operations;
      Post([this] { ledger.Retry(); });
    }
  }

  bool Begin(int parent, Failure failure = Failure::kNone,
             const std::function<void()>& midway = nullptr) {
    if (ledger.Closing()) {
      return false;
    }
    Claim claim = ledger.Acquire(parent);
    if (SessionPtr current = Current(parent); current && current->dying) {
      return false;
    }
    if (failure == Failure::kBeforeSession) {
      return false;
    }
    SessionPtr session = GetOrCreate(parent);
    if (midway) {
      midway();
    }
    Check(session->alive && !session->dying,
          "a claimed session survives whatever runs during its creation");
    if (failure == Failure::kAfterSession) {
      Nominate(session);
      return false;
    }
    Claim admission = ledger.Acquire(parent);
    if (failure == Failure::kAdmission) {
      Nominate(session);
      return false;
    }
    AddBrowser(session);
    return true;
  }

  bool Routed(int parent, Failure failure = Failure::kNone,
              bool orphan_renderers = false) {
    SessionPtr session = GetOrCreate(parent);
    if (failure == Failure::kBeforeSession) {
      if (orphan_renderers && !session->browsers && !session->dying) {
        session->renderers = 1;
      }
      return false;
    }
    if (session->browsers) {
      ++session->browsers;
      return true;
    }
    if (session->dying) {
      Nominate(session);
      return false;
    }
    Claim admission = ledger.Acquire(parent);
    if (failure != Failure::kNone) {
      Nominate(session);
      return false;
    }
    AddBrowser(session);
    return true;
  }

  void Prepare(int parent, std::function<void(bool)> done) {
    if (ledger.Closing()) {
      done(false);
      return;
    }
    ++leases[parent];
    ledger.Await(ledger.Acquire(parent),
                 [this, parent, done = std::move(done)](bool settled) {
                   done(settled && !disabled[parent]);
                   --leases[parent];
                 });
  }

  void PrivateWindow(int parent, Failure failure, int* outcome) {
    Prepare(parent, [this, parent, failure, outcome](bool ready) {
      ++*outcome;
      if (ready) {
        Begin(parent, failure);
      }
    });
  }

  void DelegateOpen(int parent, int* outcome) {
    SessionPtr current = Current(parent);
    if (!current || !current->dying) {
      ++*outcome;
      Routed(parent);
      return;
    }
    ++leases[parent];
    ledger.Await(ledger.Acquire(parent), [this, parent, outcome](bool settled) {
      ++*outcome;
      if (settled && !disabled[parent]) {
        Routed(parent);
      }
      --leases[parent];
    });
  }

  bool CanRemoveParent(int parent) {
    return !leases[parent] && !Current(parent);
  }

  void Quiesce() {
    for (int round = 0; round < 64; ++round) {
      RunAll();
      bool changed = false;
      for (auto& [parent, session] : std::map<int, SessionPtr>(slots)) {
        if (session->dying) {
          RenderersExit(parent);
          changed = true;
        }
      }
      if (!changed && tasks.empty()) {
        return;
      }
    }
    Check(false, "the world settles");
  }

  void CheckSettled() {
    Check(tasks.empty(), "no posted work remains");
    for (const auto& [parent, session] : slots) {
      Check(session->alive && !session->dying, "no session is left half torn down");
      Check(session->browsers > 0 || session->operations > 0 ||
                ledger.Claims(parent) > 0,
            "every surviving private session still has a window, an operation "
            "or a creation");
    }
  }

  void CheckPromptTeardown() {
    for (const auto& [parent, session] : slots) {
      if (session->dying || session->browsers || session->operations ||
          ledger.Claims(parent)) {
        continue;
      }
      Check(false, "an unused private session is torn down without delay");
    }
  }

  Host host;
  Ledger ledger{host};
  std::map<int, SessionPtr> slots;
  std::map<int, bool> disabled;
  std::map<int, int> leases;
  std::deque<std::function<void()>> tasks;
  std::function<void(const SessionPtr&)> on_teardown;
  bool retry_posted = false;
  int next_id = 1;
  int created = 0;
  int teardowns = 0;
};

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

void ClaimsAreMoveOnlyAndReleaseOnce() {
  World world;
  {
    Claim empty;
    Check(!empty, "a default claim holds nothing");
    empty.Reset();
    Claim first = world.ledger.Acquire(1);
    Check(world.ledger.Claims(1) == 1, "acquiring counts one claim");
    Claim second = std::move(first);
    Check(!first && second, "moving a claim transfers it");
    Check(world.ledger.Claims(1) == 1, "moving a claim does not add a count");
    Claim& alias = second;
    second = std::move(alias);
    Check(second && world.ledger.Claims(1) == 1,
          "self-assignment keeps exactly one claim");
    Claim third = world.ledger.Acquire(1);
    Check(world.ledger.Claims(1) == 2, "claims are counted");
    third = std::move(second);
    Check(world.ledger.Claims(1) == 1,
          "assigning over a claim releases the overwritten one");
    third.Reset();
    third.Reset();
    Check(world.ledger.Claims(1) == 0, "reset releases once and only once");
  }
  Check(world.ledger.Idle(), "every claim is gone after its scope");
}

void OverlappingCreationsShareOneSession() {
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

void CreationClaimsBeforeLastWindowCloses() {
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

void LastWindowClosesBeforeCreation() {
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

void ChromiumOpensDuringTeardown() {
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

void ChromiumOpensWithAndWithoutPrivateWindows() {
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

void ChromiumErrorsBeforeAskingForAWindow() {
  World world;
  Check(!world.Routed(1, Failure::kBeforeSession), "the extension request fails early");
  Check(world.Current(1) != nullptr, "Chromium left a session behind");
  world.RunAll();
  Check(world.teardowns == 1, "the orphaned session is torn down");
  world.Quiesce();
  world.CheckSettled();
  Check(world.slots.empty(), "no orphan survives");
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

void ReentrantCreationNeitherDoubleClaimsNorReleasesEarly() {
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

void ReentrantWaitersAndTeardownObservers() {
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

void QuitDuringCreation() {
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

void CancelledQuitKeepsTheRequest() {
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

void QuitCancelledTooLateReportsNotReady() {
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

void WaitingOnAnAbandonedSessionThatIsClosing() {
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

void QuitWhileSettlingReportsNotSettled() {
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

void DestroyedCreatorsReleaseTheirClaims() {
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

void ParentDisabledOrRemovedWhileWaiting() {
  World world;
  Check(world.Begin(1), "first window opens");
  world.RunAll();
  world.CloseWindow(1);
  int outcomes = 0;
  world.PrivateWindow(1, Failure::kNone, &outcomes);
  Check(!world.CanRemoveParent(1), "removal waits for the request");
  world.disabled[1] = true;
  world.Quiesce();
  Check(outcomes == 1, "the request completes once");
  Check(world.slots.empty(), "a disabled profile opens nothing");
  Check(world.CanRemoveParent(1), "removal can proceed afterwards");
  world.CheckSettled();
}

void OperationsKeepTheSessionUntilTheyEnd() {
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

void ClaimDuringRetryKeepsTheSession() {
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

void ClaimTakenByATeardownObserverDuringRetry() {
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

void AwaitWhileQuittingFailsAtOnce() {
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

void SessionClosedOutsideParcWhileWaiting() {
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

void SpuriousEndKeepsWaiting() {
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

void Randomized() {
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

}

@interface PrivateSessionLedgerTests : ParcNativeTestCase
@end

@implementation PrivateSessionLedgerTests

- (void)testClaimsAreMoveOnlyAndReleaseOnce {
  ClaimsAreMoveOnlyAndReleaseOnce();
}

- (void)testOverlappingCreationsShareOneSession {
  OverlappingCreationsShareOneSession();
}

- (void)testCreationClaimsBeforeLastWindowCloses {
  CreationClaimsBeforeLastWindowCloses();
}

- (void)testFailingAfterSessionAfterLastWindowCloseReleasesTheSession {
  FailedCreationAfterLastWindowClosed(Failure::kAfterSession);
}

- (void)testFailingAdmissionAfterLastWindowCloseReleasesTheSession {
  FailedCreationAfterLastWindowClosed(Failure::kAdmission);
}

- (void)testLastWindowClosesBeforeCreation {
  LastWindowClosesBeforeCreation();
}

- (void)testChromiumOpensDuringTeardown {
  ChromiumOpensDuringTeardown();
}

- (void)testChromiumOpensWithAndWithoutPrivateWindows {
  ChromiumOpensWithAndWithoutPrivateWindows();
}

- (void)testChromiumErrorsBeforeAskingForAWindow {
  ChromiumErrorsBeforeAskingForAWindow();
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

- (void)testReentrantCreationNeitherDoubleClaimsNorReleasesEarly {
  ReentrantCreationNeitherDoubleClaimsNorReleasesEarly();
}

- (void)testReentrantWaitersAndTeardownObservers {
  ReentrantWaitersAndTeardownObservers();
}

- (void)testQuitDuringCreation {
  QuitDuringCreation();
}

- (void)testCancelledQuitKeepsTheRequest {
  CancelledQuitKeepsTheRequest();
}

- (void)testQuitCancelledTooLateReportsNotReady {
  QuitCancelledTooLateReportsNotReady();
}

- (void)testWaitingOnAnAbandonedSessionThatIsClosing {
  WaitingOnAnAbandonedSessionThatIsClosing();
}

- (void)testQuitWhileSettlingReportsNotSettled {
  QuitWhileSettlingReportsNotSettled();
}

- (void)testDestroyedCreatorsReleaseTheirClaims {
  DestroyedCreatorsReleaseTheirClaims();
}

- (void)testParentDisabledOrRemovedWhileWaiting {
  ParentDisabledOrRemovedWhileWaiting();
}

- (void)testOperationsKeepTheSessionUntilTheyEnd {
  OperationsKeepTheSessionUntilTheyEnd();
}

- (void)testClaimDuringRetryKeepsTheSession {
  ClaimDuringRetryKeepsTheSession();
}

- (void)testClaimTakenByATeardownObserverDuringRetry {
  ClaimTakenByATeardownObserverDuringRetry();
}

- (void)testSpuriousEndKeepsWaiting {
  SpuriousEndKeepsWaiting();
}

- (void)testAwaitWhileQuittingFailsAtOnce {
  AwaitWhileQuittingFailsAtOnce();
}

- (void)testSessionClosedOutsideParcWhileWaiting {
  SessionClosedOutsideParcWhileWaiting();
}

- (void)testRandomized {
  Randomized();
}

@end
