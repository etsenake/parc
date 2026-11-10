// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_EXTENSION_CONTEXT_MENU_H_
#define PARC_NATIVE_EXTENSION_CONTEXT_MENU_H_

#include <memory>

#include "base/functional/callback.h"
#include "chrome/browser/extensions/extension_context_menu_model.h"

class BrowserWindowInterface;
class ExtensionActionViewModel;
@protocol PCNativeMenuPresenter;

namespace parc {
class NativeExtensionActionHost;

// Browser-owned, synchronous native menu service. The caller must retain the
// real action model and Browser/Profile through Show's nested AppKit loop.
// Cancel before tearing down those services; return from Show before destroying
// Browser/Profile. Destruction of this presenter itself during Show is safe.
//
// Exact host hook:
//   NativeExtensionActionHost::ShowActionContextMenu(model, presenter) ->
//   Show(model, presenter).
// The existing fallback caller retains its model across that hook. Toolbar
// callers must provide the same ownership, not retain a naked GetActionForId().
// Pinning also requires the accompanying optional-feedback upstream patch.
class NativeExtensionContextMenu final {
 public:
  NativeExtensionContextMenu(BrowserWindowInterface& browser,
                             NativeExtensionActionHost& host);
  ~NativeExtensionContextMenu();
  NativeExtensionContextMenu(const NativeExtensionContextMenu&) = delete;
  NativeExtensionContextMenu& operator=(const NativeExtensionContextMenu&) =
      delete;

  // True means AppKit actually began tracking the menu, including cancellation.
  // It does not mean a command was selected or a downstream UI succeeded.
  // A cancelled in-flight Show still holds its action-model lease until return;
  // another presenter cannot replace that model during an executing command.
  // `app_presenter` shows the same menu in the app's style instead of AppKit
  // at the pointer, within the same synchronous Show.
  bool Show(ExtensionActionViewModel& model,
            id<PCNativeMenuPresenter> app_presenter = nil,
            extensions::ExtensionContextMenuModel::ContextMenuSource source =
                extensions::ExtensionContextMenuModel::ContextMenuSource::
                    kToolbarAction);
  void Cancel();
  // Terminal: prevents new tracking, cancels the actual menu, and posts ready
  // only after every synchronous Show/model lease has unwound. Browser/Profile
  // must remain alive until ready. Safe if cancellation destroys this
  // presenter.
  void CancelAndWait(base::OnceClosure ready);
  // Call when the shell's selected Browser or security state changes. Actual
  // tab/page/extension/window invalidation is observed by the active session.
  void HostStateChanged();

 private:
  class Session;
  struct RunState;
  BrowserWindowInterface& browser_;
  NativeExtensionActionHost& host_;
  std::shared_ptr<Session> session_;
  std::shared_ptr<RunState> run_state_;
};
}  // namespace parc
#endif
