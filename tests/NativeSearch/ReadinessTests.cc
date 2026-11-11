#include <cstdio>
#include <memory>
#include <string_view>

#include "../../Engine/ParcNative/native_search_readiness.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/observer_list.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_executor.h"
#include "base/test/bind.h"
#include "components/search_engines/template_url_service_observer.h"

namespace {
int checks = 0;
void Expect(bool value) {
  ++checks;
  CHECK(value);
}
void Idle() {
  base::RunLoop().RunUntilIdle();
}

struct Service {
  void Notify() {
    ++depth;
    for (auto& observer : observers)
      observer.OnTemplateURLServiceChanged();
    --depth;
  }
  void Add() {
    ++additions;
    Notify();
  }
  base::ObserverList<TemplateURLServiceObserver> observers;
  int depth = 0;
  int additions = 0;
};
struct Owner final : TemplateURLServiceObserver {
  explicit Owner(Service& service, bool synchronous = false)
      : service(service),
        synchronous(synchronous),
        readiness(
            base::BindRepeating(&Owner::Prepare, base::Unretained(this))) {
    service.observers.AddObserver(this);
  }
  ~Owner() override { service.observers.RemoveObserver(this); }
  void OnTemplateURLServiceChanged() override {
    if (synchronous)
      Prepare();
    else
      readiness.Schedule();
    if (nest) {
      nest = false;
      base::RunLoop loop(base::RunLoop::Type::kNestableTasksAllowed);
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, loop.QuitClosure());
      loop.Run();
      Expect(service.additions == 0);
    }
  }
  void Prepare() {
    ++preparations;
    if (installed)
      return;
    installed = true;
    service.Add();
    if (stop_in_prepare)
      readiness.Stop();
  }
  Service& service;
  bool synchronous;
  bool nest = false;
  bool installed = false;
  bool stop_in_prepare = false;
  int preparations = 0;
  parc::NativeSearchReadiness readiness;
};
}

int main(int argc, char** argv) {
  base::SingleThreadTaskExecutor executor;
  if (argc == 2 &&
      std::string_view(argv[1]) == "--synchronous-negative-control") {
    Service service;
    Owner owner(service, true);
    service.Notify();
    return 99;
  }
  {
    Service service;
    Owner owner(service);
    int delivered = 0;
    owner.readiness.Add(base::BindLambdaForTesting([&] {
      Expect(service.depth == 0 && service.additions == 1);
      ++delivered;
    }));
    Idle();
    Expect(owner.preparations == 0 && delivered == 0);
    owner.nest = true;
    executor.task_runner()->PostTask(
        FROM_HERE, base::BindLambdaForTesting([&] {
          service.Notify();
          service.Notify();
          Expect(owner.preparations == 0 && delivered == 0);
        }));
    Idle();
    Expect(owner.preparations == 1 && delivered == 1);
    Expect(service.additions == 1);
    owner.readiness.Add(base::BindLambdaForTesting([&] { ++delivered; }));
    owner.readiness.Schedule();
    Expect(delivered == 1);
    Idle();
    Expect(owner.preparations == 2 && delivered == 2 && service.additions == 1);
    service.Notify();
    Idle();
    Expect(owner.preparations == 3 && delivered == 2 && service.additions == 1);
  }
  {
    Service service;
    Owner owner(service);
    int delivered = 0;
    owner.readiness.Add(base::BindLambdaForTesting([&] { ++delivered; }));
    service.Notify();
    owner.readiness.Stop();
    owner.readiness.Stop();
    Expect(delivered == 0);
    Idle();
    Expect(delivered == 1 && service.additions == 0 && owner.preparations == 0);
    owner.readiness.Add(base::BindLambdaForTesting([&] { ++delivered; }));
    owner.readiness.Schedule();
    Expect(delivered == 1);
    Idle();
    Expect(delivered == 2 && service.additions == 0);
  }
  {
    Service service;
    auto owner = std::make_unique<Owner>(service);
    int delivered = 0;
    owner->readiness.Add(base::BindLambdaForTesting([&] { ++delivered; }));
    service.Notify();
    owner.reset();
    Expect(delivered == 0);
    Idle();
    Expect(delivered == 1 && service.additions == 0);
  }
  {
    Service service;
    Owner owner(service);
    owner.stop_in_prepare = true;
    int delivered = 0;
    owner.readiness.Add(base::BindLambdaForTesting([&] { ++delivered; }));
    service.Notify();
    Idle();
    Expect(delivered == 1 && service.additions == 1 && owner.preparations == 1);
  }
  {
    std::unique_ptr<parc::NativeSearchReadiness> readiness;
    int delivered = 0;
    readiness = std::make_unique<parc::NativeSearchReadiness>(
        base::BindLambdaForTesting([&] { readiness.reset(); }));
    readiness->Add(base::BindLambdaForTesting([&] { ++delivered; }));
    readiness->Schedule();
    Idle();
    Expect(!readiness && delivered == 1);
  }
  {
    int prepared = 0, delivered = 0;
    parc::NativeSearchReadiness* current = nullptr;
    parc::NativeSearchReadiness readiness(base::BindLambdaForTesting([&] {
      ++prepared;
      if (prepared == 1) {
        current->Add(base::BindLambdaForTesting([&] { ++delivered; }));
        current->Schedule();
      }
    }));
    current = &readiness;
    readiness.Add(base::BindLambdaForTesting([&] {
      ++delivered;
      current->Add(base::BindLambdaForTesting([&] { ++delivered; }));
      current->Schedule();
    }));
    readiness.Schedule();
    Idle();
    Expect(prepared == 2 && delivered == 3);
  }
  std::printf("PASS: %d native search-readiness assertions\n", checks);
}
