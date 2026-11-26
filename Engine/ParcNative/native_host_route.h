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

  const BrowserWindowInterface* source_browser = nullptr;
  content::WebContents* source_contents = nullptr;
  bool user_gesture = false;

  gfx::Rect initial_bounds = {};
  bool initial_origin_specified = false;
  bool can_resize = true;
  bool can_maximize = true;
  bool can_fullscreen = true;
  bool is_document_picture_in_picture = false;
};

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

  virtual std::unique_ptr<NativeBrowserWindowHost> BindHost(
      BrowserWindowInterface& browser) = 0;

 private:
  base::WeakPtr<Profile> profile_;
  BrowserWindowInterface::Type type_;
  bool consumed_ = false;
};

class NativeRoute final {};

void RegisterNativeRoute(Profile& profile);
NativeRoute* GetNativeRoute(Profile& profile);
}
#endif
