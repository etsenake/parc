#pragma once

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

namespace PrivateSessionLedgerTestsSupport {


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

void FailedCreationAfterLastWindowClosed(Failure failure);
void FailureAtEachStep(bool window_open, Failure failure);

}
