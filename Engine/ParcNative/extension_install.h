#ifndef PARC_NATIVE_EXTENSION_INSTALL_H_
#define PARC_NATIVE_EXTENSION_INSTALL_H_
#include <memory>
#include <vector>

#include "chrome/browser/extensions/extension_install_native_host.h"
class BrowserWindowInterface;
namespace parc {
class NativeExtensionActionHost;
// One service per actual Browser, sharing the existing native security gate.
// Register before installers can start; cancel before page detach or host
// destruction. Installer decisions never mutate policy or grants directly.
class NativeExtensionInstallService final
    : public extensions::ExtensionInstallNativeHost {
 public:
  NativeExtensionInstallService(BrowserWindowInterface&,
                                NativeExtensionActionHost&);
  ~NativeExtensionInstallService() override;
  std::shared_ptr<extensions::ExtensionInstallNativeBinding> Capture(
      content::WebContents*) override;
  void HostStateChanged() override;
  void PageHostWillDetach(content::WebContents*) override;
  void Shutdown();

 private:
  class Request;
  BrowserWindowInterface& browser_;
  NativeExtensionActionHost& host_;
  bool shutdown_ = false;
  std::vector<std::weak_ptr<Request>> requests_;
  ui::ScopedUnownedUserData<extensions::ExtensionInstallNativeHost>
      registration_;
};
}  // namespace parc
#endif
