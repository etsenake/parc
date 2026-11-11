// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BROWSER_H_
#define PARC_NATIVE_NATIVE_BROWSER_H_

#include <memory>
#include <optional>

#include "base/functional/callback.h"
#include "base/memory/raw_ref.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

class Browser;
class BrowserFocusController;
class BrowserUiController;
class BrowserWebContentsDelegate;
class BrowserWindow;
class BrowserWindowInterface;
class DesktopBrowserWindowCapabilities;
class DevtoolsUIController;
class Profile;
class ExclusiveAccessManager;
class UnloadController;
struct BrowserWindowCreateParams;
struct BrowserWindowDeleter;
namespace chrome {
class BrowserCommandController;
}
namespace content {
class WebContents;
}
namespace input {
struct NativeWebKeyboardEvent;
}
namespace ui {
class ColorProviderSource;
}
namespace web_app {
class AppBrowserController;
}

namespace parc {
class PreparedNativeWindow;

// Parc's part of a Browser whose window is a native shell window. The Browser
// owns it from construction, before its features and window exist, until
// destruction. All methods run on the UI thread.
class NativeBrowser final {
 public:
  DECLARE_USER_DATA(NativeBrowser);

  // Takes the one-use reservation PrepareNativeBrowserWindow put in `params`.
  // Null for an ordinary Browser.
  static std::unique_ptr<NativeBrowser> Create(Browser& browser,
                                               BrowserWindowCreateParams& params);
  static NativeBrowser* From(BrowserWindowInterface* browser);
  static const NativeBrowser* From(const BrowserWindowInterface* browser);
  ~NativeBrowser();
  NativeBrowser(const NativeBrowser&) = delete;
  NativeBrowser& operator=(const NativeBrowser&) = delete;

  // BrowserWindow::CreateBrowserWindow.
  std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateWindow();
  // BrowserManagerService::AddBrowser, once it owns the Browser. Attaches the
  // window to the reserved NSWindow.
  void OnRegistered();
  // true keeps BrowserManagerService ownership until `retry`, which is posted
  // only after every native host has drained.
  bool DeferDeletion(base::OnceClosure retry);
  bool DeletionReady() const;

  // BrowserWindowFeatures::InitPostWindowConstruction.
  ui::ColorProviderSource& ColorProviderSource();
  std::unique_ptr<BrowserFocusController> CreateFocusController();
  std::unique_ptr<DevtoolsUIController> CreateDevtoolsController();
  std::unique_ptr<BrowserWebContentsDelegate> CreateWebContentsDelegate(
      ExclusiveAccessManager& exclusive_access_manager,
      chrome::BrowserCommandController& command_controller,
      UnloadController& unload_controller,
      web_app::AppBrowserController* app_browser_controller,
      BrowserWindow& window,
      DesktopBrowserWindowCapabilities& capabilities,
      BrowserUiController& browser_ui_controller);

  // Browser::SetAsDelegate: binds or releases the page's native presentation.
  void SetAsDelegate(content::WebContents& contents, bool set_delegate);
  // chrome::Navigate created `contents` for this Browser before inserting it.
  void OnWebContentsCreated(content::WebContents& contents);

 private:
  NativeBrowser(Browser& browser,
                std::shared_ptr<PreparedNativeWindow> reservation);

  enum class Deletion { kActive, kDraining, kReady };

  const raw_ref<Browser> browser_;
  std::shared_ptr<PreparedNativeWindow> reservation_;
  Deletion deletion_ = Deletion::kActive;
  ui::ScopedUnownedUserData<NativeBrowser> scoped_data_holder_;
};

bool IsNativeBrowser(const BrowserWindowInterface* browser);
// Includes Browsers scheduled for deletion (upstream public collection hides
// those), so engine shutdown cannot race native service draining.
size_t NativeBrowsersAlive();

// True keeps a primary OTR Profile whose last Browser closed while a native
// operation still holds it; RetryNativeOTRProfileDestruction destroys it once
// the operations end, unless a Browser reopened it.
bool DeferNativeOTRProfileDestruction(Profile& profile);
// Native operations changed; called from the Profile registry notification.
void RetryNativeOTRProfileDestruction();

// CreateBrowserWindow preflight, before any Browser or feature exists. A
// native Profile gets a one-use window reservation in `params`. false is a
// cancelled native creation, never a Chrome-window fallback.
bool PrepareNativeBrowserWindow(BrowserWindowCreateParams& params);

// DevTools frontend for a native page, before its first navigation.
void PrepareNativeDevtoolsContents(content::WebContents* inspected,
                                   content::WebContents& tools);
// nullopt keeps ordinary Chromium routing. A native result is terminal,
// including a rejected skip_if_unhandled event, so menus are not offered twice.
std::optional<bool> HandleNativeDevtoolsKey(
    content::WebContents* inspected,
    content::WebContents* tools,
    const input::NativeWebKeyboardEvent& event);
}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_BROWSER_H_
