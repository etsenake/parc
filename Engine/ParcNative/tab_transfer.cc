// Copyright 2026 Parc contributors.
#include "tab_transfer.h"

#include <memory>
#include <algorithm>
#include "base/auto_reset.h"
#include <optional>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/memory/weak_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_group_model.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "components/tabs/public/tab_group.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"

namespace parc {
namespace {
bool active_collection = false;
const std::vector<content::WebContents*>* collection_targets = nullptr;
content::WebContents* active_transfer = nullptr;  // UI-thread identity only.
class EmptySourceClose {
 public:
  explicit EmptySourceClose(base::OnceClosure* output) : output_(output) {
    CHECK(!output_ || !*output_);
  }
  ~EmptySourceClose() {
    if (output_) {
      *output_ = std::move(close);
    } else if (close) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, std::move(close));
    }
  }
  base::OnceClosure close;

 private:
  base::OnceClosure* output_;
};
class Reservation {
 public:
  Reservation(BrowserWindowInterface& browser, base::OnceClosure* close)
      : browser_(browser.GetWeakPtr()),
        token_(UnloadController::From(&browser)->ReserveTabTransfer()),
        close_(close) {}
  ~Reservation() {
    if (browser_ && token_) {
      auto close =
          UnloadController::From(browser_.get())->ReleaseTabTransfer(*token_);
      if (close_) {
        *close_ = std::move(close);
      }
      // The destination already belonged to the caller. In particular, an
      // initially empty destination remains owned after a failed attachment.
    }
  }
  explicit operator bool() const { return token_.has_value(); }

 private:
  base::WeakPtr<BrowserWindowInterface> browser_;
  std::optional<UnloadController::TabCloseToken> token_;
  base::OnceClosure* close_;
};
class ActiveTransfer {
 public:
  explicit ActiveTransfer(content::WebContents& contents) {
    CHECK(!active_transfer);
    active_transfer = &contents;
  }
  ~ActiveTransfer() { active_transfer = nullptr; }
};
bool HasTransferableTabs(BrowserWindowInterface& browser) {
  return browser.GetType() == BrowserWindowInterface::TYPE_NORMAL ||
         browser.GetType() == BrowserWindowInterface::TYPE_POPUP;
}
bool Owns(BrowserWindowInterface* browser,
          content::WebContents* contents,
          tabs::TabInterface* expected) {
  if (!browser || browser->IsDeleteScheduled() || !contents ||
      contents->IsBeingDestroyed() || !expected) {
    return false;
  }
  auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  return tab == expected && tab->GetBrowserWindowInterface() == browser &&
         browser->GetTabStripModel()->GetIndexOfTab(tab) !=
             TabStripModel::kNoTab;
}
}  // namespace
bool HasLiveTabTransfer() {
  return active_transfer != nullptr || active_collection;
}
bool IsLiveTabTransferTarget(content::WebContents* contents) {
  return contents && (contents == active_transfer ||
      (collection_targets && std::ranges::find(*collection_targets, contents) != collection_targets->end()));
}
static TabTransferResult TransferOne(
    content::WebContents& contents,
    BrowserWindowInterface& destination,
    base::RepeatingCallback<bool(BrowserWindowInterface&,
                                 content::WebContents&)> present,
    base::OnceClosure* deferred_empty_owner_close,
    bool collection_reserved = false) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(present);
  auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
  auto* source = tab ? tab->GetBrowserWindowInterface() : nullptr;
  if (active_transfer || !source || source == &destination ||
      source->GetProfile() != destination.GetProfile() ||
      !HasTransferableTabs(*source) || !HasTransferableTabs(destination) ||
      !Owns(source, &contents, tab) || destination.IsDeleteScheduled()) {
    return TabTransferResult::kRefused;
  }
  EmptySourceClose empty_source_close(deferred_empty_owner_close);
  std::unique_ptr<Reservation> source_hold;
  std::unique_ptr<Reservation> destination_hold;
  if (!collection_reserved) {
    source_hold = std::make_unique<Reservation>(*source, &empty_source_close.close);
    if (!*source_hold) return TabTransferResult::kRefused;
    destination_hold = std::make_unique<Reservation>(destination, nullptr);
    if (!*destination_hold) return TabTransferResult::kRefused;
  }
  ActiveTransfer active(contents);
  const auto source_weak = source->GetWeakPtr();
  const auto destination_weak = destination.GetWeakPtr();
  const auto contents_weak = contents.GetWeakPtr();
  const auto tab_weak = tab->GetWeakPtr();
  auto* source_model = source->GetTabStripModel();
  const int source_index = source_model->GetIndexOfTab(tab);
  const bool was_active = source_model->GetActiveWebContents() == &contents;
  std::vector<std::pair<base::WeakPtr<tabs::TabInterface>,
                        base::WeakPtr<tabs::TabInterface>>>
      source_openers;
  for (int i = 0; i < source_model->count(); ++i) {
    auto* source_tab = source_model->GetTabAtIndex(i);
    auto* opener = source_model->GetOpenerOfTabAt(i);
    source_openers.emplace_back(
        source_tab->GetWeakPtr(),
        opener ? opener->GetWeakPtr() : base::WeakPtr<tabs::TabInterface>());
  }
  const bool was_pinned = source_model->IsTabPinned(source_index);
  const auto group = source_model->GetTabGroupForTab(source_index);
  const auto group_visuals =
      group ? std::make_optional(*source_model->group_model()
                                      ->GetTabGroup(*group)
                                      ->visual_data())
            : std::nullopt;
  auto restore = [&](std::unique_ptr<tabs::TabModel> returning) {
    if (!source_weak || source_weak->IsDeleteScheduled() || !returning) {
      return false;
    }
    auto* model = source_weak->GetTabStripModel();
    const auto existing_group =
        group && model->group_model()->ContainsTabGroup(*group) ? group
                                                                : std::nullopt;
    model->InsertDetachedTabAt(
        source_index, std::move(returning),
        (was_active ? ADD_ACTIVE : ADD_NONE) | (was_pinned ? ADD_PINNED : 0),
        existing_group);
    if (!source_weak || !contents_weak || !tab_weak ||
        !Owns(source_weak.get(), contents_weak.get(), tab_weak.get())) {
      return false;
    }
    // Detaching a group's final member destroys that group. Restore the same
    // source grouping only on rollback; successful moves deliberately carry
    //
    if (group && !existing_group) {
      model->AddToGroupForRestore({model->GetIndexOfTab(tab_weak.get())},
                                  *group);
      if (!source_weak || !contents_weak || !tab_weak ||
          !Owns(source_weak.get(), contents_weak.get(), tab_weak.get())) {
        return false;
      }
      model->ChangeTabGroupVisuals(*group, *group_visuals);
    }
    if (!source_weak || !contents_weak || !tab_weak ||
        !Owns(source_weak.get(), contents_weak.get(), tab_weak.get())) {
      return false;
    }
    // Detach repairs the source tab-strip opener graph. If presentation fails,
    // restore surviving source relationships as well as actual tab ownership.
    // This never changes the renderer's independent window.opener state.
    for (const auto& [saved_tab, opener] : source_openers) {
      if (saved_tab &&
          saved_tab->GetBrowserWindowInterface() == source_weak.get() &&
          (!opener ||
           opener->GetBrowserWindowInterface() == source_weak.get())) {
        model->SetOpenerOfTabAt(model->GetIndexOfTab(saved_tab.get()),
                                opener.get());
      }
    }
    return true;
  };
  //
  // is not a destination user activation.
  if (source_model->active_index() == TabStripModel::kNoTab) {
    source_model->ActivateTabAt(source_index);
  }
  if (!source_weak || !destination_weak || !contents_weak || !tab_weak ||
      !Owns(source_weak.get(), contents_weak.get(), tab_weak.get())) {
    return TabTransferResult::kExternallyInterrupted;
  }
  auto owned = source_model->DetachTabAtForInsertion(
      source_model->GetIndexOfTab(tab_weak.get()));
  if (!owned || owned.get() != tab_weak.get() ||
      owned->GetContents() != contents_weak.get()) {
    return TabTransferResult::kExternallyInterrupted;
  }
  if (!source_weak || !destination_weak ||
      destination_weak->IsDeleteScheduled()) {
    // The supplied owner contract forbids synchronous Browser destruction.
    // If another owner nevertheless disappeared, retain the live tab in its
    // surviving source rather than dropping it to create a new URL later.
    if (source_weak && !source_weak->IsDeleteScheduled()) {
      if (!restore(std::move(owned))) {
        return TabTransferResult::kExternallyInterrupted;
      }
      const bool restored = present.Run(*source_weak, *contents_weak);
      return restored && source_weak && contents_weak && tab_weak &&
                     Owns(source_weak.get(), contents_weak.get(),
                          tab_weak.get())
                 ? TabTransferResult::kRestoredToSource
                 : TabTransferResult::kExternallyInterrupted;
    }
    return TabTransferResult::kExternallyInterrupted;
  }
  destination_weak->GetTabStripModel()->AppendTab(
      std::move(owned), destination_weak->GetTabStripModel()->empty());
  if (!destination_weak || !contents_weak || !tab_weak ||
      !Owns(destination_weak.get(), contents_weak.get(), tab_weak.get())) {
    return TabTransferResult::kExternallyInterrupted;
  }
  const bool attached = present.Run(*destination_weak, *contents_weak);
  if (attached && destination_weak && contents_weak && tab_weak &&
      Owns(destination_weak.get(), contents_weak.get(), tab_weak.get())) {
    return TabTransferResult::kTransferred;
  }
  if (!source_weak || !destination_weak || !contents_weak || !tab_weak ||
      source_weak->IsDeleteScheduled() ||
      !Owns(destination_weak.get(), contents_weak.get(), tab_weak.get())) {
    return TabTransferResult::kExternallyInterrupted;
  }
  auto* destination_model = destination_weak->GetTabStripModel();
  owned = destination_model->DetachTabAtForInsertion(
      destination_model->GetIndexOfTab(tab_weak.get()));
  if (!source_weak || source_weak->IsDeleteScheduled()) {
    return TabTransferResult::kExternallyInterrupted;
  }
  if (!restore(std::move(owned))) {
    return TabTransferResult::kExternallyInterrupted;
  }
  const bool restored = present.Run(*source_weak, *contents_weak);
  return restored && source_weak && contents_weak && tab_weak &&
                 Owns(source_weak.get(), contents_weak.get(), tab_weak.get())
             ? TabTransferResult::kRestoredToSource
             : TabTransferResult::kExternallyInterrupted;
}
TabTransferResult TransferLiveTab(
    content::WebContents& contents, BrowserWindowInterface& destination,
    base::RepeatingCallback<bool(BrowserWindowInterface&, content::WebContents&)> present,
    base::OnceClosure* deferred_empty_owner_close) {
  if (active_collection) return TabTransferResult::kRefused;
  return TransferOne(contents, destination, std::move(present), deferred_empty_owner_close);
}

TabTransferResult TransferLiveTabs(
    const std::vector<content::WebContents*>& contents,
    BrowserWindowInterface& destination,
    base::RepeatingCallback<bool(BrowserWindowInterface&, content::WebContents&)> present,
    base::OnceCallback<bool()> commit,
    std::vector<base::OnceClosure>* deferred_empty_owner_close) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(present); CHECK(commit); CHECK(deferred_empty_owner_close);
  if (active_transfer || active_collection || contents.empty()) return TabTransferResult::kRefused;
  auto* first = contents.front() ? tabs::TabInterface::MaybeGetFromContents(contents.front()) : nullptr;
  auto* source = first ? first->GetBrowserWindowInterface() : nullptr;
  if (!source || source == &destination || source->GetProfile() != destination.GetProfile())
    return TabTransferResult::kRefused;
  struct CollectionClose {
    std::vector<base::OnceClosure>* output;
    base::OnceClosure close;
    ~CollectionClose() { if (close) output->push_back(std::move(close)); }
  } collection_close{deferred_empty_owner_close, {}};
  Reservation source_hold(*source, &collection_close.close);
  if (!source_hold) return TabTransferResult::kRefused;
  Reservation destination_hold(destination, nullptr);
  if (!destination_hold) return TabTransferResult::kRefused;
  struct Original {
    base::WeakPtr<content::WebContents> page;
    base::WeakPtr<tabs::TabInterface> tab;
    int index;
    bool pinned;
  };
  std::vector<Original> originals;
  auto* model = source->GetTabStripModel();
  std::vector<std::pair<base::WeakPtr<tabs::TabInterface>, base::WeakPtr<tabs::TabInterface>>> openers;
  for (int i = 0; i < model->count(); ++i) {
    auto* opener = model->GetOpenerOfTabAt(i);
    openers.emplace_back(model->GetTabAtIndex(i)->GetWeakPtr(), opener ? opener->GetWeakPtr() : base::WeakPtr<tabs::TabInterface>());
  }
  for (auto* page : contents) {
    auto* tab = page ? tabs::TabInterface::MaybeGetFromContents(page) : nullptr;
    if (!Owns(source, page, tab) || std::ranges::count(contents, page) != 1)
      return TabTransferResult::kRefused;
    const int index = model->GetIndexOfTab(tab);
    // Native group state is not the shell's split model. Reuse the established
    // single-tab route for unrelated native groups; do not dismantle one here.
    if (model->GetTabGroupForTab(index)) return TabTransferResult::kRefused;
    originals.push_back({page->GetWeakPtr(), tab->GetWeakPtr(), index, model->IsTabPinned(index)});
  }
  auto source_weak = source->GetWeakPtr();
  auto destination_weak = destination.GetWeakPtr();
  auto active_source = model->GetActiveWebContents() ? model->GetActiveWebContents()->GetWeakPtr() : base::WeakPtr<content::WebContents>();
  auto active_destination = destination.GetTabStripModel()->GetActiveWebContents()
      ? destination.GetTabStripModel()->GetActiveWebContents()->GetWeakPtr() : base::WeakPtr<content::WebContents>();
  base::AutoReset<bool> collection(&active_collection, true);
  base::AutoReset<const std::vector<content::WebContents*>*> targets(&collection_targets, &contents);
  bool all_moved = true;
  for (const auto& original : originals) {
    if (!source_weak || !destination_weak || !Owns(source_weak.get(), original.page.get(), original.tab.get())) { all_moved = false; break; }
    base::OnceClosure close;
    auto result = TransferOne(*original.page, *destination_weak, present, &close, true);
    if (close) deferred_empty_owner_close->push_back(std::move(close));
    if (result != TabTransferResult::kTransferred) { all_moved = false; break; }
  }
  all_moved = all_moved && destination_weak && std::ranges::all_of(originals, [&](const auto& original) {
    return Owns(destination_weak.get(), original.page.get(), original.tab.get());
  });
  if (all_moved && std::move(commit).Run()) {
    // Once durable state commits, external interference is recovery work, not
    // permission to roll native pages back beneath the published destination.
    return destination_weak && std::ranges::all_of(originals, [&](const auto& original) {
      return Owns(destination_weak.get(), original.page.get(), original.tab.get());
    }) ? TabTransferResult::kTransferred : TabTransferResult::kExternallyInterrupted;
  }
  for (auto it = originals.rbegin(); it != originals.rend(); ++it) {
    if (source_weak && destination_weak && Owns(destination_weak.get(), it->page.get(), it->tab.get())) {
      base::OnceClosure discard_destination_close;
      TransferOne(*it->page, *source_weak, present, &discard_destination_close, true);
      // This destination predated rollback. Its empty lifetime is caller-owned.
    }
  }
  if (!source_weak || !std::ranges::all_of(originals, [&](const auto& original) {
        return Owns(source_weak.get(), original.page.get(), original.tab.get());
      })) return TabTransferResult::kExternallyInterrupted;
  // Restore original native order, pinned bits and opener relationships. No URL
  // or renderer is recreated; shell split geometry never entered TabStripModel.
  auto ordered = originals;
  std::ranges::sort(ordered, {}, &Original::index);
  for (const auto& original : ordered) {
    if (!source_weak || !Owns(source_weak.get(), original.page.get(), original.tab.get()))
      return TabTransferResult::kExternallyInterrupted;
    model = source_weak->GetTabStripModel();
    model->SetTabPinned(model->GetIndexOfTab(original.tab.get()), original.pinned);
    if (!source_weak || !Owns(source_weak.get(), original.page.get(), original.tab.get()))
      return TabTransferResult::kExternallyInterrupted;
    model->MoveWebContentsAt(model->GetIndexOfTab(original.tab.get()),
                            std::min(original.index, model->count() - 1), false);
  }
  if (!source_weak) return TabTransferResult::kExternallyInterrupted;
  model = source_weak->GetTabStripModel();
  for (const auto& [tab, opener] : openers) {
    if (!source_weak) return TabTransferResult::kExternallyInterrupted;
    model = source_weak->GetTabStripModel();
    if (tab && tab->GetBrowserWindowInterface() == source_weak.get() &&
        (!opener || opener->GetBrowserWindowInterface() == source_weak.get()))
      model->SetOpenerOfTabAt(model->GetIndexOfTab(tab.get()), opener.get());
  }
  if (active_source && source_weak) {
    const int index = source_weak->GetTabStripModel()->GetIndexOfWebContents(active_source.get());
    if (index != TabStripModel::kNoTab) source_weak->GetTabStripModel()->ActivateTabAt(index);
  }
  if (active_destination && destination_weak) {
    const int index = destination_weak->GetTabStripModel()->GetIndexOfWebContents(active_destination.get());
    if (index != TabStripModel::kNoTab) destination_weak->GetTabStripModel()->ActivateTabAt(index);
  }
  return source_weak && std::ranges::all_of(originals, [&](const auto& original) {
    return Owns(source_weak.get(), original.page.get(), original.tab.get());
  }) ? TabTransferResult::kRestoredToSource : TabTransferResult::kExternallyInterrupted;
}
}  // namespace parc
