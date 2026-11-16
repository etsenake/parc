// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BROWSER_H_
#define PARC_NATIVE_NATIVE_BROWSER_H_

#include <memory>
#include <optional>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "private_session_ledger.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

class Browser;
class BrowserUiController;
class BrowserWebContentsDelegate;
class BrowserWindow;
class BrowserWindowInterface;
class DesktopBrowserWindowCapabilities;
class Profile;
class ExclusiveAccessManager;
class GURL;
class UnloadController;
struct BrowserWindowCreateParams;
struct BrowserWindowDeleter;
namespace chrome {
class BrowserCommandController;
}
namespace content {
class NavigationHandle;
class WebContents;
struct OpenURLParams;
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
class NativeProfileLease;
class PreparedNativeWindow;

struct NativePrivateSessionHost {
  using Key = Profile*;
  using Session = base::WeakPtr<Profile>;
  using Waiter = base::OnceCallback<void(bool)>;

  PrivateSessionUse Use(const Session& session);
  bool HasOperations(const Session& session);
  void Destroy(const Session& session);
  void ScheduleRetry();
  bool Dying(Key parent);
  void WatchEnd(Key parent);
  void Finish(Waiter waiter, bool settled);
};
using NativePrivateSessionClaim =
    PrivateSessionLedger<NativePrivateSessionHost>::Claim;

class NativeBrowser final {
 public:
  DECLARE_USER_DATA(NativeBrowser);

  static void OnBrowserCreated(Browser& browser);
  static void OnBrowserDestroyed(Browser& browser);
  static NativeBrowser* From(BrowserWindowInterface* browser);
  static const NativeBrowser* From(const BrowserWindowInterface* browser);
  ~NativeBrowser();
  NativeBrowser(const NativeBrowser&) = delete;
  NativeBrowser& operator=(const NativeBrowser&) = delete;

  static std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateWindow(
      BrowserWindowInterface* browser);
  static void OnRegistered(BrowserWindowInterface* browser);
  static bool DeferDeletion(BrowserWindowInterface* browser);
  static bool DeletionReady(const BrowserWindowInterface* browser);

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

  static void SetAsDelegate(Browser& browser,
                            content::WebContents& contents,
                            bool set_delegate);
  static void OnWebContentsCreated(BrowserWindowInterface* browser,
                                   content::WebContents& contents);

 private:
  NativeBrowser(Browser& browser,
                std::unique_ptr<PreparedNativeWindow> reservation,
                NativePrivateSessionClaim claim);

  enum class Deletion { kActive, kDraining, kReady };

  const raw_ref<Browser> browser_;
  std::unique_ptr<PreparedNativeWindow> reservation_;
  NativePrivateSessionClaim claim_;
  Deletion deletion_ = Deletion::kActive;
  ui::ScopedUnownedUserData<NativeBrowser> scoped_data_holder_;
};

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

BrowserWindowInterface* CreateBrowserWindowFrom(
    BrowserWindowInterface* opener,
    BrowserWindowCreateParams params);

bool IsNativeBrowser(const BrowserWindowInterface* browser);
size_t NativeBrowsersAlive();

bool DeferNativeOTRProfileDestruction(Profile& profile);
void RetryNativeOTRProfileDestruction();
NativePrivateSessionClaim ClaimNativePrivateSession(Profile& parent);
void AwaitNativePrivateSession(scoped_refptr<NativeProfileLease> parent,
                               base::OnceCallback<void(Profile*)> ready);
void NominateNativePrivateSession(Profile& off_the_record);
void SetNativePrivateSessionsClosing(bool closing);
bool NativePrivateSessionsIdle();
bool DeferNativePrivateOpen(
    content::WebContents& source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)>&
        navigation_handle_callback);

bool PrepareNativeBrowserWindow(BrowserWindowCreateParams& params);
void SkipNativeBrowserAdmission();

void PrepareNativeDevtoolsContents(content::WebContents* inspected,
                                   content::WebContents& tools);
std::optional<bool> HandleNativeDevtoolsKey(
    content::WebContents* inspected,
    content::WebContents* tools,
    const input::NativeWebKeyboardEvent& event);
void OpenNativeDevtoolsLink(Profile& profile, const GURL& url);
}

#endif
