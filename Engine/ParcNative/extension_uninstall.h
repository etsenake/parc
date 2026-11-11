//
// Current-engine adaptation: actual DialogModel, strict instance/owner binding.
#ifndef PARC_NATIVE_EXTENSION_UNINSTALL_H_
#define PARC_NATIVE_EXTENSION_UNINSTALL_H_
#include <memory>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/extensions/extension_uninstall_dialog.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"
class BrowserWindowInterface;
namespace content {
class WebContents;
}
namespace ui {
class DialogModel;
}
namespace parc {
class NativeExtensionActionHost;
// Bound before icon loading to one Browser/Profile/window/extension instance.
// Arm may cancel reentrantly; callers must guard their own lifetime. A false
// result is refusal, never permission to fall back to a different presenter.
class ExtensionUninstallNativeBinding {
 public:
  virtual ~ExtensionUninstallNativeBinding() = default;
  virtual bool Arm(base::RepeatingClosure cancel) = 0;
  virtual void Show(std::unique_ptr<ui::DialogModel> model) = 0;
  virtual void Close() = 0;
};
// Browser-owned, registered before action menus. Drain before Browser/Profile,
// TabList and shell services die. No popup/menu model owns asynchronous
// consent. Capture always returns a binding, including an invalid one that
// cancels.
class NativeExtensionUninstallService final {
 public:
  DECLARE_USER_DATA(NativeExtensionUninstallService);
  NativeExtensionUninstallService(BrowserWindowInterface&,
                                  NativeExtensionActionHost&);
  ~NativeExtensionUninstallService();
  bool CanPresent(const extensions::Extension&) const;
  std::shared_ptr<ExtensionUninstallNativeBinding> Capture(
      const extensions::Extension&);
  // Shell security/selection changes must notify this alongside menu/popup
  // services.
  void HostStateChanged();
  void PageHostWillDetach(content::WebContents*);
  void Shutdown();

 private:
  class Request;
  BrowserWindowInterface& browser_;
  NativeExtensionActionHost& host_;
  bool shutdown_ = false;
  std::vector<std::weak_ptr<Request>> requests_;
  ui::ScopedUnownedUserData<NativeExtensionUninstallService> registration_;
};
// Chromium's uninstall dialog presented through a binding instead of Views.
// Confirm arms the binding before Chromium loads the icon; a refused binding
// reports cancellation.
class NativeExtensionUninstallDialog final
    : public extensions::ExtensionUninstallDialog {
 public:
  NativeExtensionUninstallDialog(
      Profile* profile,
      gfx::NativeWindow parent,
      Delegate* delegate,
      std::shared_ptr<ExtensionUninstallNativeBinding> binding);
  ~NativeExtensionUninstallDialog() override;
  void Confirm(const scoped_refptr<const extensions::Extension>& extension,
               extensions::UninstallReason reason,
               extensions::UninstallSource source);

 private:
  void Show() override;
  void Close() override;
  void Accepted();
  void Closing();
  void Report(CloseAction action);

  const std::shared_ptr<ExtensionUninstallNativeBinding> binding_;
  // The shown model, cleared before its close is reported.
  raw_ptr<ui::DialogModel> model_ = nullptr;
  // Chromium's delegate hears the outcome once.
  bool reported_ = false;
  base::WeakPtrFactory<NativeExtensionUninstallDialog> weak_factory_{this};
};
// ExtensionContextMenuModel's UNINSTALL command. Native Browsers confirm through
// their service; any other Browser keeps Chromium's Views dialog.
void BeginExtensionUninstall(BrowserWindowInterface* browser,
                             const extensions::Extension* extension);
}  // namespace parc
#endif
