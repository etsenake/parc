// Copyright 2026 Parc contributors.
#include "extension_action_container.h"

#include <algorithm>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_delegate.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "extension_popup.h"
#include "extension_security_context.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/command.h"
#import "window_security_reservation.h"

namespace parc {
class NativeExtensionActionContainer::ActionDelegate final
    : public ExtensionActionDelegate {
 public:
  explicit ActionDelegate(base::WeakPtr<NativeExtensionActionContainer> owner)
      : owner_(owner) {}
  void AttachToModel(ExtensionActionViewModel* model) override {
    CHECK(!model_);
    model_ = model;
  }
  void DetachFromModel() override {
    UnregisterCommand();
    model_ = nullptr;
  }
  bool IsCurrent() const {
    return owner_ && model_ && owner_->Find(model_->GetId()).get() == model_;
  }
  void RegisterCommand() override {
    if (IsCurrent()) {
      owner_->RegisterCommand(*model_);
    }
  }
  void UnregisterCommand() override {
    if (IsCurrent()) {
      owner_->UnregisterCommand(model_->GetId());
    }
  }
  bool IsShowingPopup() const override {
    return IsCurrent() && owner_->HasPopupFor(model_->GetId());
  }
  void HidePopup() override {
    if (IsCurrent()) {
      owner_->HidePopupFor(model_->GetId());
    }
  }
  gfx::NativeView GetPopupNativeViewForTesting() override {
    return IsShowingPopup() ? owner_->popup_->native_view() : gfx::NativeView();
  }
  void TriggerPopup(std::unique_ptr<extensions::ExtensionViewHost> host,
                    PopupShowAction action,
                    bool by_user,
                    ShowPopupCallback callback) override {
    if (IsCurrent()) {
      owner_->TriggerPopup(model_->GetId(), std::move(host), action, by_user,
                           std::move(callback));
    } else if (callback) {
      std::move(callback).Run(nullptr);
    }
  }
  void ShowContextMenuAsFallback() override {
    auto owner = owner_;
    if (!owner || !IsCurrent()) {
      return;
    }
    const std::string id = model_->GetId();
    auto model =
        owner->Find(id);
    if (model && !owner->shell_.ShowActionContextMenu(*model, nil) && owner) {
      owner->shell_.ExtensionCapabilityUnavailable(id, "action context menu");
    }
  }
  void CloseExtensionsMenuIfOpen() override {
    if (owner_) {
      owner_->CloseExtensionsMenuIfOpen();
    }
  }
  content::WebContents* GetActiveWebContents() const override {
    return owner_ ? owner_->GetActiveWebContents() : nullptr;
  }

 private:
  base::WeakPtr<NativeExtensionActionContainer> owner_;
  ExtensionActionViewModel* model_ = nullptr;
};

NativeExtensionActionContainer::NativeExtensionActionContainer(
    BrowserWindowInterface& browser,
    NativeExtensionActionHost& host)
    : browser_(browser),
      shell_(host),
      registration_(browser.GetUnownedUserDataHost(), *this) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  tabs_ = TabListInterface::From(&browser);
  model_ = ToolbarActionsModel::Get(browser.GetProfile());
  CHECK(tabs_ && model_);
  tabs_->AddTabListInterfaceObserver(this);
  model_->AddObserver(this);
  extensions::SecurityDialogTracker::GetInstance()->AddObserver(this);
  auto weak = weak_factory_.GetWeakPtr();
  security_observer_ = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification* notification) {
                if (weak &&
                    notification.object == weak->shell_.PopupParentWindow()) {
                  weak->HostStateChanged();
                }
              }];
  if (model_->actions_initialized()) {
    for (const auto& id : model_->action_ids()) {
      Add(id);
    }
  }
}
NativeExtensionActionContainer::~NativeExtensionActionContainer() {
  Shutdown();
}
struct NativeExtensionActionContainer::ShutdownState
    : public std::enable_shared_from_this<ShutdownState> {
  std::map<std::string, std::shared_ptr<ExtensionActionViewModel>> actions;
  std::vector<std::shared_ptr<NativeExtensionPopup>> sessions;
  std::vector<base::OnceClosure> completions;
  size_t pending = 0;
  bool complete = false;
  bool finish_posted = false;
  void AddCompletion(base::OnceClosure callback) {
    if (!callback) {
      return;
    }
    if (complete) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
          FROM_HERE, std::move(callback));
    } else {
      completions.push_back(std::move(callback));
    }
  }
  void ScheduleFinish() {
    if (finish_posted) {
      return;
    }
    finish_posted = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(&ShutdownState::Finish, shared_from_this()));
  }
  void Finish() {
    CHECK(pending == 0 && !complete);
    actions.clear();
    sessions.clear();
    complete = true;
    auto ready = std::move(completions);
    for (auto& callback : ready) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, std::move(callback));
    }
  }
  void Closed() {
    CHECK(pending);
    if (--pending == 0) {
      ScheduleFinish();
    }
  }
  void Start() {
    pending = sessions.size();
    if (!pending) {
      ScheduleFinish();
      return;
    }
    auto snapshot = sessions;
    for (auto& session : snapshot) {
      session->Close(
          base::BindOnce(&ShutdownState::Closed, shared_from_this()));
    }
  }
};
void NativeExtensionActionContainer::Shutdown() {
  Shutdown({});
}
void NativeExtensionActionContainer::Shutdown(base::OnceClosure completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (shutdown_) {
    CHECK(shutdown_state_);
    shutdown_state_->AddCompletion(std::move(completion));
    return;
  }
  shutdown_ = true;
  auto state = std::make_shared<ShutdownState>();
  shutdown_state_ = state;
  state->AddCompletion(std::move(completion));
  extensions::SecurityDialogTracker::GetInstance()->RemoveObserver(this);
  if (security_observer_) {
    [NSNotificationCenter.defaultCenter removeObserver:security_observer_];
  }
  security_observer_ = nil;
  weak_factory_.InvalidateWeakPtrs();
  if (model_) {
    model_->RemoveObserver(this);
    model_ = nullptr;
  }
  if (tabs_) {
    tabs_->RemoveTabListInterfaceObserver(this);
    tabs_ = nullptr;
  }
  ++popup_generation_;
  if (popup_) {
    state->sessions.push_back(std::exchange(popup_, nullptr));
  }
  for (auto& entry : closing_popups_) {
    state->sessions.push_back(std::move(entry.second));
  }
  closing_popups_.clear();
  state->actions = std::move(actions_);
  popup_id_.clear();
  commands_.clear();
  state->Start();
}
std::shared_ptr<ExtensionActionViewModel> NativeExtensionActionContainer::Find(
    const std::string& id) const {
  const auto it = actions_.find(id);
  return it == actions_.end() ? nullptr : it->second;
}
void NativeExtensionActionContainer::Add(const std::string& id) {
  if (shutdown_ || actions_.contains(id)) {
    return;
  }
  const auto* extension =
      extensions::ExtensionRegistry::Get(browser_.GetProfile())
          ->enabled_extensions()
          .GetByID(id);
  if (!extension ||
      !extensions::ExtensionActionManager::Get(browser_.GetProfile())
           ->GetExtensionAction(*extension)) {
    return;
  }
  auto action = ExtensionActionViewModel::Create(
      id, &browser_,
      std::make_unique<ActionDelegate>(weak_factory_.GetWeakPtr()));
  actions_.emplace(id, std::move(action));
  actions_.at(id)->RegisterCommand();
}
ToolbarActionViewModel* NativeExtensionActionContainer::GetActionForId(
    const std::string& id) {
  return Find(id).get();
}
content::WebContents* NativeExtensionActionContainer::GetActiveWebContents()
    const {
  if (shutdown_ || !tabs_) {
    return nullptr;
  }
  auto* tab = tabs_->GetActiveTab();
  return tab ? tab->GetContents() : nullptr;
}
bool NativeExtensionActionContainer::HasAnyExtensions() const {
  return !actions_.empty();
}
void NativeExtensionActionContainer::RegisterCommand(
    ExtensionActionViewModel& action) {
  commands_.erase(action.GetId());
  extensions::Command command;
  if (!shutdown_ && action.GetExtensionCommand(&command)) {
    commands_.emplace(action.GetId(), command.accelerator());
  }
}
void NativeExtensionActionContainer::UnregisterCommand(const std::string& id) {
  commands_.erase(id);
}
bool NativeExtensionActionContainer::DispatchActionAccelerator(
    const ui::Accelerator& accelerator) {
  if (shutdown_ || !shell_.IsSelectedBrowser() || !GetActiveWebContents()) {
    return false;
  }
  std::vector<std::string> ids;
  for (const auto& [id, key] : commands_) {
    if (key == accelerator) {
      ids.push_back(id);
    }
  }
  auto weak = weak_factory_.GetWeakPtr();
  for (const auto& id : ids) {
    auto model = Find(id);
    if (model && model->CanHandleAccelerators() &&
        model->TryHandleAcceleratorPress()) {
      return true;
    }
    if (!weak) {
      return false;
    }
  }
  return false;
}
bool NativeExtensionActionContainer::HasPopupFor(const std::string& id) const {
  return popup_ && !popup_->closing() && popup_id_ == id;
}
void NativeExtensionActionContainer::HideActivePopup() {
  const auto generation = popup_generation_++;
  auto old = std::exchange(popup_, nullptr);
  popup_id_.clear();
  if (old) {
    closing_popups_.emplace_back(generation, old);
    old->Close();
  }
}
void NativeExtensionActionContainer::HidePopupFor(const std::string& id) {
  if (HasPopupFor(id)) {
    HideActivePopup();
  }
}
void NativeExtensionActionContainer::TriggerPopup(
    const std::string& id_ref,
    std::unique_ptr<extensions::ExtensionViewHost> host,
    PopupShowAction action,
    bool by_user,
    ShowPopupCallback callback) {
  const std::string id = id_ref;
  auto weak = weak_factory_.GetWeakPtr();
  if (shutdown_ || !host || host->browser_context() != browser_.GetProfile() ||
      host->extension_id() != id || !Find(id) || !shell_.IsSelectedBrowser() ||
      !shell_.PopupParentWindow() || shell_.HasVisibleBrowserSecurityUI() ||
      extensions::SecurityDialogTracker::GetInstance()
          ->BrowserHasVisibleSecurityDialogs(&browser_) ||
      PCNativeWindowHasSecurityReservation(shell_.PopupParentWindow())) {
    if (callback) {
      std::move(callback).Run(nullptr);
    }
    return;
  }
  (void)by_user;
  const uint64_t expected = popup_generation_ + 1;
  HideActivePopup();
  if (!weak || shutdown_ || popup_generation_ != expected) {
    if (callback) {
      std::move(callback).Run(nullptr);
    }
    return;
  }
  const uint64_t generation = ++popup_generation_;
  shell_.CloseExtensionsMenu();
  if (!weak || shutdown_ || generation != popup_generation_ || !Find(id)) {
    if (callback) {
      std::move(callback).Run(nullptr);
    }
    return;
  }
  NativeExtensionPopup::Callbacks hooks;
  hooks.anchor = base::BindRepeating(
      [](base::WeakPtr<NativeExtensionActionContainer> self) {
        return self ? self->shell_.PopupAnchor() : nil;
      },
      weak);
  hooks.security_ui_visible = base::BindRepeating(
      [](base::WeakPtr<NativeExtensionActionContainer> self) {
        return !self || self->shell_.HasVisibleBrowserSecurityUI() ||
               extensions::SecurityDialogTracker::GetInstance()
                   ->BrowserHasVisibleSecurityDialogs(&self->browser_) ||
               PCNativeWindowHasSecurityReservation(
                   self->shell_.PopupParentWindow());
      },
      weak);
  hooks.menu_key = base::BindRepeating(
      [](base::WeakPtr<NativeExtensionActionContainer> self,
         content::WebContents* contents,
         const input::NativeWebKeyboardEvent& event) {
        return self && self->shell_.HandlePopupMenuKey(contents, event);
      },
      weak);
  hooks.inspect = base::BindRepeating(
      [](base::WeakPtr<NativeExtensionActionContainer> self,
         content::WebContents* contents) {
        if (!self) {
          return false;
        }
        const bool supported = self->shell_.InspectPopup(contents);
        if (!supported && self) {
          self->shell_.ExtensionCapabilityUnavailable(self->popup_id_,
                                                      "popup inspection");
        }
        return supported;
      },
      weak);
  hooks.request_hide = base::BindRepeating(
      [](base::WeakPtr<NativeExtensionActionContainer> self,
         uint64_t generation, const std::string& id) {
        if (self && self->popup_generation_ == generation) {
          auto action = self->Find(id);
          if (action) {
            action->HidePopup();
          } else {
            self->HideActivePopup();
          }
        }
      },
      weak, generation, id);
  hooks.closed = base::BindOnce(
      [](base::WeakPtr<NativeExtensionActionContainer> self,
         uint64_t generation) {
        if (self && self->popup_generation_ == generation) {
          self->popup_.reset();
          self->popup_id_.clear();
          ++self->popup_generation_;
        }
        if (self) {
          std::erase_if(self->closing_popups_, [generation](const auto& entry) {
            return entry.first == generation;
          });
        }
      },
      weak, generation);
  popup_id_ = id;
  auto session = std::make_shared<NativeExtensionPopup>(
      std::move(host), shell_.PopupParentWindow(), action, std::move(callback),
      std::move(hooks));
  popup_ = session;
  session->Start();
}
bool NativeExtensionActionContainer::ShowToolbarActionPopupForAPICall(
    const std::string& id,
    ShowPopupCallback callback) {
  auto action = Find(id);
  auto* contents = GetActiveWebContents();
  if (shutdown_ || !action || !contents || !shell_.IsSelectedBrowser()) {
    return false;
  }
  const auto* extension =
      extensions::ExtensionRegistry::Get(browser_.GetProfile())
          ->enabled_extensions()
          .GetByID(id);
  if (!extension) {
    return false;
  }
  auto* extension_action =
      extensions::ExtensionActionManager::Get(browser_.GetProfile())
          ->GetExtensionAction(*extension);
  const int tab_id = sessions::SessionTabHelper::IdForTab(contents).id();
  if (!extension_action || !extension_action->GetIsVisible(tab_id) ||
      !extension_action->HasPopup(tab_id)) {
    return false;
  }
  action->TriggerPopupForAPI(std::move(callback));
  return true;
}
void NativeExtensionActionContainer::CloseExtensionsMenuIfOpen() {
  if (!shutdown_) {
    shell_.CloseExtensionsMenu();
  }
}
void NativeExtensionActionContainer::ToggleExtensionsMenu() {
  if (shutdown_) {
    return;
  }
  auto weak = weak_factory_.GetWeakPtr();
  if (!shell_.ToggleExtensionsMenu() && weak) {
    shell_.ExtensionCapabilityUnavailable({}, "extensions menu");
  }
}
void NativeExtensionActionContainer::OnSecurityDialogAdded(
    views::Widget* widget) {
  if (!shutdown_ &&
      SecurityWidgetBelongsToWindow(widget, shell_.PopupParentWindow())) {
    HideActivePopup();
  }
}
void NativeExtensionActionContainer::HostStateChanged() {
  if (shutdown_) {
    return;
  }
  if (!shell_.IsSelectedBrowser()) {
    HideActivePopup();
  } else if (auto session = popup_) {
    session->SecurityUIChanged();
  }
}
const std::vector<std::string>&
NativeExtensionActionContainer::pinned_action_ids() const {
  static const std::vector<std::string> empty;
  return model_ ? model_->pinned_action_ids() : empty;
}
void NativeExtensionActionContainer::SetPinned(const std::string& id,
                                               bool pinned) {
  if (model_ && Find(id) && !browser_.GetProfile()->IsOffTheRecord() &&
      !model_->IsActionForcePinned(id) &&
      model_->IsActionPinned(id) != pinned) {
    model_->SetActionVisibility(id, pinned);
  }
}
void NativeExtensionActionContainer::OnToolbarActionAdded(
    const std::string& id) {
  Add(id);
  if (!shutdown_) {
    shell_.ExtensionActionsChanged();
  }
}
void NativeExtensionActionContainer::OnToolbarActionRemoved(
    const std::string& id) {
  auto weak = weak_factory_.GetWeakPtr();
  auto node = actions_.extract(id);
  commands_.erase(id);
  HidePopupFor(id);
  if (weak && !shutdown_) {
    shell_.ExtensionActionsChanged();
  }
}
void NativeExtensionActionContainer::OnToolbarActionUpdated(
    const std::string& id) {
  if (!shutdown_) {
    shell_.ExtensionActionsChanged();
  }
}
void NativeExtensionActionContainer::OnToolbarModelInitialized() {
  if (!model_ || shutdown_) {
    return;
  }
  for (const auto& id : model_->action_ids()) {
    Add(id);
  }
  shell_.ExtensionActionsChanged();
}
void NativeExtensionActionContainer::OnToolbarPinnedActionsChanged() {
  if (!shutdown_) {
    shell_.ExtensionActionsChanged();
  }
}
void NativeExtensionActionContainer::OnToolbarActionsModelShutdown() {
  Shutdown();
}
void NativeExtensionActionContainer::OnActiveTabChanged(TabListInterface&,
                                                        tabs::TabInterface*) {
  auto weak = weak_factory_.GetWeakPtr();
  HideActivePopup();
  if (weak && !shutdown_)
    shell_.ExtensionActionsChanged();
}
void NativeExtensionActionContainer::OnAllTabsAreClosing(TabListInterface&) {
  HideActivePopup();
}
void NativeExtensionActionContainer::OnTabListDestroyed(TabListInterface&) {
  tabs_ = nullptr;
  Shutdown();
}
}
