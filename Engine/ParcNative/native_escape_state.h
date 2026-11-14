// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_ESCAPE_STATE_H_
#define PARC_NATIVE_ESCAPE_STATE_H_

#include <algorithm>
#include <cstdint>
#include <optional>
#include <vector>

namespace parc {
class NativeEscapeState {
 public:
  enum class Status { kUnconsumed, kPossiblyConsumed, kConsuming };
  struct Snapshot {
    Status status;
    bool editable;
    bool repeated;
    bool prefers_confirmation() const {
      return status == Status::kConsuming || editable;
    }
  };

  void ConsumedRawKeyDown() { status_ = Status::kConsuming; }
  Snapshot Complete(bool editable, double now, double repeat_delay) {
    Snapshot result{status_, editable, false};
    switch (status_) {
      case Status::kConsuming:
        Reset();
        break;
      case Status::kUnconsumed:
        status_ = Status::kPossiblyConsumed;
        possible_at_ = now;
        break;
      case Status::kPossiblyConsumed:
        if (now - possible_at_ <= repeat_delay) {
          Reset();
          result.status = Status::kUnconsumed;
          result.repeated = true;
        } else {
          possible_at_ = now;
        }
        break;
    }
    return result;
  }
  void Reset() {
    status_ = Status::kUnconsumed;
    possible_at_ = 0;
  }

 private:
  Status status_ = Status::kUnconsumed;
  double possible_at_ = 0;
};
// Native transport bookkeeping. Only the caller can admit an original owner
// and certify a renderer ACK; invalidation never creates a replacement target.
class NativeEscapeEvents {
 public:
  struct Key {
    int64_t timestamp;
    int native_key;
    double appkit_timestamp;
    uint64_t modifiers;
  };
  // Cocoa can send PROCESSKEY and then the real raw key for the same native
  // event when an IME commits/cancels composition. That second phase must not
  // become a new Peek dismissal after marked text has disappeared.
  void IgnoreNative(double timestamp, int key, uint64_t modifiers) {
    ignored_ = Key{0, key, timestamp, modifiers};
  }
  bool IsIgnored(double timestamp, int key, uint64_t modifiers) const {
    return ignored_ && ignored_->appkit_timestamp == timestamp &&
           ignored_->native_key == key && ignored_->modifiers == modifiers;
  }
  bool Begin(Key key) {
    // NSEvent timestamps are monotonic since system startup. Keep this physical
    // event high-water mark across owner invalidation, so a duplicate preflight
    // or late callback can never re-admit input against a replacement owner.
    if (latest_native_timestamp_ &&
        key.appkit_timestamp <= *latest_native_timestamp_)
      return false;
    latest_native_timestamp_ = key.appkit_timestamp;
    pending_.push_back({++sequence_, key, std::nullopt});
    return true;
  }
  bool HasAckKey(int64_t timestamp, int key) const {
    return std::ranges::any_of(pending_, [&](const Pending& request) {
      return request.key.timestamp == timestamp &&
             request.key.native_key == key;
    });
  }
  std::optional<uint64_t> Acknowledge(int64_t timestamp,
                                      int key,
                                      bool consumed,
                                      bool editable,
                                      double now,
                                      double repeat_delay) {
    auto it = std::ranges::find_if(pending_, [&](const Pending& request) {
      return request.key.timestamp == timestamp &&
             request.key.native_key == key;
    });
    if (it == pending_.end() || it->snapshot)
      return std::nullopt;
    if (consumed)
      state_.ConsumedRawKeyDown();
    it->snapshot = state_.Complete(editable, now, repeat_delay);
    return it->sequence;
  }
  bool OwnsUnhandled(double timestamp, int key, uint64_t modifiers) const {
    return std::ranges::any_of(pending_, [&](const Pending& request) {
      return request.snapshot && request.key.appkit_timestamp == timestamp &&
             request.key.native_key == key &&
             request.key.modifiers == modifiers;
    });
  }
  std::optional<NativeEscapeState::Snapshot> Take(uint64_t sequence) {
    auto it = std::ranges::find(pending_, sequence, &Pending::sequence);
    if (it == pending_.end() || !it->snapshot)
      return std::nullopt;
    auto result = it->snapshot;
    pending_.erase(it);
    return result;
  }
  void Invalidate() {
    pending_.clear();
    state_.Reset();
  }

 private:
  struct Pending {
    uint64_t sequence;
    Key key;
    std::optional<NativeEscapeState::Snapshot> snapshot;
  };
  std::optional<Key> ignored_;
  std::optional<double> latest_native_timestamp_;
  uint64_t sequence_ = 0;
  std::vector<Pending> pending_;
  NativeEscapeState state_;
};
}  // namespace parc
#endif  // PARC_NATIVE_ESCAPE_STATE_H_
