// Copyright 2026 Parc contributors.
#include "native_browser.h"

#include <algorithm>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/ptr_util.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/policy/profile_policy_connector.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_manager_service.h"
#include "chrome/browser/ui/browser_web_contents_delegate/browser_web_contents_delegate.h"
#include "chrome/browser/ui/browser_window_deleter.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "native_appkit_host.h"
#include "native_auxiliary_services.h"
#include "native_browser_web_contents_delegate.h"
#include "native_browser_window.h"
#include "native_engine_entry.h"
#include "native_host_route.h"
#include "native_page_binding.h"
#include "native_profiles.h"

namespace parc {
namespace {
size_t native_browsers_alive = 0;

std::vector<base::WeakPtr<Profile>>& DeferredOTRProfiles() {
  static base::NoDestructor<std::vector<base::WeakPtr<Profile>>> value;
  return *value;
}

NativeBrowserWindow& WindowOf(Browser& browser) {
  return *static_cast<NativeBrowserWindow*>(browser.GetWindow());
}
}  // namespace

DEFINE_USER_DATA(NativeBrowser);

// static
std::unique_ptr<NativeBrowser> NativeBrowser::Create(
    Browser& browser,
    BrowserWindowCreateParams& params) {
  if (!params.native_window) {
    return nullptr;
  }
  // Moved out so the Browser's retained creation params never carry it.
  return base::WrapUnique(
      new NativeBrowser(browser, std::move(params.native_window)));
}

// static
NativeBrowser* NativeBrowser::From(BrowserWindowInterface* browser) {
  return browser ? Get(browser->GetUnownedUserDataHost()) : nullptr;
}

// static
const NativeBrowser* NativeBrowser::From(
    const BrowserWindowInterface* browser) {
  return browser ? Get(browser->GetUnownedUserDataHost()) : nullptr;
}

NativeBrowser::NativeBrowser(Browser& browser,
                             std::shared_ptr<PreparedNativeWindow> reservation)
    : browser_(browser),
      reservation_(std::move(reservation)),
      scoped_data_holder_(browser.GetUnownedUserDataHost(), *this) {
  ++native_browsers_alive;
}

NativeBrowser::~NativeBrowser() {
  CHECK(DeletionReady());
  CHECK(native_browsers_alive);
  --native_browsers_alive;
  NotifyNativeEngineOwnershipChanged();
}

// static
std::unique_ptr<BrowserWindow, BrowserWindowDeleter>
NativeBrowser::CreateWindow(BrowserWindowInterface* browser) {
  auto* native = From(browser);
  if (!native) {
    return nullptr;
  }
  CHECK(native->reservation_);
  return std::unique_ptr<BrowserWindow, BrowserWindowDeleter>(
      new NativeBrowserWindow(*native->browser_,
                              native->reservation_->Bind(*native->browser_)));
}

void NativeBrowser::OnRegistered() {
  auto reservation = std::exchange(reservation_, {});
  CHECK(reservation);
  CHECK(WindowOf(*browser_).AttachToNativeWindow(
      reservation->GetNativeWindow()));
}

bool NativeBrowser::DeletionReady() const {
  return deletion_ == Deletion::kReady;
}

bool NativeBrowser::DeferDeletion(base::OnceClosure retry) {
  if (DeletionReady()) {
    return false;
  }
  if (deletion_ == Deletion::kDraining) {
    return true;
  }
  deletion_ = Deletion::kDraining;
  PrepareAppKitBrowserForDeletion(
      *browser_,
      base::BindOnce(
          [](base::WeakPtr<BrowserWindowInterface> browser,
             base::OnceClosure retry) {
            // Never destroy the Browser on the service's final callback stack.
            base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
                FROM_HERE,
                base::BindOnce(
                    [](base::WeakPtr<BrowserWindowInterface> browser,
                       base::OnceClosure retry) {
                      auto* native = NativeBrowser::From(browser.get());
                      if (!native) {
                        return;
                      }
                      CHECK(native->deletion_ == Deletion::kDraining);
                      native->deletion_ = Deletion::kReady;
                      std::move(retry).Run();
                    },
                    browser, std::move(retry)));
          },
          browser_->GetWeakPtr(), std::move(retry)));
  return true;
}

// static
ui::ColorProviderSource* NativeBrowser::ColorProviderSource(
    BrowserWindowInterface* browser) {
  auto* native = From(browser);
  return native ? &WindowOf(*native->browser_) : nullptr;
}

// static
std::unique_ptr<BrowserWebContentsDelegate>
NativeBrowser::CreateWebContentsDelegate(
    BrowserWindowInterface* browser,
    ExclusiveAccessManager& exclusive_access_manager,
    chrome::BrowserCommandController& command_controller,
    UnloadController& unload_controller,
    web_app::AppBrowserController* app_browser_controller,
    BrowserWindow& window,
    DesktopBrowserWindowCapabilities& capabilities,
    BrowserUiController& browser_ui_controller) {
  return std::make_unique<NativeBrowserWebContentsDelegate>(
      browser, exclusive_access_manager, command_controller,
      unload_controller, app_browser_controller, window, capabilities,
      browser_ui_controller);
}

void NativeBrowser::SetAsDelegate(content::WebContents& contents,
                                  bool set_delegate) {
  auto* binding = NativePageBinding::FromWebContents(&contents);
  if (!binding) {
    if (!set_delegate) {
      return;
    }
    NativePageBinding::CreateForWebContents(&contents);
    binding = NativePageBinding::FromWebContents(&contents);
  }
  binding->SetBrowser(set_delegate ? &*browser_ : nullptr);
}

void NativeBrowser::OnWebContentsCreated(content::WebContents& contents) {
  // Navigate starts the first load before inserting the tab. Its delegate
  // callbacks during that load already belong to this Browser.
  contents.SetDelegate(BrowserWebContentsDelegate::From(&*browser_));
  SetAsDelegate(contents, true);
}

bool IsNativeBrowser(const BrowserWindowInterface* browser) {
  return !!NativeBrowser::From(browser);
}

size_t NativeBrowsersAlive() {
  return native_browsers_alive;
}

bool DeferNativeOTRProfileDestruction(Profile& profile) {
  if (!NativeProfileHasOperations(profile)) {
    return false;
  }
  auto& deferred = DeferredOTRProfiles();
  if (std::ranges::none_of(deferred, [&](const base::WeakPtr<Profile>& entry) {
        return entry.get() == &profile;
      })) {
    deferred.push_back(profile.GetWeakPtr());
  }
  return true;
}

void RetryNativeOTRProfileDestruction() {
  // Destruction below can reenter the registry and this function.
  auto deferred = std::exchange(DeferredOTRProfiles(), {});
  for (auto& profile : deferred) {
    if (!profile) {
      continue;
    }
    if (NativeProfileHasOperations(*profile)) {
      DeferredOTRProfiles().push_back(profile);
    } else if (ProfileBrowserCollection::GetForProfile(profile.get())
                   ->IsEmpty()) {
      BrowserManagerService::DestroyUnusedOTRProfile(*profile);
    }
  }
}

bool PrepareNativeBrowserWindow(BrowserWindowCreateParams& params) {
  Profile& profile = *params.profile;
  if (!GetNativeRoute(profile)) {
    if (GetNativeRoute(*profile.GetOriginalProfile())) {
      NativeCreationFailed(
          profile, "This private profile has no registered native window route");
      return false;
    }
    if (params.native_window) {
      LOG(ERROR) << "Native window reservation for an unregistered Profile";
      return false;
    }
    if (IsNativeBrowser(params.opener)) {
      LOG(ERROR) << "Native opener cannot create an unregistered profile window";
      return false;
    }
    return true;
  }
  auto weak_profile = profile.GetWeakPtr();
  auto fail = [&](const std::string& message) {
    if (weak_profile) {
      NativeCreationFailed(*weak_profile, message);
    }
    return false;
  };
  if (params.window) {
    return fail("Native route cannot use a supplied Chrome window");
  }
  if (profile.GetProfilePolicyConnector()->IsManaged()) {
    return fail("Managed profile native data-protection UI is unavailable");
  }
  if (!params.native_window) {
    NativeWindowRequest request{
        profile, params.type,
        params.type == BrowserWindowInterface::TYPE_DEVTOOLS
            ? NativeWindowReason::kDevTools
            : (params.type == BrowserWindowInterface::TYPE_POPUP ||
               params.type == BrowserWindowInterface::TYPE_APP_POPUP)
                  ? NativeWindowReason::kPopup
                  : NativeWindowReason::kInternal,
        params.opener, nullptr, params.from_user_gesture};
    request.initial_bounds = params.initial_bounds;
    request.initial_origin_specified =
        params.initial_origin_specified ==
            BrowserWindowCreateParams::ValueSpecified::kSpecified ||
        (params.initial_origin_specified ==
             BrowserWindowCreateParams::ValueSpecified::kUnknown &&
         !params.initial_bounds.origin().IsOrigin());
    request.can_resize = params.can_resize;
    request.can_maximize = params.can_maximize;
    request.can_fullscreen = params.can_fullscreen;
    auto prepared = PrepareAppKitWindow(request);
    if (!prepared.has_value()) {
      return fail(prepared.error());
    }
    params.native_window = std::move(*prepared);
  }
  if (!weak_profile || !params.native_window ||
      !params.native_window->CanBind(profile, params.type)) {
    return fail("Native window reservation expired or was already consumed");
  }
  return true;
}

void PrepareNativeDevtoolsContents(content::WebContents* inspected,
                                   content::WebContents& tools) {
  if (!inspected ||
      inspected->GetBrowserContext() != tools.GetBrowserContext()) {
    return;
  }
  auto* tab = tabs::TabInterface::MaybeGetFromContents(inspected);
  auto* owner = tab ? tab->GetBrowserWindowInterface() : nullptr;
  if (!owner || owner->IsDeleteScheduled() || !IsNativeBrowser(owner)) {
    return;
  }
  auto* profile = Profile::FromBrowserContext(tools.GetBrowserContext());
  if (GetNativeRoute(*profile)) {
    PrepareNativeAuxiliaryServices(tools);
  }
}

std::optional<bool> HandleNativeDevtoolsKey(
    content::WebContents* inspected,
    content::WebContents* tools,
    const input::NativeWebKeyboardEvent& event) {
  if (!tools ||
      !GetNativeRoute(*Profile::FromBrowserContext(tools->GetBrowserContext()))) {
    return std::nullopt;
  }
  return HandleAppKitDevtoolsKey(inspected, *tools, event);
}
}  // namespace parc
