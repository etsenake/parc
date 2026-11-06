// Copyright 2026 Parc contributors.
#include "cef/libcef/browser/parc_native/native_host_route.h"

#include "base/check.h"
#include "base/supports_user_data.h"
#include "cef/libcef/browser/parc_native/native_browser_window.h"
#include "cef/libcef/browser/parc_native/native_engine_entry.h"
#include "chrome/browser/policy/profile_policy_connector.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/browser_thread.h"

namespace parc {
namespace {
const char kNativeRouteKey = 0;
size_t native_browsers_alive = 0;
struct RouteData final : base::SupportsUserData::Data {
  explicit RouteData(std::shared_ptr<NativeRoute> value)
      : route(std::move(value)) {}
  std::shared_ptr<NativeRoute> route;
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
NativeRoute::NativeRoute(Profile& profile,
                         std::shared_ptr<NativeWindowProvider> provider,
                         CefRefPtr<CefClient> client)
    : profile_(profile.GetWeakPtr()),
      provider_(std::move(provider)),
      client_(std::move(client)) {
  CHECK(provider_);
  CHECK(client_);
}
NativeRoute::~NativeRoute() = default;
void NativeRoute::BrowserCreated() {
  CheckUI();
  ++native_browsers_alive;
}
void NativeRoute::BrowserDestroyed() {
  CheckUI();
  CHECK(native_browsers_alive);
  --native_browsers_alive;
  NotifyNativeEngineOwnershipChanged();
}
size_t NativeBrowsersAlive() {
  CheckUI();
  return native_browsers_alive;
}
Profile* NativeRoute::profile() const {
  CheckUI();
  return profile_.get();
}
NativeWindowProvider& NativeRoute::provider() const {
  CheckUI();
  return *provider_;
}
CefRefPtr<CefClient> NativeRoute::client() const {
  CheckUI();
  return client_;
}
base::expected<std::shared_ptr<PreparedNativeWindow>, std::string>
NativeRoute::Prepare(const NativeWindowRequest& request) {
  CheckUI();
  if (profile_.get() != &request.profile) {
    return base::unexpected(
        "Native window profile no longer exists or differs");
  }
  if (request.profile.GetProfilePolicyConnector()->IsManaged()) {
    return base::unexpected(
        "Managed profile native data-protection UI is unavailable");
  }
  auto prepared = provider_->Prepare(request);
  if (!prepared.has_value()) {
    return base::unexpected(prepared.error());
  }
  if (!profile_ || !*prepared ||
      !(*prepared)->CanBind(request.profile, request.type)) {
    return base::unexpected(
        "Native window reservation is unavailable or mismatched");
  }
  return std::shared_ptr<PreparedNativeWindow>(std::move(*prepared));
}
std::shared_ptr<NativeRoute> RegisterNativeRoute(
    Profile& profile,
    std::shared_ptr<NativeWindowProvider> provider,
    CefRefPtr<CefClient> client) {
  CheckUI();
  CHECK(!profile.GetUserData(&kNativeRouteKey));
  auto route = std::shared_ptr<NativeRoute>(
      new NativeRoute(profile, std::move(provider), std::move(client)));
  profile.SetUserData(&kNativeRouteKey, std::make_unique<RouteData>(route));
  return route;
}
std::shared_ptr<NativeRoute> GetNativeRoute(Profile& profile) {
  CheckUI();
  auto* data = static_cast<RouteData*>(profile.GetUserData(&kNativeRouteKey));
  return data ? data->route : nullptr;
}
}  // namespace parc
