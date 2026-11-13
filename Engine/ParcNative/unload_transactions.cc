// Copyright 2026 Parc contributors.
#include "unload_transactions.h"

#include <algorithm>
#include <map>
#include <memory>
#include <set>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/tab_contents/web_contents_collection.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/web_applications/web_app_tabbed_utils.h"
#include "components/performance_manager/public/execution_context_priority/execution_context_priority.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "ui/base/base_window.h"

namespace parc {
namespace {

class TabClosePendingReply final
    : public content::WebContentsUserData<TabClosePendingReply>,
      public content::WebContentsObserver {
 public:
  static bool Has(content::WebContents* contents) {
    auto* value = FromWebContents(contents);
    return value && !!value->reply_;
  }
  static void Install(content::WebContents* contents,
                      uint64_t token,
                      base::OnceCallback<void(bool)> reply) {
    CreateForWebContents(contents);
    auto* value = FromWebContents(contents);
    CHECK(!value->reply_);
    value->token_ = token;
    value->reply_ = std::move(reply);
  }
  static void Complete(base::WeakPtr<content::WebContents> contents,
                       uint64_t token,
                       bool allow) {
    if (!contents) {
      return;
    }
    auto* value = FromWebContents(contents.get());
    if (!value || !value->reply_ || (token && value->token_ != token)) {
      return;
    }
    auto reply = std::move(value->reply_);
    std::move(reply).Run(allow);
  }

 private:
  friend class content::WebContentsUserData<TabClosePendingReply>;
  explicit TabClosePendingReply(content::WebContents* contents)
      : content::WebContentsUserData<TabClosePendingReply>(*contents),
        content::WebContentsObserver(contents) {}
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (navigation->HasCommitted() && navigation->IsInPrimaryMainFrame() &&
        !navigation->IsSameDocument()) {
      Complete(web_contents()->GetWeakPtr(), token_, false);
    }
  }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    Complete(web_contents()->GetWeakPtr(), token_, false);
  }
  uint64_t token_ = 0;
  base::OnceCallback<void(bool)> reply_;
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(TabClosePendingReply);

uint64_t NextTabCloseToken() {
  static constinit uint64_t value = 0;
  CHECK_NE(++value, 0u);
  return value;
}

struct TabCloseRequest {
  struct Target {
    base::WeakPtr<content::WebContents> contents;
    base::WeakPtr<tabs::TabInterface> tab;
    content::WeakDocumentPtr document;
    bool approved = false;
  };
  TabCloseToken token;
  std::vector<Target> targets;
  base::RepeatingCallback<void(bool)> callback;
  bool started = false;
  bool ready = false;
  bool committed = false;
  bool awaiting = false;
};

class UnloadTransactions final : public WebContentsCollection::Observer,
                                 public TabStripModelObserver {
 public:
  UnloadTransactions(UnloadController& controller,
                     BrowserWindowInterface& browser,
                     base::RepeatingCallback<bool()> unclosable_app,
                     UnloadEventsRunner run_unload_events)
      : controller_(controller),
        browser_(browser),
        unclosable_app_(std::move(unclosable_app)),
        run_unload_events_(std::move(run_unload_events)) {
    browser_->GetTabStripModel()->AddObserver(this);
  }
  UnloadTransactions(const UnloadTransactions&) = delete;
  UnloadTransactions& operator=(const UnloadTransactions&) = delete;
  ~UnloadTransactions() override = default;

  std::optional<TabCloseToken> ReserveTabTransfer();
  base::OnceClosure ReleaseTabTransfer(TabCloseToken token);
  std::optional<TabCloseToken> ReserveTabClosePreflight(
      const std::vector<content::WebContents*>& contents,
      base::RepeatingCallback<void(bool)> prepared);
  bool RunTabClosePreflight(TabCloseToken token);
  bool IsTabClosePreflightReady(TabCloseToken token) const;
  bool CommitTabClosePreflight(TabCloseToken token);
  void ReleaseTabClosePreflight(TabCloseToken token);
  bool HasTabClosePreflight() const;
  void CancelTabClosePreflight();

  bool AbsorbsTabStripEmpty();
  bool BlocksWindowClose() const;
  bool HoldsClosingStatus() const;
  bool BlocksShutdownBeforeUnload() const;
  bool HoldsContents(content::WebContents* contents) const;
  std::optional<bool> UnloadEventsResult(content::WebContents* contents) const;
  bool ConsumesBeforeUnloadReply(content::WebContents* contents, bool proceed);

 private:
  void WebContentsDestroyed(content::WebContents* contents) override;
  void RenderProcessGone(content::WebContents* contents,
                         base::TerminationStatus status) override;
  void DidFinishNavigation(content::WebContents* contents,
                           content::NavigationHandle* navigation) override;
  void OnTabStripModelChanged(TabStripModel* tab_strip_model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override;

  void TabAttached(content::WebContents* contents);
  void TabDetached(content::WebContents* contents);

  bool ValidateTabCloseRequest() const;
  bool HasPendingTabCloseReply() const;
  bool IsTabCloseTarget(content::WebContents* contents) const;
  void AdvanceTabClosePreflight(TabCloseToken token);
  void CompleteTabCloseDecision(content::WebContents* contents,
                                TabCloseToken token,
                                bool allow);
  void ClosePreparedTabs(TabCloseToken token);
  bool CheckCommittedTabClose(TabCloseToken token);

  const raw_ref<UnloadController> controller_;
  const raw_ref<BrowserWindowInterface> browser_;
  const base::RepeatingCallback<bool()> unclosable_app_;
  const UnloadEventsRunner run_unload_events_;
  WebContentsCollection web_contents_collection_{this};
  std::unique_ptr<TabCloseRequest> tab_close_request_;
  std::optional<TabCloseToken> tab_transfer_token_;
  bool tab_transfer_saw_empty_ = false;
  std::map<raw_ptr<content::WebContents>, TabCloseToken> tab_close_pending_;
  base::WeakPtrFactory<UnloadTransactions> weak_factory_{this};
};

std::map<const UnloadController*, std::unique_ptr<UnloadTransactions>>&
Registry() {
  static base::NoDestructor<
      std::map<const UnloadController*, std::unique_ptr<UnloadTransactions>>>
      value;
  return *value;
}

UnloadTransactions* StateOf(const UnloadController& controller) {
  auto found = Registry().find(&controller);
  return found == Registry().end() ? nullptr : found->second.get();
}

UnloadTransactions& TransactionsOf(const UnloadController& controller) {
  auto* state = StateOf(controller);
  CHECK(state);
  return *state;
}

std::optional<TabCloseToken> UnloadTransactions::ReserveTabTransfer() {
  if (tab_transfer_token_ || HasTabClosePreflight() ||
      controller_->is_attempting_to_close_browser() ||
      controller_->is_delete_scheduled() || unclosable_app_.Run()) {
    return std::nullopt;
  }
  tab_transfer_saw_empty_ = false;
  tab_transfer_token_ = NextTabCloseToken();
  return tab_transfer_token_;
}

base::OnceClosure UnloadTransactions::ReleaseTabTransfer(TabCloseToken token) {
  if (tab_transfer_token_ != token) {
    return {};
  }
  tab_transfer_token_.reset();
  const bool became_empty = std::exchange(tab_transfer_saw_empty_, false);
  if (!became_empty || !browser_->GetTabStripModel()->empty()) {
    return {};
  }
  return base::BindOnce(
      [](base::WeakPtr<BrowserWindowInterface> browser) {
        if (browser && !browser->IsDeleteScheduled() &&
            browser->GetTabStripModel()->empty()) {
          browser->GetWindow()->Close();
        }
      },
      browser_->GetWeakPtr());
}

std::optional<TabCloseToken> UnloadTransactions::ReserveTabClosePreflight(
    const std::vector<content::WebContents*>& contents,
    base::RepeatingCallback<void(bool)> prepared) {
  if (contents.empty() || !prepared ||
      controller_->is_attempting_to_close_browser() || tab_transfer_token_ ||
      HasTabClosePreflight() || controller_->is_delete_scheduled() ||
      browser_->GetType() == BrowserWindowInterface::Type::TYPE_DEVTOOLS ||
      unclosable_app_.Run()) {
    return std::nullopt;
  }
  auto request = std::make_unique<TabCloseRequest>();
  request->token = NextTabCloseToken();
  request->callback = std::move(prepared);
  std::set<content::WebContents*> unique;
  for (auto* contents_to_close : contents) {
    auto* tab =
        contents_to_close
            ? tabs::TabInterface::MaybeGetFromContents(contents_to_close)
            : nullptr;
    if (!contents_to_close || contents_to_close->IsBeingDestroyed() || !tab ||
        tab->GetBrowserWindowInterface() != &*browser_ ||
        TabClosePendingReply::Has(contents_to_close) ||
        !unique.insert(contents_to_close).second ||
        !controller_->CanCloseContents(contents_to_close)) {
      return std::nullopt;
    }
    request->targets.push_back(
        {contents_to_close->GetWeakPtr(), tab->GetWeakPtr(),
         contents_to_close->GetPrimaryMainFrame()->GetWeakDocumentPtr()});
  }
  const auto token = request->token;
  tab_close_request_ = std::move(request);
  return token;
}

bool UnloadTransactions::RunTabClosePreflight(TabCloseToken token) {
  if (!tab_close_request_ || tab_close_request_->token != token ||
      tab_close_request_->started || !ValidateTabCloseRequest()) {
    return false;
  }
  tab_close_request_->started = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&UnloadTransactions::AdvanceTabClosePreflight,
                                weak_factory_.GetWeakPtr(), token));
  return true;
}

bool UnloadTransactions::HasPendingTabCloseReply() const {
  for (int index = 0; index < browser_->GetTabStripModel()->count(); ++index) {
    if (TabClosePendingReply::Has(
            browser_->GetTabStripModel()->GetWebContentsAt(index))) {
      return true;
    }
  }
  return false;
}

bool UnloadTransactions::HasTabClosePreflight() const {
  return tab_close_request_ || HasPendingTabCloseReply();
}

bool UnloadTransactions::IsTabCloseTarget(
    content::WebContents* contents) const {
  if (!tab_close_request_) {
    return false;
  }
  return std::ranges::any_of(tab_close_request_->targets,
                             [contents](const auto& target) {
                               return target.contents.get() == contents;
                             });
}

bool UnloadTransactions::ValidateTabCloseRequest() const {
  if (!tab_close_request_ || controller_->is_attempting_to_close_browser() ||
      controller_->is_delete_scheduled() || unclosable_app_.Run()) {
    return false;
  }
  for (const auto& target : tab_close_request_->targets) {
    auto* contents = target.contents.get();
    if (!contents || contents->IsBeingDestroyed() || !target.tab ||
        tabs::TabInterface::MaybeGetFromContents(contents) !=
            target.tab.get() ||
        target.tab->GetBrowserWindowInterface() != &*browser_ ||
        target.document.AsRenderFrameHostIfValid() !=
            contents->GetPrimaryMainFrame()) {
      return false;
    }
    const int index =
        browser_->GetTabStripModel()->GetIndexOfWebContents(contents);
    if (index == TabStripModel::kNoTab ||
        !web_app::IsTabClosable(browser_->GetTabStripModel(), index)) {
      return false;
    }
  }
  return true;
}

bool UnloadTransactions::IsTabClosePreflightReady(TabCloseToken token) const {
  return tab_close_request_ && tab_close_request_->token == token &&
         tab_close_request_->ready && !tab_close_request_->committed &&
         ValidateTabCloseRequest();
}

void UnloadTransactions::AdvanceTabClosePreflight(TabCloseToken token) {
  if (!tab_close_request_ || tab_close_request_->token != token ||
      tab_close_request_->committed || tab_close_request_->awaiting ||
      tab_close_request_->ready) {
    return;
  }
  if (!ValidateTabCloseRequest()) {
    CancelTabClosePreflight();
    return;
  }
  for (const auto& target : tab_close_request_->targets) {
    if (target.approved) {
      continue;
    }
    auto contents = target.contents;
    tab_close_request_->awaiting = true;
    tab_close_pending_[contents.get()] = token;
    TabClosePendingReply::Install(
        contents.get(), token,
        base::BindOnce(
            [](base::WeakPtr<UnloadTransactions> transactions,
               base::WeakPtr<content::WebContents> contents,
               TabCloseToken token, bool allow) {
              if (transactions && contents) {
                transactions->CompleteTabCloseDecision(contents.get(), token,
                                                       allow);
              }
            },
            weak_factory_.GetWeakPtr(), contents, token));
    const auto weak = weak_factory_.GetWeakPtr();
    const bool pending = run_unload_events_.Run(
        contents.get(),
        base::BindOnce(&TabClosePendingReply::Complete, contents, token));
    if (!weak || !tab_close_request_ || tab_close_request_->token != token) {
      return;
    }
    if (!pending && contents && tab_close_pending_.contains(contents.get())) {
      TabClosePendingReply::Complete(contents, token, true);
    }
    return;
  }
  tab_close_request_->ready = true;
  auto callback = tab_close_request_->callback;
  callback.Run(true);
}

void UnloadTransactions::CompleteTabCloseDecision(
    content::WebContents* contents,
    TabCloseToken token,
    bool allow) {
  auto pending = tab_close_pending_.find(contents);
  if (pending != tab_close_pending_.end() && pending->second == token) {
    tab_close_pending_.erase(pending);
  }
  if (!tab_close_request_ || tab_close_request_->token != token ||
      tab_close_request_->committed) {
    return;
  }
  if (!allow || !ValidateTabCloseRequest()) {
    CancelTabClosePreflight();
    return;
  }
  for (auto& target : tab_close_request_->targets) {
    if (target.contents.get() == contents) {
      target.approved = true;
      break;
    }
  }
  tab_close_request_->awaiting = false;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&UnloadTransactions::AdvanceTabClosePreflight,
                                weak_factory_.GetWeakPtr(), token));
}

bool UnloadTransactions::CommitTabClosePreflight(TabCloseToken token) {
  if (!IsTabClosePreflightReady(token)) {
    return false;
  }
  tab_close_request_->committed = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&UnloadTransactions::ClosePreparedTabs,
                                weak_factory_.GetWeakPtr(), token));
  return true;
}

bool UnloadTransactions::CheckCommittedTabClose(TabCloseToken token) {
  if (!tab_close_request_ || tab_close_request_->token != token ||
      !tab_close_request_->committed) {
    return false;
  }
  for (const auto& target : tab_close_request_->targets) {
    if (!target.contents || target.contents->IsBeingDestroyed()) {
      continue;
    }
    if (!target.tab || target.tab->GetBrowserWindowInterface() != &*browser_ ||
        tabs::TabInterface::MaybeGetFromContents(target.contents.get()) !=
            target.tab.get() ||
        target.document.AsRenderFrameHostIfValid() !=
            target.contents->GetPrimaryMainFrame()) {
      auto callback = std::move(tab_close_request_->callback);
      tab_close_request_.reset();
      if (callback) {
        callback.Run(false);
      }
      return false;
    }
  }
  return true;
}

void UnloadTransactions::ClosePreparedTabs(TabCloseToken token) {
  if (!CheckCommittedTabClose(token)) {
    return;
  }
  auto targets = tab_close_request_->targets;
  auto weak = weak_factory_.GetWeakPtr();
  for (const auto& target : targets) {
    if (!weak || !CheckCommittedTabClose(token)) {
      return;
    }
    if (!target.contents || !target.tab ||
        target.tab->GetBrowserWindowInterface() != &*browser_ ||
        tabs::TabInterface::MaybeGetFromContents(target.contents.get()) !=
            target.tab.get()) {
      continue;
    }
    target.contents->ClosePage();
  }
}

void UnloadTransactions::ReleaseTabClosePreflight(TabCloseToken token) {
  if (!tab_close_request_ || tab_close_request_->token != token) {
    return;
  }
  if (tab_close_request_->committed) {
    tab_close_request_.reset();
    return;
  }
  CancelTabClosePreflight();
}

void UnloadTransactions::CancelTabClosePreflight() {
  if (!tab_close_request_) {
    return;
  }
  auto request = std::move(tab_close_request_);
  if (request->committed) {
    return;
  }
  auto callback = std::move(request->callback);
  for (const auto& target : request->targets) {
    if (!target.contents || target.contents->IsBeingDestroyed()) {
      continue;
    }
    performance_manager::execution_context_priority::SetPageIsClosing(
        target.contents.get(), false);
    if (target.contents) {
      DevToolsWindow::OnPageCloseCanceled(target.contents.get());
    }
    if (target.contents) {
      target.contents->SetClosedByUserGesture(false);
    }
  }
  if (callback) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(callback, false));
  }
}

void UnloadTransactions::TabAttached(content::WebContents* contents) {
  web_contents_collection_.StartObserving(contents);
}

void UnloadTransactions::TabDetached(content::WebContents* contents) {
  tab_close_pending_.erase(contents);
  if (IsTabCloseTarget(contents)) {
    if (!tab_close_request_->committed) {
      CancelTabClosePreflight();
    } else {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE,
          base::BindOnce(
              [](base::WeakPtr<UnloadTransactions> self, TabCloseToken token) {
                if (self) {
                  self->CheckCommittedTabClose(token);
                }
              },
              weak_factory_.GetWeakPtr(), tab_close_request_->token));
    }
  }
  web_contents_collection_.StopObserving(contents);
}

void UnloadTransactions::OnTabStripModelChanged(
    TabStripModel* tab_strip_model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  if (change.type() == TabStripModelChange::kInserted) {
    for (const auto& contents : change.GetInsert()->contents) {
      TabAttached(contents.contents);
    }
  } else if (change.type() == TabStripModelChange::kReplaced) {
    TabDetached(change.GetReplace()->old_contents);
    TabAttached(change.GetReplace()->new_contents);
  } else if (change.type() == TabStripModelChange::kRemoved) {
    for (const auto& contents : change.GetRemove()->contents) {
      TabDetached(contents.contents);
    }
  }
}

void UnloadTransactions::RenderProcessGone(content::WebContents* contents,
                                           base::TerminationStatus status) {
  tab_close_pending_.erase(contents);
  if (IsTabCloseTarget(contents) && !tab_close_request_->committed) {
    CancelTabClosePreflight();
  }
  web_contents_collection_.StopObserving(contents);
}

bool UnloadTransactions::AbsorbsTabStripEmpty() {
  if (!tab_transfer_token_) {
    return false;
  }
  tab_transfer_saw_empty_ = true;
  return true;
}

bool UnloadTransactions::BlocksWindowClose() const {
  return tab_transfer_token_ || HasPendingTabCloseReply() ||
         (tab_close_request_ && (!tab_close_request_->committed ||
                                 !browser_->GetTabStripModel()->empty()));
}

bool UnloadTransactions::HoldsClosingStatus() const {
  return tab_close_request_ && !tab_close_request_->committed;
}

bool UnloadTransactions::BlocksShutdownBeforeUnload() const {
  return tab_transfer_token_ || HasTabClosePreflight();
}

bool UnloadTransactions::HoldsContents(content::WebContents* contents) const {
  return tab_transfer_token_ || TabClosePendingReply::Has(contents) ||
         (IsTabCloseTarget(contents) && !tab_close_request_->committed);
}

std::optional<bool> UnloadTransactions::UnloadEventsResult(
    content::WebContents* contents) const {
  if (tab_transfer_token_) {
    return true;
  }
  if (IsTabCloseTarget(contents)) {
    return !tab_close_request_->committed;
  }
  if (TabClosePendingReply::Has(contents)) {
    return true;
  }
  return std::nullopt;
}

bool UnloadTransactions::ConsumesBeforeUnloadReply(
    content::WebContents* contents,
    bool proceed) {
  if (TabClosePendingReply::Has(contents)) {
    TabClosePendingReply::Complete(contents->GetWeakPtr(), 0, proceed);
    return true;
  }
  return IsTabCloseTarget(contents) && !tab_close_request_->committed;
}

void UnloadTransactions::DidFinishNavigation(
    content::WebContents* contents,
    content::NavigationHandle* navigation) {
  if (IsTabCloseTarget(contents) && navigation->HasCommitted() &&
      navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) {
    if (tab_close_request_->committed) {
      CheckCommittedTabClose(tab_close_request_->token);
    } else {
      CancelTabClosePreflight();
    }
  }
}

void UnloadTransactions::WebContentsDestroyed(content::WebContents* contents) {
  tab_close_pending_.erase(contents);
  if (IsTabCloseTarget(contents) && !tab_close_request_->committed) {
    CancelTabClosePreflight();
  }
}
}

std::optional<TabCloseToken> ReserveTabTransfer(UnloadController& controller) {
  return TransactionsOf(controller).ReserveTabTransfer();
}

base::OnceClosure ReleaseTabTransfer(UnloadController& controller,
                                     TabCloseToken token) {
  return TransactionsOf(controller).ReleaseTabTransfer(token);
}

std::optional<TabCloseToken> ReserveTabClosePreflight(
    UnloadController& controller,
    const std::vector<content::WebContents*>& contents,
    base::RepeatingCallback<void(bool)> prepared) {
  return TransactionsOf(controller).ReserveTabClosePreflight(
      contents, std::move(prepared));
}

bool RunTabClosePreflight(UnloadController& controller, TabCloseToken token) {
  return TransactionsOf(controller).RunTabClosePreflight(token);
}

bool IsTabClosePreflightReady(const UnloadController& controller,
                              TabCloseToken token) {
  return TransactionsOf(controller).IsTabClosePreflightReady(token);
}

bool CommitTabClosePreflight(UnloadController& controller,
                             TabCloseToken token) {
  return TransactionsOf(controller).CommitTabClosePreflight(token);
}

void ReleaseTabClosePreflight(UnloadController& controller,
                              TabCloseToken token) {
  TransactionsOf(controller).ReleaseTabClosePreflight(token);
}

bool HasTabClosePreflight(const UnloadController& controller) {
  return TransactionsOf(controller).HasTabClosePreflight();
}

void OnUnloadControllerCreated(UnloadController& controller,
                               BrowserWindowInterface& browser,
                               base::RepeatingCallback<bool()> unclosable_app,
                               UnloadEventsRunner run_unload_events) {
  auto [it, inserted] = Registry().try_emplace(
      &controller, std::make_unique<UnloadTransactions>(
                       controller, browser, std::move(unclosable_app),
                       std::move(run_unload_events)));
  CHECK(inserted);
}

void OnUnloadControllerDestroyed(UnloadController& controller) {
  auto found = Registry().find(&controller);
  if (found == Registry().end()) {
    return;
  }
  found->second->CancelTabClosePreflight();
  std::unique_ptr<UnloadTransactions> state = std::move(found->second);
  Registry().erase(found);
}

bool AbsorbsTabStripEmpty(UnloadController& controller) {
  auto* state = StateOf(controller);
  return state && state->AbsorbsTabStripEmpty();
}

bool BlocksWindowClose(const UnloadController& controller) {
  auto* state = StateOf(controller);
  return state && state->BlocksWindowClose();
}

bool HoldsClosingStatus(const UnloadController& controller) {
  auto* state = StateOf(controller);
  return state && state->HoldsClosingStatus();
}

bool BlocksShutdownBeforeUnload(const UnloadController& controller) {
  auto* state = StateOf(controller);
  return state && state->BlocksShutdownBeforeUnload();
}

bool HoldsContents(const UnloadController& controller,
                   content::WebContents* contents) {
  auto* state = StateOf(controller);
  return state && state->HoldsContents(contents);
}

std::optional<bool> UnloadEventsResult(const UnloadController& controller,
                                       content::WebContents* contents) {
  auto* state = StateOf(controller);
  return state ? state->UnloadEventsResult(contents) : std::nullopt;
}

bool HasTabCloseReply(content::WebContents* contents) {
  return TabClosePendingReply::Has(contents);
}

bool ConsumesBeforeUnloadReply(UnloadController& controller,
                               content::WebContents* contents,
                               bool proceed) {
  auto* state = StateOf(controller);
  return state && state->ConsumesBeforeUnloadReply(contents, proceed);
}
}
