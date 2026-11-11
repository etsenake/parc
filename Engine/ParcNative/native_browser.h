// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BROWSER_H_
#define PARC_NATIVE_NATIVE_BROWSER_H_

#include <memory>
#include <optional>

#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

class Browser;
class BrowserUiController;
class BrowserWebContentsDelegate;
class BrowserWindow;
class BrowserWindowInterface;
class DesktopBrowserWindowCapabilities;
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

// Parc's part of a Browser whose window is a native shell window. Parc owns it
// from the start of the Browser's constructor, before its features and window
// exist, to the end of its destructor, after both are gone. All methods run on
// the UI thread.
class NativeBrowser final {
 public:
  DECLARE_USER_DATA(NativeBrowser);

  // Browser::Browser takes the one-use reservation PrepareNativeBrowserWindow
  // accepted for it; an ordinary Browser gets no record. Browser::~Browser
  // releases the record.
  static void OnBrowserCreated(Browser& browser);
  static void OnBrowserDestroyed(Browser& browser);
  static NativeBrowser* From(BrowserWindowInterface* browser);
  static const NativeBrowser* From(const BrowserWindowInterface* browser);
  ~NativeBrowser();
  NativeBrowser(const NativeBrowser&) = delete;
  NativeBrowser& operator=(const NativeBrowser&) = delete;

  // BrowserWindow::CreateBrowserWindow; null for an ordinary Browser.
  static std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateWindow(
      BrowserWindowInterface* browser);
  // BrowserManagerService::AddBrowser, once it owns the Browser and before
  // any observer. Attaches a native Browser's window to its reserved NSWindow.
  static void OnRegistered(BrowserWindowInterface* browser);
  // BrowserManagerService::DeleteBrowser, before it releases the Browser. true
  // keeps the service's ownership until every native host has drained, then
  // posts SynchronouslyDestroyBrowser again. An ordinary Browser is ready.
  static bool DeferDeletion(BrowserWindowInterface* browser);
  static bool DeletionReady(const BrowserWindowInterface* browser);

  // BrowserWindowFeatures::InitPostWindowConstruction. The color source is
  // null for an ordinary Browser; only native ones reach the delegate factory.
  static ui::ColorProviderSource* ColorProviderSource(
      BrowserWindowInterface* browser);
  static std::unique_ptr<BrowserWebContentsDelegate> CreateWebContentsDelegate(
      BrowserWindowInterface* browser,
      ExclusiveAccessManager& exclusive_access_manager,
      chrome::BrowserCommandController& command_controller,
      UnloadController& unload_controller,
      web_app::AppBrowserController* app_browser_controller,
      BrowserWindow& window,
      DesktopBrowserWindowCapabilities& capabilities,
      BrowserUiController& browser_ui_controller);

  // Browser::SetAsDelegate: binds or releases the page's native presentation.
  static void SetAsDelegate(Browser& browser,
                            content::WebContents& contents,
                            bool set_delegate);
  // chrome::Navigate created `contents` for `browser` before inserting it.
  static void OnWebContentsCreated(BrowserWindowInterface* browser,
                                   content::WebContents& contents);

 private:
  NativeBrowser(Browser& browser,
                std::unique_ptr<PreparedNativeWindow> reservation);

  enum class Deletion { kActive, kDraining, kReady };

  const raw_ref<Browser> browser_;
  std::unique_ptr<PreparedNativeWindow> reservation_;
  Deletion deletion_ = Deletion::kActive;
  ui::ScopedUnownedUserData<NativeBrowser> scoped_data_holder_;
};

// The Browser the next Browser::Create on this stack opens from and, from
// Parc's shell, its one-use window reservation. Only that Create's admission
// consumes it; a Browser created during that admission sees no context.
class ScopedNativeBrowserCreation final {
 public:
  ScopedNativeBrowserCreation(const BrowserWindowInterface* opener,
                              std::unique_ptr<PreparedNativeWindow> window);
  ~ScopedNativeBrowserCreation();
  ScopedNativeBrowserCreation(const ScopedNativeBrowserCreation&) = delete;
  ScopedNativeBrowserCreation& operator=(const ScopedNativeBrowserCreation&) =
      delete;

 private:
  friend bool PrepareNativeBrowserWindow(BrowserWindowCreateParams& params);
  static ScopedNativeBrowserCreation* Claim();

  const raw_ptr<const BrowserWindowInterface> opener_;
  std::unique_ptr<PreparedNativeWindow> window_;
  bool claimed_ = false;
  const raw_ptr<ScopedNativeBrowserCreation> outer_;
};

// The navigator's and DevTools' Browser creation, opened from `opener`.
BrowserWindowInterface* CreateBrowserWindowFrom(
    BrowserWindowInterface* opener,
    BrowserWindowCreateParams params);

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

// Browser::Create's admission, before any Browser or feature exists. A native
// Profile's Browser gets a one-use window reservation for its constructor.
// false is a cancelled native creation, never a Chrome-window fallback.
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
