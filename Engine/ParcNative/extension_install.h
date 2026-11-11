#ifndef PARC_NATIVE_EXTENSION_INSTALL_H_
#define PARC_NATIVE_EXTENSION_INSTALL_H_
#include <memory>
#include <vector>

#include "chrome/browser/extensions/extension_install_prompt.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"
class BrowserWindowInterface;
class Profile;
namespace parc {
class NativeExtensionActionHost;
// One service per actual Browser, sharing the existing native security gate.
// Register before installers can start; cancel before page detach or host
// destruction. Installer decisions never mutate policy or grants directly.
class NativeExtensionInstallService final {
 public:
  DECLARE_USER_DATA(NativeExtensionInstallService);
  NativeExtensionInstallService(BrowserWindowInterface&,
                                NativeExtensionActionHost&);
  ~NativeExtensionInstallService();
  std::shared_ptr<extensions::ExtensionInstallNativeBinding> Capture(
      content::WebContents*);
  void HostStateChanged();
  void PageHostWillDetach(content::WebContents*);
  void Shutdown();
  static void MarkProfile(Profile*);
  static std::shared_ptr<extensions::ExtensionInstallNativeBinding> CaptureFor(
      ExtensionInstallPromptShowParams&);

 private:
  class Request;
  BrowserWindowInterface& browser_;
  NativeExtensionActionHost& host_;
  bool shutdown_ = false;
  std::vector<std::weak_ptr<Request>> requests_;
  ui::ScopedUnownedUserData<NativeExtensionInstallService> registration_;
};
}  // namespace parc
#endif
