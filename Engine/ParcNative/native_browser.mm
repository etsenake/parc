// Copyright 2026 Parc contributors.
#include "native_browser.h"

#include <algorithm>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/ptr_util.h"
#include "base/no_destructor.h"
#include "base/supports_user_data.h"
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
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/window_open_disposition.h"
#include "native_appkit_host.h"
#include "native_auxiliary_services.h"
#include "native_browser_web_contents_delegate.h"
#include "native_browser_window.h"
#include "native_engine_entry.h"
#include "native_host_route.h"
#include "native_page_binding.h"
#include "native_profiles.h"
#include "parc/chromium_hooks.h"

namespace parc {
namespace {
ScopedNativeBrowserCreation* innermost_creation = nullptr;

std::vector<std::unique_ptr<NativeBrowser>>& Records() {
  static base::NoDestructor<std::vector<std::unique_ptr<NativeBrowser>>> value;
  return *value;
}

struct PendingWindow {
  std::unique_ptr<PreparedNativeWindow> window;
  NativePrivateSessionClaim claim;
};

std::vector<PendingWindow>& PendingWindows() {
  static base::NoDestructor<std::vector<PendingWindow>> value;
  return *value;
}

using PrivateSessions = PrivateSessionLedger<NativePrivateSessionHost>;

PrivateSessions& Sessions() {
  CHECK(NSThread.isMainThread);
  static NativePrivateSessionHost host;
  static base::NoDestructor<PrivateSessions> sessions(host);
  return *sessions;
}

bool session_retry_posted = false;

Profile* PrimaryOTRProfileOf(Profile& parent) {
  return parent.HasPrimaryOTRProfile()
             ? parent.GetPrimaryOTRProfile(false)
             : nullptr;
}

const char kPrivateSessionEndKey = 0;

void PostPrivateSessionEnded(base::WeakPtr<Profile> parent) {
  if (!base::SingleThreadTaskRunner::HasCurrentDefault()) {
    return;
  }
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<Profile> parent) {
                       if (parent) {
                         Sessions().Ended(parent.get());
                       }
                     },
                     std::move(parent)));
}

class PrivateSessionEnd final : public base::SupportsUserData::Data {
 public:
  explicit PrivateSessionEnd(Profile& parent) : parent_(parent.GetWeakPtr()) {}
  ~PrivateSessionEnd() override { PostPrivateSessionEnded(parent_); }

 private:
  const base::WeakPtr<Profile> parent_;
};

NativeBrowserWindow& WindowOf(Browser& browser) {
  return *static_cast<NativeBrowserWindow*>(browser.GetWindow());
}
}

DEFINE_USER_DATA(NativeBrowser);

void NativeBrowser::OnBrowserCreated(Browser& browser) {
  auto& pending = PendingWindows();
  CHECK(!pending.empty());
  PendingWindow entry = std::move(pending.back());
  pending.pop_back();
  if (entry.window) {
    Records().push_back(base::WrapUnique(new NativeBrowser(
        browser, std::move(entry.window), std::move(entry.claim))));
  }
}

void NativeBrowser::OnBrowserDestroyed(Browser& browser) {
  auto& records = Records();
  auto it = std::ranges::find(records, From(&browser),
                              &std::unique_ptr<NativeBrowser>::get);
  if (it == records.end()) {
    return;
  }
  std::unique_ptr<NativeBrowser> record = std::move(*it);
  records.erase(it);
}

NativeBrowser* NativeBrowser::From(BrowserWindowInterface* browser) {
  return browser ? Get(browser->GetUnownedUserDataHost()) : nullptr;
}

const NativeBrowser* NativeBrowser::From(
    const BrowserWindowInterface* browser) {
  return browser ? Get(browser->GetUnownedUserDataHost()) : nullptr;
}

NativeBrowser::NativeBrowser(Browser& browser,
                             std::unique_ptr<PreparedNativeWindow> reservation,
                             NativePrivateSessionClaim claim)
    : browser_(browser),
      reservation_(std::move(reservation)),
      claim_(std::move(claim)),
      scoped_data_holder_(browser.GetUnownedUserDataHost(), *this) {}

NativeBrowser::~NativeBrowser() {
  CHECK(deletion_ == Deletion::kReady);
  NotifyNativeEngineOwnershipChanged();
}

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

void NativeBrowser::OnRegistered(BrowserWindowInterface* browser) {
  auto* native = From(browser);
  if (!native) {
    return;
  }
  auto reservation = std::exchange(native->reservation_, {});
  auto claim = std::move(native->claim_);
  CHECK(reservation);
  CHECK(WindowOf(*native->browser_)
            .AttachToNativeWindow(reservation->GetNativeWindow()));
}

bool NativeBrowser::DeletionReady(const BrowserWindowInterface* browser) {
  const auto* native = From(browser);
  return !native || native->deletion_ == Deletion::kReady;
}

bool NativeBrowser::DeferDeletion(BrowserWindowInterface* browser) {
  auto* native = From(browser);
  if (!native || native->deletion_ == Deletion::kReady) {
    return false;
  }
  if (native->deletion_ == Deletion::kDraining) {
    return true;
  }
  native->deletion_ = Deletion::kDraining;
  PrepareAppKitBrowserForDeletion(
      *native->browser_,
      base::BindOnce(
          [](base::WeakPtr<BrowserWindowInterface> browser) {
            base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
                FROM_HERE,
                base::BindOnce(
                    [](base::WeakPtr<BrowserWindowInterface> browser) {
                      auto* native = NativeBrowser::From(browser.get());
                      if (!native) {
                        return;
                      }
                      CHECK(native->deletion_ == Deletion::kDraining);
                      native->deletion_ = Deletion::kReady;
                      BrowserManagerService::SynchronouslyDestroyBrowser(
                          browser.get());
                    },
                    browser));
          },
          native->browser_->GetWeakPtr()));
  return true;
}

ui::ColorProviderSource* NativeBrowser::ColorProviderSource(
    BrowserWindowInterface* browser) {
  auto* native = From(browser);
  return native ? &WindowOf(*native->browser_) : nullptr;
}

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

void NativeBrowser::SetAsDelegate(Browser& browser,
                                  content::WebContents& contents,
                                  bool set_delegate) {
  if (!From(&browser)) {
    return;
  }
  auto* binding = NativePageBinding::FromWebContents(&contents);
  if (!binding) {
    if (!set_delegate) {
      return;
    }
    NativePageBinding::CreateForWebContents(&contents);
    binding = NativePageBinding::FromWebContents(&contents);
  }
  binding->SetBrowser(set_delegate ? &browser : nullptr);
}

void NativeBrowser::OnWebContentsCreated(BrowserWindowInterface* browser,
                                         content::WebContents& contents) {
  auto* native = From(browser);
  if (!native) {
    return;
  }
  contents.SetDelegate(BrowserWebContentsDelegate::From(&*native->browser_));
  SetAsDelegate(*native->browser_, contents, true);
}

ScopedNativeBrowserCreation::ScopedNativeBrowserCreation(
    const BrowserWindowInterface* opener,
    std::unique_ptr<PreparedNativeWindow> window)
    : opener_(opener), window_(std::move(window)), outer_(innermost_creation) {
  innermost_creation = this;
}

ScopedNativeBrowserCreation::~ScopedNativeBrowserCreation() {
  CHECK_EQ(innermost_creation, this);
  innermost_creation = outer_;
}

ScopedNativeBrowserCreation* ScopedNativeBrowserCreation::Claim() {
  if (!innermost_creation || innermost_creation->claimed_) {
    return nullptr;
  }
  innermost_creation->claimed_ = true;
  return innermost_creation;
}

BrowserWindowInterface* CreateBrowserWindowFrom(
    BrowserWindowInterface* opener,
    BrowserWindowCreateParams params) {
  ScopedNativeBrowserCreation creation(opener, nullptr);
  return CreateBrowserWindow(std::move(params));
}

bool IsNativeBrowser(const BrowserWindowInterface* browser) {
  return !!NativeBrowser::From(browser);
}

size_t NativeBrowsersAlive() {
  return Records().size();
}

PrivateSessionUse NativePrivateSessionHost::Use(const Session& session) {
  if (!session) {
    return PrivateSessionUse::kGone;
  }
  if (session->ShutdownStarted()) {
    return PrivateSessionUse::kDying;
  }
  auto* browsers = ProfileBrowserCollection::GetForProfile(session.get());
  return browsers && !browsers->IsEmpty() ? PrivateSessionUse::kOpen
                                          : PrivateSessionUse::kIdle;
}

bool NativePrivateSessionHost::HasOperations(const Session& session) {
  return session && NativeProfileHasOperations(*session);
}

void NativePrivateSessionHost::Destroy(const Session& session) {
  if (session) {
    parc_hooks::DestroyUnusedOTRProfile(*session);
  }
}

void NativePrivateSessionHost::ScheduleRetry() {
  if (session_retry_posted ||
      !base::SingleThreadTaskRunner::HasCurrentDefault()) {
    return;
  }
  session_retry_posted = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce([] {
        session_retry_posted = false;
        Sessions().Retry();
      }));
}

bool NativePrivateSessionHost::Dying(Key parent) {
  Profile* off_the_record = PrimaryOTRProfileOf(*parent);
  return off_the_record && off_the_record->ShutdownStarted();
}

void NativePrivateSessionHost::WatchEnd(Key parent) {
  Profile* off_the_record = PrimaryOTRProfileOf(*parent);
  if (!off_the_record) {
    PostPrivateSessionEnded(parent->GetWeakPtr());
    return;
  }
  if (!off_the_record->GetUserData(&kPrivateSessionEndKey)) {
    off_the_record->SetUserData(&kPrivateSessionEndKey,
                                std::make_unique<PrivateSessionEnd>(*parent));
  }
}

void NativePrivateSessionHost::Finish(Waiter waiter, bool settled) {
  std::move(waiter).Run(settled);
}

bool DeferNativeOTRProfileDestruction(Profile& profile) {
  return profile.IsOffTheRecord() &&
         Sessions().Defer(profile.GetOriginalProfile(), profile.GetWeakPtr());
}

void RetryNativeOTRProfileDestruction() {
  Sessions().Retry();
}

NativePrivateSessionClaim ClaimNativePrivateSession(Profile& parent) {
  CHECK(!parent.IsOffTheRecord());
  return Sessions().Acquire(&parent);
}

void AwaitNativePrivateSession(NativeProfileLeasePtr lease,
                               base::OnceCallback<void(Profile*)> ready) {
  CHECK(lease);
  Profile* parent = lease->profile();
  if (!parent || parent->IsOffTheRecord()) {
    std::move(ready).Run(nullptr);
    return;
  }
  Sessions().Await(
      ClaimNativePrivateSession(*parent),
      base::BindOnce(
          [](NativeProfileLeasePtr lease,
             base::OnceCallback<void(Profile*)> ready, bool settled) {
            std::move(ready).Run(settled ? lease->profile() : nullptr);
          },
          std::move(lease), std::move(ready)));
}

void NominateNativePrivateSession(Profile& off_the_record) {
  if (off_the_record.IsPrimaryOTRProfileWithRegularParent() &&
      !off_the_record.ShutdownStarted()) {
    Sessions().Nominate(off_the_record.GetOriginalProfile(),
                        off_the_record.GetWeakPtr());
  }
}

void SetNativePrivateSessionsClosing(bool closing) {
  Sessions().SetClosing(closing);
}

bool NativePrivateSessionsIdle() {
  return Sessions().Idle();
}

bool DeferNativePrivateOpen(
    content::WebContents& source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)>&
        navigation_handle_callback) {
  if (params.disposition != WindowOpenDisposition::OFF_THE_RECORD) {
    return false;
  }
  Profile* parent = Profile::FromBrowserContext(source.GetBrowserContext());
  Profile* off_the_record =
      parent->IsOffTheRecord() ? nullptr : PrimaryOTRProfileOf(*parent);
  if (!off_the_record || !off_the_record->ShutdownStarted()) {
    return false;
  }
  content::RenderFrameHost* frame = content::RenderFrameHost::FromID(
      params.source_render_process_id, params.source_render_frame_id);
  if (!frame) {
    frame = source.GetPrimaryMainFrame();
  }
  auto lease = NativeLeaseForProfile(*parent);
  if (!frame || content::WebContents::FromRenderFrameHost(frame) != &source ||
      !lease || lease->profile() != parent) {
    return false;
  }
  AwaitNativePrivateSession(
      std::move(lease),
      base::BindOnce(
          [](base::WeakPtr<content::WebContents> source,
             content::WeakDocumentPtr document, content::OpenURLParams params,
             base::OnceCallback<void(content::NavigationHandle&)> callback,
             Profile* parent) {
            content::RenderFrameHost* frame =
                document.AsRenderFrameHostIfValid();
            if (parent && source && frame && frame->IsActive() &&
                content::WebContents::FromRenderFrameHost(frame) ==
                    source.get() &&
                Profile::FromBrowserContext(source->GetBrowserContext()) ==
                    parent) {
              source->OpenURL(params, std::move(callback));
            }
          },
          source.GetWeakPtr(), frame->GetWeakDocumentPtr(), params,
          std::move(navigation_handle_callback)));
  return true;
}

bool PrepareNativeBrowserWindow(BrowserWindowCreateParams& params) {
  ScopedNativeBrowserCreation* const creation =
      ScopedNativeBrowserCreation::Claim();
  const BrowserWindowInterface* const opener =
      creation ? creation->opener_.get() : nullptr;
  std::unique_ptr<PreparedNativeWindow> window =
      creation ? std::move(creation->window_) : nullptr;
  Profile& profile = *params.profile;
  const bool private_session = profile.IsPrimaryOTRProfileWithRegularParent();
  if (!GetNativeRoute(profile) &&
      (!GetNativeRoute(*profile.GetOriginalProfile()) || !private_session ||
       window)) {
    if (GetNativeRoute(*profile.GetOriginalProfile())) {
      NativeCreationFailed(
          profile, "This private profile has no registered native window route");
      NominateNativePrivateSession(profile);
      return false;
    }
    if (window) {
      LOG(ERROR) << "Native window reservation for an unregistered Profile";
      return false;
    }
    if (IsNativeBrowser(opener)) {
      LOG(ERROR) << "Native opener cannot create an unregistered profile window";
      return false;
    }
    PendingWindows().push_back({});
    return true;
  }
  auto weak_profile = profile.GetWeakPtr();
  auto fail = [&](const std::string& message) {
    if (weak_profile) {
      NativeCreationFailed(*weak_profile, message);
    }
    if (weak_profile && private_session) {
      NominateNativePrivateSession(*weak_profile);
    }
    return false;
  };
  if (profile.IsOffTheRecord() && profile.ShutdownStarted()) {
    return fail("This private session is closing");
  }
  NativePrivateSessionClaim claim;
  if (private_session) {
    claim = ClaimNativePrivateSession(*profile.GetOriginalProfile());
  }
  if (params.window) {
    return fail("Native route cannot use a supplied Chrome window");
  }
  if (profile.GetProfilePolicyConnector()->IsManaged()) {
    return fail("Managed profile native data-protection UI is unavailable");
  }
  if (!window) {
    NativeWindowRequest request{
        profile, params.type,
        params.type == BrowserWindowInterface::TYPE_DEVTOOLS
            ? NativeWindowReason::kDevTools
            : (params.type == BrowserWindowInterface::TYPE_POPUP ||
               params.type == BrowserWindowInterface::TYPE_APP_POPUP)
                  ? NativeWindowReason::kPopup
                  : NativeWindowReason::kInternal,
        opener, nullptr, params.from_user_gesture};
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
    window = std::move(*prepared);
  }
  if (!weak_profile || !window || !window->CanBind(profile, params.type)) {
    return fail("Native window reservation expired or was already consumed");
  }
  PendingWindows().push_back({std::move(window), std::move(claim)});
  return true;
}

void SkipNativeBrowserAdmission() {
  PendingWindows().push_back({});
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
}
