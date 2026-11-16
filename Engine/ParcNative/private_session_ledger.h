// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_PRIVATE_SESSION_LEDGER_H_
#define PARC_NATIVE_PRIVATE_SESSION_LEDGER_H_

#include <cstddef>
#include <map>
#include <optional>
#include <utility>
#include <vector>

namespace parc {

enum class PrivateSessionUse { kGone, kDying, kOpen, kIdle };

template <typename Host>
class PrivateSessionLedger {
 public:
  using Key = typename Host::Key;
  using Session = typename Host::Session;
  using Waiter = typename Host::Waiter;

  class Claim {
   public:
    Claim() = default;
    Claim(Claim&& other) noexcept
        : ledger_(std::exchange(other.ledger_, nullptr)), key_(other.key_) {}
    Claim& operator=(Claim&& other) noexcept {
      if (this != &other) {
        Reset();
        ledger_ = std::exchange(other.ledger_, nullptr);
        key_ = other.key_;
      }
      return *this;
    }
    Claim(const Claim&) = delete;
    Claim& operator=(const Claim&) = delete;
    ~Claim() { Reset(); }

    explicit operator bool() const { return ledger_ != nullptr; }
    Key key() const { return key_; }
    void Reset() {
      if (PrivateSessionLedger* ledger = std::exchange(ledger_, nullptr)) {
        ledger->Release(key_);
      }
    }

   private:
    friend class PrivateSessionLedger;
    Claim(PrivateSessionLedger& ledger, Key key) : ledger_(&ledger), key_(key) {}

    PrivateSessionLedger* ledger_ = nullptr;
    Key key_{};
  };

  explicit PrivateSessionLedger(Host& host) : host_(host) {}
  ~PrivateSessionLedger() { Require(Idle()); }
  PrivateSessionLedger(const PrivateSessionLedger&) = delete;
  PrivateSessionLedger& operator=(const PrivateSessionLedger&) = delete;

  Claim Acquire(Key key) {
    ++entries_[key].claims;
    return Claim(*this, key);
  }

  size_t Claims(Key key) const {
    const auto found = entries_.find(key);
    return found == entries_.end() ? 0 : found->second.claims;
  }

  bool Idle() const {
    for (const auto& [key, entry] : entries_) {
      if (entry.claims || !entry.waiters.empty()) {
        return false;
      }
    }
    return true;
  }

  bool Pending(Key key) const {
    const auto found = entries_.find(key);
    return found != entries_.end() && found->second.candidate.has_value();
  }

  bool Closing() const { return closing_; }

  bool Defer(Key key, const Session& session) {
    if (!Claims(key) && !host_.HasOperations(session)) {
      return false;
    }
    entries_[key].candidate = session;
    return true;
  }

  void Nominate(Key key, const Session& session) {
    entries_[key].candidate = session;
    host_.ScheduleRetry();
  }

  void Retry() {
    std::vector<std::pair<Key, Session>> due;
    for (auto& [key, entry] : entries_) {
      if (!entry.claims && entry.candidate) {
        due.emplace_back(key, std::move(*entry.candidate));
        entry.candidate.reset();
      }
    }
    Prune();
    for (auto& [key, session] : due) {
      if (Claims(key)) {
        Keep(key, session);
        continue;
      }
      switch (host_.Use(session)) {
        case PrivateSessionUse::kGone:
        case PrivateSessionUse::kDying:
        case PrivateSessionUse::kOpen:
          break;
        case PrivateSessionUse::kIdle:
          if (host_.HasOperations(session)) {
            Keep(key, session);
          } else {
            host_.Destroy(session);
          }
          break;
      }
    }
  }

  void Await(Claim claim, Waiter waiter) {
    Require(claim.ledger_ == this);
    const Key key = claim.key();
    if (!closing_ && host_.Dying(key)) {
      entries_[key].waiters.push_back({std::move(claim), std::move(waiter)});
      host_.WatchEnd(key);
      return;
    }
    host_.Finish(std::move(waiter), !closing_);
  }

  void Ended(Key key) {
    const auto found = entries_.find(key);
    if (found == entries_.end() || found->second.waiters.empty()) {
      return;
    }
    if (host_.Dying(key)) {
      host_.WatchEnd(key);
      return;
    }
    std::vector<Parked> ready = std::exchange(found->second.waiters, {});
    Settle(ready, true);
  }

  void SetClosing(bool closing) { closing_ = closing; }

 private:
  struct Parked {
    Claim claim;
    Waiter waiter;
  };
  struct Entry {
    size_t claims = 0;
    std::optional<Session> candidate;
    std::vector<Parked> waiters;
  };

  static void Require(bool condition) {
    if (!condition) {
      __builtin_trap();
    }
  }

  void Release(Key key) {
    const auto found = entries_.find(key);
    Require(found != entries_.end() && found->second.claims);
    if (--found->second.claims) {
      return;
    }
    Require(found->second.waiters.empty());
    if (found->second.candidate) {
      host_.ScheduleRetry();
    } else {
      entries_.erase(found);
    }
  }

  void Keep(Key key, const Session& session) {
    Entry& entry = entries_[key];
    if (!entry.candidate) {
      entry.candidate = session;
    }
  }

  void Prune() {
    for (auto it = entries_.begin(); it != entries_.end();) {
      if (!it->second.claims && !it->second.candidate &&
          it->second.waiters.empty()) {
        it = entries_.erase(it);
      } else {
        ++it;
      }
    }
  }

  void Settle(std::vector<Parked>& ready, bool settled) {
    for (Parked& parked : ready) {
      host_.Finish(std::move(parked.waiter), settled && !closing_);
      parked.claim.Reset();
    }
  }

  Host& host_;
  std::map<Key, Entry> entries_;
  bool closing_ = false;
};

}

#endif
