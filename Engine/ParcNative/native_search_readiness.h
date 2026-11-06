// Copyright 2026 Parc contributors.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_SEARCH_READINESS_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_SEARCH_READINESS_H_

#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/location.h"
#include "base/memory/weak_ptr.h"
#include "base/task/single_thread_task_runner.h"

namespace parc {

// Profile-owned search readiness. TemplateURLService observers may enqueue work
// here, but must not mutate that service during its non-reentrant notification.
// Preparation and client delivery both run outside the originating observer,
// including when another observer pumps a nested UI loop.
class NativeSearchReadiness {
 public:
  explicit NativeSearchReadiness(base::RepeatingClosure prepare)
      : prepare_(std::move(prepare)) {}
  NativeSearchReadiness(const NativeSearchReadiness&) = delete;
  NativeSearchReadiness& operator=(const NativeSearchReadiness&) = delete;
  ~NativeSearchReadiness() { Stop(); }

  void Add(base::OnceClosure callback) {
    if (stopped_) {
      Post(std::move(callback));
      return;
    }
    pending_.push_back(std::move(callback));
  }

  void Schedule() {
    // Add() during preparation joins this drain. Notifications caused by the
    // preparation itself cannot recursively prepare or enqueue a redundant
    // task.
    if (stopped_ || scheduled_ || preparing_)
      return;
    scheduled_ = true;
    Post(base::BindOnce(&NativeSearchReadiness::Run,
                        weak_factory_.GetWeakPtr()));
  }

  void Stop() {
    if (stopped_)
      return;
    stopped_ = true;
    weak_factory_.InvalidateWeakPtrs();
    prepare_.Reset();
    Release();
  }

 private:
  static void Post(base::OnceClosure callback) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, std::move(callback));
  }

  void Run() {
    scheduled_ = false;
    preparing_ = true;
    auto weak = weak_factory_.GetWeakPtr();
    // Preparation can synchronously notify other service observers. Keep the
    // closure itself alive if an observer stops/destroys this owner.
    auto prepare = prepare_;
    prepare.Run();
    if (!weak)
      return;
    preparing_ = false;
    Release();
  }

  void Release() {
    auto pending = std::move(pending_);
    pending_.clear();
    for (auto& callback : pending)
      Post(std::move(callback));
  }

  base::RepeatingClosure prepare_;
  std::vector<base::OnceClosure> pending_;
  bool scheduled_ = false;
  bool preparing_ = false;
  bool stopped_ = false;
  base::WeakPtrFactory<NativeSearchReadiness> weak_factory_{this};
};

}  // namespace parc
#endif  // CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_SEARCH_READINESS_H_
