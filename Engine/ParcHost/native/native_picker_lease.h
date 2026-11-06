// Copyright 2026 Parc contributors.
// A delegated native picker ID is owned by the source list until its exact
// selected ID is transferred to a request. Its creation callback may arrive
// after the list's worker thread is gone.
#ifndef PARC_NATIVE_PICKER_LEASE_H_
#define PARC_NATIVE_PICKER_LEASE_H_

#include <cstdint>
#include <functional>
#include <mutex>
#include <optional>
#include <utility>

namespace parc {
class NativePickerLease {
 public:
  using Id = intptr_t;
  explicit NativePickerLease(std::function<void(Id)> close)
      : close_(std::move(close)) {}
  NativePickerLease(const NativePickerLease&) = delete;
  NativePickerLease& operator=(const NativePickerLease&) = delete;
  ~NativePickerLease() { Release(); }

  // Called on the native callback's sequence, not the possibly stopped worker.
  void Created(Id id) {
    std::optional<Id> close;
    {
      std::lock_guard lock(mutex_);
      if (created_) return;  // The creation callback is one-shot.
      created_ = id;
      if (!owner_ && transferred_ != id) close = id;
    }
    if (close) close_(*close);
  }
  // Called on the source-list worker before that worker is destroyed.
  void Transfer(Id id) {
    std::lock_guard lock(mutex_);
    if (owner_) transferred_ = id;
  }
  void Release() {
    std::optional<Id> close;
    {
      std::lock_guard lock(mutex_);
      if (!owner_) return;
      owner_ = false;
      if (created_ && created_ != transferred_) close = created_;
    }
    if (close) close_(*close);
  }
 private:
  std::mutex mutex_;
  std::function<void(Id)> close_;
  std::optional<Id> created_;
  std::optional<Id> transferred_;
  bool owner_ = true;
};
}  // namespace parc
#endif  // PARC_NATIVE_PICKER_LEASE_H_
