//
// Current-engine adaptation: actual DialogModel, strict instance/owner binding.
#ifndef PARC_NATIVE_EXTENSION_UNINSTALL_H_
#define PARC_NATIVE_EXTENSION_UNINSTALL_H_
#include <memory>
#include <vector>

#include "chrome/browser/extensions/extension_uninstall_native_host.h"
class BrowserWindowInterface;
namespace content {
class WebContents;
}
namespace parc {
class NativeExtensionActionHost;
// Browser-owned, registered before action menus. Drain before Browser/Profile,
// TabList and shell services die. No popup/menu model owns asynchronous
// consent.
class NativeExtensionUninstallService final
    : public extensions::ExtensionUninstallNativeHost {
 public:
  NativeExtensionUninstallService(BrowserWindowInterface&,
                                  NativeExtensionActionHost&);
  ~NativeExtensionUninstallService() override;
  bool CanPresent(const extensions::Extension&) const override;
  std::shared_ptr<extensions::ExtensionUninstallNativeBinding> Capture(
      const extensions::Extension&) override;
  void HostStateChanged() override;
  void PageHostWillDetach(content::WebContents*) override;
  void Shutdown();

 private:
  class Request;
  BrowserWindowInterface& browser_;
  NativeExtensionActionHost& host_;
  bool shutdown_ = false;
  std::vector<std::weak_ptr<Request>> requests_;
  ui::ScopedUnownedUserData<extensions::ExtensionUninstallNativeHost>
      registration_;
};
}  // namespace parc
#endif
