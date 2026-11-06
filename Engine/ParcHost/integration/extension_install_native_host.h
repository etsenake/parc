// Parc native extension consent boundary. Real installer/policy remain owners.
#ifndef CHROME_BROWSER_EXTENSIONS_EXTENSION_INSTALL_NATIVE_HOST_H_
#define CHROME_BROWSER_EXTENSIONS_EXTENSION_INSTALL_NATIVE_HOST_H_
#include <memory>
#include <string>

#include "extensions/browser/extension_install_prompt_client.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"
class Profile;
class SkBitmap;
namespace gfx { class ImageSkia; }
class ExtensionInstallPromptShowParams;
namespace content {
class WebContents;
}
namespace extensions {
class Extension;
class InstallPromptData;
// Captured before asynchronous icon loading. Never retargets an existing
// request to the frontmost Browser, a different page, or another Profile.
class ExtensionInstallNativeBinding {
 public:
  virtual ~ExtensionInstallNativeBinding() = default;
  // Takes the actual installer callback, even when presentation is unavailable.
  // Result is delivered once, asynchronously, outside the current UI call.
  virtual bool Begin(const Extension*,
                     ExtensionInstallPromptClient::DoneCallback) = 0;
  virtual bool CanContinue() const = 0;
  virtual void Show(std::unique_ptr<InstallPromptData>) = 0;
  // Cancel before destroying the owning controller or native host. This only
  // resolves pending consent; it does not undo or claim an installation.
  virtual void Cancel() = 0;
  // The caller remains the supervised delegate. ACCEPTED is delivered only
  // after genuine parent reauthentication, never from a native button alone.
  virtual void ShowParentApproval(const Extension*, const gfx::ImageSkia&,
                                 ExtensionInstallPromptClient::DoneCallback) = 0;
  // Called only by the real install client callbacks. False success never
  // means consent denial: message is Chromium's actual installation error.
  virtual void InstallationFinished(const Extension*,
                                    bool success,
                                    const std::u16string& message,
                                    const SkBitmap* icon = nullptr,
                                    bool app_installed_bubble = false) = 0;
};
class ExtensionInstallNativeHost {
 public:
  DECLARE_USER_DATA(ExtensionInstallNativeHost);
  virtual ~ExtensionInstallNativeHost() = default;
  virtual std::shared_ptr<ExtensionInstallNativeBinding> Capture(
      content::WebContents*) = 0;
  virtual void HostStateChanged() = 0;
  virtual void PageHostWillDetach(content::WebContents*) = 0;
  // Native mode is Profile-owned and remains marked when its last window
  // closes. An ownerless request is aborted, never sent to an unrelated Views
  // window. Profile destruction releases the marker normally.
  static void MarkProfile(Profile*);
  static std::shared_ptr<ExtensionInstallNativeBinding> CaptureFor(
      ExtensionInstallPromptShowParams&);
};
}  // namespace extensions
#endif
