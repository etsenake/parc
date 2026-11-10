// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_EXTENSION_ACTION_CONTAINER_H_
#define PARC_NATIVE_EXTENSION_ACTION_CONTAINER_H_
#include <map>
#include <memory>
#include <string>

#include "base/memory/weak_ptr.h"
#include "chrome/browser/tab_list/tab_list_interface_observer.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "chrome/browser/ui/views/extensions/security_dialog_tracker.h"
#import "extension_popup_presenter.h"
#include "ui/base/accelerators/accelerator.h"
@class PCNativeWindowSecurityReservation;
@protocol PCNativeMenuPresenter;
class ExtensionActionViewModel;
class BrowserWindowInterface;
class TabListInterface;
namespace extensions {
class ExtensionViewHost;
}
namespace input {
struct NativeWebKeyboardEvent;
}

namespace parc {
class NativeExtensionPopup;
// Mandatory native shell services. Unsupported contextual UI must return false
// and is reported; no Chrome BrowserView or fabricated successful menu
// fallback. The const query methods are side-effect-free main-thread snapshots:
// they must not pump events or mutate/destroy the owning Browser/container.
// Imperative menu/inspection/change callbacks may reenter and are guarded
// accordingly.
class NativeExtensionActionHost {
 public:
  virtual ~NativeExtensionActionHost() = default;
  virtual NSWindow* PopupParentWindow() const = 0;
  virtual PCExtensionPopupAnchor* PopupAnchor() const = 0;
  virtual bool IsSelectedBrowser() const = 0;
  virtual bool HasVisibleBrowserSecurityUI() const = 0;
  // A security presenter may exclude only its own exact sheet/reservation.
  // Hosts without that distinction keep the conservative aggregate query.
  virtual bool HasVisibleBrowserSecurityUIExcluding(
      NSWindow* owned_sheet,
      PCNativeWindowSecurityReservation* owned_reservation) const {
    return HasVisibleBrowserSecurityUI();
  }
  virtual bool HandlePopupMenuKey(content::WebContents*,
                                  const input::NativeWebKeyboardEvent&) = 0;
  virtual bool InspectPopup(content::WebContents*) = 0;
  // A nil presenter shows AppKit's menu at the pointer.
  virtual bool ShowActionContextMenu(ExtensionActionViewModel&,
                                     id<PCNativeMenuPresenter> presenter) = 0;
  virtual void CloseExtensionsMenu() = 0;
  virtual bool ToggleExtensionsMenu() = 0;
  virtual void ExtensionActionsChanged() = 0;
  virtual void ExtensionCapabilityUnavailable(const std::string& action_id,
                                              const char* capability) = 0;
};

// Browser-owned; construct only after real Profile/TabList/ToolbarActionsModel
// initialization. Destroy BEFORE those services or the supplied shell host.
// Action models remain upstream-owned types and perform actual permission
// grants.
class NativeExtensionActionContainer final
    : public ExtensionsContainer,
      public ToolbarActionsModel::Observer,
      public TabListInterfaceObserver,
      public extensions::SecurityDialogTracker::Observer {
 public:
  NativeExtensionActionContainer(BrowserWindowInterface& browser,
                                 NativeExtensionActionHost& host);
  ~NativeExtensionActionContainer();
  NativeExtensionActionContainer(const NativeExtensionActionContainer&) =
      delete;
  NativeExtensionActionContainer& operator=(
      const NativeExtensionActionContainer&) = delete;
  ToolbarActionViewModel* GetActionForId(const std::string& id) override;
  void HideActivePopup() override;
  void CloseExtensionsMenuIfOpen() override;
  bool ShowToolbarActionPopupForAPICall(const std::string& id,
                                        ShowPopupCallback callback) override;
  void ToggleExtensionsMenu() override;
  bool HasAnyExtensions() const override;
  content::WebContents* GetActiveWebContents() const override;
  bool DispatchActionAccelerator(const ui::Accelerator& accelerator);
  // Call on shell selection/activation changes and native security UI changes.
  void HostStateChanged();
  const std::vector<std::string>& pinned_action_ids() const;
  void SetPinned(const std::string& id, bool pinned);
  void Shutdown();
  // Production Browser deletion waits for this posted completion. It retains
  // actual action models and retiring popup hosts until all close callbacks
  // have returned; Browser/Profile must remain alive until then.
  void Shutdown(base::OnceClosure completion);

 private:
  class ActionDelegate;
  struct ShutdownState;
  friend class ActionDelegate;
  friend class NativeExtensionActionBridge;
  std::shared_ptr<ExtensionActionViewModel> Find(const std::string& id) const;
  void Add(const std::string& id);
  void RegisterCommand(ExtensionActionViewModel& model);
  void UnregisterCommand(const std::string& id);
  void HidePopupFor(const std::string& id);
  bool HasPopupFor(const std::string& id) const;
  void TriggerPopup(const std::string& id,
                    std::unique_ptr<extensions::ExtensionViewHost> host,
                    PopupShowAction action,
                    bool by_user,
                    ShowPopupCallback callback);
  void OnToolbarActionAdded(const std::string& id) override;
  void OnToolbarActionRemoved(const std::string& id) override;
  void OnToolbarActionUpdated(const std::string& id) override;
  void OnToolbarModelInitialized() override;
  void OnToolbarPinnedActionsChanged() override;
  void OnToolbarActionsModelShutdown() override;
  void OnSecurityDialogAdded(views::Widget*) override;
  void OnActiveTabChanged(TabListInterface&, tabs::TabInterface*) override;
  void OnAllTabsAreClosing(TabListInterface&) override;
  void OnTabListDestroyed(TabListInterface&) override;
  BrowserWindowInterface& browser_;
  NativeExtensionActionHost& shell_;
  ToolbarActionsModel* model_ = nullptr;
  TabListInterface* tabs_ = nullptr;
  std::map<std::string, std::shared_ptr<ExtensionActionViewModel>> actions_;
  std::map<std::string, ui::Accelerator> commands_;
  std::shared_ptr<NativeExtensionPopup> popup_;
  std::vector<std::pair<uint64_t, std::shared_ptr<NativeExtensionPopup>>>
      closing_popups_;
  std::string popup_id_;
  uint64_t popup_generation_ = 0;
  bool shutdown_ = false;
  std::shared_ptr<ShutdownState> shutdown_state_;
  id __strong security_observer_;
  ui::ScopedUnownedUserData<ExtensionsContainer> registration_;
  base::WeakPtrFactory<NativeExtensionActionContainer> weak_factory_{this};
};
}  // namespace parc
#endif
