// Bridges the FairPlay core's PostTask onto a Chromium sequence.
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_TASK_RUNNER_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_TASK_RUNNER_H_

#include <functional>
#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/scoped_refptr.h"
#include "base/task/sequenced_task_runner.h"
#include "third_party/parc_fairplay/core/fairplay_types.h"

namespace parc::fairplay {

// The core posts every client callback through this. AVFoundation calls it
// from its private queues, and base::SequencedTaskRunner::PostTask is safe
// from any thread. Tasks the runner drops at shutdown are never run.
inline PostTask PostTaskTo(
    scoped_refptr<base::SequencedTaskRunner> task_runner) {
  return [task_runner = std::move(task_runner)](std::function<void()> task) {
    task_runner->PostTask(
        FROM_HERE, base::BindOnce([](std::function<void()> run) { run(); },
                                  std::move(task)));
  };
}

}  // namespace parc::fairplay

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_TASK_RUNNER_H_
