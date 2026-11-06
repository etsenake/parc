// Parc native uninstall presentation boundary; ordinary Views is unchanged.
#ifndef CHROME_BROWSER_EXTENSIONS_EXTENSION_UNINSTALL_NATIVE_HOST_H_
#define CHROME_BROWSER_EXTENSIONS_EXTENSION_UNINSTALL_NATIVE_HOST_H_
#include <memory>

#include "base/functional/callback.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"
namespace content {
class WebContents;
}
namespace ui {
class DialogModel;
}
namespace extensions {
class Extension;
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
// Browser-owned registration. Capture always returns a binding, including an
// invalid one that cancels; null means no native route only when no host
// exists.
class ExtensionUninstallNativeHost {
 public:
  DECLARE_USER_DATA(ExtensionUninstallNativeHost);
  virtual ~ExtensionUninstallNativeHost() = default;
  virtual bool CanPresent(const Extension& extension) const = 0;
  // Shell security/selection changes must notify this alongside menu/popup
  // services.
  virtual void HostStateChanged() = 0;
  virtual void PageHostWillDetach(content::WebContents*) = 0;
  virtual std::shared_ptr<ExtensionUninstallNativeBinding> Capture(
      const Extension& extension) = 0;
};
}  // namespace extensions
#endif
