// Copyright 2026 Parc contributors.
#include "native_host_route.h"

#include "base/check.h"
#include "base/supports_user_data.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/browser_thread.h"
#include "native_browser_window.h"

namespace parc {
namespace {
const char kNativeRouteKey = 0;
struct RouteData final : base::SupportsUserData::Data {
  NativeRoute route;
};
void CheckUI() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
}
}  // namespace
PreparedNativeWindow::PreparedNativeWindow(Profile& profile,
                                           BrowserWindowInterface::Type type)
    : profile_(profile.GetWeakPtr()), type_(type) {
  CheckUI();
}
PreparedNativeWindow::~PreparedNativeWindow() = default;
bool PreparedNativeWindow::CanBind(Profile& profile,
                                   BrowserWindowInterface::Type type) const {
  CheckUI();
  return !consumed_ && profile_.get() == &profile && type_ == type &&
         GetNativeWindow();
}
std::unique_ptr<NativeBrowserWindowHost> PreparedNativeWindow::Bind(
    BrowserWindowInterface& browser) {
  CheckUI();
  CHECK(CanBind(*browser.GetProfile(), browser.GetType()));
  consumed_ = true;  // Commit before application callbacks/reentry.
  auto host = BindHost(browser);
  CHECK(host);
  return host;
}
void RegisterNativeRoute(Profile& profile) {
  CheckUI();
  CHECK(!profile.GetUserData(&kNativeRouteKey));
  profile.SetUserData(&kNativeRouteKey, std::make_unique<RouteData>());
}
NativeRoute* GetNativeRoute(Profile& profile) {
  CheckUI();
  auto* data = static_cast<RouteData*>(profile.GetUserData(&kNativeRouteKey));
  return data ? &data->route : nullptr;
}
}  // namespace parc
