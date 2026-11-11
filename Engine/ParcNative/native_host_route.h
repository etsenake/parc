// Copyright 2026 Parc contributors.
//
// caller-supplied NSWindow and actual TabStripModel/WebContents ownership.
#ifndef PARC_NATIVE_NATIVE_HOST_ROUTE_H_
#define PARC_NATIVE_NATIVE_HOST_ROUTE_H_

#include <memory>

#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/native_ui_types.h"

class Profile;
namespace content {
class WebContents;
}
namespace parc {
class NativeBrowserWindowHost;

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

// Marks a Profile whose Browsers Parc's shell hosts. Profile user data owns it.
// OTR profiles register their own route explicitly and never inherit a
// consumed normal-profile window.
class NativeRoute final {};

// UI thread only. Duplicate registration is rejected rather than changing the
// policy under live Browsers. Profile destruction removes it automatically.
void RegisterNativeRoute(Profile& profile);
NativeRoute* GetNativeRoute(Profile& profile);
}  // namespace parc
#endif  // PARC_NATIVE_NATIVE_HOST_ROUTE_H_
