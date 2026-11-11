// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/parc_media_task_runners.h.
// The main-thread task runners Parc gives WebMediaPlayerImpl and
// WebMediaPlayerMS on Safari-identity pages and while casting.
#ifndef THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_MEDIA_TASK_RUNNERS_H_
#define THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_MEDIA_TASK_RUNNERS_H_

#include <stdint.h>

#include <utility>

#include "base/containers/circular_deque.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/location.h"
#include "base/memory/scoped_refptr.h"
#include "base/synchronization/lock.h"
#include "base/task/single_thread_task_runner.h"
#include "base/thread_annotations.h"
#include "base/time/time.h"

namespace blink {

// Parc: the main-thread task runner of a player made for a Safari-identity
// page. Its tasks go to the frame task runner of the frame the player belongs
// to, which ParcWebMediaPlayerExtension::ParcMoveToFrame() replaces: a frame's
// queues stop running once the frame goes, and the player can outlive the
// frame that made it.
class ParcFrameTaskRunner final : public base::SingleThreadTaskRunner {
 public:
  explicit ParcFrameTaskRunner(
      scoped_refptr<base::SingleThreadTaskRunner> target)
      : target_(std::move(target)) {}

  void SetTarget(scoped_refptr<base::SingleThreadTaskRunner> target) {
    base::AutoLock auto_lock(lock_);
    target_ = std::move(target);
  }

  // base::SingleThreadTaskRunner implementation.
  bool PostDelayedTask(const base::Location& from_here,
                       base::OnceClosure task,
                       base::TimeDelta delay) override {
    return Target()->PostDelayedTask(from_here, std::move(task), delay);
  }
  bool PostNonNestableDelayedTask(const base::Location& from_here,
                                  base::OnceClosure task,
                                  base::TimeDelta delay) override {
    return Target()->PostNonNestableDelayedTask(from_here, std::move(task),
                                                delay);
  }
  bool RunsTasksInCurrentSequence() const override {
    return Target()->RunsTasksInCurrentSequence();
  }

 private:
  ~ParcFrameTaskRunner() override = default;

  scoped_refptr<base::SingleThreadTaskRunner> Target() const {
    base::AutoLock auto_lock(lock_);
    return target_;
  }

  mutable base::Lock lock_;
  scoped_refptr<base::SingleThreadTaskRunner> target_ GUARDED_BY(lock_);
};

// Parc: runs the pipeline's and its data source's main-thread tasks in order
// on the frame's media task runner, as Chromium does, except that while the
// player casts they run
// on `casting_task_runner_`, which a frozen frame (the back/forward cache)
// doesn't stop, taking those already waiting with them. A cast started just
// before the page was left then reaches the receiver, as WebKit's AVPlayer
// moves to its AirPlay target without the page
// (MediaPlayerPrivateAVFoundationObjC::setShouldPlayToPlaybackTarget).
class ParcCastingTaskRunner final : public base::SingleThreadTaskRunner {
 public:
  ParcCastingTaskRunner(
      scoped_refptr<base::SingleThreadTaskRunner> frame_task_runner,
      scoped_refptr<base::SingleThreadTaskRunner> casting_task_runner)
      : frame_task_runner_(std::move(frame_task_runner)),
        casting_task_runner_(std::move(casting_task_runner)) {}

  void SetCasting(bool casting) {
    base::AutoLock lock(lock_);
    casting_ = casting;
    if (casting && !tasks_.empty()) {
      casting_task_runner_->PostTask(
          FROM_HERE,
          base::BindOnce(&ParcCastingTaskRunner::RunThrough,
                         base::WrapRefCounted(this), tasks_.back().first));
    }
  }

  bool PostDelayedTask(const base::Location& from_here,
                       base::OnceClosure task,
                       base::TimeDelta delay) override {
    // Order holds only among immediate tasks. A delayed one posted while
    // casting (the data source's MultiBufferDataSource::SeekTask) joins them
    // when due, running where they run then.
    base::AutoLock lock(lock_);
    if (!delay.is_zero()) {
      if (!casting_) {
        return frame_task_runner_->PostDelayedTask(from_here, std::move(task),
                                                   delay);
      }
      return casting_task_runner_->PostDelayedTask(
          from_here,
          base::BindOnce(&ParcCastingTaskRunner::PostWhenDue,
                         base::WrapRefCounted(this), from_here,
                         std::move(task)),
          delay);
    }
    const uint64_t id = next_id_++;
    tasks_.emplace_back(id, std::move(task));
    return (casting_ ? casting_task_runner_ : frame_task_runner_)
        ->PostTask(from_here,
                   base::BindOnce(&ParcCastingTaskRunner::RunThrough,
                                  base::WrapRefCounted(this), id));
  }

  bool PostNonNestableDelayedTask(const base::Location& from_here,
                                  base::OnceClosure task,
                                  base::TimeDelta delay) override {
    return frame_task_runner_->PostNonNestableDelayedTask(
        from_here, std::move(task), delay);
  }

  bool RunsTasksInCurrentSequence() const override {
    return frame_task_runner_->RunsTasksInCurrentSequence();
  }

 private:
  ~ParcCastingTaskRunner() override = default;

  void PostWhenDue(const base::Location& from_here, base::OnceClosure task) {
    PostTask(from_here, std::move(task));
  }

  // Runs the tasks up to `id` not yet run; a task posted to the other task
  // runner may already have.
  void RunThrough(uint64_t id) {
    while (true) {
      base::OnceClosure task;
      {
        base::AutoLock lock(lock_);
        if (tasks_.empty() || tasks_.front().first > id) {
          return;
        }
        task = std::move(tasks_.front().second);
        tasks_.pop_front();
      }
      std::move(task).Run();
    }
  }

  const scoped_refptr<base::SingleThreadTaskRunner> frame_task_runner_;
  const scoped_refptr<base::SingleThreadTaskRunner> casting_task_runner_;
  base::Lock lock_;
  base::circular_deque<std::pair<uint64_t, base::OnceClosure>> tasks_
      GUARDED_BY(lock_);
  uint64_t next_id_ GUARDED_BY(lock_) = 0;
  bool casting_ GUARDED_BY(lock_) = false;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_MEDIA_TASK_RUNNERS_H_
