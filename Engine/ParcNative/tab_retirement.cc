// Copyright 2026 Parc contributors.
#include "tab_retirement.h"

#include <algorithm>
#include <map>
#include <memory>
#include <set>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"

namespace parc {
namespace {
class TabRetirement;
std::shared_ptr<TabRetirement>& ActiveTabRetirement() {
  static base::NoDestructor<std::shared_ptr<TabRetirement>> value;
  return *value;
}
class TabRetirement final : public std::enable_shared_from_this<TabRetirement> {
 public:
  TabRetirement(std::vector<content::WebContents*> pages,
                base::RepeatingCallback<bool()> context_is_valid,
                base::OnceCallback<bool()> should_commit,
                base::OnceCallback<void(bool)> completion)
      : pages_(std::move(pages)),
        context_is_valid_(std::move(context_is_valid)),
        should_commit_(std::move(should_commit)),
        completion_(std::move(completion)) {}
  bool Contains(content::WebContents* page) const {
    return std::ranges::contains(pages_, page);
  }
  void Start() {
    auto keep_alive = shared_from_this();
    if (pages_.empty()) {
      const bool allow =
          context_is_valid_.Run() && std::move(should_commit_).Run();
      Finish(allow);
      return;
    }
    std::set<content::WebContents*> unique;
    for (auto* contents : pages_) {
      if (!contents || !unique.insert(contents).second) {
        Finish(false);
        return;
      }
      auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
      auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
      if (!browser) {
        Finish(false);
        return;
      }
      auto [it, inserted] = groups_.try_emplace(browser);
      if (inserted) {
        it->second.browser = browser->GetWeakPtr();
      }
      it->second.pages.push_back(contents->GetWeakPtr());
      remaining_.insert(contents);
      observers_.push_back(
          std::make_unique<PageObserver>(contents, weak_factory_.GetWeakPtr()));
    }
    WarnNext();
  }

 private:
  class PageObserver final : public content::WebContentsObserver {
   public:
    PageObserver(content::WebContents* contents,
                 base::WeakPtr<TabRetirement> owner)
        : content::WebContentsObserver(contents), owner_(owner) {}

   private:
    void WebContentsDestroyed() override {
      auto* identity = web_contents();
      Observe(nullptr);
      if (owner_) {
        owner_->Destroyed(identity);
      }
    }
    base::WeakPtr<TabRetirement> owner_;
  };
  struct Group {
    base::WeakPtr<BrowserWindowInterface> browser;
    std::vector<base::WeakPtr<content::WebContents>> pages;
    std::optional<UnloadController::TabCloseToken> token;
    bool warned = false;
    bool started = false;
    bool ready = false;
  };
  bool Validate() const {
    for (const auto& [identity, group] : groups_) {
      if (!group.browser) {
        return false;
      }
      for (auto contents : group.pages) {
        if (!contents || contents->IsBeingDestroyed()) {
          return false;
        }
        auto* tab = tabs::TabInterface::MaybeGetFromContents(contents.get());
        if (!tab || tab->GetBrowserWindowInterface() != identity) {
          return false;
        }
      }
    }
    return context_is_valid_.Run();
  }
  void WarnNext() {
    auto keep_alive = shared_from_this();
    if (done_ || !Validate()) {
      Finish(false);
      return;
    }
    for (auto& [identity, group] : groups_) {
      if (group.warned) {
        continue;
      }
      auto* controller = UnloadController::From(identity);
      if (controller->is_attempting_to_close_browser() ||
          controller->HasTabClosePreflight() ||
          controller->GetBrowserClosingStatus() ==
              BrowserWindowInterface::ClosingStatus::kDeniedByPolicy) {
        Finish(false);
        return;
      }
      group.warned = true;
      // Closing the last requested tab can close the Browser. Resolve its real
      // download/window policy warning before any page confirmation or unload.
      if (group.pages.size() ==
          static_cast<size_t>(identity->GetTabStripModel()->count())) {
        auto result = controller->MaybeWarnBeforeClosing(base::BindOnce(
            [](base::WeakPtr<TabRetirement> self,
               UnloadController::WarnBeforeClosingResult result) {
              base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
                  FROM_HERE,
                  base::BindOnce(&TabRetirement::WarningResult, self, result));
            },
            weak_factory_.GetWeakPtr()));
        if (done_) {
          return;
        }
        if (!Validate()) {
          Finish(false);
          return;
        }
        if (result == UnloadController::WarnBeforeClosingResult::kDoNotClose) {
          return;
        }
      }
    }
    Prepare();
  }
  void WarningResult(UnloadController::WarnBeforeClosingResult result) {
    if (done_) {
      return;
    }
    if (result != UnloadController::WarnBeforeClosingResult::kOkToClose) {
      Finish(false);
      return;
    }
    WarnNext();
  }
  void Prepare() {
    if (!Validate()) {
      Finish(false);
      return;
    }
    for (auto& [identity, group] : groups_) {
      std::vector<content::WebContents*> targets;
      for (auto contents : group.pages) {
        targets.push_back(contents.get());
      }
      group.token = UnloadController::From(identity)->ReserveTabClosePreflight(
          targets, base::BindRepeating(&TabRetirement::Prepared,
                                       weak_factory_.GetWeakPtr(), identity));
      if (!group.token) {
        Finish(false);
        return;
      }
    }
    RunNextGroup();
  }
  void RunNextGroup() {
    for (auto& [identity, group] : groups_) {
      if (group.ready) {
        continue;
      }
      if (!group.started) {
        group.started = true;
        if (!group.browser ||
            !UnloadController::From(identity)->RunTabClosePreflight(
                *group.token)) {
          Finish(false);
        }
      }
      return;
    }
  }
  void Prepared(BrowserWindowInterface* identity, bool allow) {
    auto keep_alive = shared_from_this();
    if (done_) {
      return;
    }
    if (committed_) {
      if (!allow) {
        Finish(false);
      }
      return;
    }
    if (!allow || !Validate()) {
      Finish(false);
      return;
    }
    groups_.at(identity).ready = true;
    for (const auto& [browser, group] : groups_) {
      if (!group.ready) {
        RunNextGroup();
        return;
      }
      if (!UnloadController::From(browser)->IsTabClosePreflightReady(
              *group.token)) {
        Finish(false);
        return;
      }
    }
    // The model's intent/age/selection check is a real user-code boundary.
    // It may navigate, close, replace or reparent pages, so every lease must be
    // validated again after it returns and before the first commit is armed.
    auto validator = std::move(should_commit_);
    if (!std::move(validator).Run() || done_ || !Validate()) {
      Finish(false);
      return;
    }
    for (const auto& [browser, group] : groups_) {
      if (!group.browser ||
          !UnloadController::From(browser)->IsTabClosePreflightReady(
              *group.token)) {
        Finish(false);
        return;
      }
    }
    // These calls are callback-free and post unload. Every real controller is
    // committed before the first renderer receives ClosePage; a later Stay
    // therefore cannot cause a destructive partial transaction.
    committed_ = true;
    for (const auto& [browser, group] : groups_) {
      CHECK(UnloadController::From(browser)->CommitTabClosePreflight(
          *group.token));
    }
  }
  void Destroyed(content::WebContents* contents) {
    auto keep_alive = shared_from_this();
    remaining_.erase(contents);
    if (!committed_) {
      Finish(false);
    } else if (remaining_.empty()) {
      Finish(true);
    }
  }
  void Finish(bool success) {
    auto keep_alive = shared_from_this();
    if (done_) {
      return;
    }
    done_ = true;
    weak_factory_.InvalidateWeakPtrs();
    for (auto& [identity, group] : groups_) {
      if (group.browser && group.token) {
        UnloadController::From(identity)->ReleaseTabClosePreflight(
            *group.token);
      }
    }
    auto callback = std::move(completion_);
    // Observers and this transaction stay alive until their callback stacks
    // unwind, even when the final page destruction occurs synchronously.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(
            [](std::shared_ptr<TabRetirement> keep_alive,
               base::OnceCallback<void(bool)> callback, bool success) {
              if (ActiveTabRetirement() == keep_alive) {
                ActiveTabRetirement().reset();
              }
              std::move(callback).Run(success);
            },
            keep_alive, std::move(callback), success));
  }
  std::vector<content::WebContents*> pages_;  // Identities only.
  base::RepeatingCallback<bool()> context_is_valid_;
  base::OnceCallback<bool()> should_commit_;
  base::OnceCallback<void(bool)> completion_;
  std::map<BrowserWindowInterface*, Group> groups_;
  std::vector<std::unique_ptr<PageObserver>> observers_;
  std::set<content::WebContents*> remaining_;
  bool committed_ = false;
  bool done_ = false;
  base::WeakPtrFactory<TabRetirement> weak_factory_{this};
};
}  // namespace
bool HasTabRetirementWork() {
  return !!ActiveTabRetirement();
}
bool IsTabRetiring(content::WebContents* page) {
  return ActiveTabRetirement() && ActiveTabRetirement()->Contains(page);
}

void RequestTabRetirement(std::vector<content::WebContents*> pages,
                          base::RepeatingCallback<bool()> context_is_valid,
                          base::OnceCallback<bool()> should_commit,
                          base::OnceCallback<void(bool)> completion) {
  CHECK(context_is_valid && should_commit && completion);
  if (HasTabRetirementWork()) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(completion), false));
    return;
  }
  auto transaction = std::make_shared<TabRetirement>(
      std::move(pages), std::move(context_is_valid), std::move(should_commit),
      std::move(completion));
  ActiveTabRetirement() = transaction;
  transaction->Start();
}
}  // namespace parc
