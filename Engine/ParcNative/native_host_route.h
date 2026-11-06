// Copyright 2026 Parc contributors.
//
// caller-supplied NSWindow and actual TabStripModel/WebContents ownership.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_HOST_ROUTE_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_HOST_ROUTE_H_

#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/types/expected.h"
#include "cef/include/cef_client.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/native_ui_types.h"

class BrowserFocusController;
class DevtoolsUIController;
class Profile;
namespace input {
struct NativeWebKeyboardEvent;
}
namespace content {
class WebContents;
}
namespace parc {
class NativeBrowserWindowHost;
class NativeRoute;

enum class NativeWindowReason { kExternal, kInternal, kPopup, kDevTools };
struct NativeWindowRequest {
  Profile& profile;
  BrowserWindowInterface::Type type;
  NativeWindowReason reason;
  // Borrowed for this synchronous Prepare invocation only. No nested event
  // loop, direct Browser destruction or retaining these raw pointers.
  const BrowserWindowInterface* source_browser = nullptr;
  content::WebContents* source_contents = nullptr;
  bool user_gesture = false;
  // Copy the final BrowserWindowCreateParams after Chromium has resolved the
  // disposition. These are presentation values, never a substitute for the
  // original pending WebContents or its navigation/opener state.
  gfx::Rect initial_bounds = {};
  bool initial_origin_specified = false;
  bool can_resize = true;
  bool can_maximize = true;
  bool can_fullscreen = true;
};

// Owns a prepared shell reservation, not a Browser. Derived implementations
// keep the exact caller-supplied window and required services viable until
// Bind, or release them on cancellation. Reusing a physical NSWindow still
// requires a fresh instance. No key/frontmost-window lookup is permitted.
class PreparedNativeWindow {
 public:
  virtual ~PreparedNativeWindow();
  PreparedNativeWindow(const PreparedNativeWindow&) = delete;
  PreparedNativeWindow& operator=(const PreparedNativeWindow&) = delete;
  virtual gfx::NativeWindow GetNativeWindow() const = 0;
  bool CanBind(Profile& profile, BrowserWindowInterface::Type type) const;
  std::unique_ptr<NativeBrowserWindowHost> Bind(
      BrowserWindowInterface& browser);

 protected:
  PreparedNativeWindow(Profile& profile, BrowserWindowInterface::Type type);
  // Required complete host. Called only after BrowserWindowFeatures::Init.
  // Preparation already established capability; a null return is a violated
  // programming contract, never an instruction to construct Chrome UI.
  virtual std::unique_ptr<NativeBrowserWindowHost> BindHost(
      BrowserWindowInterface& browser) = 0;

 private:
  base::WeakPtr<Profile> profile_;
  BrowserWindowInterface::Type type_;
  bool consumed_ = false;
};

class NativeWindowProvider {
 public:
  virtual ~NativeWindowProvider() = default;
  virtual base::expected<std::unique_ptr<PreparedNativeWindow>, std::string>
  Prepare(const NativeWindowRequest& request) = 0;
  // BrowserWindowFeatures owns the returned controller. It must use the real
  // selected page/shell focus manager; no Stub or dummy Views FocusManager.
  virtual std::unique_ptr<BrowserFocusController> CreateFocusController(
      BrowserWindowInterface& browser) = 0;
  virtual std::unique_ptr<DevtoolsUIController> CreateDevtoolsController(
      BrowserWindowInterface& browser) = 0;
  // Direct DevTools/Toolbox delegate route, separate from Browser page keys.
  // Native menu once, then the actual inspected Browser's registry. No Views.
  virtual bool HandleDevtoolsKey(content::WebContents* inspected,
                                 content::WebContents& tools,
                                 const input::NativeWebKeyboardEvent&) = 0;
  // A real CEF host is now bound/unbound. Tab insertion may precede SetBrowser;
  // the host must reconcile actual TabStripModel membership before attachment.
  virtual void PageOwnerChanged(BrowserWindowInterface* browser,
                                content::WebContents& contents) = 0;
  // BrowserManager retains the actual Browser/Profile until ready. Stop new
  // requests, retire all extension hosts/managers, then invoke exactly once.
  virtual void PrepareBrowserForDeletion(BrowserWindowInterface& browser,
                                         base::OnceClosure ready) = 0;
  // Exact application error path. Queries above do not emit success callbacks.
  virtual void CreationFailed(Profile& profile, const std::string& reason) = 0;
};

// Profile lifetime owns the registration; callers may retain the policy but it
// becomes unusable when that exact Profile dies. OTR profiles register their
// own route explicitly and never inherit a consumed normal-profile window.
class NativeRoute final {
 public:
  ~NativeRoute();
  Profile* profile() const;
  NativeWindowProvider& provider() const;
  CefRefPtr<CefClient> client() const;
  void BrowserCreated();
  void BrowserDestroyed();
  base::expected<std::shared_ptr<PreparedNativeWindow>, std::string> Prepare(
      const NativeWindowRequest& request);

 private:
  friend std::shared_ptr<NativeRoute> RegisterNativeRoute(
      Profile&,
      std::shared_ptr<NativeWindowProvider>,
      CefRefPtr<CefClient>);
  NativeRoute(Profile&,
              std::shared_ptr<NativeWindowProvider>,
              CefRefPtr<CefClient>);
  base::WeakPtr<Profile> profile_;
  std::shared_ptr<NativeWindowProvider> provider_;
  CefRefPtr<CefClient> client_;
};

// UI thread only. Duplicate registration is rejected rather than changing the
// policy under live Browsers. Profile destruction removes it automatically.
std::shared_ptr<NativeRoute> RegisterNativeRoute(
    Profile& profile,
    std::shared_ptr<NativeWindowProvider> provider,
    CefRefPtr<CefClient> client);
std::shared_ptr<NativeRoute> GetNativeRoute(Profile& profile);
// Includes Browsers scheduled for deletion (upstream public collection hides
// those), so engine shutdown cannot race native service draining.
size_t NativeBrowsersAlive();
}  // namespace parc
#endif
