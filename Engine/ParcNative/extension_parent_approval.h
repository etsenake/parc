// Native presentation over Chromium's supervised-profile reauthentication APIs.
#pragma once
#import <AppKit/AppKit.h>
#include <memory>
#include "base/functional/callback.h"
#include "extensions/browser/extension_install_prompt_client.h"
class Profile;
namespace extensions { class Extension; }
namespace gfx { class ImageSkia; }
namespace parc {
class NativeExtensionParentApproval {
 public:
  using Result = extensions::ExtensionInstallPromptClient::Result;
  virtual ~NativeExtensionParentApproval() = default;
  static std::shared_ptr<NativeExtensionParentApproval> Create(
      Profile*, const extensions::Extension*, const gfx::ImageSkia&, NSWindow*,
      base::RepeatingCallback<bool()> validate,
      base::RepeatingCallback<bool(NSWindow*)> input_allowed,
      base::OnceCallback<void(Result)> done);
  virtual void Start() = 0;
  virtual void Cancel() = 0;
  virtual NSWindow* sheet() const = 0;
};
}  // namespace parc
