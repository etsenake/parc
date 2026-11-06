// Copyright 2026 Parc contributors.
#include <map>
#include <algorithm>
#include <atomic>
#include <memory>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "base/check.h"
#include "cef/libcef/browser/parc_native/native_internal_urls.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/callback_list.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "cef/include/cef_browser_process_handler.h"
#include "cef/include/cef_command_line.h"
#include "cef/include/cef_keyboard_handler.h"
#include "cef/include/cef_life_span_handler.h"
#include "cef/include/cef_permission_handler.h"
#include "cef/include/cef_request_handler.h"
#include "cef/include/cef_resource_bundle_handler.h"
#include "cef/include/cef_resource_request_handler.h"
#include "cef/libcef/browser/browser_host_base.h"
#include "cef/libcef/browser/chrome/chrome_browser_host_impl.h"
#include "cef/libcef/browser/chrome/chrome_browser_context.h"
#include "chrome/browser/prefs/incognito_mode_prefs.h"
#include "cef/libcef/browser/context.h"
#include "cef/libcef/browser/parc_native/video_overlay_window.h"
#include "cef/libcef/browser/request_context_impl.h"
#include "cef/libcef/common/net/scheme_registration.h"
#include "chrome/browser/devtools/devtools_ui_controller.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/download/download_prefs.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/profiles/profile_destroyer.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/nuke_profile_directory_utils.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/focus/browser_focus_controller.h"
#include "chrome/browser/ui/hung_renderer/hung_renderer_core.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/storage_partition.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/webui/current_channel_logo.h"
#include "chrome/common/pref_names.h"
#include "chrome/grit/branded_strings.h"
#include "chrome/grit/generated_resources.h"
#include "chrome/grit/theme_resources.h"
#include "components/prefs/pref_service.h"
#include "components/tabs/public/tab_interface.h"
#include "services/network/public/mojom/cookie_manager.mojom.h"
#include "components/translate/core/browser/translate_pref_names.h"
#include "content/public/browser/browser_accessibility_state.h"
#include "content/public/browser/scoped_accessibility_mode.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "downloads.h"
#include "file_dialog.h"
#include "native_appkit_host.h"
#include "native_shortcuts.h"
#include "native_link_routing.h"
#include "native_appkit_page.h"
#include "native_search.h"
#include "native_profile_removal.h"
#include "native_capture_picker.h"
#include "native_gmc_presentation.h"
#include "native_browser_window.h"
#import "native_download_arrival.h"
#include "native_chrome_platform_delegate.h"
#include "native_engine_entry.h"
#include "native_host_route.h"
#include "native_startup_policy.h"
#include "native_page_retirement.h"
#include "pane_compositor.h"
#include "tab_transfer.h"
#include "window_security_reservation.h"
#include "url/url_constants.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/resource/resource_scale_factor.h"
#include "ui/gfx/mac/coordinate_conversion.h"

@interface PCNativePrivateDownloadContext () {
  base::WeakPtr<Profile> _downloadProfile;
}
- (instancetype)initWithProfile:(Profile&)profile;
- (void)invalidate;
@end

@interface PCNativeWindowRequest () {
 @public
  base::WeakPtr<Profile> _originalProfile;
}
- (instancetype)initWithRequest:(const parc::NativeWindowRequest&)request
                          kind:(PCNativeWindowKind)kind;
@end
@implementation PCNativeWindowRequest
@synthesize profilePath = _profilePath;
@synthesize kind = _kind;
@synthesize offTheRecord = _offTheRecord;
@synthesize source = _source;
@synthesize initialFrame = _initialFrame;
@synthesize initialOriginSpecified = _initialOriginSpecified;
@synthesize canResize = _canResize;
@synthesize canMaximize = _canMaximize;
@synthesize canFullscreen = _canFullscreen;
@synthesize userGesture = _userGesture;
- (instancetype)initWithRequest:(const parc::NativeWindowRequest&)request
                          kind:(PCNativeWindowKind)kind {
  self = [super init];
  if (self) {
    _profilePath = [base::SysUTF8ToNSString(request.profile.GetPath().value()) copy];
    _kind = kind;
    _offTheRecord = request.profile.IsOffTheRecord();
    _originalProfile = request.profile.GetWeakPtr();
    _source = parc::AppKitBindingForBrowser(request.source_browser);
    _initialFrame = gfx::ScreenRectToNSRect(request.initial_bounds);
    _initialOriginSpecified = request.initial_origin_specified;
    _canResize = request.can_resize;
    _canMaximize = request.can_maximize;
    _canFullscreen = request.can_fullscreen;
    _userGesture = request.user_gesture;
  }
  return self;
}
@end

namespace parc {
bool IsNativeDownloadDialogProfile(Profile& profile);
gfx::NativeWindow PrepareNativeDownloadDialogParent(Profile& profile);
bool IsNativeDownloadDialogParent(Profile& profile, gfx::NativeWindow window);
namespace {
NSError* Error(NSString* message) {
  return [NSError errorWithDomain:@"org.parc.independent-engine"
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}
NSMapTable<NSWindow*, PCNativeBrowserWindow*>* Windows() {
  static NSMapTable<NSWindow*, PCNativeBrowserWindow*>* value =
      [NSMapTable weakToStrongObjectsMapTable];
  return value;
}
__weak id<PCNativeBrowserApplicationClient> application_client;
// Retained Arc142 BrowserApp role/manual/enhanced hooks request basic mode3;
// full15 is a distinct scoped capability, not an unconditional startup policy.
// Current Chromium registers real NSWorkspace VoiceOver KVO on NSApp. Keep its
// complete/screen-reader mode separate from ordinary native AX inspection.
struct NativeAccessibility {
  bool initialized = false;
  bool stopped = false;
  bool basic_requested = false;
  bool voice_over = false;
  const void* observation_context = nullptr;
  std::unique_ptr<content::ScopedAccessibilityMode> basic;
  std::unique_ptr<content::ScopedAccessibilityMode> screen_reader;

  void Apply() {
    if (!initialized || stopped) {
      return;
    }
    auto* state = content::BrowserAccessibilityState::GetInstance();
    if (basic_requested && !basic) {
      basic = state->CreateScopedModeForProcess(ui::kAXModeBasic |
                                                ui::AXMode::kFromPlatform);
    }
    if (voice_over && !screen_reader) {
      screen_reader = state->CreateScopedModeForProcess(
          ui::kAXModeComplete | ui::AXMode::kFromPlatform |
          ui::AXMode::kScreenReader);
    } else if (!voice_over) {
      screen_reader.reset();
    }
  }
};
NativeAccessibility& Accessibility() {
  static base::NoDestructor<NativeAccessibility> value;
  return *value;
}
bool ready = false;
bool quitting = false;
bool close_transaction_active = false;
bool preparing_global_close = false;
size_t pending_creations = 0;
bool preparing_live_transfer = false;
std::vector<base::OnceClosure>& ReadyQueue() {
  static base::NoDestructor<std::vector<base::OnceClosure>> value;
  return *value;
}
struct ProfileRecord {
  CefRefPtr<CefRequestContext> context;
  base::WeakPtr<Profile> profile;
  std::vector<base::OnceCallback<
      void(Profile*, CefRefPtr<CefRequestContext>, NSError*)>>
      waiters;
  NSError* __strong failure;
};
std::map<std::string, ProfileRecord>& Profiles() {
  static base::NoDestructor<std::map<std::string, ProfileRecord>> value;
  return *value;
}
NSString* ProfilePath(Profile& profile) {
  return base::SysUTF8ToNSString(profile.GetPath().value());
}
}  // namespace
class BindingState {
 public:
  NSWindow* __weak window;
  id<PCNativeBrowserWindowClient> __weak client;
  std::map<Profile*, base::WeakPtr<BrowserWindowInterface>> browsers;
  NSString* __strong website_theme_stylesheet;
  // Immutable context kind; a dead OTR identity never falls back to its parent.
  bool private_mode = false;
  base::WeakPtr<Profile> private_profile;
  std::set<BrowserWindowInterface*> pending_close;
  std::vector<void (^)(BOOL)> close_callbacks;
  uint64_t ownership_epoch = 0;
  uint64_t selection_generation = 0;
  size_t pending_reservations = 0;
  // Page creations waiting for a delete-scheduled Browser to unregister.
  std::vector<base::OnceClosure> retirement_waiters;
  bool close_in_progress = false;
  bool close_approved = false;
  void FinishClose(bool allow) {
    if (!close_in_progress) {
      return;
    }
    close_in_progress = false;
    close_approved = allow;
    pending_close.clear();
    auto callbacks = std::move(close_callbacks);
    close_callbacks.clear();
    // Never release the shell/window owner from a Browser teardown callback
    // stack. All exact Browsers have unregistered before an approval arrives.
    for (auto callback : callbacks) {
      dispatch_async(dispatch_get_main_queue(), ^{
        callback(allow);
      });
    }
  }
};
}  // namespace parc

@interface PCNativeBrowserWindow ()
- (instancetype)initWithClient:(id<PCNativeBrowserWindowClient>)client;
- (parc::BindingState&)state;
@end

namespace parc {
namespace {
void NotifyEmptyBinding(PCNativeBrowserWindow* binding, bool aborted) {
  const uint64_t epoch = [binding state].ownership_epoch;
  dispatch_async(dispatch_get_main_queue(), ^{
    auto& state = [binding state];
    if (state.ownership_epoch != epoch || !state.browsers.empty() ||
        state.pending_reservations != 0) {
      return;
    }
    id<PCNativeBrowserWindowClient> client = binding.client;
    if (!binding.window || [client nativeBrowserWindow] != binding.window) {
      return;
    }
    if (aborted) {
      if ([client respondsToSelector:@selector
                  (nativeBrowserCreationReservationDidAbort:)]) {
        [client nativeBrowserCreationReservationDidAbort:binding];
      }
    } else if ([client respondsToSelector:@selector
                       (nativeBrowserDidReleaseLastBrowser:)]) {
      [client nativeBrowserDidReleaseLastBrowser:binding];
    }
  });
}
class PreparedAppKitWindow final : public PreparedNativeWindow {
 public:
  PreparedAppKitWindow(Profile& profile,
                       BrowserWindowInterface::Type type,
                       PCNativeBrowserWindow* binding)
      : PreparedNativeWindow(profile, type),
        binding_(binding),
        reserved_window_(binding.window),
        reserved_client_(binding.client),
        path_(ProfilePath(profile)) {
    CHECK(reserved_window_ && reserved_client_);
    CHECK_EQ(reserved_window_, [reserved_client_ nativeBrowserWindow]);
    ++[binding_ state].ownership_epoch;
    ++[binding_ state].pending_reservations;
  }
  ~PreparedAppKitWindow() override {
    if (!bound_) {
      --[binding_ state].pending_reservations;
      NotifyEmptyBinding(binding_, true);
    }
  }
  gfx::NativeWindow GetNativeWindow() const override {
    return gfx::NativeWindow(reserved_window_);
  }

 protected:
  std::unique_ptr<NativeBrowserWindowHost> BindHost(
      BrowserWindowInterface& browser) override {
    CHECK_EQ(reserved_window_, binding_.window);
    bound_ = true;
    --[binding_ state].pending_reservations;
    return CreateAppKitBrowserHost(browser, binding_, path_);
  }

 private:
  PCNativeBrowserWindow* __strong binding_;
  NSWindow* __strong reserved_window_;
  id<PCNativeBrowserWindowClient> __strong reserved_client_;
  NSString* __strong path_;
  bool bound_ = false;
};
class Provider final : public NativeWindowProvider {
 public:
  base::expected<std::unique_ptr<PreparedNativeWindow>, std::string> Prepare(
      const NativeWindowRequest& request) override {
    if (quitting || IsNativeProfileRemovalBlocked(
                        request.profile.GetOriginalProfile()->GetPath())) {
      return base::unexpected("The native application or Profile is closing.");
    }
    id<PCNativeBrowserApplicationClient> application = application_client;
    if (!application) {
      return base::unexpected("The native application is not registered.");
    }
    PCNativeWindowKind kind = PCNativeWindowKindBrowser;
    if (request.type == BrowserWindowInterface::TYPE_DEVTOOLS) {
      kind = PCNativeWindowKindDeveloperTools;
    } else if (request.type ==
               BrowserWindowInterface::TYPE_PICTURE_IN_PICTURE) {
      kind = PCNativeWindowKindPictureInPicture;
    } else if (request.type == BrowserWindowInterface::TYPE_POPUP ||
               request.type == BrowserWindowInterface::TYPE_APP_POPUP) {
      kind = PCNativeWindowKindPopup;
    }
    PCNativeWindowRequest* descriptor =
        [[PCNativeWindowRequest alloc] initWithRequest:request kind:kind];
    id<PCNativeBrowserWindowClient> client =
        [application prepareNativeWindowForRequest:descriptor];
    if (!client) {
      return base::unexpected(
          "The application declined the new native window.");
    }
    NSError* error = nil;
    PCNativeBrowserWindow* binding =
        [PCNativeBrowserApplication registerWindowClient:client error:&error];
    if (!binding) {
      return base::unexpected(
          base::SysNSStringToUTF8(error.localizedDescription));
    }
    if ([binding state].close_in_progress || [binding state].close_approved) {
      return base::unexpected("The supplied native window is closing.");
    }
    if ([binding state].private_mode != request.profile.IsOffTheRecord() ||
        ([binding state].private_mode &&
         [binding state].private_profile.get() != &request.profile)) {
      return base::unexpected("The supplied window belongs to another browsing context.");
    }
    auto found = [binding state].browsers.find(&request.profile);
    if (found != [binding state].browsers.end() && found->second) {
      return base::unexpected(
          "This physical window already owns a Browser for this Profile.");
    }
    return std::make_unique<PreparedAppKitWindow>(request.profile, request.type,
                                                  binding);
  }
  std::unique_ptr<BrowserFocusController> CreateFocusController(
      BrowserWindowInterface& browser) override {
    return CreateAppKitFocusController(browser);
  }
  std::unique_ptr<DevtoolsUIController> CreateDevtoolsController(
      BrowserWindowInterface& browser) override {
    return CreateAppKitDevtoolsController(browser);
  }
  bool HandleDevtoolsKey(content::WebContents* inspected,
                         content::WebContents& tools,
                         const input::NativeWebKeyboardEvent& event) override {
    return HandleAppKitDevtoolsKey(inspected, tools, event);
  }
  void PageOwnerChanged(BrowserWindowInterface* browser,
                        content::WebContents& contents) override {
    AppKitPageOwnerChanged(browser, contents);
  }
  void PrepareBrowserForDeletion(BrowserWindowInterface& browser,
                                 base::OnceClosure completion) override {
    PrepareAppKitBrowserForDeletion(browser, std::move(completion));
  }
  void CreationFailed(Profile& profile, const std::string& reason) override {
    for (PCNativeBrowserWindow* binding in Windows().objectEnumerator) {
      if ([binding state].browsers.contains(&profile)) {
        [binding.client nativeBrowser:binding
                     didFailWithError:Error(base::SysUTF8ToNSString(reason))];
      }
    }
  }
};
//
// crashProcess/wait forward to that object (Core 0x68d4f04/0x68d4f18).
//
// AppKit sheet is an explicit presentation adaptation for the independent
// engine, retaining CEF's genuine hang timer and renderer termination actions.
class NativeHungRenderer final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<NativeHungRenderer> {
 public:
  ~NativeHungRenderer() override { Finish(false, false); }

  void Show(CefRefPtr<CefUnresponsiveProcessCallback> callback) {
    // CEF detaches its previous callback before delivering a replacement.
    const auto alive = weak_factory_.GetWeakPtr();
    Finish(false, false);
    if (!alive) {
      callback->Wait();
      return;
    }
    callback_ = std::move(callback);
    auto* contents = web_contents();
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    PCNativePage* page = ExistingNativePage(contents);
    auto* frame = contents->GetPrimaryMainFrame();
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    NSWindow* window = page.nativeView.window;
    if (!tab || !tab->IsActivated() || !frame || !frame->IsActive() ||
        !browser || browser->IsDeleteScheduled() || !window ||
        !window.isKeyWindow || !window.visible || window.miniaturized ||
        page.nativeView.hiddenOrHasHiddenAncestor || IsNativePageRetiring(page) ||
        window.attachedSheet || PCNativeWindowHasSecurityReservation(window)) {
      // Background/obscured pages keep their real timer. They never steal a
      // different page's window or silently terminate a shared process.
      Finish(true, false);
      return;
    }
    browser_ = browser->GetWeakPtr();
    document_ = frame->GetWeakDocumentPtr();
    window_ = window;
    const auto weak = weak_factory_.GetWeakPtr();
    deactivate_ = tab->RegisterWillDeactivate(base::BindRepeating(
        [](base::WeakPtr<NativeHungRenderer> self, tabs::TabInterface*) {
          if (self) self->Finish(true, false);
        }, weak));
    detach_ = tab->RegisterWillDetach(base::BindRepeating(
        [](base::WeakPtr<NativeHungRenderer> self, tabs::TabInterface*,
           tabs::TabInterface::DetachReason) {
          if (self) self->Finish(true, false);
        }, weak));
    discard_ = tab->RegisterWillDiscardContents(base::BindRepeating(
        [](base::WeakPtr<NativeHungRenderer> self, tabs::TabInterface*,
           content::WebContents*, content::WebContents*) {
          if (self) self->Finish(false, false);
        }, weak));
    // Acquiring a reservation can synchronously dismiss another native owner.
    auto reservation = [PCNativeWindowSecurityReservation acquireForWindow:window];
    if (!weak || !OwnerCurrent() || !reservation.isOnlyReservation) {
      [reservation invalidate];
      if (weak) Finish(true, false);
      return;
    }
    reservation_ = reservation;
    observations_ = [NSMutableArray array];
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
                                      NSWindowDidMiniaturizeNotification,
                                      PCNativeWindowSecurityStateChanged]) {
      [observations_ addObject:[NSNotificationCenter.defaultCenter
          addObserverForName:name object:window queue:nil
          usingBlock:^(NSNotification*) {
            if (weak && (name != PCNativeWindowSecurityStateChanged ||
                         !weak->OwnerCurrent() ||
                         !weak->reservation_.isOnlyReservation)) {
              weak->Finish(true, false);
            }
          }]];
    }
    //
    // it and its Renderer.HungRendererDialog.UserAction histogram). Its text:
    // the plural title and body, then each page sharing the hung process,
    // with Wait as the default (OK) button and Exit Page(s) as Cancel.
    // The page list approximates the hung process by the main frame's.
    content::RenderProcessHost* process = frame->GetProcess();
    const std::vector<content::WebContents*> hung =
        GetHungWebContentsList(contents, process);
    const int count = static_cast<int>(hung.size());
    alert_ = [[NSAlert alloc] init];
    alert_.alertStyle = NSAlertStyleWarning;
    alert_.messageText = base::SysUTF16ToNSString(l10n_util::GetPluralStringFUTF16(
        IDS_BROWSER_HANGMONITOR_RENDERER_TITLE, count));
    NSMutableString* info = [base::SysUTF16ToNSString(
        l10n_util::GetPluralStringFUTF16(IDS_BROWSER_HANGMONITOR_RENDERER, count))
        mutableCopy];
    [info appendString:@"\n"];
    for (content::WebContents* affected : hung) {
      [info appendFormat:@"\n%@", base::SysUTF16ToNSString(
          GetHungWebContentsTitle(affected, process))];
    }
    alert_.informativeText = info;
    [alert_ addButtonWithTitle:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(
        IDS_BROWSER_HANGMONITOR_RENDERER_WAIT))];
    [alert_ addButtonWithTitle:base::SysUTF16ToNSString(
        l10n_util::GetPluralStringFUTF16(IDS_BROWSER_HANGMONITOR_RENDERER_END, count))];
    alert_.buttons.firstObject.keyEquivalent = @"\r";
    const uint64_t generation = generation_;
    [alert_ beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
      if (!weak || weak->generation_ != generation) return;
      const bool terminate = response == NSAlertSecondButtonReturn &&
          weak->OwnerCurrent() && weak->reservation_.isOnlyReservation;
      weak->Finish(true, terminate);
    }];
  }

  void Responsive() { Finish(false, false); }

 private:
  friend class content::WebContentsUserData<NativeHungRenderer>;
  explicit NativeHungRenderer(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<NativeHungRenderer>(*contents) {}

  bool OwnerCurrent() const {
    auto* contents = web_contents();
    auto* frame = document_.AsRenderFrameHostIfValid();
    auto* tab = contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
    PCNativePage* page = ExistingNativePage(contents);
    return callback_ && contents && !contents->IsBeingDestroyed() &&
        frame && frame->IsActive() && frame == contents->GetPrimaryMainFrame() &&
        browser_ && !browser_->IsDeleteScheduled() && browser_->GetWindow() &&
        tab && tab->IsActivated() && tab->GetBrowserWindowInterface() == browser_.get() &&
        window_ && window_.visible && !window_.miniaturized &&
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window_ &&
        page.nativeView.window == window_ && !page.nativeView.hiddenOrHasHiddenAncestor &&
        !IsNativePageRetiring(page);
  }

  void Finish(bool restart_timer, bool terminate) {
    ++generation_; // Old AppKit completion blocks cannot consume a new request.
    auto callback = std::move(callback_);
    callback_ = nullptr;
    auto browser = browser_;
    auto document = document_;
    auto contents = web_contents() ? web_contents()->GetWeakPtr()
                                  : base::WeakPtr<content::WebContents>();
    NSWindow* __weak window = window_;
    NSAlert* alert = alert_;
    auto reservation = reservation_;
    alert_ = nil;
    reservation_ = nil;
    browser_.reset();
    document_ = {};
    window_ = nil;
    deactivate_ = {};
    detach_ = {};
    discard_ = {};
    for (id observer in observations_) {
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
    observations_ = nil;
    // All state is retired before AppKit/reservation callbacks can reenter or
    // destroy this object. Only local values are used after these operations.
    if (alert.window.sheetParent) {
      [alert.window.sheetParent endSheet:alert.window returnCode:NSModalResponseCancel];
    }
    [alert.window orderOut:nil];
    [reservation invalidate];
    if (!callback || !restart_timer) return;
    auto* tab = contents ? tabs::TabInterface::MaybeGetFromContents(contents.get()) : nullptr;
    auto* frame = document.AsRenderFrameHostIfValid();
    PCNativePage* page = ExistingNativePage(contents.get());
    const bool current = contents && !contents->IsBeingDestroyed() && frame &&
        frame->IsActive() && frame == contents->GetPrimaryMainFrame() && browser &&
        !browser->IsDeleteScheduled() && browser->GetWindow() && tab &&
        tab->IsActivated() && tab->GetBrowserWindowInterface() == browser.get() &&
        window && window.visible && !window.miniaturized &&
        browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window &&
        page.nativeView.window == window && !IsNativePageRetiring(page);
    if (terminate && current) callback->Terminate();
    else callback->Wait();
  }

  void PrimaryPageChanged(content::Page&) override { Finish(false, false); }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    Finish(false, false);
  }
  void WebContentsDestroyed() override { Finish(false, false); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) Finish(true, false);
  }
  CefRefPtr<CefUnresponsiveProcessCallback> callback_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  content::WeakDocumentPtr document_;
  NSWindow* __weak window_ = nil;
  NSAlert* __strong alert_ = nil;
  PCNativeWindowSecurityReservation* __strong reservation_ = nil;
  NSMutableArray* __strong observations_ = nil;
  base::CallbackListSubscription deactivate_, detach_, discard_;
  uint64_t generation_ = 0;
  base::WeakPtrFactory<NativeHungRenderer> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(NativeHungRenderer);

class NativeClient final : public CefClient,
                           public CefDisplayHandler,
                           public CefKeyboardHandler,
                           public CefLifeSpanHandler,
                           public CefPermissionHandler,
                           public CefRequestHandler,
                           public CefResourceRequestHandler {
 public:
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override {
    if (!frame || !frame->IsMain()) return;
    auto host = CefBrowserHostBase::FromBrowser(browser);
    if (auto* contents = host ? host->GetWebContents() : nullptr)
      UpdateNativeLinkURL(*contents, GURL(url.ToString()));
  }
  void OnStatusMessage(CefRefPtr<CefBrowser> browser,
                       const CefString& value) override {
    auto host = CefBrowserHostBase::FromBrowser(browser);
    if (auto* contents = host ? host->GetWebContents() : nullptr) {
      // CEF resolves the callback from the original source WebContents. Never
      // route through the selected tab or replace Chromium's mouse processing.
      const GURL target(value.ToString());
      UpdateNativePageStatusText(*contents, base::SysUTF8ToNSString(
          target.SchemeIs("chrome") ? PublicInternalURL(target).spec()
                                   : value.ToString()));
    }
  }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override {
    return this;
  }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame> frame,
      CefRefPtr<CefRequest> request,
      bool is_navigation,
      bool,
      const CefString&,
      bool&) override {
    // Only OnProtocolExecution is needed, and CEF reaches it only for schemes
    // the network stack doesn't handle. A handler on a web request makes CEF
    // load its cookies through a UI-thread round trip before the request
    // starts, so a busy main thread held every navigation (measured up to
    // 1.4 s for a new tab); without one the network service sends it at once.
    return is_navigation && browser && frame && frame->IsValid() && request &&
                   !scheme::IsInternalHandledScheme(
                       GURL(request->GetURL().ToString()).scheme())
               ? this
               : nullptr;
  }
  void OnProtocolExecution(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefFrame> frame,
                           CefRefPtr<CefRequest>,
                           bool& allow_os_execution) override {
    // In the pinned Chrome runtime this enables HandleExternalProtocolHelper,
    // which revalidates the captured WeakDocumentPtr and calls Chrome's genuine
    // sandbox/scheme/enterprise/user-gesture/default-app policy path. This is
    // not platform_util::OpenExternal and does not itself grant a launch.
    allow_os_execution = browser && frame && frame->IsValid();
  }

  void OnBeforeClose(CefRefPtr<CefBrowser>) override {
    NotifyNativeEngineOwnershipChanged();
  }
  bool OnRequestMediaAccessPermission(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame>,
      const CefString&,
      uint32_t requested_permissions,
      CefRefPtr<CefMediaAccessCallback> callback) override {
    // Chromium owns origin/policy checks, OS permission and capture-device
    // construction. The registered native picker handles display selection.
    return false;
  }
  bool OnShowPermissionPrompt(
      CefRefPtr<CefBrowser> browser,
      uint64_t,
      const CefString&,
      uint32_t,
      CefRefPtr<CefPermissionPromptCallback> callback) override {
    callback->Continue(CEF_PERMISSION_RESULT_IGNORE);
    // A native page must have been intercepted by the typed factory. Do not
    // fall back to a generic monostate grant if that ownership route is absent.
    ReportUnavailable(browser, @"Native permission host is unavailable");
    return true;
  }
  bool OnSelectClientCertificate(
      CefRefPtr<CefBrowser> browser,
      bool,
      const CefString&,
      int,
      const X509CertificateList&,
      CefRefPtr<CefSelectClientCertificateCallback> callback) override {
    // Preserve Chrome enterprise filtering and auto-selection before the
    // page-owned native selector factory. Do not consume the CEF callback.
    return false;
  }
  bool OnRenderProcessUnresponsive(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefUnresponsiveProcessCallback> callback) override {
    auto host = CefBrowserHostBase::FromBrowser(browser);
    auto* contents = host ? host->GetWebContents() : nullptr;
    if (!contents || contents->IsBeingDestroyed()) {
      callback->Wait();
      return true;
    }
    NativeHungRenderer::CreateForWebContents(contents);
    NativeHungRenderer::FromWebContents(contents)->Show(std::move(callback));
    return true;
  }
  void OnRenderProcessResponsive(CefRefPtr<CefBrowser> browser) override {
    auto host = CefBrowserHostBase::FromBrowser(browser);
    auto* contents = host ? host->GetWebContents() : nullptr;
    if (auto* dialog = contents ? NativeHungRenderer::FromWebContents(contents) : nullptr) {
      dialog->Responsive();
    }
  }
  // CefRequestHandler's documented defaults cancel credentials and invalid
  // TLS requests. Native security presenters remain open capability gates.
  void ReportUnavailable(CefRefPtr<CefBrowser> browser, NSString* capability) {
    auto base = CefBrowserHostBase::FromBrowser(browser);
    auto host = base ? ChromeBrowserHostImpl::GetBrowserForContents(
                           base->GetWebContents())
                     : nullptr;
    PCNativeBrowserWindow* binding =
        host ? AppKitBindingForBrowser(host->browser()) : nil;
    [binding.client nativeBrowser:binding capabilityUnavailable:capability];
  }
  bool OnKeyEvent(CefRefPtr<CefBrowser> browser,
                  const CefKeyEvent& event,
                  CefEventHandle os_event) override {
    // Only this recovered menu bridge runs here. If not consumed, CEF's
    // original Browser delegate runs DevTools, then the native action registry.
    NSEvent* native = (__bridge NSEvent*)os_event;
    auto host = CefBrowserHostBase::FromBrowser(browser);
    auto* contents = host ? host->GetWebContents() : nullptr;
    if (contents && event.type == KEYEVENT_RAWKEYDOWN) {
      if (auto result = HandleUnhandledNativeShortcut(*contents, native))
        return *result;
    }
    return event.type == KEYEVENT_RAWKEYDOWN &&
           native.type == NSEventTypeKeyDown &&
           (native.modifierFlags &
            NSEventModifierFlagDeviceIndependentFlagsMask) &&
           [NSApp.mainMenu performKeyEquivalent:native];
  }

 private:
  IMPLEMENT_REFCOUNTING(NativeClient);
};
CefRefPtr<CefClient> Client() {
  static base::NoDestructor<CefRefPtr<CefClient>> client(new NativeClient);
  return *client;
}
std::shared_ptr<NativeWindowProvider> ProviderInstance() {
  static base::NoDestructor<std::shared_ptr<Provider>> provider(
      std::make_shared<Provider>());
  return *provider;
}
NSDictionary* DownloadValues(const NativeDownloadSnapshot& snapshot,
                             bool off_the_record) {
NSString* status = @"pending";
switch (snapshot.state) {
  case download::DownloadItem::IN_PROGRESS:
    status = snapshot.paused ? @"paused" : @"downloading";
    break;
  case download::DownloadItem::COMPLETE:
    status = @"completed";
    break;
  case download::DownloadItem::CANCELLED:
    status = @"cancelled";
    break;
  case download::DownloadItem::INTERRUPTED:
    status = @"failed";
    break;
  case download::DownloadItem::MAX_DOWNLOAD_STATE:
    CHECK(false);
}
return @{
  @"offTheRecord" : @(off_the_record),
    @"id" : base::SysUTF8ToNSString(snapshot.guid),
  @"profilePath" :
      base::SysUTF8ToNSString(snapshot.profile_path.value()),
  @"name" : base::SysUTF8ToNSString(snapshot.name),
  @"path" : base::SysUTF8ToNSString(snapshot.path.value()),
  @"sourceURL" : base::SysUTF8ToNSString(snapshot.url),
  @"sourceDomain" : base::SysUTF8ToNSString(snapshot.source_domain),
  @"mimeType" : base::SysUTF8ToNSString(snapshot.mime_type),
  @"timeRemaining" : @(snapshot.time_remaining_seconds),
  @"itemIdentity" : base::SysUTF8ToNSString(snapshot.item_identity),
  @"startedAt" : @(snapshot.started_at),
  @"canOpen" : @(snapshot.can_open),
  @"canReveal" : @(snapshot.can_reveal),
  @"canRemove" : @(snapshot.can_remove),
  @"canCopyFile" : @(snapshot.can_copy_file),
  @"canToggleOpen" : @(snapshot.can_toggle_open),
  @"openWhenComplete" : @(snapshot.open_when_complete),
  @"fileMissing" : @(snapshot.file_missing),
  @"status" : status,
  @"receivedBytes" : @(snapshot.received),
  @"totalBytes" : @(snapshot.total),
  @"errorCode" : @(snapshot.interrupt_reason),
  @"available" : @(snapshot.available),
  @"removed" : @(snapshot.removed),
  @"requiresReview" : @(snapshot.requires_review),
  @"canPause" : @(snapshot.can_pause),
  @"canResume" : @(snapshot.can_resume),
  @"canCancel" : @(snapshot.can_cancel),
  @"canReview" : @(snapshot.can_review),
  @"canRetry" : @(snapshot.can_retry),
  @"statusText" : base::SysUTF16ToNSString(snapshot.status_text)
};
}

Profile* PrivateDownloadsProfile(PCNativeBrowserWindow* binding) {
  if (!binding || !binding.window || [binding.client nativeBrowserWindow] != binding.window)
    return nullptr;
  Profile* original = [binding state].private_profile.get();
  if (!original || NativePrivateProfileForWindow(binding, ProfilePath(*original)) != original)
    return nullptr;
  for (const auto& [profile, browser] : [binding state].browsers) {
    if (profile == original && browser && browser->GetProfile() == original)
      return original;
  }
  return nullptr;
}

NSMutableDictionary<NSString*, PCNativePrivateDownloadContext*>* PrivateDownloadContexts() {
  static NSMutableDictionary<NSString*, PCNativePrivateDownloadContext*>* contexts = [NSMutableDictionary dictionary];
  return contexts;
}

// One observation per actual OTR context. This does not retain the Profile or
// keep an Incognito Browser alive. Shared presentation retains only its lease.
class PrivateDownloadLifetime final : public base::SupportsUserData::Data,
                                      public ProfileObserver {
 public:
  explicit PrivateDownloadLifetime(Profile& profile) : profile_(&profile),
      context_([[PCNativePrivateDownloadContext alloc] initWithProfile:profile]) {
    profile_->AddObserver(this);
    PrivateDownloadContexts()[context_.identifier] = context_;
  }
  ~PrivateDownloadLifetime() override {
    if (profile_) profile_->RemoveObserver(this);
    [context_ invalidate];
    [PrivateDownloadContexts() removeObjectForKey:context_.identifier];
  }
  PCNativePrivateDownloadContext* context() const { return context_; }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    CHECK_EQ(profile_, profile);
    NSMutableArray<PCNativeBrowserWindow*>* owners = [NSMutableArray array];
    for (PCNativeBrowserWindow* binding in Windows().objectEnumerator.allObjects) {
      if ([binding state].private_profile.get() == profile) [owners addObject:binding];
    }
    profile_->RemoveObserver(this);
    profile_ = nullptr;
    [context_ invalidate];
    [PrivateDownloadContexts() removeObjectForKey:context_.identifier];
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce([](NSArray<PCNativeBrowserWindow*>* owners,
                                   PCNativePrivateDownloadContext* context) {
          id<PCNativeBrowserApplicationClient> app = application_client;
          if ([app respondsToSelector:@selector(nativeApplicationPrivateDownloadContextDidInvalidate:)])
            [app nativeApplicationPrivateDownloadContextDidInvalidate:context];
          for (PCNativeBrowserWindow* binding in owners) {
            id<PCNativeBrowserWindowClient> client = binding.client;
            if (binding.isPrivateBrowsing && binding.window &&
                [client nativeBrowserWindow] == binding.window &&
                [client respondsToSelector:@selector(nativeBrowserPrivateDownloadsDidInvalidate:)])
              [client nativeBrowserPrivateDownloadsDidInvalidate:binding];
          }
        }, [owners copy], context_));
  }
 private:
  raw_ptr<Profile> profile_;
  PCNativePrivateDownloadContext* __strong context_;
};
const char kPrivateDownloadLifetime = 0;
void InstallPrivateDownloads(Profile& profile) {
  CHECK(profile.IsOffTheRecord());
  if (!profile.GetUserData(&kPrivateDownloadLifetime))
    profile.SetUserData(&kPrivateDownloadLifetime,
                       std::make_unique<PrivateDownloadLifetime>(profile));
  NativeDownloads::Install(profile, base::BindRepeating(
      [](base::WeakPtr<Profile> original, NativeDownloadSnapshot snapshot) {
        if (!original || original->ShutdownStarted()) return;
        NSDictionary* values = DownloadValues(snapshot, true);
        auto* lifetime = static_cast<PrivateDownloadLifetime*>(original->GetUserData(&kPrivateDownloadLifetime));
        id<PCNativeBrowserApplicationClient> app = application_client;
        if (lifetime && [app respondsToSelector:@selector(nativeApplicationPrivateDownloadDidUpdate:context:)])
          [app nativeApplicationPrivateDownloadDidUpdate:values context:lifetime->context()];
        if (!original || original->ShutdownStarted()) return;
        // Snapshot the bindings; a client may close a window during delivery.
        for (PCNativeBrowserWindow* binding in Windows().objectEnumerator.allObjects) {
          if (!original || original->ShutdownStarted()) return;
          if (PrivateDownloadsProfile(binding) != original.get()) continue;
          id<PCNativeBrowserWindowClient> client = binding.client;
          if ([client respondsToSelector:@selector(nativeBrowser:privateDownloadDidUpdate:)])
            [client nativeBrowser:binding privateDownloadDidUpdate:values];
        }
      }, profile.GetWeakPtr()), base::BindRepeating(
      [](base::WeakPtr<Profile> original, NativeDownloadSnapshot snapshot,
         content::WeakDocumentPtr document) {
        if (!original || original->ShutdownStarted()) return;
        auto* lifetime = static_cast<PrivateDownloadLifetime*>(
            original->GetUserData(&kPrivateDownloadLifetime));
        if (!lifetime) return;
        PresentNativeDownloadArrival(*original, std::move(snapshot),
            std::move(document), lifetime->context().identifier);
      }, profile.GetWeakPtr()));
}

//
// download.prompt_for_download with false (core 0x2dfd310-0x2dfd334), and the
// main binary writes it only from Settings' Download Location "Ask every time"
//
// from ad4055a until this change stored true as a user value in every
// persistent Profile that had none. That value cannot be told apart from a
// choice, so each Profile directory gets exactly one pass that clears a stored
// true back to Chromium's default. A stored false is kept, and later choices
// stay authoritative because the pass never repeats. Only the user layer is
// cleared: a managed value stays in force, and a seeded true cannot resurface
// when a policy is lifted. The pass is recorded only once the cleared value is
// on disk, since Chromium batches pref writes and a crash before that write
// must not strand the seeded true behind a completed marker.
NSString* const kSeededPromptCleared = @"parc.downloads.seededPromptCleared.v1";
void ClearSeededDownloadPrompt(Profile& profile) {
  NSString* directory = base::SysUTF8ToNSString(profile.GetPath().value());
  if (!directory.length || [[NSUserDefaults.standardUserDefaults
          stringArrayForKey:kSeededPromptCleared] containsObject:directory])
    return;
  PrefService* prefs = profile.GetPrefs();
  const base::Value* stored = prefs->GetUserPrefValue(prefs::kPromptForDownload);
  if (stored && stored->is_bool() && stored->GetBool()) {
    prefs->ClearPref(prefs::kPromptForDownload);
  }
  prefs->CommitPendingWrite(base::BindOnce([](NSString* path) {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSArray<NSString*>* cleared =
        [defaults stringArrayForKey:kSeededPromptCleared] ?: @[];
    if (![cleared containsObject:path])
      [defaults setObject:[cleared arrayByAddingObject:path]
                   forKey:kSeededPromptCleared];
  }, directory));
}

class ContextHandler final : public CefRequestContextHandler {
 public:
  explicit ContextHandler(std::string path) : path_(std::move(path)) {}
  void OnRequestContextInitialized(
      CefRefPtr<CefRequestContext> context) override {
    auto* profile = CefRequestContextImpl::GetProfile(context);
    auto& record = Profiles().at(path_);
    if (!profile || profile->IsOffTheRecord() ||
        profile->GetPath().value() != path_) {
      record.failure =
          Error(@"Chromium did not create the requested persistent Profile.");
      record.context = nullptr;
      auto callbacks = std::move(record.waiters);
      record.waiters.clear();
      for (auto& callback : callbacks) {
        std::move(callback).Run(nullptr, nullptr, record.failure);
      }
      NotifyNativeEngineOwnershipChanged();
      return;
    }
    record.context = context;
    record.profile = profile->GetWeakPtr();
    InitializeNativeSearch(*profile);
    // Register before GetDownloadManager can enumerate restored items.
    if (!GetNativeRoute(*profile)) {
      CHECK(RegisterNativeRoute(*profile, ProviderInstance(), Client()));
    }
    // Keep Chromium's complete target determination/security/filename policy
    //
    ClearSeededDownloadPrompt(*profile);
    NativeDownloads::Install(
        *profile, base::BindRepeating([](NativeDownloadSnapshot snapshot) {
          CHECK(NSThread.isMainThread);
          if (IsNativeProfileRemovalBlocked(snapshot.profile_path))
            return;
          NSDictionary* values = DownloadValues(snapshot, false);
          id<PCNativeBrowserApplicationClient> client = application_client;
          [client nativeApplicationDownloadDidUpdate:values];
        }), base::BindRepeating(
            [](base::WeakPtr<Profile> original, NativeDownloadSnapshot snapshot,
               content::WeakDocumentPtr document) {
              if (original && !original->ShutdownStarted())
                PresentNativeDownloadArrival(*original, std::move(snapshot),
                                             std::move(document), nil);
            }, profile->GetWeakPtr()));

    auto callbacks = std::move(record.waiters);
    record.waiters.clear();
    for (auto& callback : callbacks) {
      std::move(callback).Run(profile, context, nil);
    }
    // A quit waiting for idle can proceed now the Profile has loaded.
    NotifyNativeEngineOwnershipChanged();
  }

 private:
  const std::string path_;
  IMPLEMENT_REFCOUNTING(ContextHandler);
};
void WithProfile(
    NSString* path,
    base::OnceCallback<void(Profile*, CefRefPtr<CefRequestContext>, NSError*)>
        callback) {
  CHECK(ready);
  std::string requested = base::SysNSStringToUTF8(path);
  // After quit is approved no Profile starts loading: its waiters would hold
  // the idle shutdown open or strand callbacks at CefShutdown.
  if (quitting && !Profiles().contains(requested)) {
    std::move(callback).Run(nullptr, nullptr, Error(@"Parc is quitting."));
    return;
  }
  if (IsNativeProfileRemovalBlocked(base::FilePath(base::SysNSStringToUTF8(path)))) {
    std::move(callback).Run(nullptr, nullptr,
                           Error(@"This Profile is being removed."));
    return;
  }
  std::string key = base::SysNSStringToUTF8(path);
  auto& record = Profiles()[key];
  if (record.failure) {
    std::move(callback).Run(nullptr, nullptr, record.failure);
    return;
  }
  if (record.profile) {
    std::move(callback).Run(record.profile.get(), record.context, nil);
    return;
  }
  record.waiters.push_back(std::move(callback));
  if (record.context) {
    return;
  }
  CefRequestContextSettings settings;
  CefString(&settings.cache_path) = key;
  auto context =
      CefRequestContext::CreateContext(settings, new ContextHandler(key));
  if (!record.failure) {
    record.context = context;
  }
  if (!context && !record.failure) {
    record.failure =
        Error(@"Chromium could not initialize the requested Profile.");
    auto callbacks = std::move(record.waiters);
    record.waiters.clear();
    for (auto& waiter : callbacks) {
      std::move(waiter).Run(nullptr, nullptr, record.failure);
    }
  }
}
//
//
// mark, black on light pages and white on dark ones, both served by the
// browser's chrome://theme. Parc's history page and toolbar do the same with
// Parc's mark; the toolbar patch asks for current-channel-logo-white, which
// ThemeSource serves as IDR_PRODUCT_LOGO_NAME_22_WHITE. Only the browser
// process publishes this, once its context exists.
struct ProductBranding {
  std::u16string history_menu_item;
  int light_logo = -1;
};
std::atomic<const ProductBranding*> product_branding{nullptr};
void PrepareProductBranding() {
  CHECK(NSThread.isMainThread);
  if (product_branding.load(std::memory_order_relaxed)) {
    return;
  }
  auto* branding = new ProductBranding;
  branding->history_menu_item =
      l10n_util::GetStringUTF16(IDS_HISTORY_HISTORY_MENU_ITEM);
  base::ReplaceSubstringsAfterOffset(&branding->history_menu_item, 0,
                                     u"Chromium", u"Parc");
  // The light toolbar logo is chrome://theme/current-channel-logo, served by
  // the browser's ThemeSource.
  branding->light_logo = webui::CurrentChannelLogoResourceId();
  product_branding.store(branding, std::memory_order_release);
}
// The mark's alpha in grey |white|, centred and 20 of 24 pixels tall like
//
std::string MarkPNG(CGImageRef mark, CGFloat white, size_t side) {
  base::apple::ScopedCFTypeRef<CGColorSpaceRef> space(
      CGColorSpaceCreateWithName(kCGColorSpaceSRGB));
  base::apple::ScopedCFTypeRef<CGContextRef> context(
      CGBitmapContextCreate(nullptr, side, side, 8, 0, space.get(),
                            kCGImageAlphaPremultipliedLast));
  if (!context) {
    return std::string();
  }
  const CGFloat height = side * 20.0 / 24.0;
  const CGFloat width =
      height * CGImageGetWidth(mark) / CGImageGetHeight(mark);
  const CGRect rect =
      CGRectMake((side - width) / 2, (side - height) / 2, width, height);
  CGContextClipToMask(context.get(), rect, mark);
  CGContextSetRGBFillColor(context.get(), white, white, white, 1);
  CGContextFillRect(context.get(), rect);
  base::apple::ScopedCFTypeRef<CGImageRef> image(
      CGBitmapContextCreateImage(context.get()));
  NSData* png =
      image ? [[[NSBitmapImageRep alloc] initWithCGImage:image.get()]
                  representationUsingType:NSBitmapImageFileTypePNG
                               properties:@{}]
            : nil;
  return png ? std::string(static_cast<const char*>(png.bytes), png.length)
             : std::string();
}
struct ProductLogos {
  std::string light_1x;
  std::string light_2x;
  std::string dark_1x;
  std::string dark_2x;
};
ProductLogos MakeProductLogos() {
  ProductLogos logos;
  NSURL* url = [NSBundle.mainBundle URLForResource:@"Monochrome"
                                     withExtension:@"png"
                                      subdirectory:@"AppIcons/Marks"];
  NSImage* image = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
  base::apple::ScopedCFTypeRef<CGImageRef> mark(
      [image CGImageForProposedRect:nullptr context:nil hints:nil],
      base::scoped_policy::RETAIN);
  if (!mark) {
    return logos;
  }
  logos.light_1x = MarkPNG(mark.get(), 0, 32);
  logos.light_2x = MarkPNG(mark.get(), 0, 64);
  logos.dark_1x = MarkPNG(mark.get(), 1, 32);
  logos.dark_2x = MarkPNG(mark.get(), 1, 64);
  return logos;
}
class ProductBrandingHandler final : public CefResourceBundleHandler {
 public:
  bool GetLocalizedString(int string_id, CefString& string) override {
    const auto* branding = product_branding.load(std::memory_order_acquire);
    if (!branding || string_id != IDS_HISTORY_HISTORY_MENU_ITEM) {
      return false;
    }
    string = branding->history_menu_item;
    return true;
  }
  bool GetDataResource(int resource_id,
                       void*& data,
                       size_t& data_size) override {
    return GetDataResourceForScale(resource_id, SCALE_FACTOR_NONE, data,
                                   data_size);
  }
  bool GetDataResourceForScale(int resource_id,
                               ScaleFactor scale_factor,
                               void*& data,
                               size_t& data_size) override {
    const auto* branding = product_branding.load(std::memory_order_acquire);
    const bool light = branding && branding->light_logo >= 0 &&
                       resource_id == branding->light_logo;
    if (!light &&
        (!branding || resource_id != IDR_PRODUCT_LOGO_NAME_22_WHITE)) {
      return false;
    }
    // Rendered on first use and kept, since the bundle doesn't copy it.
    static const base::NoDestructor<ProductLogos> logos(MakeProductLogos());
    // CEF passes Chromium's ui::ResourceScaleFactor through unchanged.
    const bool double_scale =
        ui::GetScaleForResourceScaleFactor(
            static_cast<ui::ResourceScaleFactor>(scale_factor)) > 1;
    const std::string& bytes =
        light ? (double_scale ? logos->light_2x : logos->light_1x)
              : (double_scale ? logos->dark_2x : logos->dark_1x);
    if (bytes.empty()) {
      return false;
    }
    data = const_cast<char*>(bytes.data());
    data_size = bytes.size();
    return true;
  }

 private:
  IMPLEMENT_REFCOUNTING(ProductBrandingHandler);
};
class NativeApplication final : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }
  CefRefPtr<CefResourceBundleHandler> GetResourceBundleHandler() override {
    return branding_;
  }
  void OnRegisterCustomPreferences(
      cef_preferences_type_t type,
      CefRawPtr<CefPreferenceRegistrar> registrar) override {
    if (type != CEF_PREFERENCES_TYPE_REQUEST_CONTEXT)
      return;
    RegisterNativeSearchPreferences(*registrar);
    // Page translation is excluded (it needs a Google API key), so Chrome's
    // Languages settings start with Google Translate off.
    auto offer = CefValue::Create();
    offer->SetBool(false);
    CefString error;
    CHECK(registrar->SetDefaultPreference(
        translate::prefs::kOfferTranslateEnabled, offer, error))
        << error.ToString();
  }
  CefRefPtr<CefClient> GetDefaultClient() override { return Client(); }
  void OnBeforeCommandLineProcessing(
      const CefString&,
      CefRefPtr<CefCommandLine> command) override {
    parc::ApplyNativeStartupPolicy(*command);
  }
  void OnBeforeChildProcessLaunch(
      CefRefPtr<CefCommandLine> command) override {
    const auto browser = CefCommandLine::GetGlobalCommandLine();
    // Explicit diagnostic opt-in follows only the renderer receiving the
    // observed input. Ordinary launches and other child processes are unchanged.
    if (command->GetSwitchValue("type") == "renderer" && browser &&
        browser->HasSwitch("parc-input-diagnostics")) {
      command->AppendSwitch("parc-input-diagnostics");
    }
  }
  bool OnAlreadyRunningAppRelaunch(
      CefRefPtr<CefCommandLine> command_line,
      const CefString& current_directory) override {
    CHECK(NSThread.isMainThread);
    // Consume the handoff even while closing: returning false delegates to
    // CEF's stock Chrome-window creation, which is never our native route.
    id<PCNativeBrowserApplicationClient> client = application_client;
    if (!client || quitting || preparing_global_close) {
      return true;
    }
    std::vector<CefString> argv;
    command_line->GetArgv(argv);
    NSMutableArray<NSString*>* arguments =
        [NSMutableArray arrayWithCapacity:argv.size()];
    for (const auto& argument : argv) {
      [arguments addObject:base::SysUTF8ToNSString(argument.ToString())];
    }
    [client nativeApplicationRelaunchedWithArguments:[arguments copy]
                                    currentDirectory:base::SysUTF8ToNSString(
                                                         current_directory
                                                             .ToString())];
    // The callback may start close or create work; no borrowed client state
    // or CefCommandLine references are used after it returns.
    return true;
  }
  void OnContextInitialized() override {
    CHECK(NSThread.isMainThread);
    PrepareProductBranding();
    auto& accessibility = Accessibility();
    CHECK(!accessibility.initialized && !accessibility.stopped);
    accessibility.initialized = true;
    accessibility.observation_context =
        content::BrowserAccessibilityState::GetInstance();
    // Consume actual system state and any role/manual requests received while
    // CEF was starting. No renderer AX mode is requested merely by startup.
    accessibility.voice_over = NSWorkspace.sharedWorkspace.voiceOverEnabled;
    accessibility.Apply();
    auto* profile = CefRequestContextImpl::GetProfile(nullptr);
    if (profile && !GetNativeRoute(*profile)) {
      if (!GetNativeRoute(*profile)) {
        CHECK(RegisterNativeRoute(*profile, ProviderInstance(), Client()));
      }
    }
    InstallNativeGmcPresentationHandler();
    DesktopMediaPicker::SetNativeFactory(
        base::BindRepeating(&WrapNativeCapturePicker));
    SetNativeCapturePickerRoute(base::BindRepeating(
        [](content::WebContents& contents) {
          auto* profile = Profile::FromBrowserContext(contents.GetBrowserContext());
          return profile && !!GetNativeRoute(*profile);
        }));
    ready = true;
    SetNativeDownloadDialogParentCallbacks({
        &IsNativeDownloadDialogProfile, &PrepareNativeDownloadDialogParent,
        &IsNativeDownloadDialogParent});
    auto requests = std::move(ReadyQueue());
    ReadyQueue().clear();
    for (auto& request : requests) {
      std::move(request).Run();
    }
  }

 private:
  const CefRefPtr<CefResourceBundleHandler> branding_ =
      new ProductBrandingHandler;
  IMPLEMENT_REFCOUNTING(NativeApplication);
};
}  // namespace
CefRefPtr<CefApp> CreateNativeApplication() {
  return new NativeApplication;
}
bool HasPendingNativeApplicationWork() {
  if (HasNativePageRetirementWork() || HasLiveTabTransfer() ||
      preparing_live_transfer) {
    return true;
  }
  return pending_creations != 0 || close_transaction_active ||
         preparing_global_close;
}
// A Profile still loading (Settings asks for its search and download
// preferences on open) has callbacks CefShutdown must not strand; quitting
// then tripped PrepareNativeApplicationShutdown's waiters CHECK.
bool HasLoadingNativeProfiles() {
  for (const auto& [path, record] : Profiles()) {
    if (!record.waiters.empty())
      return true;
  }
  return false;
}
void PrepareNativeApplicationShutdown() {
  CHECK(NSThread.isMainThread);
  ready = false;
  // CefShutdown follows and terminates Chromium's ImageTransportFactory, which
  // every pane compositor uses; they go first, as BrowserCompositorMac's do.
  ShutDownPaneCompositors();
  auto& accessibility = Accessibility();
  accessibility.stopped = true;
  accessibility.screen_reader.reset();
  accessibility.basic.reset();
  CHECK(pending_creations == 0);
  CHECK(ReadyQueue().empty());
  for (const auto& [path, record] : Profiles()) {
    CHECK(record.waiters.empty());
    auto profile = record.profile;
    if (profile) {
      CancelNativeDownloadFileDialogs(*profile);
    }
    if (profile) {
      if (auto* downloads = NativeDownloads::From(*profile)) {
        downloads->Shutdown();
      }
    }
  }
  SetNativeDownloadDialogParentCallbacks({});
  Profiles().clear();
  [Windows() removeAllObjects];
  application_client = nil;
}
std::shared_ptr<NativeWindowProvider> CreateAppKitWindowProvider() {
  return ProviderInstance();
}

bool IsNativeDownloadDialogProfile(Profile& profile) {
  CHECK(NSThread.isMainThread);
  if (profile.IsOffTheRecord()) return NativeContextForProfile(profile) && GetNativeRoute(profile);
  const auto record = Profiles().find(profile.GetPath().value());
  return ready && !quitting && !preparing_global_close &&
         !IsNativeProfileRemovalBlocked(profile.GetPath()) &&
         record != Profiles().end() && record->second.profile.get() == &profile &&
         GetNativeRoute(profile);
}

bool IsNativeDownloadDialogParent(Profile& profile, gfx::NativeWindow window) {
  CHECK(NSThread.isMainThread);
  if (!ready || quitting || preparing_global_close || !window ||
      IsNativeProfileRemovalBlocked(profile.GetPath()) || !GetNativeRoute(profile)) {
    return false;
  }
  if (profile.IsOffTheRecord()) {
    auto* binding = [Windows() objectForKey:window.GetNativeNSWindow()];
    return NativePrivateProfileForWindow(binding, ProfilePath(profile)) == &profile;
  }
  const auto record = Profiles().find(profile.GetPath().value());
  if (record == Profiles().end() || record->second.profile.get() != &profile) {
    return false;
  }
  NSWindow* parent = window.GetNativeNSWindow();
  PCNativeBrowserWindow* binding = [Windows() objectForKey:parent];
  id<PCNativeBrowserApplicationClient> client = application_client;
  if (!binding || !binding.client || binding.window != parent ||
      [binding.client nativeBrowserWindow] != parent ||
      [binding state].close_in_progress || [binding state].close_approved ||
      ![client respondsToSelector:
                   @selector(nativeDownloadDialogWindow:representsProfilePath:)]) {
    return false;
  }
  return [client nativeDownloadDialogWindow:parent
                      representsProfilePath:ProfilePath(profile)];
}

gfx::NativeWindow PrepareNativeDownloadDialogParent(Profile& profile) {
  CHECK(NSThread.isMainThread);
  if (profile.IsOffTheRecord()) {
    for (NSWindow* window in NSApp.orderedWindows) {
      auto* binding = [Windows() objectForKey:window];
      if (window.isVisible && !window.attachedSheet &&
          NativePrivateProfileForWindow(binding, ProfilePath(profile)) == &profile)
        return gfx::NativeWindow(window);
    }
    return {};
  }
  id<PCNativeBrowserApplicationClient> client = application_client;
  if (!ready || quitting || preparing_global_close ||
      IsNativeProfileRemovalBlocked(profile.GetPath()) || !GetNativeRoute(profile) ||
      ![client respondsToSelector:
                   @selector(nativeDownloadDialogWindowForProfilePath:)] ||
      ![client respondsToSelector:
                   @selector(nativeDownloadDialogWindow:representsProfilePath:)]) {
    return {};
  }
  const auto record = Profiles().find(profile.GetPath().value());
  if (record == Profiles().end() || record->second.profile.get() != &profile) {
    return {};
  }
  // Shell construction may reenter the engine. Keep the actual CEF context
  // alive, but re-resolve its weak Profile identity after the callback.
  auto context = record->second.context;
  auto identity = profile.GetWeakPtr();
  NSWindow* parent =
      [client nativeDownloadDialogWindowForProfilePath:ProfilePath(profile)];
  const auto window = gfx::NativeWindow(parent);
  return context && identity && IsNativeDownloadDialogParent(*identity, window)
             ? window
             : gfx::NativeWindow();
}
namespace {
class NativeCloseTransaction;
std::shared_ptr<NativeCloseTransaction>& ActiveCloseTransaction() {
  static base::NoDestructor<std::shared_ptr<NativeCloseTransaction>> value;
  return *value;
}
// This coordinates genuine UnloadControllers, never a duplicated beforeunload
// state machine. Like BrowserCloseManager, confirmation runs across every
// Browser before any BrowserWindow::Close commits actual page unload.
class NativeCloseTransaction final
    : public std::enable_shared_from_this<NativeCloseTransaction> {
 public:
  NativeCloseTransaction(NSArray<PCNativeBrowserWindow*>* bindings, bool all)
      : bindings_([bindings copy]), all_windows_(all) {}
  void AddCompletion(void (^completion)(BOOL)) {
    CHECK(completion);
    completions_.push_back([completion copy]);
  }
  bool all_windows() const { return all_windows_; }
  void Start() {
    auto keep_alive = shared_from_this();
    for (PCNativeBrowserWindow* binding in bindings_) {
      auto& state = [binding state];
      CHECK(!state.close_in_progress);
      state.close_in_progress = true;
      state.close_approved = false;
      CancelInvalidNativeDownloadFileDialogs(gfx::NativeWindow(binding.window));
      for (const auto& [profile, browser] : state.browsers) {
        if (!browser) {
          continue;
        }
        state.pending_close.insert(browser.get());
        browsers_.push_back(browser);
      }
    }
    // Do not interfere with an independently running single-window close.
    // That operation owns its own beforeunload callback and cannot be adopted.
    for (auto browser : browsers_) {
      if (browser && UnloadController::From(browser.get())
                         ->is_attempting_to_close_browser()) {
        Finish(false);
        return;
      }
    }
    // AppController normally provides this global Mac shutdown warning. Parc
    // supplies the existing native host service instead of bypassing downloads.
    const int downloads =
        all_windows_ ? DownloadCoreService::BlockingShutdownCountAllProfiles()
                     : 0;
    if (downloads > 0 && browsers_.empty()) {
      // A download can outlive the last Browser. There is then no genuine
      // Browser-bound warning presenter; do not silently approve shutdown.
      NSString* capability =
          @"Quit with active downloads requires a native download warning "
           "presenter. Keep Parc running until the downloads finish.";
      NSLog(@"%@", capability);
      for (PCNativeBrowserWindow* binding in bindings_) {
        [binding.client nativeBrowser:binding capabilityUnavailable:capability];
      }
      Finish(false);
      return;
    }
    if (downloads > 0) {
      auto browser = browsers_.front();
      if (!browser) {
        Finish(false);
        return;
      }
      const auto weak = weak_factory_.GetWeakPtr();
      BrowserWindow::FromBrowser(browser.get())
          ->ConfirmBrowserCloseWithPendingDownloads(
              downloads, UnloadController::DownloadCloseType::kBrowserShutdown,
              base::BindOnce(
                  [](base::WeakPtr<NativeCloseTransaction> self, bool allow) {
                    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
                        FROM_HERE,
                        base::BindOnce(
                            &NativeCloseTransaction::DownloadsConfirmed, self,
                            allow));
                  },
                  weak));
      return;
    }
    WarnNext();
  }
  void BrowserUnregistered(BrowserWindowInterface& browser) {
    if (phase_ == Phase::kDone) {
      return;
    }
    if (phase_ == Phase::kCommitting) {
      MaybeFinishCommitted();
    } else if (awaiting_ == &browser) {
      awaiting_ = nullptr;
      ++callback_epoch_;
      QueueAdvance();
    }
  }
  void Rejected() {
    if (phase_ != Phase::kDone) {
      Finish(false);
    }
  }

 private:
  enum class Phase { kWarnings, kBeforeUnload, kCommitting, kDone };
  void DownloadsConfirmed(bool allow) {
    if (phase_ != Phase::kWarnings) {
      return;
    }
    if (!allow) {
      Finish(false);
      return;
    }
    WarnNext();
  }
  void QueueAdvance() {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&NativeCloseTransaction::Advance,
                                  weak_factory_.GetWeakPtr()));
  }
  void Advance() {
    if (phase_ == Phase::kWarnings) {
      WarnNext();
    } else if (phase_ == Phase::kBeforeUnload) {
      ConfirmNext();
    }
  }
  void WarnNext() {
    auto keep_alive = shared_from_this();
    if (phase_ != Phase::kWarnings || awaiting_) {
      return;
    }
    while (warning_index_ < browsers_.size()) {
      auto browser = browsers_[warning_index_++];
      if (!browser) {
        continue;
      }
      auto* controller = UnloadController::From(browser.get());
      if (controller->GetBrowserClosingStatus() ==
          BrowserWindowInterface::ClosingStatus::kDeniedByPolicy) {
        Finish(false);
        return;
      }
      if (controller->is_attempting_to_close_browser()) {
        Finish(false);
        return;
      }
      owned_controllers_.insert(browser.get());
      awaiting_ = browser.get();
      const uint64_t epoch = ++callback_epoch_;
      const auto weak = weak_factory_.GetWeakPtr();
      auto result = controller->MaybeWarnBeforeClosing(base::BindOnce(
          [](base::WeakPtr<NativeCloseTransaction> self, uint64_t epoch,
             UnloadController::WarnBeforeClosingResult result) {
            base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
                FROM_HERE,
                base::BindOnce(&NativeCloseTransaction::WarningConfirmed, self,
                               epoch, result));
          },
          weak, epoch));
      if (phase_ != Phase::kWarnings) {
        return;
      }
      if (result == UnloadController::WarnBeforeClosingResult::kDoNotClose) {
        return;
      }
      awaiting_ = nullptr;
      ++callback_epoch_;
    }
    phase_ = Phase::kBeforeUnload;
    ConfirmNext();
  }
  void WarningConfirmed(uint64_t epoch,
                        UnloadController::WarnBeforeClosingResult result) {
    if (phase_ != Phase::kWarnings || epoch != callback_epoch_) {
      return;
    }
    awaiting_ = nullptr;
    if (result != UnloadController::WarnBeforeClosingResult::kOkToClose) {
      Finish(false);
      return;
    }
    WarnNext();
  }
  void ConfirmNext() {
    auto keep_alive = shared_from_this();
    if (phase_ != Phase::kBeforeUnload || awaiting_) {
      return;
    }
    // Rescan all genuine controllers after each approval, including new tabs
    // or newly registered handlers. Chromium remembers already-approved pages.
    for (auto browser : browsers_) {
      if (!browser) {
        continue;
      }
      auto* controller = UnloadController::From(browser.get());
      if (controller->GetBrowserClosingStatus() ==
          BrowserWindowInterface::ClosingStatus::kDeniedByPolicy) {
        Finish(false);
        return;
      }
      if (controller->is_attempting_to_close_browser() &&
          !beforeunload_started_.contains(browser.get())) {
        Finish(false);
        return;
      }
      beforeunload_started_.insert(browser.get());
      awaiting_ = browser.get();
      const uint64_t epoch = ++callback_epoch_;
      const bool pending = controller->RunBeforeUnloadForShutdown(
          false,
          base::BindRepeating(
              [](base::WeakPtr<NativeCloseTransaction> self, uint64_t epoch,
                 bool allow) {
                base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
                    FROM_HERE,
                    base::BindOnce(
                        &NativeCloseTransaction::BeforeUnloadConfirmed, self,
                        epoch, allow));
              },
              weak_factory_.GetWeakPtr(), epoch));
      if (phase_ != Phase::kBeforeUnload) {
        return;
      }
      if (pending) {
        return;
      }
      awaiting_ = nullptr;
      ++callback_epoch_;
    }
    Commit();
  }
  void BeforeUnloadConfirmed(uint64_t epoch, bool allow) {
    if (phase_ != Phase::kBeforeUnload || epoch != callback_epoch_) {
      return;
    }
    awaiting_ = nullptr;
    if (!allow) {
      Finish(false);
      return;
    }
    ConfirmNext();
  }
  void Commit() {
    auto keep_alive = shared_from_this();
    phase_ = Phase::kCommitting;
    for (auto browser : browsers_) {
      if (phase_ != Phase::kCommitting) {
        return;
      }
      if (browser) {
        RequestAppKitBrowserClose(*browser);
      }
    }
    MaybeFinishCommitted();
  }
  void MaybeFinishCommitted() {
    if (phase_ != Phase::kCommitting) {
      return;
    }
    for (PCNativeBrowserWindow* binding in bindings_) {
      if (![binding state].pending_close.empty()) {
        return;
      }
    }
    Finish(true);
  }
  void Finish(bool allow) {
    auto keep_alive = shared_from_this();
    if (phase_ == Phase::kDone) {
      return;
    }
    phase_ = Phase::kDone;
    awaiting_ = nullptr;
    ++callback_epoch_;
    if (!allow) {
      // Reset every confirmed Browser, not just the one whose user chose Stay.
      // Reset can invoke the old confirmation callback; its epoch is invalid.
      for (auto browser : browsers_) {
        if (browser && owned_controllers_.contains(browser.get())) {
          UnloadController::From(browser.get())->ResetBeforeUnloadForShutdown();
        }
      }
      if (all_windows_) {
        quitting = false;
      }
    }
    for (PCNativeBrowserWindow* binding in bindings_) {
      [binding state].FinishClose(allow);
    }
    if (ActiveCloseTransaction().get() == this) {
      ActiveCloseTransaction().reset();
      close_transaction_active = false;
    }
    auto callbacks = std::move(completions_);
    for (auto callback : callbacks) {
      dispatch_async(dispatch_get_main_queue(), ^{
        callback(allow);
      });
    }
    NotifyNativeEngineOwnershipChanged();
  }
  NSArray<PCNativeBrowserWindow*>* __strong bindings_;
  std::vector<base::WeakPtr<BrowserWindowInterface>> browsers_;
  std::vector<void (^)(BOOL)> completions_;
  std::set<BrowserWindowInterface*> owned_controllers_;
  std::set<BrowserWindowInterface*> beforeunload_started_;
  BrowserWindowInterface* awaiting_ =
      nullptr;  // Identity only; never dereferenced.
  size_t warning_index_ = 0;
  uint64_t callback_epoch_ = 0;
  bool all_windows_;
  Phase phase_ = Phase::kWarnings;
  base::WeakPtrFactory<NativeCloseTransaction> weak_factory_{this};
};
void BeginNativeClose(NSArray<PCNativeBrowserWindow*>* bindings,
                      bool all,
                      void (^completion)(BOOL)) {
  CHECK(!HasNativePageRetirementWork());
  CHECK(!HasLiveTabTransfer() && !preparing_live_transfer);
  CHECK(!ActiveCloseTransaction());
  auto transaction = std::make_shared<NativeCloseTransaction>(bindings, all);
  if (completion) {
    transaction->AddCompletion(completion);
  }
  ActiveCloseTransaction() = transaction;
  close_transaction_active = true;
  transaction->Start();
}
}  // namespace
void RegisterAppKitBrowser(PCNativeBrowserWindow* binding,
                           BrowserWindowInterface& browser) {
  ++[binding state].ownership_epoch;
  auto& browsers = [binding state].browsers;
  auto existing = browsers.find(browser.GetProfile());
  CHECK(existing == browsers.end() || !existing->second ||
        existing->second.get() == &browser);
  browsers[browser.GetProfile()] = browser.GetWeakPtr();
  SetAppKitWebsiteTheme(browser, [binding state].website_theme_stylesheet);
}
void UnregisterAppKitBrowser(PCNativeBrowserWindow* binding,
                             BrowserWindowInterface& browser) {
  auto& state = [binding state];
  auto found = state.browsers.find(browser.GetProfile());
  if (found != state.browsers.end() && found->second.get() == &browser) {
    state.browsers.erase(found);
    ++state.ownership_epoch;
    NotifyEmptyBinding(binding, false);
  }
  state.pending_close.erase(&browser);
  if (auto transaction = ActiveCloseTransaction()) {
    transaction->BrowserUnregistered(browser);
  }
  // Never create the replacement Browser on this teardown stack.
  for (auto& waiter : std::exchange(state.retirement_waiters, {})) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, std::move(waiter));
  }
  NotifyNativeEngineOwnershipChanged();
}
namespace {
// Closing a Browser's last tab schedules its deletion at once, but it stays
// registered to this window until its native drain finishes. ~Browser destroys
// BrowserWindowFeatures before tabs still in its TabStripModel, so a page added
// meanwhile outlives the window services it observes (its cookie page action
// observes the window's CookieControlsController). Callers wait for that
// Browser to unregister; their retry then creates this window's next Browser.
bool BrowserRetiringForPath(PCNativeBrowserWindow* binding, NSString* path) {
  const base::FilePath profile_path(base::SysNSStringToUTF8(path));
  for (const auto& entry : [binding state].browsers) {
    const auto& browser = entry.second;
    // An OTR Profile reports its original Profile's path.
    if (browser && browser->IsDeleteScheduled() &&
        browser->GetProfile()->GetPath() == profile_path) {
      return true;
    }
  }
  return false;
}
// A parked request holds a reservation, so the retiring Browser's
// unregistration cannot report this window empty before the retry runs.
void ParkUntilBrowserRetires(PCNativeBrowserWindow* binding,
                             base::OnceClosure retry) {
  ++[binding state].pending_reservations;
  [binding state].retirement_waiters.push_back(base::BindOnce(
      [](PCNativeBrowserWindow* binding, base::OnceClosure retry) {
        CHECK([binding state].pending_reservations);
        --[binding state].pending_reservations;
        std::move(retry).Run();
        // A retry that failed before reserving leaves the window as empty as
        // the suppressed notification found it.
        NotifyEmptyBinding(binding, false);
      },
      binding, std::move(retry)));
}
}  // namespace
void AppKitBrowserCloseResult(PCNativeBrowserWindow* binding,
                              BrowserWindowInterface& browser,
                              bool approved) {
  auto& state = [binding state];
  if (!state.close_in_progress || !state.pending_close.contains(&browser)) {
    return;
  }
  // Approval only authorizes Chromium's actual unload/drain/delete sequence.
  // The physical NSWindow remains owned until UnregisterAppKitBrowser observes
  // every corresponding Browser's completed native-service drain.
  if (!approved) {
    if (auto transaction = ActiveCloseTransaction()) {
      transaction->Rejected();
    } else {
      state.FinishClose(false);
    }
  }
}

}  // namespace parc

@interface PCNativeEmbeddedPageRequest ()
- (instancetype)initWithCompletion:(void (^)(PCNativePage*, NSError*))completion;
- (void)finishWithPage:(PCNativePage*)page error:(NSError*)error;
- (BOOL)beginCommit;
@end
@implementation PCNativeEmbeddedPageRequest {
  void (^_completion)(PCNativePage*, NSError*);
  BOOL _pending;
  BOOL _committed;
}
- (instancetype)initWithCompletion:(void (^)(PCNativePage*, NSError*))completion {
  self = [super init];
  if (self) { _completion = [completion copy]; _pending = YES; }
  return self;
}
- (BOOL)isPending { return _pending; }
- (BOOL)beginCommit {
  CHECK(NSThread.isMainThread);
  if (!_pending) return NO;
  _committed = YES;
  return YES;
}
- (void)finishWithPage:(PCNativePage*)page error:(NSError*)error {
  CHECK(NSThread.isMainThread);
  if (!_pending) return;
  _pending = NO;
  auto completion = _completion;
  _completion = nil;
  completion(page, error);
}
- (void)cancel {
  CHECK(NSThread.isMainThread);
  if (!_pending || _committed) return;
  // Mark cancellation before posting: a queued Profile callback must not
  // create content while the cancellation result waits for the next turn.
  _pending = NO;
  auto completion = _completion;
  _completion = nil;
  dispatch_async(dispatch_get_main_queue(), ^{
    completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain
        code:NSUserCancelledError userInfo:nil]);
  });
}
@end

@implementation PCNativeBrowserWindow {
  std::unique_ptr<parc::BindingState> _state;
}
- (instancetype)initWithClient:(id<PCNativeBrowserWindowClient>)client {
  self = [super init];
  if (self) {
    _state = std::make_unique<parc::BindingState>();
    _state->client = client;
    _state->window = [client nativeBrowserWindow];
  }
  return self;
}
- (parc::BindingState&)state {
  return *_state;
}
- (PCNativeBrowsingContextKind)browsingContextKind {
  CHECK(NSThread.isMainThread);
  if (!_state->window || !_state->client || _state->close_approved) {
    return PCNativeBrowsingContextKindUnavailable;
  }
  bool regular = false;
  bool off_the_record = false;
  for (const auto& [profile, browser] : _state->browsers) {
    // Use the live Browser's Profile, never a stale map key or a path lookup.
    if (!browser || browser->GetProfile() != profile) {
      continue;
    }
    if (browser->GetProfile()->IsOffTheRecord()) {
      off_the_record = true;
    } else {
      regular = true;
    }
  }
  if (regular && off_the_record) return PCNativeBrowsingContextKindMixed;
  if (off_the_record) return PCNativeBrowsingContextKindOffTheRecord;
  if (regular) return PCNativeBrowsingContextKindRegular;
  return PCNativeBrowsingContextKindUnavailable;
}
- (NSWindow*)window {
  return _state->window;
}
- (id<PCNativeBrowserWindowClient>)client {
  return _state->client;
}
- (BOOL)isPrivateBrowsing { return _state->private_mode; }
- (BOOL)adoptPrivateContextFromRequest:(PCNativeWindowRequest*)request error:(NSError**)error {
  CHECK(NSThread.isMainThread);
  auto* profile = request ? request->_originalProfile.get() : nullptr;
  if (!request.isOffTheRecord || !profile || !profile->IsOffTheRecord() ||
      !_state->browsers.empty() || _state->private_mode || !self.window ||
      _state->close_in_progress || _state->close_approved || parc::quitting) {
    if (error) *error = parc::Error(@"The original private window request is no longer available.");
    return NO;
  }
  _state->private_mode = true;
  _state->private_profile = profile->GetWeakPtr();
  parc::InstallPrivateDownloads(*profile);
  return YES;
}
- (BOOL)beginPrivateBrowsingWithProfilePath:(NSString*)path error:(NSError**)error {
  CHECK(NSThread.isMainThread);
  auto fail = [&](NSString* message) { if (error) *error = parc::Error(message); return NO; };
  if (!parc::ready || parc::quitting || parc::preparing_global_close ||
      !self.window || !self.client || !_state->browsers.empty() || _state->private_mode ||
      _state->close_in_progress || _state->close_approved || !path.isAbsolutePath ||
      ![path isEqualToString:path.stringByStandardizingPath])
    return fail(@"Wait for the original profile to finish opening before creating a private window.");
  auto found = parc::Profiles().find(base::SysNSStringToUTF8(path));
  Profile* parent = found == parc::Profiles().end() ? nullptr : found->second.profile.get();
  if (!parent || parent->IsOffTheRecord() || !found->second.context ||
      parc::IsNativeProfileRemovalBlocked(parent->GetPath()) || parent->ShutdownStarted())
    return fail(@"The original profile is not available for private browsing.");
  if (IncognitoModePrefs::GetAvailability(parent) == policy::IncognitoModeAvailability::kDisabled)
    return fail(@"Private browsing is disabled for this profile.");
  //
  // shared per-parent OTR identity and its last-Browser destruction semantics.
  const bool created_profile = !parent->HasPrimaryOTRProfile();
  Profile* profile = parent->GetPrimaryOTRProfile(/*create_if_needed=*/true);
  base::ScopedClosureRunner abandon_new_context(base::BindOnce(
      [](bool created, base::WeakPtr<Profile> weak_profile) {
        if (created && weak_profile &&
            ProfileBrowserCollection::GetForProfile(weak_profile.get())->IsEmpty())
          ProfileDestroyer::DestroyOTRProfileWhenAppropriate(weak_profile.get());
      }, created_profile, profile ? profile->GetWeakPtr() : base::WeakPtr<Profile>()));
  if (!profile || !profile->IsOffTheRecord() || profile->ShutdownStarted() ||
      GetBrowserWindowCreationStatusForProfile(*profile) != BrowserWindowInterface::CreationStatus::kOk)
    return fail(@"The private browsing context could not be opened.");
  auto context = CefRequestContextImpl::GetOrCreateForBrowserContext(
      ChromeBrowserContext::GetOrCreateForProfile(profile), nullptr);
  if (!parc::GetNativeRoute(*profile) &&
      !parc::RegisterNativeRoute(*profile, parc::ProviderInstance(), parc::Client()))
    return fail(@"The private browser cannot use this native window.");
  parc::InitializeNativeSearch(*profile);
  // Chromium owns private download items and dialogs. Do not publish their
  // URLs or filenames into the application's persistent normal download list.
  parc::InstallPrivateDownloads(*profile);
  _state->private_mode = true;
  _state->private_profile = profile->GetWeakPtr();
  CefBrowserCreateParams native_params;
  native_params.request_context = context;
  native_params.client = parc::Client();
  native_params.native_route = parc::GetNativeRoute(*profile);
  native_params.native_reservation = std::make_shared<parc::PreparedAppKitWindow>(
      *profile, BrowserWindowInterface::TYPE_NORMAL, self);
  BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL, *profile, true);
  params.should_trigger_session_restore = false;
  params.cef_params = base::MakeRefCounted<ChromeBrowserHostImpl::DelegateCreateParams>(native_params);
  auto* browser = CreateBrowserWindow(std::move(params));
  if (!browser || browser->GetProfile() != profile || parc::AppKitBindingForBrowser(browser) != self) {
    if (browser && !browser->IsDeleteScheduled() && browser->GetTabStripModel()->empty()) browser->GetWindow()->Close();
    return fail(@"The private browser window could not be created.");
  }
  return YES;
}
- (void)openURL:(NSURL*)url
    profilePath:(NSString*)path
      container:(NSView*)container
     completion:(void (^)(PCNativePage*, NSError*))completion {
  [self openURL:url
           profilePath:path
             container:container
      searchNavigation:nil
            completion:completion];
}
- (void)openURL:(NSURL*)url
         profilePath:(NSString*)path
           container:(NSView*)container
    searchNavigation:(PCNativeSearchNavigation*)search
          completion:(void (^)(PCNativePage*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  CHECK(completion);
  if (!self.window || container.window != self.window || !path.isAbsolutePath ||
      ![path isEqualToString:path.stringByStandardizingPath] ||
      _state->close_in_progress || _state->close_approved || parc::quitting) {
    completion(
        nil, parc::Error(
                 @"The supplied page window or profile path is unavailable."));
    return;
  }
  if (parc::BrowserRetiringForPath(self, path)) {
    __weak PCNativeBrowserWindow* weak_self = self;
    __weak NSView* weak_target = container;
    void (^retry_completion)(PCNativePage*, NSError*) = [completion copy];
    parc::ParkUntilBrowserRetires(self, base::BindOnce(^{
      PCNativeBrowserWindow* binding = weak_self;
      NSView* target = weak_target;
      if (!binding || !target) {
        retry_completion(nil, parc::Error(@"The page's window closed."));
        return;
      }
      [binding openURL:url profilePath:path container:target
          searchNavigation:search completion:retry_completion];
    }));
    return;
  }
  ++parc::pending_creations;
  void (^original)(PCNativePage*, NSError*) = [completion copy];
  __block BOOL settled = NO;
  completion = [^(PCNativePage* page, NSError* error) {
    if (settled) {
      return;
    }
    settled = YES;
    CHECK(parc::pending_creations);
    --parc::pending_creations;
    parc::NotifyNativeEngineOwnershipChanged();
    original(page, error);
  } copy];
  __weak PCNativeBrowserWindow* weak = self;
  __weak NSView* weak_container = container;
  auto create = base::BindOnce(^{
    if (parc::quitting) {
      completion(nil, parc::Error(@"The application is closing."));
      return;
    }
    const base::FilePath cache_root(
        CefString(&CefContext::Get()->settings().root_cache_path).ToString());
    const base::FilePath profile_path(base::SysNSStringToUTF8(path));
    if (profile_path.DirName() != cache_root) {
      completion(nil,
                 parc::Error(@"Each independent Profile must be an immediate "
                             @"child of the engine cache root."));
      return;
    }
    auto create_with_profile = base::BindOnce(^(
        Profile* actual_profile, CefRefPtr<CefRequestContext> context,
        NSError* profile_error) {
      if (!actual_profile) {
        completion(nil, profile_error);
        return;
      }
      Profile& profile = *actual_profile;
      PCNativeBrowserWindow* original_binding = weak;
      if (!original_binding || [original_binding state].private_mode != profile.IsOffTheRecord() ||
          ([original_binding state].private_mode && [original_binding state].private_profile.get() != &profile)) {
        completion(nil, parc::Error(@"The original browsing context changed."));
        return;
      }
      if (parc::IsNativeProfileRemovalBlocked(profile.GetOriginalProfile()->GetPath())) {
        completion(nil, parc::Error(@"This Profile is being removed."));
        return;
      }
      PCNativeBrowserWindow* binding = weak;
      NSView* destination_container = weak_container;
      if (!binding || destination_container.window != binding.window ||
          !binding.client || parc::quitting ||
          [binding state].close_in_progress || [binding state].close_approved) {
        completion(nil, parc::Error(
                            @"The destination window closed before creation."));
        return;
      }
      auto& state = [binding state];
      auto found = state.browsers.find(&profile);
      BrowserWindowInterface* browser =
          found == state.browsers.end() ? nullptr : found->second.get();
      content::WebContents* contents = nullptr;
      if (browser) {
        if (!parc::AppKitBrowserAcceptsNewPages(*browser)) {
          completion(nil,
                     parc::Error(@"The native Browser is finishing closure."));
          return;
        }
        auto browser_weak = browser->GetWeakPtr();
        contents = chrome::AddAndReturnTabAt(
            browser, GURL(url.absoluteString.UTF8String), TabStripModel::kNoTab,
            true);
        if (!browser_weak) {
          contents = nullptr;
        }
      } else {
        if (!context) {
          completion(
              nil,
              parc::Error(
                  @"The originating private Browser closed before creation."));
          return;
        }
        CefBrowserCreateParams params;
        params.request_context = context;
        params.client = parc::Client();
        params.url = url.absoluteString.UTF8String;
        params.native_route = parc::GetNativeRoute(profile);
        params.native_reservation =
            std::make_shared<parc::PreparedAppKitWindow>(
                profile, BrowserWindowInterface::TYPE_NORMAL, binding);
        auto created = ChromeBrowserHostImpl::Create(params);
        if (created) {
          contents = created->GetWebContents();
        }
      }
      if (!contents) {
        completion(nil, parc::Error(@"Native browser creation was refused."));
        return;
      }
      auto cef = ChromeBrowserHostImpl::GetBrowserForContents(contents);
      if (!cef || !cef->browser() || !parc::GetNativeRoute(profile)) {
        completion(
            nil,
            parc::Error(@"The real tab has not established native ownership."));
        return;
      }
      auto* platform = static_cast<parc::NativeChromePlatformDelegate*>(
          cef->platform_delegate());
      PCNativePage* page =
          parc::GetOrCreateNativePage(*contents, *platform, path);
      // Page attachment remains an exact owner operation. No URL
      // reconstruction.
      if (![binding pageDidAttach:page container:destination_container]) {
        [page requestClose:^(PCNativePageCloseResult){
        }];
        completion(
            nil,
            parc::Error(@"The page could not attach to its supplied window."));
        return;
      }
      completion(page, nil);
    });
    if (search) {
      // A selected native-page search can belong to an OTR Profile sharing its
      // persistent parent's path. Never re-resolve it through the path map.
      auto* profile = parc::ProfileForSearchNavigation(search);
      if (!profile) {
        completion(nil,
                   parc::Error(@"The originating search profile changed."));
        return;
      }
      std::move(create_with_profile)
          .Run(profile, parc::NativeContextForProfile(*profile), nil);
    } else if (PCNativeBrowserWindow* binding = weak; binding && [binding state].private_mode) {
      Profile* profile = parc::NativePrivateProfileForWindow(binding, path);
      std::move(create_with_profile).Run(profile,
          profile ? parc::NativeContextForProfile(*profile) : nullptr,
          profile ? nil : parc::Error(@"The original private browsing context closed."));
    } else {
      parc::WithProfile(path, std::move(create_with_profile));
    }
  });
  if (parc::ready) {
    std::move(create).Run();
  } else {
    parc::ReadyQueue().push_back(std::move(create));
  }
}
- (void)openBackgroundURL:(NSURL*)url
              profilePath:(NSString*)path
                container:(NSView*)container
               completion:(void (^)(PCNativePage*, NSError*))completion {
  [self openBackgroundURL:url profilePath:path container:container
      searchNavigation:nil validateOwner:^{ return YES; } completion:completion];
}
- (void)openBackgroundURL:(NSURL*)url
    profilePath:(NSString*)path container:(NSView*)container
    searchNavigation:(PCNativeSearchNavigation*)search
    validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  CHECK(completion);
  if ((!search && _state->private_mode) || !validateOwner || !validateOwner() || !url || !self.window || container.window != self.window ||
      !path.isAbsolutePath || ![path isEqualToString:path.stringByStandardizingPath]) {
    completion(nil, parc::Error(@"The supplied background page owner is unavailable."));
    return;
  }
  if (parc::BrowserRetiringForPath(self, path)) {
    __weak PCNativeBrowserWindow* weak_self = self;
    __weak NSView* weak_target = container;
    BOOL (^retry_owner)(void) = [validateOwner copy];
    void (^retry_completion)(PCNativePage*, NSError*) = [completion copy];
    parc::ParkUntilBrowserRetires(self, base::BindOnce(^{
      PCNativeBrowserWindow* binding = weak_self;
      NSView* target = weak_target;
      if (!binding || !target) {
        retry_completion(nil, parc::Error(@"The background page's window closed."));
        return;
      }
      [binding openBackgroundURL:url profilePath:path container:target
          searchNavigation:search validateOwner:retry_owner completion:retry_completion];
    }));
    return;
  }
  __weak NSView* weak_container = container;
  // The existing routing factory reserves this exact binding during async
  // Profile acquisition and creates a first Browser without showing/selecting it.
  // No source WebContents or navigation replay is involved in a saved-item copy.
  auto admitted = base::BindOnce(
      [](PCNativeBrowserWindow* binding, NSView* __weak weak_container,
         NSURL* url, NSString* path, PCNativeSearchNavigation* search,
         BOOL (^validateOwner)(void),
         void (^completion)(PCNativePage*, NSError*),
         BrowserWindowInterface* browser, bool created, NSError* error) {
        NSView* destination = weak_container;
        if (!browser || (search && parc::ProfileForSearchNavigation(search) != browser->GetProfile()) ||
            (!search && ([binding state].private_mode || browser->GetProfile()->IsOffTheRecord())) ||
            [binding state].private_mode != browser->GetProfile()->IsOffTheRecord() ||
            !validateOwner() ||
            destination.window != binding.window ||
            !binding.window || !binding.client || parc::quitting || parc::preparing_global_close ||
            [binding state].close_in_progress || [binding state].close_approved ||
            !parc::AppKitBrowserAcceptsNewPages(*browser)) {
          if (created && browser && browser->GetTabStripModel()->empty() &&
              !browser->IsDeleteScheduled()) browser->GetWindow()->Close();
          completion(nil, error ?: parc::Error(@"The background page owner changed."));
          return;
        }
        auto weak_browser = browser->GetWeakPtr();
        auto* contents = chrome::AddAndReturnTabAt(
            browser, GURL(url.absoluteString.UTF8String), TabStripModel::kNoTab,
            false);
        if (!weak_browser || !contents) {
          if (created && weak_browser && weak_browser->GetTabStripModel()->empty() &&
              !weak_browser->IsDeleteScheduled()) weak_browser->GetWindow()->Close();
          completion(nil, parc::Error(@"Background page creation was refused."));
          return;
        }
        auto cef = ChromeBrowserHostImpl::GetBrowserForContents(contents);
        if (!cef || cef->browser() != browser) {
          completion(nil, parc::Error(@"The background page has no native owner."));
          return;
        }
        auto* platform = static_cast<parc::NativeChromePlatformDelegate*>(
            cef->platform_delegate());
        PCNativePage* page = parc::GetOrCreateNativePage(*contents, *platform, path);
        if (![binding pageDidAttach:page container:destination]) {
          [page requestClose:^(PCNativePageCloseResult) {}];
          completion(nil, parc::Error(@"The background page could not attach."));
          return;
        }
        completion(page, nil);
      }, self, weak_container, url, path, search, [validateOwner copy], [completion copy]);
  if (search) {
    Profile* profile = parc::ProfileForSearchNavigation(search);
    if (!profile || parc::IsNativeProfileRemovalBlocked(profile->GetOriginalProfile()->GetPath())) {
      std::move(admitted).Run(nullptr, false, parc::Error(@"The original search Profile changed."));
      return;
    }
    auto found = _state->browsers.find(profile);
    if (found != _state->browsers.end() && found->second) {
      std::move(admitted).Run(found->second.get(), false, nil);
      return;
    }
    // OTR is tied to its original native Browser; never resolve its shared path.
    if (profile->IsOffTheRecord()) {
      std::move(admitted).Run(nullptr, false, parc::Error(@"The private Browser closed."));
      return;
    }
  }
  parc::WithNativeRoutingBrowser(self, path, std::move(admitted));
}
- (void)openNavigationState:(NSObject*)navigation
                profilePath:(NSString*)path
                  container:(NSView*)container
                 background:(BOOL)background
                 completion:(void (^)(PCNativePage*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  CHECK(completion);
  if (!navigation || !self.window || container.window != self.window || !path.isAbsolutePath ||
      ![path isEqualToString:path.stringByStandardizingPath] || !parc::ready ||
      _state->close_in_progress || _state->close_approved || parc::quitting) {
    completion(nil, parc::Error(@"The restored page's window or Profile is unavailable."));
    return;
  }
  __weak NSView* weak_container = container;
  auto admitted = base::BindOnce(
      [](PCNativeBrowserWindow* binding, NSView* __weak weak_container, NSString* path,
         NSObject* navigation, BOOL background,
         void (^completion)(PCNativePage*, NSError*),
         BrowserWindowInterface* browser, bool created, NSError* error) {
        NSView* destination = weak_container;
        auto abandon = [&](NSError* failure) {
          if (created && browser && browser->GetTabStripModel()->empty() &&
              !browser->IsDeleteScheduled()) browser->GetWindow()->Close();
          completion(nil, failure);
        };
        if (!browser || destination.window != binding.window || !binding.window ||
            !binding.client || parc::quitting || parc::preparing_global_close ||
            [binding state].close_in_progress || [binding state].close_approved ||
            !parc::AppKitBrowserAcceptsNewPages(*browser)) {
          abandon(error ?: parc::Error(@"The restored page's owner changed."));
          return;
        }
        // Created hidden like every other page: only the host's visibility
        // pass, after sizing it, can make it VISIBLE and so start its load.
        auto restored = parc::CreateRestoredContents(navigation, *browser->GetProfile(),
                                                     /*initially_hidden=*/true);
        if (!restored) {
          abandon(parc::Error(@"The page's history belongs to another Profile."));
          return;
        }
        //
        // and the restored current entry loads once attached at its size.
        auto weak_browser = browser->GetWeakPtr();
        auto* contents = restored.get();
        auto* tabs = browser->GetTabStripModel();
        tabs->InsertWebContentsAt(tabs->count(), std::move(restored),
                                  background ? AddTabTypes::ADD_NONE : AddTabTypes::ADD_ACTIVE);
        const auto inserted_failure = [](NSString* message) {
          return [NSError errorWithDomain:@"org.parc.independent-engine" code:2
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
        };
        if (!weak_browser) {
          completion(nil, inserted_failure(@"The restored page's Browser closed."));
          return;
        }
        auto cef = ChromeBrowserHostImpl::GetBrowserForContents(contents);
        if (!cef || cef->browser() != browser || !parc::GetNativeRoute(*browser->GetProfile())) {
          // Retire this inserted child through TabStripModel, as an embedded
          // page's refused creation does, instead of leaving an orphan.
          const int index = tabs->GetIndexOfWebContents(contents);
          if (index != TabStripModel::kNoTab) tabs->CloseWebContentsAt(index, 0);
          completion(nil, inserted_failure(@"The restored page has no native owner."));
          return;
        }
        // It loads once attached and laid out at its size (AppKitBrowserHost
        // Attach), as Chrome's AddRestoredTab sizes before LoadIfNecessary.
        auto* platform = static_cast<parc::NativeChromePlatformDelegate*>(cef->platform_delegate());
        PCNativePage* page = parc::GetOrCreateNativePage(*contents, *platform, path);
        if (![binding pageDidAttach:page container:destination]) {
          [page requestClose:^(PCNativePageCloseResult) {}];
          completion(nil, inserted_failure(@"The restored page could not attach."));
          return;
        }
        completion(page, nil);
      }, self, weak_container, path, navigation, background, [completion copy]);
  if (_state->private_mode) {
    // A private window restores only into its own living OTR Browser.
    Profile* profile = parc::NativePrivateProfileForWindow(self, path);
    auto found = profile ? _state->browsers.find(profile) : _state->browsers.end();
    BrowserWindowInterface* browser = found == _state->browsers.end() ? nullptr : found->second.get();
    std::move(admitted).Run(browser, false,
        browser ? nil : parc::Error(@"The original private browsing context closed."));
    return;
  }
  parc::WithNativeRoutingBrowser(self, path, std::move(admitted));
}
- (PCNativeEmbeddedPageRequest*)createEmbeddedPageWithURL:(NSURL*)url
    profilePath:(NSString*)path container:(NSView*)container
    validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  CHECK(validateOwner);
  CHECK(completion);
  PCNativeEmbeddedPageRequest* request =
      [[PCNativeEmbeddedPageRequest alloc] initWithCompletion:completion];
  __weak PCNativeBrowserWindow* weak_binding = self;
  __weak NSWindow* original_window = self.window;
  __weak NSView* weak_container = container;
  NSString* original_path = [path copy];
  NSURL* original_url = [url copy];
  auto create = base::BindOnce(^{
    PCNativeBrowserWindow* binding = weak_binding;
    NSWindow* window = original_window;
    NSView* destination = weak_container;
    const GURL target(original_url.absoluteString.UTF8String ?: "");
    if (!request.pending) return;
    if (!parc::ready || parc::quitting || parc::preparing_global_close ||
        !window || !binding || binding.window != window || !binding.client ||
        destination.window != window || !original_path.isAbsolutePath ||
        ![original_path isEqualToString:original_path.stringByStandardizingPath] ||
        !target.is_valid() || !target.SchemeIsHTTPOrHTTPS() ||
        [binding state].close_in_progress || [binding state].close_approved ||
        !validateOwner()) {
      [request finishWithPage:nil error:parc::Error(@"The embedded page owner is unavailable.")];
      return;
    }
    auto admitted = base::BindOnce(
        [](PCNativeBrowserWindow* binding, NSWindow* __weak original_window,
           NSView* __weak weak_container, NSString* path, NSURL* url,
           BOOL (^validateOwner)(void), PCNativeEmbeddedPageRequest* request,
           BrowserWindowInterface* browser, bool created, NSError* error) {
          const auto weak_browser = browser ? browser->GetWeakPtr() :
              base::WeakPtr<BrowserWindowInterface>();
          auto close_empty = [&] {
            if (created && weak_browser && weak_browser->GetTabStripModel()->empty() &&
                !weak_browser->IsDeleteScheduled()) weak_browser->GetWindow()->Close();
          };
          auto valid = [&] {
            NSWindow* window = original_window;
            NSView* container = weak_container;
            return request.pending && weak_browser && window && binding.client &&
                binding.window == window && container.window == window &&
                !parc::quitting && !parc::preparing_global_close &&
                !parc::HasNativePageRetirementWork() && !window.attachedSheet &&
                !PCNativeWindowHasSecurityReservation(window) &&
                ![binding state].close_in_progress && ![binding state].close_approved &&
                parc::AppKitBindingForBrowser(weak_browser.get()) == binding &&
                parc::AppKitBrowserAcceptsNewPages(*weak_browser) &&
                parc::NativeContextForProfile(*weak_browser->GetProfile()) &&
                [parc::ProfilePath(*weak_browser->GetProfile()) isEqualToString:path];
          };
          // Recheck native ownership after the app query too; it must not be
          // able to authorize a stale Browser by reentering during validation.
          if (!valid() || !validateOwner() || !valid() || ![request beginCommit]) {
            close_empty();
            [request finishWithPage:nil error:error ?: parc::Error(@"The Easel changed before page creation.")];
            return;
          }
          // Create the actual empty renderer first, attach and classify it,
          // then navigate the requested URL exactly once. No web script runs
          // before the view has an authoritative auxiliary owner.
          auto* contents = chrome::AddAndReturnTabAt(
              browser, GURL(url::kAboutBlankURL), TabStripModel::kNoTab, false);
          auto cef = weak_browser && contents ? ChromeBrowserHostImpl::GetBrowserForContents(contents) : nullptr;
          if (!weak_browser || !cef || cef->browser() != browser) {
            // No requested navigation has begun. Retire this actual empty
            // child through TabStripModel instead of leaving an orphan.
            if (weak_browser && contents) {
              const int index = weak_browser->GetTabStripModel()->GetIndexOfWebContents(contents);
              if (index != TabStripModel::kNoTab)
                weak_browser->GetTabStripModel()->CloseWebContentsAt(index, 0);
            }
            close_empty();
            [request finishWithPage:nil error:parc::Error(@"Embedded renderer creation was refused.")];
            return;
          }
          auto* platform = static_cast<parc::NativeChromePlatformDelegate*>(cef->platform_delegate());
          PCNativePage* page = parc::GetOrCreateNativePage(*contents, *platform, path);
          parc::MarkNativePageEmbedded(page);
          if (!valid() || ![binding pageDidAttach:page container:weak_container] || !valid()) {
            [page requestClose:^(PCNativePageCloseResult) {}];
            [request finishWithPage:nil error:parc::Error(@"The embedded renderer could not attach to its original window.")];
            return;
          }
          auto frame = cef->GetMainFrame();
          if (!frame) {
            [page requestClose:^(PCNativePageCloseResult) {}];
            [request finishWithPage:nil error:parc::Error(@"The embedded renderer has no navigation owner.")];
            return;
          }
          frame->LoadURL(url.absoluteString.UTF8String);
          [request finishWithPage:page error:nil];
        }, binding, original_window, weak_container, original_path, original_url,
        [validateOwner copy], request);
    if ([binding state].private_mode) {
      Profile* profile = parc::NativePrivateProfileForWindow(binding, original_path);
      auto found = profile ? [binding state].browsers.find(profile) : [binding state].browsers.end();
      auto* browser = found == [binding state].browsers.end() ? nullptr : found->second.get();
      std::move(admitted).Run(browser, false, nil);
    } else {
      parc::WithNativeRoutingBrowser(binding, original_path, std::move(admitted));
    }
  });
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
      FROM_HERE, std::move(create));
  return request;
}
- (void)synchronizeSelectionAndLayout {
  CHECK(NSThread.isMainThread);
  // Keep only this binding/client alive across callbacks. Browser and page
  // contents remain weak, and a newer explicit command supersedes this one.
  PCNativeBrowserWindow* binding = self;
  parc::CancelInvalidNativeDownloadFileDialogs(
      gfx::NativeWindow(binding.window));
  id<PCNativeBrowserWindowClient> client = binding.client;
  NSWindow* __weak window = binding.window;
  const auto generation = ++_state->selection_generation;
  const auto ownership_epoch = _state->ownership_epoch;
  const auto browsers = _state->browsers;
  PCNativePage* selected = [client selectedNativePage];
  auto* selected_contents = parc::ContentsForNativePage(selected);
  const auto contents = selected_contents
                            ? selected_contents->GetWeakPtr()
                            : base::WeakPtr<content::WebContents>();
  auto current_binding = [&]() {
    const auto& state = [binding state];
    return state.selection_generation == generation &&
           state.ownership_epoch == ownership_epoch && client && window &&
           binding.client == client && binding.window == window &&
           !state.close_approved && !parc::quitting &&
           (!selected ||
            (contents &&
             parc::ContentsForNativePage(selected) == contents.get() &&
             selected.nativeView.window == window));
  };
  auto current_request = [&]() {
    if (!current_binding()) {
      return false;
    }
    PCNativePage* latest = [client selectedNativePage];
    return current_binding() && latest == selected;
  };
  for (const auto& [profile, browser] : browsers) {
    if (!current_request()) {
      return;
    }
    auto current_browser = [&]() {
      if (!current_binding() || !browser) {
        return false;
      }
      const auto& current_browsers = [binding state].browsers;
      const auto found = current_browsers.find(profile);
      return found != current_browsers.end() &&
             found->second.get() == browser.get() &&
             browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() ==
                 window;
    };
    if (!current_browser()) {
      return;
    }
    auto* adapter =
        static_cast<parc::NativeBrowserWindow*>(browser->GetWindow());
    const int index =
        contents
            ? browser->GetTabStripModel()->GetIndexOfWebContents(contents.get())
            : TabStripModel::kNoTab;
    adapter->SetSelectedForNativeWindow(index != TabStripModel::kNoTab);
    if (!current_request() || !current_browser()) {
      return;
    }
    // Activation can invoke shell callbacks. Resolve the same contents again
    // only while this remains the latest exact shell selection request.
    const int current_index =
        contents
            ? browser->GetTabStripModel()->GetIndexOfWebContents(contents.get())
            : TabStripModel::kNoTab;
    if (current_index != TabStripModel::kNoTab &&
        browser->GetTabStripModel()->GetActiveWebContents() != contents.get()) {
      browser->GetTabStripModel()->ActivateTabAt(current_index);
    }
    if (!current_request() || !current_browser()) {
      return;
    }
    parc::SynchronizeAppKitBrowser(*browser);
    if (!current_request() || !current_browser()) {
      return;
    }
    parc::SynchronizeAppKitBrowserVisibility(*browser);
    if (!current_request() || !current_browser()) {
      return;
    }
    static_cast<parc::NativeBrowserWindow*>(browser->GetWindow())
        ->NotifyActiveHostGeometryChanged();
  }
}
- (void)synchronizeLayout {
  CHECK(NSThread.isMainThread);
  const auto browsers = _state->browsers;
  for (const auto& [profile, browser] : browsers) {
    if (!browser) {
      continue;
    }
    parc::SynchronizeAppKitBrowser(*browser);
    if (browser) {
      parc::SynchronizeAppKitBrowserVisibility(*browser);
    }
    if (browser) {
      static_cast<parc::NativeBrowserWindow*>(browser->GetWindow())
          ->NotifyActiveHostGeometryChanged();
    }
  }
}
- (content::WebContents*)pictureInPicturePage {
  CHECK(NSThread.isMainThread);
  auto* child = PictureInPictureWindowManager::GetInstance()->GetChildWebContents();
  auto cef = child ? ChromeBrowserHostImpl::GetBrowserForContents(child)
                   : nullptr;
  return cef && cef->browser() &&
                 parc::AppKitBindingForBrowser(cef->browser()) == self
             ? child
             : nullptr;
}
- (BOOL)canReturnPictureInPictureToOpener {
  auto* child = [self pictureInPicturePage];
  const auto options = child ? child->GetPictureInPictureOptions()
                             : std::nullopt;
  return child && !(options && options->disallow_return_to_opener);
}
- (BOOL)returnPictureInPictureToOpener {
  if (![self pictureInPicturePage]) {
    return NO;
  }
  // The opener is activated before the PiP page closes, without pausing media.
  return PictureInPictureWindowManager::GetInstance()
      ->ExitPictureInPictureViaWindowUi(
          PictureInPictureWindowManager::UiBehavior::kCloseWindowAndFocusOpener);
}
- (void)setWebsiteThemeStylesheet:(NSString*)stylesheet {
  CHECK(NSThread.isMainThread);
  _state->website_theme_stylesheet = [stylesheet copy];
  const auto browsers = _state->browsers;
  for (const auto& [profile, browser] : browsers) {
    if (browser && browser->GetProfile() == profile &&
        parc::AppKitBindingForBrowser(browser.get()) == self) {
      parc::SetAppKitWebsiteTheme(*browser,
          _state->window && _state->client && !_state->close_approved
              ? _state->website_theme_stylesheet : nil);
    }
  }
}
- (void)pageWillDetach:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(page);
  auto cef = contents ? ChromeBrowserHostImpl::GetBrowserForContents(contents)
                      : nullptr;
  if (!cef || !cef->browser() ||
      parc::AppKitBindingForBrowser(cef->browser()) != self) {
    return;
  }
  parc::DetachAppKitPage(*cef->browser(), page);
}
- (BOOL)pageDidAttach:(PCNativePage*)page container:(NSView*)container {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(page);
  if (!contents || (page.isEmbedded && !page.embeddedOwnerValid) || container.window != self.window) {
    return NO;
  }
  auto cef = ChromeBrowserHostImpl::GetBrowserForContents(contents);
  if (!cef || !cef->browser() ||
      parc::AppKitBindingForBrowser(cef->browser()) != self) {
    return NO;
  }
  return parc::AttachAppKitPage(*cef->browser(), page, container);
}
- (void)requestClose:(void (^)(BOOL))completion {
  CHECK(NSThread.isMainThread);
  CHECK(completion);
  if (parc::HasNativePageRetirementWork() || parc::HasLiveTabTransfer() ||
      parc::preparing_live_transfer) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(NO);
    });
    return;
  }
  if (_state->close_in_progress) {
    _state->close_callbacks.push_back([completion copy]);
    return;
  }
  // Overlapping aggregates cannot own the same UnloadController callbacks.
  // A busy refusal leaves every page and model unchanged and can be retried.
  if (parc::ActiveCloseTransaction() || parc::preparing_global_close) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(NO);
    });
    return;
  }
  _state->close_callbacks.push_back([completion copy]);
  parc::BeginNativeClose(@[ self ], false, nil);
}
@end

@implementation PCNativeBrowserWindow (LivePageTransfer)
- (BOOL)canAdmitHiddenPageTransferDestination {
  CHECK(NSThread.isMainThread);
  return parc::ready && !parc::quitting && self.window &&
      !self.window.miniaturized && !self.window.attachedSheet && NSApp.active &&
      !PCNativeWindowHasSecurityReservation(self.window) &&
      [PCNativeBrowserApplication windowForNativeWindow:self.window] == self &&
      ![self state].close_in_progress && ![self state].close_approved;
}
- (BOOL)canParticipateInPageTransfer {
  return parc::ready && !parc::quitting && self.window && self.window.visible &&
      !self.window.miniaturized && !self.window.attachedSheet && NSApp.active &&
      !PCNativeWindowHasSecurityReservation(self.window) &&
      [PCNativeBrowserApplication windowForNativeWindow:self.window] == self &&
      ![self state].close_in_progress && ![self state].close_approved;
}
- (void)transferPage:(PCNativePage*)page
         profilePath:(NSString*)path
           container:(NSView*)container
          completion:
              (void (^)(PCNativePageTransferResult, NSError*))completion {
  CHECK(NSThread.isMainThread);
  CHECK(completion);
  __attribute__((objc_precise_lifetime)) PCNativeBrowserWindow* keep = self;
  (void)keep;
  __block BOOL owns_operation = NO;
  auto close_empty_source = std::make_shared<base::OnceClosure>();
  auto close_new_destination = std::make_shared<base::OnceClosure>();
  auto finish = ^(PCNativePageTransferResult result, NSString* detail) {
    NSError* error = detail ? parc::Error(detail) : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      // Keep the operation reserved through callback reentry. Otherwise a
      // second transfer could empty an owner and still be awaiting its own
      // result when this older operation closes that owner below.
      completion(result, error);
      if (owns_operation) {
        owns_operation = NO;
        parc::preparing_live_transfer = false;
      }
      // Swift has now committed/released the exact page and window claims.
      // Only then may an emptied source or our newly created empty destination
      // enter normal Browser close and asynchronous native-service teardown.
      if (*close_empty_source) {
        std::move(*close_empty_source).Run();
      }
      if (*close_new_destination) {
        std::move(*close_new_destination).Run();
      }
      parc::NotifyNativeEngineOwnershipChanged();
    });
  };
  auto* contents = parc::ContentsForNativePage(page);
  auto* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  auto* source = tab ? tab->GetBrowserWindowInterface() : nullptr;
  PCNativeBrowserWindow* source_binding = parc::AppKitBindingForBrowser(source);
  NSView* source_container =
      source ? parc::AppKitPageContainer(*source, page) : nil;
  if (!parc::ready || parc::quitting || page.isEmbedded ||
      parc::HasPendingNativeApplicationWork() || !source || !source_binding ||
      source_binding == self || !source_binding.window || !self.window ||
      !self.client || container.window != self.window || !source_container ||
      source_container.window != source_binding.window ||
      container == page.nativeView ||
      [container isDescendantOf:page.nativeView] ||
      ![path isEqualToString:parc::ProfilePath(*source->GetProfile())] ||
      (source->GetType() != BrowserWindowInterface::TYPE_NORMAL &&
       source->GetType() != BrowserWindowInterface::TYPE_POPUP) ||
      !parc::AppKitBrowserAcceptsNewPages(*source) ||
      [self state].close_in_progress || [self state].close_approved) {
    finish(PCNativePageTransferRefused,
           @"The exact source page, destination window or matching Profile is "
           @"unavailable.");
    return;
  }
  const auto source_weak = source->GetWeakPtr();
  const auto contents_weak = contents->GetWeakPtr();
  const auto tab_weak = tab->GetWeakPtr();
  Profile* profile = source->GetProfile();
  auto route = parc::GetNativeRoute(*profile);
  auto cef = ChromeBrowserHostImpl::GetBrowserForContents(contents);
  if (!route || !cef || cef->browser() != source) {
    finish(PCNativePageTransferRefused,
           @"The page has no current native route.");
    return;
  }
  parc::preparing_live_transfer = true;
  owns_operation = YES;
  auto& state = [self state];
  auto found = state.browsers.find(profile);
  BrowserWindowInterface* destination =
      found == state.browsers.end() ? nullptr : found->second.get();
  bool created_destination = false;
  if (!destination) {
    if (GetBrowserWindowCreationStatusForProfile(*profile) !=
        BrowserWindowInterface::CreationStatus::kOk) {
      finish(PCNativePageTransferRefused,
             @"The destination Browser cannot be created.");
      return;
    }
    // Construct only the real empty Browser. No substitute/blank WebContents
    // exists, and the exact supplied NSWindow is the one-use reservation.
    CefBrowserCreateParams native_params;
    native_params.request_context = cef->GetRequestContext();
    native_params.client = route->client();
    native_params.native_route = route;
    native_params.native_reservation =
        std::make_shared<parc::PreparedAppKitWindow>(
            *profile, BrowserWindowInterface::TYPE_NORMAL, self);
    BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL,
                                     *profile, true);
    params.should_trigger_session_restore = false;
    params.cef_params =
        base::MakeRefCounted<ChromeBrowserHostImpl::DelegateCreateParams>(
            native_params);
    destination = CreateBrowserWindow(std::move(params));
    created_destination = destination != nullptr;
  }
  const auto empty_destination = created_destination
                                     ? destination->GetWeakPtr()
                                     : base::WeakPtr<BrowserWindowInterface>();
  if (empty_destination) {
    *close_new_destination = base::BindOnce(
        [](base::WeakPtr<BrowserWindowInterface> browser) {
          if (browser && !browser->IsDeleteScheduled() &&
              browser->GetTabStripModel()->empty()) {
            browser->GetWindow()->Close();
          }
        },
        empty_destination);
  }
  if (!destination || !source_weak || !contents_weak || !tab_weak ||
      tabs::TabInterface::MaybeGetFromContents(contents_weak.get()) !=
          tab_weak.get() ||
      tab_weak->GetBrowserWindowInterface() != source_weak.get() ||
      parc::AppKitBindingForBrowser(destination) != self ||
      destination->GetProfile() != source_weak->GetProfile() ||
      !parc::AppKitBrowserAcceptsNewPages(*destination) ||
      container.window != self.window ||
      source_container.window != source_binding.window) {
    finish(PCNativePageTransferRefused,
           @"Native ownership changed before transfer.");
    return;
  }
  auto destination_weak = destination->GetWeakPtr();
  const auto result = parc::TransferLiveTab(
      *contents_weak, *destination,
      base::BindRepeating(
          ^bool(BrowserWindowInterface& owner, content::WebContents& actual) {
            if (parc::ContentsForNativePage(page) != &actual) {
              return false;
            }
            if (destination_weak && &owner == destination_weak.get() &&
                parc::AppKitBindingForBrowser(&owner) == self &&
                container.window == self.window) {
              return parc::AttachAppKitPage(owner, page, container);
            }
            if (source_weak && &owner == source_weak.get() &&
                parc::AppKitBindingForBrowser(&owner) == source_binding &&
                source_container.window == source_binding.window) {
              return parc::AttachAppKitPage(owner, page, source_container);
            }
            return false;
          }),
      close_empty_source.get());
  switch (result) {
    case parc::TabTransferResult::kTransferred:
      finish(PCNativePageTransferTransferred, nil);
      return;
    case parc::TabTransferResult::kRefused:
      finish(PCNativePageTransferRefused,
             @"The real tab or window is busy closing.");
      return;
    case parc::TabTransferResult::kRestoredToSource:
      finish(PCNativePageTransferRestored,
             @"The destination could not attach the page; its actual tab was "
             @"restored.");
      return;
    case parc::TabTransferResult::kExternallyInterrupted:
      finish(PCNativePageTransferInterrupted,
             @"An independent owner changed the page during transfer.");
      return;
  }
}
- (void)transferPages:(NSArray<PCNativePage*>*)pages
         profilePath:(NSString*)path
          containers:(NSArray<NSView*>*)containers
              commit:(BOOL (^)(void))commit
          completion:
              (void (^)(PCNativePageTransferResult, NSError*))completion {
  CHECK(NSThread.isMainThread);
  CHECK(completion); CHECK(commit);
  pages = [pages copy];
  containers = [containers copy];
  PCNativePage* page = pages.firstObject;
  NSView* container = containers.firstObject;
  __attribute__((objc_precise_lifetime)) PCNativeBrowserWindow* keep = self;
  (void)keep;
  __block BOOL owns_operation = NO;
  auto close_empty_sources = std::make_shared<std::vector<base::OnceClosure>>();
  auto finish = ^(PCNativePageTransferResult result, NSString* detail) {
    NSError* error = detail ? parc::Error(detail) : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      // Keep the operation reserved through callback reentry. Otherwise a
      // second transfer could empty an owner and still be awaiting its own
      // result when this older operation closes that owner below.
      completion(result, error);
      if (owns_operation) {
        owns_operation = NO;
        parc::preparing_live_transfer = false;
      }
      // Both physical windows remain caller-owned. Either may contain local
      // Notes/Easels or unmaterialized sidebar items even with an empty native
      // strip. Keep their cached Browsers until the actual window-close owner
      // approves retirement, including a destination created for this attempt.
      close_empty_sources->clear();
      parc::NotifyNativeEngineOwnershipChanged();
    });
  };
  auto* contents = parc::ContentsForNativePage(page);
  auto* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  auto* source = tab ? tab->GetBrowserWindowInterface() : nullptr;
  PCNativeBrowserWindow* source_binding = parc::AppKitBindingForBrowser(source);
  NSView* source_container =
      source ? parc::AppKitPageContainer(*source, page) : nil;
  if (!parc::ready || parc::quitting || (page.isEmbedded && !page.embeddedOwnerValid) ||
      parc::HasPendingNativeApplicationWork() || !source || !source_binding ||
      source_binding == self || !source_binding.window || !self.window ||
      !self.client || container.window != self.window || !source_container ||
      source_container.window != source_binding.window ||
      container == page.nativeView ||
      [container isDescendantOf:page.nativeView] ||
      ![path isEqualToString:parc::ProfilePath(*source->GetProfile())] ||
      (source->GetType() != BrowserWindowInterface::TYPE_NORMAL &&
       source->GetType() != BrowserWindowInterface::TYPE_POPUP) ||
      !parc::AppKitBrowserAcceptsNewPages(*source) ||
      [self state].close_in_progress || [self state].close_approved) {
    finish(PCNativePageTransferRefused,
           @"The exact source page, destination window or matching Profile is "
           @"unavailable.");
    return;
  }
  if (!self.canParticipateInPageTransfer || !source_binding.canParticipateInPageTransfer ||
      pages.count == 0 || pages.count != containers.count) {
    finish(PCNativePageTransferRefused, @"The original collection is unavailable."); return;
  }
  std::vector<content::WebContents*> actual_pages;
  NSMutableArray<NSView*>* source_containers = [NSMutableArray array];
  for (NSUInteger i = 0; i < pages.count; ++i) {
    auto* actual = parc::ContentsForNativePage(pages[i]);
    auto* actual_tab = actual ? tabs::TabInterface::MaybeGetFromContents(actual) : nullptr;
    NSView* original = parc::AppKitPageContainer(*source, pages[i]);
    auto host = actual ? ChromeBrowserHostImpl::GetBrowserForContents(actual) : nullptr;
    if (!actual_tab || actual_tab->GetBrowserWindowInterface() != source || !host ||
        host->browser() != source || (pages[i].isEmbedded && !pages[i].embeddedOwnerValid) || !original ||
        original.window != source_binding.window || containers[i].window != self.window ||
        containers[i] == pages[i].nativeView || [containers[i] isDescendantOf:pages[i].nativeView] ||
        std::ranges::find(actual_pages, actual) != actual_pages.end()) {
      finish(PCNativePageTransferRefused, @"The exact collection no longer belongs to one source window."); return;
    }
    actual_pages.push_back(actual); [source_containers addObject:original];
  }
  const auto source_weak = source->GetWeakPtr();
  const auto contents_weak = contents->GetWeakPtr();
  const auto tab_weak = tab->GetWeakPtr();
  Profile* profile = source->GetProfile();
  auto route = parc::GetNativeRoute(*profile);
  auto cef = ChromeBrowserHostImpl::GetBrowserForContents(contents);
  if (!route || !cef || cef->browser() != source) {
    finish(PCNativePageTransferRefused,
           @"The page has no current native route.");
    return;
  }
  parc::preparing_live_transfer = true;
  owns_operation = YES;
  auto& state = [self state];
  auto found = state.browsers.find(profile);
  BrowserWindowInterface* destination =
      found == state.browsers.end() ? nullptr : found->second.get();
  if (!destination) {
    if (GetBrowserWindowCreationStatusForProfile(*profile) !=
        BrowserWindowInterface::CreationStatus::kOk) {
      finish(PCNativePageTransferRefused,
             @"The destination Browser cannot be created.");
      return;
    }
    // Construct only the real empty Browser. No substitute/blank WebContents
    // exists, and the exact supplied NSWindow is the one-use reservation.
    CefBrowserCreateParams native_params;
    native_params.request_context = cef->GetRequestContext();
    native_params.client = route->client();
    native_params.native_route = route;
    native_params.native_reservation =
        std::make_shared<parc::PreparedAppKitWindow>(
            *profile, BrowserWindowInterface::TYPE_NORMAL, self);
    BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL,
                                     *profile, true);
    params.should_trigger_session_restore = false;
    params.cef_params =
        base::MakeRefCounted<ChromeBrowserHostImpl::DelegateCreateParams>(
            native_params);
    destination = CreateBrowserWindow(std::move(params));
  }
  if (!destination || !source_weak || !contents_weak || !tab_weak ||
      tabs::TabInterface::MaybeGetFromContents(contents_weak.get()) !=
          tab_weak.get() ||
      tab_weak->GetBrowserWindowInterface() != source_weak.get() ||
      parc::AppKitBindingForBrowser(destination) != self ||
      destination->GetProfile() != source_weak->GetProfile() ||
      !parc::AppKitBrowserAcceptsNewPages(*destination) ||
      container.window != self.window ||
      source_container.window != source_binding.window) {
    finish(PCNativePageTransferRefused,
           @"Native ownership changed before transfer.");
    return;
  }
  // Browser creation can synchronously notify unrelated owners. Resolve every
  // original again instead of dereferencing the pre-creation raw pointer list.
  actual_pages.clear();
  for (NSUInteger i = 0; i < pages.count; ++i) {
    auto* actual = parc::ContentsForNativePage(pages[i]);
    auto* original_tab = actual ? tabs::TabInterface::MaybeGetFromContents(actual) : nullptr;
    if (!original_tab || original_tab->GetBrowserWindowInterface() != source_weak.get() ||
        source_containers[i].window != source_binding.window || containers[i].window != self.window) {
      finish(PCNativePageTransferRefused, @"An original page changed during destination preparation.");
      return;
    }
    actual_pages.push_back(actual);
  }
  auto destination_weak = destination->GetWeakPtr();
  const auto result = parc::TransferLiveTabs(
      actual_pages, *destination,
      base::BindRepeating(^bool(BrowserWindowInterface& owner, content::WebContents& actual) {
        for (NSUInteger i = 0; i < pages.count; ++i) {
          if (parc::ContentsForNativePage(pages[i]) != &actual) continue;
          if (destination_weak && &owner == destination_weak.get() &&
              parc::AppKitBindingForBrowser(&owner) == self && containers[i].window == self.window)
            return (!pages[i].isEmbedded || (source_weak &&
                parc::RebindNativeEmbeddedPageForTransfer(pages[i], *source_weak, owner))) &&
                parc::AttachAppKitPage(owner, pages[i], containers[i]);
          if (source_weak && &owner == source_weak.get() &&
              parc::AppKitBindingForBrowser(&owner) == source_binding &&
              source_containers[i].window == source_binding.window)
            return (!pages[i].isEmbedded || (destination_weak &&
                parc::RebindNativeEmbeddedPageForTransfer(pages[i], *destination_weak, owner))) &&
                parc::AttachAppKitPage(owner, pages[i], source_containers[i]);
          return false;
        }
        return false;
      }), base::BindOnce(^bool { return commit(); }), close_empty_sources.get());
  switch (result) {
    case parc::TabTransferResult::kTransferred:
      finish(PCNativePageTransferTransferred, nil);
      return;
    case parc::TabTransferResult::kRefused:
      finish(PCNativePageTransferRefused,
             @"The real tab or window is busy closing.");
      return;
    case parc::TabTransferResult::kRestoredToSource:
      finish(PCNativePageTransferRestored,
             @"The destination could not attach the page; its actual tab was "
             @"restored.");
      return;
    case parc::TabTransferResult::kExternallyInterrupted:
      finish(PCNativePageTransferInterrupted,
             @"An independent owner changed the page during transfer.");
      return;
  }
}
@end

@interface PCNativeDownloadReviewButton ()
- (instancetype)initWithAction:(PCNativeDownloadReviewAction)action
                         title:(NSString*)title;
@end
@implementation PCNativeDownloadReviewButton
@synthesize action = _action;
@synthesize title = _title;
- (instancetype)initWithAction:(PCNativeDownloadReviewAction)action
                         title:(NSString*)title {
  self = [super init];
  if (self) { _action = action; _title = [title copy]; }
  return self;
}
@end

@interface PCNativeDownloadReview ()
- (instancetype)initWithProfile:(Profile&)profile
                         values:(parc::NativeDownloadReview)values;
- (Profile*)profileIdentity;
- (const parc::NativeDownloadReview&)values;
@end

@implementation PCNativeDownloadReview {
  base::WeakPtr<Profile> _profile;
  parc::NativeDownloadReview _values;
}
@synthesize identifier = _identifier;
@synthesize profilePath = _profilePath;
@synthesize fileName = _fileName;
@synthesize sourceURL = _sourceURL;
@synthesize warning = _warning;
@synthesize secondaryWarning = _secondaryWarning;
@synthesize keepTitle = _keepTitle;
@synthesize discardTitle = _discardTitle;
@synthesize canKeep = _canKeep;
@synthesize canDiscard = _canDiscard;
@synthesize buttons = _buttons;
@synthesize linkTitles = _linkTitles;
@synthesize needsPassword = _needsPassword;
@synthesize incorrectPassword = _incorrectPassword;
@synthesize scanning = _scanning;
@synthesize needsJustification = _needsJustification;
@synthesize passwordLabel = _passwordLabel;
@synthesize passwordError = _passwordError;
@synthesize passwordEmptyError = _passwordEmptyError;
@synthesize justificationLabel = _justificationLabel;
- (instancetype)initWithProfile:(Profile&)profile
                         values:(parc::NativeDownloadReview)values {
  self = [super init];
  if (self) {
    _profile = profile.GetWeakPtr();
    _values = std::move(values);
    _profilePath = [parc::ProfilePath(profile) copy];
    _identifier = [base::SysUTF8ToNSString(_values.guid) copy];
    _fileName = [base::SysUTF16ToNSString(_values.name) copy];
    _sourceURL = [base::SysUTF8ToNSString(_values.url) copy];
    _warning = [base::SysUTF16ToNSString(_values.warning) copy];
    _secondaryWarning = [base::SysUTF16ToNSString(_values.secondary) copy];
    _keepTitle = [base::SysUTF16ToNSString(_values.keep_title) copy];
    _discardTitle = [base::SysUTF16ToNSString(_values.discard_title) copy];
    _canKeep = _values.can_keep;
    _canDiscard = _values.can_discard;
    NSMutableArray* buttons = [NSMutableArray array];
    for (const auto& button : _values.buttons) {
      PCNativeDownloadReviewAction action;
      switch (button.action) {
        case parc::NativeDownloadReviewAction::kKeep: action = PCNativeDownloadReviewActionKeep; break;
        case parc::NativeDownloadReviewAction::kDiscard: action = PCNativeDownloadReviewActionDiscard; break;
        case parc::NativeDownloadReviewAction::kScan: action = PCNativeDownloadReviewActionScan; break;
        case parc::NativeDownloadReviewAction::kBypassScan: action = PCNativeDownloadReviewActionBypassScan; break;
        case parc::NativeDownloadReviewAction::kCancelScan: action = PCNativeDownloadReviewActionCancelScan; break;
      }
      [buttons addObject:[[PCNativeDownloadReviewButton alloc]
          initWithAction:action title:base::SysUTF16ToNSString(button.title)]];
    }
    _buttons = [buttons copy];
    NSMutableArray* links = [NSMutableArray array];
    for (const auto& link : _values.links)
      [links addObject:base::SysUTF16ToNSString(link.title)];
    _linkTitles = [links copy];
    _needsPassword = _values.needs_password;
    _incorrectPassword = _values.incorrect_password;
    _scanning = _values.scanning;
    _needsJustification = _values.needs_justification;
    _passwordLabel = [base::SysUTF16ToNSString(_values.password_label) copy];
    _passwordError = [base::SysUTF16ToNSString(_values.password_error) copy];
    _passwordEmptyError = [base::SysUTF16ToNSString(_values.password_empty_error) copy];
    _justificationLabel = [base::SysUTF16ToNSString(_values.justification_label) copy];
  }
  return self;
}
- (Profile*)profileIdentity { return _profile.get(); }
- (const parc::NativeDownloadReview&)values { return _values; }
@end

@interface PCNativeDownloadPreferences ()
- (instancetype)initWithProfile:(Profile&)profile
                         values:(const parc::NativeDownloadPreferencesSnapshot&)
                                    values;
- (Profile*)profileIdentity;
@end

@implementation PCNativeDownloadPreferences {
  base::WeakPtr<Profile> _profile;
}
@synthesize profilePath = _profilePath;
@synthesize directoryURL = _directoryURL;
@synthesize promptForDownload = _promptForDownload;
@synthesize directoryManaged = _directoryManaged;
@synthesize promptManaged = _promptManaged;
- (instancetype)initWithProfile:(Profile&)profile
                         values:(const parc::NativeDownloadPreferencesSnapshot&)
                                    values {
  self = [super init];
  if (self) {
    _profile = profile.GetWeakPtr();
    _profilePath = [parc::ProfilePath(profile) copy];
    _directoryURL =
        [NSURL fileURLWithPath:base::SysUTF8ToNSString(values.directory.value())
                   isDirectory:YES];
    _promptForDownload = values.prompt;
    _directoryManaged = values.directory_managed;
    _promptManaged = values.prompt_managed;
  }
  return self;
}
- (Profile*)profileIdentity {
  return _profile.get();
}
@end

namespace parc {
namespace {
Profile* DownloadPreferencesProfile(NSString* path,
                                    PCNativeDownloadPreferences* expected) {
  if (!ready || quitting || preparing_global_close || !path.length ||
      IsNativeProfileRemovalBlocked(base::FilePath(base::SysNSStringToUTF8(path)))) {
    return nullptr;
  }
  auto found = Profiles().find(base::SysNSStringToUTF8(path));
  if (found == Profiles().end() || !found->second.context ||
      found->second.failure || !found->second.profile) {
    return nullptr;
  }
  Profile* profile = found->second.profile.get();
  if (profile->IsOffTheRecord() ||
      ![ProfilePath(*profile) isEqualToString:path] ||
      !GetNativeRoute(*profile) || !NativeDownloads::From(*profile) ||
      (expected && [expected profileIdentity] != profile)) {
    return nullptr;
  }
  return profile;
}
PCNativeDownloadPreferences* DownloadPreferencesSnapshot(Profile& profile) {
  auto* preferences = DownloadPrefs::FromBrowserContext(&profile);
  return [[PCNativeDownloadPreferences alloc]
      initWithProfile:profile
               values:ReadNativeDownloadPreferences(profile, *preferences)];
}
}  // namespace
}  // namespace parc

@implementation PCNativeBrowserApplication
+ (NSArray<PCNativePrivateDownloadContext*>*)privateDownloadContexts {
  CHECK(NSThread.isMainThread);
  return [parc::PrivateDownloadContexts().allValues copy];
}
// Preparation may load the existing normal parent Profile but creates no page.
// The receiving app keeps its exact selected profile identity while this runs.
+ (void)preparePrivateBrowsingWithProfilePath:(NSString*)path
    completion:(void (^)(NSError*))completion {
  CHECK(NSThread.isMainThread);
  parc::WithNativeProfile(path, base::BindOnce(
      [](void (^completion)(NSError*), Profile* profile,
         CefRefPtr<CefRequestContext> context, NSError* error) {
        if (error || !profile || !context || profile->IsOffTheRecord() ||
            profile->ShutdownStarted()) {
          completion(error ?: parc::Error(@"The original profile is unavailable."));
          return;
        }
        if (IncognitoModePrefs::GetAvailability(profile) == policy::IncognitoModeAvailability::kDisabled) {
          completion(parc::Error(@"Private browsing is disabled for this profile."));
          return;
        }
        completion(nil);
      }, [completion copy]));
}
+ (void)accessibilityRoleRequested {
  CHECK(NSThread.isMainThread);
  auto& accessibility = parc::Accessibility();
  accessibility.basic_requested = true;
  accessibility.Apply();
}
+ (void)accessibilitySetValue:(id)value forAttribute:(NSString*)attribute {
  CHECK(NSThread.isMainThread);
  if (([attribute isEqualToString:@"AXManualAccessibility"] ||
       [attribute isEqualToString:@"AXEnhancedUserInterface"]) &&
      [value isKindOfClass:NSNumber.class] && [value boolValue]) {
    //
    // accessibility. They do not claim that a screen reader is running.
    [self accessibilityRoleRequested];
  }
}
+ (BOOL)accessibilityHandleObservationForKeyPath:(NSString*)keyPath
                                        ofObject:(id)object
                                          change:(NSDictionary*)change
                                         context:(void*)context {
  CHECK(NSThread.isMainThread);
  // Match the exact observer installed by BrowserAccessibilityStateImplMac,
  // just as ChromeBrowserApplication does. Forward unrelated KVO to AppKit.
  if (![keyPath isEqualToString:@"voiceOverEnabled"] ||
      object != NSWorkspace.sharedWorkspace) {
    return NO;
  }
  auto& accessibility = parc::Accessibility();
  // The initial notification is sent from the real singleton's constructor.
  // Cache its exact KVO identity during initialization; do not consult engine
  // state after shutdown, even if AppKit later delivers that context.
  if (!accessibility.observation_context && !accessibility.stopped) {
    accessibility.observation_context =
        content::BrowserAccessibilityState::GetInstance();
  }
  if (!accessibility.observation_context ||
      context != accessibility.observation_context) {
    return NO;
  }
  id value = change[NSKeyValueChangeNewKey];
  if ([value isKindOfClass:NSNumber.class]) {
    accessibility.voice_over = [value boolValue];
    accessibility.Apply();
  }
  return YES;
}
+ (PCNativeBrowserWindow*)windowForNativeWindow:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  return [parc::Windows() objectForKey:window];
}
+ (PCNativeBrowserWindow*)ownerForPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(page);
  if (!contents || contents->IsBeingDestroyed()) {
    return nil;
  }
  auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  auto* owner = tab ? tab->GetBrowserWindowInterface() : nullptr;
  auto cef = ChromeBrowserHostImpl::GetBrowserForContents(contents);
  if (!owner || owner->IsDeleteScheduled() || !cef || cef->browser() != owner ||
      owner->GetTabStripModel()->GetIndexOfTab(tab) == TabStripModel::kNoTab) {
    return nil;
  }
  return parc::AppKitBindingForBrowser(owner);
}
+ (PCNativeBrowserWindow*)registerWindowClient:
                              (id<PCNativeBrowserWindowClient>)client
                                         error:(NSError**)error {
  CHECK(NSThread.isMainThread);
  NSWindow* window = [client nativeBrowserWindow];
  if (!window || !client) {
    if (error) {
      *error = parc::Error(@"A real native window and client are required.");
    }
    return nil;
  }
  PCNativeBrowserWindow* existing = [parc::Windows() objectForKey:window];
  if (existing) {
    if (existing.client != client) {
      if (error) {
        *error =
            parc::Error(@"This native window is registered to another client.");
      }
      return nil;
    }
    return existing;
  }
  PCNativeBrowserWindow* binding =
      [[PCNativeBrowserWindow alloc] initWithClient:client];
  NSView* side = [client nativeBrowserSidePanelContainer:binding];
  if (!side || side.window != window) {
    if (error) {
      *error = parc::Error(
          @"The native side-panel container must belong to this window.");
    }
    return nil;
  }
  [parc::Windows() setObject:binding forKey:window];
  return binding;
}
+ (void)loadDownloadPreferencesForProfilePath:(NSString*)profilePath
    completion:(void (^)(PCNativeDownloadPreferences*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  parc::WithNativeProfile(profilePath, base::BindOnce(
      [](NSString* path, void (^reply)(PCNativeDownloadPreferences*, NSError*),
         Profile* profile, CefRefPtr<CefRequestContext> context, NSError* error) {
        // Recheck the registered original identity after asynchronous acquisition
        // and again at publication; profile removal cannot publish stale settings.
        base::WeakPtr<Profile> original = profile ? profile->GetWeakPtr() : nullptr;
        NSError* failure = error;
        if (!failure && (!context || !original ||
            parc::DownloadPreferencesProfile(path, nil) != original.get())) {
          failure = parc::Error(@"Download settings are unavailable for this profile.");
        }
        dispatch_async(dispatch_get_main_queue(), ^{
          if (failure) { reply(nil, failure); return; }
          if (!original || parc::DownloadPreferencesProfile(path, nil) != original.get()) {
            reply(nil, parc::Error(@"The profile closed before its download settings loaded."));
            return;
          }
          reply(parc::DownloadPreferencesSnapshot(*original), nil);
        });
      }, [profilePath copy], [completion copy]));
}
+ (PCNativeDownloadPreferences*)downloadPreferencesForProfilePath:
    (NSString*)profilePath {
  CHECK(NSThread.isMainThread);
  Profile* profile = parc::DownloadPreferencesProfile(profilePath, nil);
  return profile ? parc::DownloadPreferencesSnapshot(*profile) : nil;
}
+ (PCNativeDownloadPreferences*)
    setDownloadDirectoryURL:(NSURL*)directoryURL
             forPreferences:(PCNativeDownloadPreferences*)preferences
                      error:(NSError**)error {
  CHECK(NSThread.isMainThread);
  if (error) {
    *error = nil;
  }
  Profile* profile =
      parc::DownloadPreferencesProfile(preferences.profilePath, preferences);
  // A native folder chooser supplies an absolute local file URL. Do not treat
  // network URLs, relative URL resolutions or embedded NUL as file paths.
  NSString* path = directoryURL.path;
  const std::string bytes = base::SysNSStringToUTF8(path);
  const bool local_host = !directoryURL.host.length ||
                          [directoryURL.host isEqualToString:@"localhost"];
  if (!profile || !directoryURL.isFileURL || directoryURL.baseURL ||
      !local_host || !path.isAbsolutePath ||
      bytes.find('\0') != std::string::npos) {
    if (error) {
      *error = parc::Error(@"Choose a local folder for the current profile.");
    }
    return nil;
  }
  // Keep the real request context alive across synchronous pref observers.
  CefRefPtr<CefRequestContext> context =
      parc::Profiles()
          .at(base::SysNSStringToUTF8(preferences.profilePath))
          .context;
  auto weak_profile = profile->GetWeakPtr();
  auto* values = DownloadPrefs::FromBrowserContext(profile);
  const bool accepted = parc::SetNativeDownloadDirectory(*profile, *values,
                                                         base::FilePath(bytes));
  if (!accepted || !weak_profile ||
      parc::DownloadPreferencesProfile(preferences.profilePath, preferences) !=
          weak_profile.get()) {
    if (error) {
      *error = parc::Error(
          @"The download folder could not be changed for this profile.");
    }
    return nil;
  }
  return parc::DownloadPreferencesSnapshot(*weak_profile);
}
+ (PCNativeDownloadPreferences*)
    setPromptForDownload:(BOOL)prompt
          forPreferences:(PCNativeDownloadPreferences*)preferences
                   error:(NSError**)error {
  CHECK(NSThread.isMainThread);
  if (error) {
    *error = nil;
  }
  Profile* profile =
      parc::DownloadPreferencesProfile(preferences.profilePath, preferences);
  if (!profile) {
    if (error) {
      *error = parc::Error(
          @"Download preferences are unavailable for this profile.");
    }
    return nil;
  }
  CefRefPtr<CefRequestContext> context =
      parc::Profiles()
          .at(base::SysNSStringToUTF8(preferences.profilePath))
          .context;
  auto weak_profile = profile->GetWeakPtr();
  const bool accepted = parc::SetNativeDownloadPrompt(*profile, prompt);
  if (!accepted || !weak_profile ||
      parc::DownloadPreferencesProfile(preferences.profilePath, preferences) !=
          weak_profile.get()) {
    if (error) {
      *error = parc::Error(
          @"The save-location prompt could not be changed for this profile.");
    }
    return nil;
  }
  return parc::DownloadPreferencesSnapshot(*weak_profile);
}
+ (void)refreshDownloadsForProfilePath:(NSString*)profilePath
                           completion:(void (^)(NSArray<NSString*>*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  void (^reply)(NSArray<NSString*>*, NSError*) = [completion copy];
  parc::WithNativeProfile(profilePath, base::BindOnce(
      [](void (^reply)(NSArray<NSString*>*, NSError*), Profile* profile,
         CefRefPtr<CefRequestContext> context, NSError* error) {
        auto* service = profile && !profile->IsOffTheRecord()
            ? parc::NativeDownloads::From(*profile) : nullptr;
        if (error || !context || !service) {
          NSError* failure = error ?: parc::Error(@"Downloads are unavailable for this Profile.");
          dispatch_async(dispatch_get_main_queue(), ^{ reply(nil, failure); });
          return;
        }
        service->Refresh(base::BindOnce(
            [](void (^reply)(NSArray<NSString*>*, NSError*),
               base::WeakPtr<Profile> profile, bool loaded) {
              auto* service = profile ? parc::NativeDownloads::From(*profile) : nullptr;
              if (!loaded || !service) {
                reply(nil, parc::Error(@"The download Profile was closed before its history loaded."));
                return;
              }
              NSMutableArray<NSString*>* ids = [NSMutableArray array];
              for (const auto& snapshot : service->Snapshots()) {
                [ids addObject:base::SysUTF8ToNSString(snapshot.guid)];
              }
              reply([ids copy], nil);
            }, reply, profile->GetWeakPtr()));
      }, reply));
}
// Existing P0 callers keep their API. New Library callers always supply identity.
+ (BOOL)performDownloadAction:(PCNativeDownloadAction)action
                  identifier:(NSString*)identifier
                 profilePath:(NSString*)profilePath {
  return [self performDownloadAction:action identifier:identifier profilePath:profilePath itemIdentity:@""];
}
+ (BOOL)performDownloadAction:(PCNativeDownloadAction)action
                   identifier:(NSString*)identifier
                  profilePath:(NSString*)profilePath
                 itemIdentity:(NSString*)itemIdentity {
  CHECK(NSThread.isMainThread);
  if (!parc::ready || parc::quitting || parc::preparing_global_close ||
      parc::IsNativeProfileRemovalBlocked(base::FilePath(base::SysNSStringToUTF8(profilePath)))) {
    return NO;
  }
  auto found = parc::Profiles().find(base::SysNSStringToUTF8(profilePath));
  if (found == parc::Profiles().end() || !found->second.profile) {
    return NO;
  }
  auto* service = parc::NativeDownloads::From(*found->second.profile);
  if (!service) {
    return NO;
  }
  parc::NativeDownloadAction command;
  switch (action) {
    case PCNativeDownloadActionOpen: command = parc::NativeDownloadAction::kOpen; break;
    case PCNativeDownloadActionReveal: command = parc::NativeDownloadAction::kReveal; break;
    case PCNativeDownloadActionRemove: command = parc::NativeDownloadAction::kRemove; break;
    case PCNativeDownloadActionToggleOpen: command = parc::NativeDownloadAction::kToggleOpen; break;
    case PCNativeDownloadActionPause:
      command = parc::NativeDownloadAction::kPause;
      break;
    case PCNativeDownloadActionResume:
      command = parc::NativeDownloadAction::kResume;
      break;
    case PCNativeDownloadActionCancel:
      command = parc::NativeDownloadAction::kCancel;
      break;
    case PCNativeDownloadActionRetry:
      command = parc::NativeDownloadAction::kRetry;
      break;
    default:
      return NO;
  }
  auto context = found->second.context;
  return context && service->Perform(base::SysNSStringToUTF8(identifier), command, base::SysNSStringToUTF8(itemIdentity));
}
+ (NSURL*)downloadFileURLForIdentifier:(NSString*)identifier
                            profilePath:(NSString*)profilePath
                           itemIdentity:(NSString*)itemIdentity {
  CHECK(NSThread.isMainThread);
  if (!parc::ready || parc::quitting || parc::preparing_global_close || itemIdentity.length == 0 ||
      parc::IsNativeProfileRemovalBlocked(base::FilePath(base::SysNSStringToUTF8(profilePath)))) return nil;
  auto found = parc::Profiles().find(base::SysNSStringToUTF8(profilePath));
  if (found == parc::Profiles().end() || !found->second.profile || !found->second.context) return nil;
  auto* service = parc::NativeDownloads::From(*found->second.profile);
  if (!service) return nil;
  auto path = service->FilePath(base::SysNSStringToUTF8(identifier), base::SysNSStringToUTF8(itemIdentity));
  if (!path || ![NSFileManager.defaultManager fileExistsAtPath:base::SysUTF8ToNSString(path->value())]) return nil;
  return [NSURL fileURLWithPath:base::SysUTF8ToNSString(path->value())];
}
+ (PCNativeDownloadReview*)downloadReviewForIdentifier:(NSString*)identifier
                                          profilePath:(NSString*)profilePath {
  CHECK(NSThread.isMainThread);
  if (!parc::ready || parc::quitting || parc::preparing_global_close ||
      parc::IsNativeProfileRemovalBlocked(base::FilePath(base::SysNSStringToUTF8(profilePath)))) return nil;
  auto found = parc::Profiles().find(base::SysNSStringToUTF8(profilePath));
  if (found == parc::Profiles().end() || !found->second.profile ||
      !found->second.context) return nil;
  auto* profile = found->second.profile.get();
  auto* service = parc::NativeDownloads::From(*profile);
  if (!service) return nil;
  auto value = service->Review(base::SysNSStringToUTF8(identifier));
  return value ? [[PCNativeDownloadReview alloc] initWithProfile:*profile
                                                        values:std::move(*value)]
               : nil;
}
+ (BOOL)performDownloadReviewAction:(PCNativeDownloadReviewAction)action
                         forReview:(PCNativeDownloadReview*)review
                          password:(NSString*)password
                     justification:(NSString*)justification {
  CHECK(NSThread.isMainThread);
  if (!parc::ready || parc::quitting || parc::preparing_global_close || !review ||
      parc::IsNativeProfileRemovalBlocked(base::FilePath(base::SysNSStringToUTF8(review.profilePath))))
    return NO;
  auto found = parc::Profiles().find(base::SysNSStringToUTF8(review.profilePath));
  if (found == parc::Profiles().end() || !found->second.profile ||
      found->second.profile.get() != [review profileIdentity]) return NO;
  auto context = found->second.context;
  auto* service = parc::NativeDownloads::From(*found->second.profile);
  if (!context || !service) return NO;
  parc::NativeDownloadReviewAction command;
  switch (action) {
    case PCNativeDownloadReviewActionKeep:
      command = parc::NativeDownloadReviewAction::kKeep;
      break;
    case PCNativeDownloadReviewActionDiscard:
      command = parc::NativeDownloadReviewAction::kDiscard;
      break;
    case PCNativeDownloadReviewActionScan:
      command = parc::NativeDownloadReviewAction::kScan;
      break;
    case PCNativeDownloadReviewActionBypassScan:
      command = parc::NativeDownloadReviewAction::kBypassScan;
      break;
    case PCNativeDownloadReviewActionCancelScan:
      command = parc::NativeDownloadReviewAction::kCancelScan;
      break;
    default:
      return NO;
  }
  auto values = [review values];
  // Passwords are transient call arguments, never snapshots/history/logs.
  return service->PerformReview(values, command, base::SysNSStringToUTF8(password),
                                base::SysNSStringToUTF16(justification));
}
+ (NSURL*)downloadReviewLinkAtIndex:(NSUInteger)index
                         forReview:(PCNativeDownloadReview*)review {
  CHECK(NSThread.isMainThread);
  if (!parc::ready || parc::quitting || parc::preparing_global_close || !review ||
      parc::IsNativeProfileRemovalBlocked(base::FilePath(base::SysNSStringToUTF8(review.profilePath)))) return nil;
  auto found = parc::Profiles().find(base::SysNSStringToUTF8(review.profilePath));
  if (found == parc::Profiles().end() || !found->second.profile ||
      found->second.profile.get() != [review profileIdentity]) return nil;
  auto context = found->second.context;
  auto* service = parc::NativeDownloads::From(*found->second.profile);
  if (!context || !service) return nil;
  auto url = service->ReviewLink([review values], index);
  return url ? [NSURL URLWithString:base::SysUTF8ToNSString(*url)] : nil;
}
+ (void)setApplicationClient:(id<PCNativeBrowserApplicationClient>)client {
  CHECK(NSThread.isMainThread);
  parc::application_client = client;
}
+ (void)requestCloseAllWindows:(void (^)(BOOL))completion {
  CHECK(NSThread.isMainThread);
  CHECK(completion);
  if (parc::preparing_global_close || parc::HasNativePageRetirementWork() ||
      parc::HasLiveTabTransfer() || parc::preparing_live_transfer) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(NO);
    });
    return;
  }
  if (auto transaction = parc::ActiveCloseTransaction()) {
    if (transaction->all_windows()) {
      transaction->AddCompletion(completion);
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(NO);
      });
    }
    return;
  }
  parc::quitting = true;
  parc::preparing_global_close = true;
  // Pending pre-initialization closures observe the closing gate and settle
  // their exact caller; they never acquire a Browser after global approval.
  auto queued = std::move(parc::ReadyQueue());
  parc::ReadyQueue().clear();
  for (auto& request : queued) {
    std::move(request).Run();
  }
  parc::preparing_global_close = false;
  parc::BeginNativeClose(parc::Windows().objectEnumerator.allObjects, true,
                         completion);
}
@end
@implementation PCNativeBrowserApplication (CookieStore)
+ (BOOL)restoresSessionCookies {
  // native-session-cookies.patch: ProfileImpl::ShouldRestoreOldSessionCookies.
  return YES;
}
+ (void)flushCookieStores {
  CHECK(NSThread.isMainThread);
  if (!parc::ready || parc::quitting) return;
  for (auto& entry : parc::Profiles()) {
    Profile* profile = entry.second.profile.get();
    if (!profile || profile->ShutdownStarted()) continue;
    if (auto* cookies = profile->GetDefaultStoragePartition()
                            ->GetCookieManagerForBrowserProcess()) {
      cookies->FlushCookieStore(base::DoNothing());
    }
  }
}
@end

@implementation PCNativeBrowserWindow (PrivateDownloads)
- (BOOL)privateDownloadsAvailable {
  CHECK(NSThread.isMainThread);
  auto* profile = parc::PrivateDownloadsProfile(self);
  return profile && parc::NativeDownloads::From(*profile);
}
- (void)refreshPrivateDownloadsWithCompletion:(void (^)(NSArray<NSString*>*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  auto* profile = parc::PrivateDownloadsProfile(self);
  auto* service = profile ? parc::NativeDownloads::From(*profile) : nullptr;
  if (!service) {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, parc::Error(@"Private downloads are no longer available.")); });
    return;
  }
  __weak PCNativeBrowserWindow* weak = self;
  service->Refresh(base::BindOnce(
      [](PCNativeBrowserWindow* binding, base::WeakPtr<Profile> original,
         void (^reply)(NSArray<NSString*>*, NSError*), bool loaded) {
        auto* profile = parc::PrivateDownloadsProfile(binding);
        auto* service = profile ? parc::NativeDownloads::From(*profile) : nullptr;
        if (!loaded || !original || profile != original.get() || !service) {
          reply(nil, parc::Error(@"The private download context closed before it loaded."));
          return;
        }
        NSMutableArray<NSString*>* ids = [NSMutableArray array];
        for (const auto& snapshot : service->Snapshots())
          [ids addObject:base::SysUTF8ToNSString(snapshot.guid)];
        reply([ids copy], nil);
      }, weak, profile->GetWeakPtr(), [completion copy]));
}
- (BOOL)performPrivateDownloadAction:(PCNativeDownloadAction)action
                         identifier:(NSString*)identifier itemIdentity:(NSString*)identity {
  CHECK(NSThread.isMainThread);
  auto* profile = parc::PrivateDownloadsProfile(self);
  auto* service = profile ? parc::NativeDownloads::From(*profile) : nullptr;
  if (!service || identity.length == 0) return NO;
  parc::NativeDownloadAction command;
  switch (action) {
    case PCNativeDownloadActionOpen: command = parc::NativeDownloadAction::kOpen; break;
    case PCNativeDownloadActionReveal: command = parc::NativeDownloadAction::kReveal; break;
    case PCNativeDownloadActionRemove: command = parc::NativeDownloadAction::kRemove; break;
    case PCNativeDownloadActionToggleOpen: command = parc::NativeDownloadAction::kToggleOpen; break;
    case PCNativeDownloadActionPause:
      command = parc::NativeDownloadAction::kPause;
      break;
    case PCNativeDownloadActionResume:
      command = parc::NativeDownloadAction::kResume;
      break;
    case PCNativeDownloadActionCancel:
      command = parc::NativeDownloadAction::kCancel;
      break;
    case PCNativeDownloadActionRetry:
      command = parc::NativeDownloadAction::kRetry;
      break;
    default:
      return NO;
  }
  return service->Perform(base::SysNSStringToUTF8(identifier), command, base::SysNSStringToUTF8(identity));
}
- (NSURL*)privateDownloadFileURLForIdentifier:(NSString*)identifier itemIdentity:(NSString*)identity {
  CHECK(NSThread.isMainThread);
  auto* profile = parc::PrivateDownloadsProfile(self);
  auto* service = profile ? parc::NativeDownloads::From(*profile) : nullptr;
  if (!service || identity.length == 0) return nil;
  auto path = service->FilePath(base::SysNSStringToUTF8(identifier), base::SysNSStringToUTF8(identity));
  if (!path || ![NSFileManager.defaultManager fileExistsAtPath:base::SysUTF8ToNSString(path->value())]) return nil;
  return [NSURL fileURLWithPath:base::SysUTF8ToNSString(path->value())];
}
- (PCNativeDownloadReview*)privateDownloadReviewForIdentifier:(NSString*)identifier itemIdentity:(NSString*)identity {
  CHECK(NSThread.isMainThread);
  auto* profile = parc::PrivateDownloadsProfile(self);
  auto* service = profile ? parc::NativeDownloads::From(*profile) : nullptr;
  if (!service || identity.length == 0) return nil;
  auto value = service->Review(base::SysNSStringToUTF8(identifier));
  if (!value || value->item_identity.ToString() != base::SysNSStringToUTF8(identity)) return nil;
  return [[PCNativeDownloadReview alloc] initWithProfile:*profile values:std::move(*value)];
}
- (BOOL)performPrivateDownloadReviewAction:(PCNativeDownloadReviewAction)action
                               forReview:(PCNativeDownloadReview*)review
                                password:(NSString*)password justification:(NSString*)justification {
  CHECK(NSThread.isMainThread);
  auto* profile = parc::PrivateDownloadsProfile(self);
  auto* service = profile ? parc::NativeDownloads::From(*profile) : nullptr;
  if (!service || !review || [review profileIdentity] != profile) return NO;
  parc::NativeDownloadReviewAction command;
  switch (action) {
    case PCNativeDownloadReviewActionKeep:
      command = parc::NativeDownloadReviewAction::kKeep;
      break;
    case PCNativeDownloadReviewActionDiscard:
      command = parc::NativeDownloadReviewAction::kDiscard;
      break;
    case PCNativeDownloadReviewActionScan:
      command = parc::NativeDownloadReviewAction::kScan;
      break;
    case PCNativeDownloadReviewActionBypassScan:
      command = parc::NativeDownloadReviewAction::kBypassScan;
      break;
    case PCNativeDownloadReviewActionCancelScan:
      command = parc::NativeDownloadReviewAction::kCancelScan;
      break;
    default:
      return NO;
  }
  return service->PerformReview([review values], command, base::SysNSStringToUTF8(password),
                                base::SysNSStringToUTF16(justification));
}
- (NSURL*)privateDownloadReviewLinkAtIndex:(NSUInteger)index forReview:(PCNativeDownloadReview*)review {
  CHECK(NSThread.isMainThread);
  auto* profile = parc::PrivateDownloadsProfile(self);
  auto* service = profile ? parc::NativeDownloads::From(*profile) : nullptr;
  if (!service || !review || [review profileIdentity] != profile) return nil;
  auto url = service->ReviewLink([review values], index);
  return url ? [NSURL URLWithString:base::SysUTF8ToNSString(*url)] : nil;
}
@end

@implementation PCNativePrivateDownloadContext
@synthesize identifier = _identifier;
@synthesize profilePath = _profilePath;
- (instancetype)initWithProfile:(Profile&)profile {
  self = [super init];
  if (self) {
    CHECK(profile.IsOffTheRecord());
    _downloadProfile = profile.GetWeakPtr();
    _identifier = NSUUID.UUID.UUIDString;
    _profilePath = [parc::ProfilePath(profile) copy];
  }
  return self;
}
- (void)invalidate { _downloadProfile.reset(); }
- (PCNativeBrowserWindow*)sourceWindow {
  CHECK(NSThread.isMainThread);
  if (!_downloadProfile || _downloadProfile->ShutdownStarted()) return nil;
  for (PCNativeBrowserWindow* binding in parc::Windows().objectEnumerator.allObjects)
    if (parc::PrivateDownloadsProfile(binding) == _downloadProfile.get()) return binding;
  return nil;
}
- (BOOL)isValid { return self.sourceWindow.privateDownloadsAvailable; }
- (void)refreshWithCompletion:(void (^)(NSArray<NSString*>*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  Profile* profile = self.isValid ? _downloadProfile.get() : nullptr;
  auto* service = profile ? parc::NativeDownloads::From(*profile) : nullptr;
  if (!service) {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, parc::Error(@"The private download context is no longer available.")); });
    return;
  }
  __weak PCNativePrivateDownloadContext* weak = self;
  service->Refresh(base::BindOnce(
      [](PCNativePrivateDownloadContext* context, base::WeakPtr<Profile> original,
         void (^reply)(NSArray<NSString*>*, NSError*), bool loaded) {
        auto* service = original && !original->ShutdownStarted() ? parc::NativeDownloads::From(*original) : nullptr;
        if (!loaded || !context.isValid || !service) {
          reply(nil, parc::Error(@"The private download context closed before it loaded."));
          return;
        }
        NSMutableArray<NSString*>* ids = [NSMutableArray array];
        for (const auto& snapshot : service->Snapshots())
          [ids addObject:base::SysUTF8ToNSString(snapshot.guid)];
        reply([ids copy], nil);
      }, weak, profile->GetWeakPtr(), [completion copy]));
}
- (BOOL)performAction:(PCNativeDownloadAction)action identifier:(NSString*)identifier itemIdentity:(NSString*)identity {
  return [self.sourceWindow performPrivateDownloadAction:action identifier:identifier itemIdentity:identity];
}
- (NSURL*)fileURLForIdentifier:(NSString*)identifier itemIdentity:(NSString*)identity {
  return [self.sourceWindow privateDownloadFileURLForIdentifier:identifier itemIdentity:identity];
}
- (PCNativeDownloadReview*)reviewForIdentifier:(NSString*)identifier itemIdentity:(NSString*)identity {
  return [self.sourceWindow privateDownloadReviewForIdentifier:identifier itemIdentity:identity];
}
- (BOOL)performReviewAction:(PCNativeDownloadReviewAction)action forReview:(PCNativeDownloadReview*)review
                  password:(NSString*)password justification:(NSString*)justification {
  return [self.sourceWindow performPrivateDownloadReviewAction:action forReview:review password:password justification:justification];
}
- (NSURL*)reviewLinkAtIndex:(NSUInteger)index forReview:(PCNativeDownloadReview*)review {
  return [self.sourceWindow privateDownloadReviewLinkAtIndex:index forReview:review];
}
@end

namespace parc {
bool CanCreateNativeVideoPiPWindow() {
  id<PCNativeBrowserApplicationClient> client = application_client;
  return ready && !quitting && !preparing_global_close &&
         [client respondsToSelector:@selector
                 (createVideoPictureInPictureWindow:
                                        sourceFrame:action:changed:)] &&
         [client
             respondsToSelector:@selector(releaseVideoPictureInPictureWindow:)];
}
id<PCNativeVideoPiPWindow> CreateAppKitVideoPiPWindow(
    NSView* view,
    NSRect source,
    void (^action)(PCVideoPiPAction, double),
    dispatch_block_t changed,
    id<PCNativeBrowserApplicationClient> __strong* owner) {
  // The Browser entry already performed capability preflight. The concrete
  // factory needs the captured app service, not a key/frontmost window.
  id<PCNativeBrowserApplicationClient> client = application_client;
  CHECK([client respondsToSelector:@selector
                (createVideoPictureInPictureWindow:
                                       sourceFrame:action:changed:)]);
  *owner = client;
  id<PCNativeVideoPiPWindow> window =
      [client createVideoPictureInPictureWindow:view
                                    sourceFrame:source
                                         action:action
                                        changed:changed];
  CHECK(window && window.videoView == view && !window.invalidated);
  return window;
}
void ReleaseAppKitVideoPiPWindow(id<PCNativeVideoPiPWindow> window,
                                 id<PCNativeBrowserApplicationClient> owner) {
  [window invalidate];
  [owner releaseVideoPictureInPictureWindow:window];
}
}  // namespace parc

namespace parc {
Profile* NativePrivateProfileForWindow(PCNativeBrowserWindow* binding, NSString* path) {
  if (!binding || !binding.window || !binding.client || [binding state].browsers.empty() || quitting || preparing_global_close ||
      [binding state].close_in_progress || [binding state].close_approved || ![binding state].private_mode)
    return nullptr;
  Profile* profile = [binding state].private_profile.get();
  return profile && profile->IsOffTheRecord() && !profile->ShutdownStarted() &&
      [ProfilePath(*profile) isEqual:path] && !IsNativeProfileRemovalBlocked(profile->GetOriginalProfile()->GetPath())
      ? profile : nullptr;
}
CefRefPtr<CefRequestContext> NativeContextForProfile(Profile& profile) {
  if (profile.IsOffTheRecord()) {
    if (quitting || preparing_global_close || profile.ShutdownStarted() ||
        IsNativeProfileRemovalBlocked(profile.GetOriginalProfile()->GetPath())) return nullptr;
    auto* context = ChromeBrowserContext::FromProfile(&profile);
    return context ? CefRequestContextImpl::GetOrCreateForBrowserContext(context, nullptr) : nullptr;
  }
  auto found = Profiles().find(profile.GetPath().value());
  return !quitting && !preparing_global_close &&
                 !IsNativeProfileRemovalBlocked(profile.GetOriginalProfile()->GetPath()) &&
                 found != Profiles().end() &&
                 found->second.profile.get() == &profile
             ? found->second.context
             : nullptr;
}
void WithNativeProfile(
    NSString* path,
    base::OnceCallback<void(Profile*, CefRefPtr<CefRequestContext>, NSError*)>
        callback) {
  CHECK(NSThread.isMainThread);
  NSString* requested = [path copy];
  auto run = base::BindOnce(
      [](NSString* path, decltype(callback) callback) {
        if (quitting || preparing_global_close || !path.isAbsolutePath ||
            ![path isEqualToString:path.stringByStandardizingPath]) {
          std::move(callback).Run(
              nullptr, nullptr,
              Error(@"The requested profile is unavailable."));
          return;
        }
        const base::FilePath root(
            CefString(&CefContext::Get()->settings().root_cache_path)
                .ToString());
        if (base::FilePath(base::SysNSStringToUTF8(path)).DirName() != root) {
          std::move(callback).Run(nullptr, nullptr,
                                  Error(@"The requested profile is outside the "
                                        @"engine profile root."));
          return;
        }
        WithProfile(path, std::move(callback));
      },
      requested, std::move(callback));
  if (ready)
    std::move(run).Run();
  else
    ReadyQueue().push_back(std::move(run));
}

void AbandonEmptyNativeRoutingWindow(PCNativeBrowserWindow* binding) {
  if (binding && [binding state].browsers.empty()) NotifyEmptyBinding(binding, true);
}
void WithNativeRoutingBrowser(PCNativeBrowserWindow* binding, NSString* path,
    base::OnceCallback<void(BrowserWindowInterface*, bool, NSError*)> callback) {
  CHECK(NSThread.isMainThread);
  CHECK(callback);
  if (!ready || quitting || preparing_global_close || !binding.window ||
      !binding.client || [binding state].close_in_progress ||
      [binding state].close_approved) {
    std::move(callback).Run(nullptr, false, Error(@"The destination window is unavailable."));
    return;
  }
  if (BrowserRetiringForPath(binding, path)) {
    __weak PCNativeBrowserWindow* weak_binding = binding;
    ParkUntilBrowserRetires(binding, base::BindOnce(
        [](PCNativeBrowserWindow* __weak weak_binding, NSString* path,
           base::OnceCallback<void(BrowserWindowInterface*, bool, NSError*)> callback) {
          if (PCNativeBrowserWindow* binding = weak_binding) {
            WithNativeRoutingBrowser(binding, path, std::move(callback));
          } else {
            std::move(callback).Run(nullptr, false, Error(@"The destination window is unavailable."));
          }
        },
        weak_binding, [path copy], std::move(callback)));
    return;
  }
  ++pending_creations;
  // Hold this exact destination through asynchronous Profile acquisition.
  // Concurrent admitted tab opens must not abort one another's empty shell.
  ++[binding state].ownership_epoch;
  ++[binding state].pending_reservations;
  WithNativeProfile(path, base::BindOnce(
      [](PCNativeBrowserWindow* binding,
         base::OnceCallback<void(BrowserWindowInterface*, bool, NSError*)> callback,
         Profile* profile, CefRefPtr<CefRequestContext> context, NSError* error) {
        auto finish = [&](BrowserWindowInterface* browser, bool created, NSError* failure) {
          auto weak = browser ? browser->GetWeakPtr() : base::WeakPtr<BrowserWindowInterface>();
          CHECK(pending_creations);
          --pending_creations;
          CHECK([binding state].pending_reservations);
          --[binding state].pending_reservations;
          NotifyNativeEngineOwnershipChanged();
          std::move(callback).Run(weak.get(), created, failure);
        };
        if (!profile || !context || !NativeContextForProfile(*profile) ||
            quitting || preparing_global_close || !binding.window || !binding.client ||
            [binding state].close_in_progress || [binding state].close_approved) {
          finish(nullptr, false, error ?: Error(@"The destination Profile or window is unavailable."));
          return;
        }
        auto& state = [binding state];
        auto found = state.browsers.find(profile);
        auto* browser = found == state.browsers.end() ? nullptr : found->second.get();
        bool created = false;
        if (!browser) {
          auto route = GetNativeRoute(*profile);
          if (!route || profile->IsOffTheRecord() ||
              GetBrowserWindowCreationStatusForProfile(*profile) !=
                  BrowserWindowInterface::CreationStatus::kOk) {
            finish(nullptr, false, Error(@"The destination Browser cannot be created."));
            return;
          }
          CefBrowserCreateParams native_params;
          native_params.request_context = context;
          native_params.client = route->client();
          native_params.native_route = route;
          native_params.native_reservation = std::make_shared<PreparedAppKitWindow>(
              *profile, BrowserWindowInterface::TYPE_NORMAL, binding);
          BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL, *profile, true);
          params.should_trigger_session_restore = false;
          params.cef_params = base::MakeRefCounted<ChromeBrowserHostImpl::DelegateCreateParams>(native_params);
          browser = CreateBrowserWindow(std::move(params));
          created = browser != nullptr;
        }
        if (!browser || browser->GetProfile() != profile ||
            AppKitBindingForBrowser(browser) != binding || !AppKitBrowserAcceptsNewPages(*browser)) {
          if (created && browser && !browser->IsDeleteScheduled() &&
              browser->GetTabStripModel()->empty()) browser->GetWindow()->Close();
          finish(nullptr, created, Error(@"The destination Browser changed before routing."));
          return;
        }
        finish(browser, created, nil);
      }, binding, std::move(callback)));
}

bool NativeProfileRemovalApplicationReady() {
  return ready && !quitting && !preparing_global_close;
}

NSError* CheckNativeProfileRemovalOwners(const base::FilePath& path,
                                        base::WeakPtr<Profile>* identity) {
  CHECK(NSThread.isMainThread);
  if (!NativeProfileRemovalApplicationReady() || HasPendingNativeApplicationWork())
    return Error(@"Wait for the current browser operation to finish before removing this Profile.");
  auto* manager = g_browser_process->profile_manager();
  if (manager->IsNativeProfileLifecyclePending(path))
    return Error(@"This Profile is still finishing native retirement.");
  Profile* profile = manager->GetProfileByPath(path);
  bool has_fallback = false;
  for (Profile* other : manager->GetLoadedProfiles()) {
    if (other->GetPath() != path && !other->IsOffTheRecord() &&
        !other->IsGuestSession() && !other->IsSystemProfile() &&
        !IsProfileDirectoryMarkedForDeletion(other->GetPath()) &&
        !IsNativeProfileRemovalBlocked(other->GetPath())) {
      has_fallback = true;
      break;
    }
  }
  if (!has_fallback)
    return Error(@"Open another Profile before removing this one.");
  auto found = Profiles().find(path.value());
  if (found != Profiles().end()) {
    auto& record = found->second;
    if (!record.waiters.empty() || (record.context && !record.profile))
      return Error(@"This Profile is still being initialized.");
    if (record.context) {
      auto* impl = static_cast<CefRequestContextImpl*>(record.context.get());
      if (!record.context->HasOneRef() ||
          !impl->GetBrowserContext()->HasOnlyCefRequestContext(impl))
        return Error(@"This Profile still has an active page or native operation.");
    }
    if (record.profile.get() != profile)
      return Error(@"The native Profile identity changed.");
  } else if (CefBrowserContext::FromCachePath(path)) {
    return Error(@"Another native context still owns this Profile.");
  }
  if (profile) {
    auto* browsers = ProfileBrowserCollection::GetForProfile(profile);
    if (profile->IsOffTheRecord() || !profile->GetAllOffTheRecordProfiles().empty() ||
        (browsers && !browsers->IsEmpty()))
      return Error(@"Close this Profile's normal and private windows before removing it.");
    auto* downloads = profile->GetDownloadManager();
    if (!downloads->IsManagerInitialized())
      return Error(@"Wait for this Profile's downloads to finish initializing.");
    content::DownloadManager::DownloadVector items;
    downloads->GetAllDownloads(&items);
    for (const auto& item : items) {
      if (item->GetState() == download::DownloadItem::IN_PROGRESS)
        return Error(@"Finish or cancel this Profile's downloads before removing it.");
    }
  }
  *identity = profile ? profile->GetWeakPtr() : base::WeakPtr<Profile>();
  return nil;
}

void ReleaseNativeProfileForRemoval(const base::FilePath& path) {
  CHECK(NSThread.isMainThread);
  auto found = Profiles().find(path.value());
  if (found == Profiles().end())
    return;
  CHECK(found->second.waiters.empty());
  if (auto* profile = found->second.profile.get()) {
    CancelNativeDownloadFileDialogs(*profile);
    if (auto* downloads = NativeDownloads::From(*profile))
      downloads->Shutdown();
  }
  // Remove the public registry before the last CEF ref starts shutdown.
  auto context = std::move(found->second.context);
  Profiles().erase(found);
  context = nullptr;
}
}  // namespace parc
