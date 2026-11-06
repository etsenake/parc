// Copyright 2026 Parc contributors.
#include "native_appkit_host.h"
#include "cef/libcef/browser/parc_native/native_internal_urls.h"
#include "native_link_routing.h"

#include <cmath>
#include <map>
#include <memory>
#include <set>
#include <utility>
#include <vector>

#include "autofill_bubble_handler.h"
#include "base/apple/foundation_util.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/timer/timer.h"
#include "cef/libcef/browser/chrome/chrome_browser_host_impl.h"
#include "chrome/browser/devtools/devtools_ui_controller.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/accelerator_table.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/focus/browser_focus_controller.h"
#include "chrome/browser/ui/intent_picker_tab_helper.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/toolbar/toolbar_action_view_model.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "chrome/browser/ui/views/eye_dropper/eye_dropper.h"
#include "components/apps/link_capturing/intent_picker_info.h"
#include "components/input/native_web_keyboard_event.h"
#include "content/browser/renderer_host/browser_compositor_view_mac.h"
#include "content/browser/renderer_host/delegated_frame_host.h"
#include "content/browser/renderer_host/render_frame_metadata_provider_impl.h"
#include "content/browser/renderer_host/render_widget_host_impl.h"
#include "content/browser/renderer_host/render_widget_host_view_mac.h"
#include "content/public/browser/eye_dropper.h"
#include "components/viz/common/frame_timing_details.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/common/page_visibility_state.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/weak_document_ptr.h"
#include "devtools_pane.h"
#include "extension_action_bridge.h"
#include "extension_action_container.h"
#include "extension_context_menu.h"
#include "extension_side_panel.h"
#include "find_bar.h"
#include "focus_manager.h"
#include "native_appkit_page.h"
#include "native_background_picture_in_picture_api.h"
#include "native_browser_window.h"
#include "native_capture_picker.h"
#include "native_confirm_infobars.h"
#include "native_chrome_platform_delegate.h"
#include "native_exclusive_access.h"
#include "native_fullscreen_window.h"
#include "native_host_route.h"
#include "native_intent_picker.h"
#include "native_intent_picker_api.h"
#include "native_payment_entry.h"
#include "native_website_theme.h"
#include "page_host.h"
#include "pane_compositor.h"
#include "password_prompt.h"
#include "sad_tab.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/compositor/compositor.h"
#include "ui/compositor/layer.h"
#include "ui/compositor/layer_surface.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "window_security_reservation.h"

namespace parc {
struct NativeOpenAppToken {
  base::WeakPtr<BrowserWindowInterface> browser;
  base::WeakPtr<content::WebContents> page;
  content::WeakDocumentPtr document;
  GURL url;
  NSWindow* __weak window;
};
}
@interface PCNativeOpenAppAction () {
 @package
  std::shared_ptr<parc::NativeOpenAppToken> _token;
}
@property(nonatomic, readwrite, copy) NSString* title;
- (instancetype)initWithToken:(std::shared_ptr<parc::NativeOpenAppToken>)token;
@end
@implementation PCNativeOpenAppAction
@synthesize title = _title;
- (instancetype)initWithToken:(std::shared_ptr<parc::NativeOpenAppToken>)token {
  if ((self = [super init])) {
    _token = std::move(token);
    _title = @"Open in App…";
  }
  return self;
}
@end

namespace parc {
class AppKitBrowserHost;
}
@interface PCNativeMenuTarget : NSObject
@property(nonatomic, copy) void (^invoke)(NSString*);
- (void)perform:(NSMenuItem*)sender;
@end
@implementation PCNativeMenuTarget
@synthesize invoke = _invoke;
- (void)perform:(NSMenuItem*)sender {
  void (^callback)(NSString*) = self.invoke;
  if (callback && [sender.representedObject isKindOfClass:NSString.class]) {
    callback(sender.representedObject);
  }
}
@end

namespace parc {
namespace {

std::map<const BrowserWindowInterface*, base::WeakPtr<AppKitBrowserHost>>&
Hosts() {
  static base::NoDestructor<
      std::map<const BrowserWindowInterface*, base::WeakPtr<AppKitBrowserHost>>>
      value;
  return *value;
}
// One responder domain per actual native window, shared across Profiles.
PCNativeFocusManager* FocusManager(NSWindow* window) {
  static NSMapTable<NSWindow*, PCNativeFocusManager*>* managers =
      [NSMapTable weakToStrongObjectsMapTable];
  PCNativeFocusManager* manager = [managers objectForKey:window];
  if (!manager) {
    manager = [[PCNativeFocusManager alloc] initWithWindow:window];
    [managers setObject:manager forKey:window];
  }
  return manager;
}
bool MenuKey(const input::NativeWebKeyboardEvent& event) {
  if (event.skip_if_unhandled ||
      event.GetType() != blink::WebInputEvent::Type::kRawKeyDown) {
    return false;
  }
  NSEvent* native = event.os_event.Get();
  return native && native.type == NSEventTypeKeyDown &&
         (native.modifierFlags &
          NSEventModifierFlagDeviceIndependentFlagsMask) &&
         [NSApp.mainMenu performKeyEquivalent:native];
}
// Chromium's own visibility tracking still runs for Parc's pages:
// WebContentsViewCocoa re-reads WebContentsOcclusionCheckerMac's flag for its
// window when its view is shown, hidden or moved and on each checker update,
// and marks the page occluded a second later. The flag also counts a window
// fully covered by another of the app's windows, which macOS reports visible,
// but it follows macOS's occlusion state without the key-window exception
// WindowCurrentlyOccluded makes, so it can stop the front window's page
// painting with no pass to follow.
class PageVisibilityWatch final : public content::WebContentsObserver {
 public:
  PageVisibilityWatch(content::WebContents& contents,
                      base::RepeatingCallback<void(content::Visibility)> changed)
      : content::WebContentsObserver(&contents), changed_(std::move(changed)) {}
  void OnVisibilityChanged(content::Visibility visibility) override {
    changed_.Run(visibility);
  }

 private:
  base::RepeatingCallback<void(content::Visibility)> changed_;
};
}  // namespace

class AppKitBrowserHost final : public NativeBrowserWindowHost,
                                public NativeExtensionActionHost,
                                public NativeAutofillBubbleHost,
                                public NativeFindBarHost,
                                public NativeSidePanelHost,
                                public ui::AcceleratorProvider,
                                public TabStripModelObserver {
 public:
  AppKitBrowserHost(BrowserWindowInterface& browser,
                    PCNativeBrowserWindow* binding,
                    NSString* path)
      : browser_(browser), binding_(binding), profile_path_([path copy]) {
    CHECK(NSThread.isMainThread);
    CHECK(binding.window && binding.client);
    CHECK_EQ(binding.window, [binding.client nativeBrowserWindow]);
    CHECK(!Hosts().contains(&browser));
    Hosts().emplace(&browser, weak_factory_.GetWeakPtr());
    autofill_ = std::make_unique<NativeAutofillBubbleHandler>(browser, *this);
    actions_ = std::make_unique<NativeExtensionActionContainer>(browser, *this);
    context_menu_ =
        std::make_unique<NativeExtensionContextMenu>(browser, *this);
    action_bridge_ = std::make_unique<NativeExtensionActionBridge>(
        browser_, *actions_,
        base::BindRepeating(
            [](base::WeakPtr<AppKitBrowserHost> host,
               content::WebContents& contents) {
              return host && host->ValidActionPage(contents);
            },
            weak_factory_.GetWeakPtr()),
        base::BindRepeating(&AppKitBrowserHost::NotifyActionChanges,
                            weak_factory_.GetWeakPtr()));
    payment_entry_ = std::make_unique<NativePaymentEntry>(
        browser_,
        base::BindRepeating(
            [](base::WeakPtr<AppKitBrowserHost> host,
               content::WebContents& contents) {
              return host && host->ValidActionPage(contents);
            },
            weak_factory_.GetWeakPtr()),
        base::BindRepeating(&AppKitBrowserHost::NotifyPaymentChanges,
                            weak_factory_.GetWeakPtr()));
    browser_.GetTabStripModel()->AddObserver(this);
  }
  ~AppKitBrowserHost() override { BeginTeardown(); }
  PCNativeBrowserWindow* binding() const { return binding_; }
  bool selected() const { return selected_ && !tearing_down_ && !draining_; }
  // A delete-scheduled Browser destroys its window features before any tab
  // still in its TabStripModel, so it takes no page even before its drain.
  bool acceptsNewPages() const {
    return !tearing_down_ && !draining_ && !browser_.IsDeleteScheduled();
  }
  void DidAttachWindow(gfx::NativeWindow window) override {
    CHECK(window.GetNativeNSWindow() == binding_.window);
    window_ = window.GetNativeNSWindow();
    if (browser_.GetType() != BrowserWindowInterface::TYPE_PICTURE_IN_PICTURE)
      InstallNativeFullscreenWindow(window_);
    was_attached_ = true;
    focus_ = FocusManager(window_);
    pane_compositors_ = std::make_unique<NativePaneCompositorClaim>(window_);
    RegisterAppKitBrowser(binding_, browser_);
    // Browser manager registration has completed; real SidePanel registries
    // exist, and this service is installed before any content/API exposure.
    side_panel_ = std::make_unique<NativeExtensionSidePanel>(browser_, *this);
    InstallAppActivityObservers();
    Synchronize();
  }
  void DidDetachWindow(gfx::NativeWindow window) override {
    if (window.GetNativeNSWindow() != window_) {
      return;
    }
    RemoveAppActivityObservers();
    DetachAllPages();
    pane_compositors_.reset();
    window_ = nil;
    selected_ = false;
    HostChanged();
  }
  void DidChangeSelectedBrowser(bool selected) override {
    selected_ = selected;
    if (selected) {
      auto* contents = browser_.GetTabStripModel()->GetActiveWebContents();
      selected_page_pending_ = contents ? contents->GetWeakPtr() : nullptr;
    }
    HostChanged();
    if (!tearing_down_) {
      Synchronize();
    }
  }
  void BrowserCloseApproved() override {
    AppKitBrowserCloseResult(binding_, browser_, true);
  }
  void BrowserCloseCancelled(
      BrowserWindowInterface::ClosingStatus status) override {
    // Chromium reports asynchronous unload progress through this callback too.
    // It is not a user cancellation and must not release the physical window.
    if (status !=
        BrowserWindowInterface::ClosingStatus::kDeniedUnloadHandlersNeedTime) {
      AppKitBrowserCloseResult(binding_, browser_, false);
    }
  }
  void PrepareForDeletion(base::OnceClosure completion) {
    CHECK(completion);
    if (drained_) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, std::move(completion));
      return;
    }
    deletion_completions_.push_back(std::move(completion));
    if (draining_) {
      return;
    }
    draining_ = true;
    action_bridge_->BeginShutdown();
    payment_entry_->BeginShutdown();
    auto weak = weak_factory_.GetWeakPtr();
    auto decisions = std::move(decisions_);
    for (const auto& decision : decisions) {
      CancelNativeHostDecision(decision.value);
      if (!weak) {
        return;
      }
    }
    CloseExtensionsMenu();
    if (!weak) {
      return;
    }
    autofill_->BeginTeardown();
    if (!weak) {
      return;
    }
    ++exclusive_generation_;
    exclusive_.reset();
    if (!weak) {
      return;
    }
    DetachAllPages();
    if (!weak) {
      return;
    }
    // The menu owns a scoped action-model dispatch lease. Release that lease
    // before either service can release its action/coordinator ownership.
    context_menu_->CancelAndWait(
        base::BindOnce(&AppKitBrowserHost::MenuDrained, weak));
  }
  void MenuDrained() {
    // The direct-action lease also covers callbacks that spin a nested loop;
    // posting a task alone cannot prove the upstream dispatch has returned.
    action_bridge_->Shutdown(base::BindOnce(
        &AppKitBrowserHost::PaymentDispatchDrain, weak_factory_.GetWeakPtr()));
  }
  void PaymentDispatchDrain() {
    payment_entry_->Shutdown(base::BindOnce(
        &AppKitBrowserHost::ActionDispatchDrained, weak_factory_.GetWeakPtr()));
  }
  void ActionDispatchDrained() {
    CHECK(draining_ && !drained_ && drains_pending_ == 0);
    auto weak = weak_factory_.GetWeakPtr();
    drains_pending_ = side_panel_ ? 2 : 1;
    if (side_panel_) {
      side_panel_->Shutdown(
          base::BindOnce(&AppKitBrowserHost::ServiceDrained, weak));
    }
    actions_->Shutdown(
        base::BindOnce(&AppKitBrowserHost::ServiceDrained, weak));
  }
  void ServiceDrained() {
    CHECK(draining_ && drains_pending_);
    if (--drains_pending_) {
      return;
    }
    // The BrowserManager still owns the genuine Browser/Profile. Service
    // callbacks confirm all ExtensionViewHosts have actually been released.
    side_panel_.reset();
    drained_ = true;
    auto completions = std::move(deletion_completions_);
    for (auto& completion : completions) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, std::move(completion));
    }
  }
  void BeginTeardown() override {
    if (tearing_down_) {
      return;
    }
    CHECK(drained_ || !was_attached_)
        << "Native Browser deletion requires service drain";
    tearing_down_ = true;
    RemoveAppActivityObservers();
    Hosts().erase(&browser_);
    browser_.GetTabStripModel()->RemoveObserver(this);
    // No new browser-owned work can enter after invalidation. Dialogs and
    // menus cancel before their actual Profile/TabList/action owners disappear.
    action_bridge_->BeginShutdown();
    payment_entry_->BeginShutdown();
    context_menu_->Cancel();
    CloseExtensionsMenu();
    actions_->Shutdown();
    autofill_->BeginTeardown();
    exclusive_.reset();
    DetachAllPages();
    pane_compositors_.reset();
    UnregisterAppKitBrowser(binding_, browser_);
    side_panel_.reset();
    // NativeBrowserWindow destroys feature-owned FindBar/command controllers
    // after this callback. Keep their stopped services allocated until the host
    // destructor, which follows TearDownPreBrowserWindowDestruction.
    weak_factory_.InvalidateWeakPtrs();
  }
  gfx::Rect GetWindowBounds(gfx::NativeWindow window) const override {
    return gfx::ScreenRectFromNSRect(window.GetNativeNSWindow().frame);
  }
  void SetWindowBounds(gfx::NativeWindow window,
                       const gfx::Rect& bounds) override {
    [window.GetNativeNSWindow() setFrame:gfx::ScreenRectToNSRect(bounds)
                                 display:YES];
  }
  void FlashWindow(gfx::NativeWindow, bool flash) override {
    if (flash && !attention_) {
      attention_ = [NSApp requestUserAttention:NSInformationalRequest];
    } else if (!flash && attention_) {
      [NSApp cancelUserAttentionRequest:attention_];
      attention_ = 0;
    }
  }
  NativeExtensionActionHost& GetExtensionActionHost() override { return *this; }
  autofill::AutofillBubbleHandler& GetAutofillBubbleHandler() override {
    return *autofill_;
  }
  ui::AcceleratorProvider& GetAcceleratorProvider() override { return *this; }
  bool GetAcceleratorForCommandId(int command,
                                  ui::Accelerator* result) const override {
    return ::GetAcceleratorForCommandId(command, result);
  }
  std::unique_ptr<FindBar> CreateFindBar() override {
    return std::make_unique<NativeFindBar>(*this);
  }
  bool DispatchExtensionActionAccelerator(
      const ui::Accelerator& accelerator) override {
    return !tearing_down_ && actions_->DispatchActionAccelerator(accelerator);
  }
  bool IsToolbarAvailable() const override {
    return selected() && window_ && binding_.client;
  }
  void ShowIntentPicker(std::vector<apps::IntentPickerAppInfo> apps,
                        bool stay, bool remember,
                        apps::IntentPickerBubbleType type,
                        const std::optional<url::Origin>& origin,
                        IntentPickerResponse callback) override {
    // Generic synchronous callers address the Browser's current page. The
    // asynchronous link-intent producer uses the exact-page route below.
    auto* contents = browser_.GetTabStripModel()->GetActiveWebContents();
    ShowIntentPickerForPage(contents, std::move(apps), stay, remember, type,
                            origin, std::move(callback));
  }
  void ShowIntentPickerForPage(content::WebContents* contents,
                              std::vector<apps::IntentPickerAppInfo> apps,
                              bool stay, bool remember,
                              apps::IntentPickerBubbleType type,
                              const std::optional<url::Origin>& origin,
                              IntentPickerResponse callback) {
    if (!contents || !ValidActionPage(*contents)) {
      if (callback) base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(std::move(callback), std::string(),
              apps::PickerEntryType::kUnknown,
              apps::IntentPickerCloseReason::ERROR_BEFORE_PICKER, false));
      return;
    }
    auto page = contents->GetWeakPtr();
    ShowNativeIntentPicker(browser_, *contents, window_,
        ExistingNativePage(contents).nativeView,
        base::BindRepeating([](base::WeakPtr<AppKitBrowserHost> host,
                              base::WeakPtr<content::WebContents> page) {
          return host && page && host->ValidActionPage(*page);
        }, weak_factory_.GetWeakPtr(), page),
        std::move(apps), stay, remember, type, origin, std::move(callback));
  }
  PCNativeOpenAppAction* OpenAppAction(content::WebContents& contents) {
    auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
    auto* helper = tab ? IntentPickerTabHelper::From(tab) : nullptr;
    if (!ValidActionPage(contents) || !helper || !helper->should_show_icon())
      return nil;
    auto token = std::make_shared<NativeOpenAppToken>();
    token->browser = browser_.GetWeakPtr();
    token->page = contents.GetWeakPtr();
    token->document = contents.GetPrimaryMainFrame()->GetWeakDocumentPtr();
    token->url = contents.GetLastCommittedURL();
    token->window = window_;
    return [[PCNativeOpenAppAction alloc] initWithToken:std::move(token)];
  }
  bool ExecuteOpenAppAction(PCNativeOpenAppAction* action,
                            content::WebContents& contents) {
    auto token = action ? action->_token : nullptr;
    auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
    auto* helper = tab ? IntentPickerTabHelper::From(tab) : nullptr;
    if (!token || token->browser.get() != &browser_ ||
        token->page.get() != &contents || token->window != window_ ||
        token->document.AsRenderFrameHostIfValid() != contents.GetPrimaryMainFrame() ||
        token->url != contents.GetLastCommittedURL() ||
        !ValidActionPage(contents) || !helper || !helper->should_show_icon() ||
        !window_.isKeyWindow || window_.attachedSheet ||
        PCNativeWindowHasSecurityReservation(window_)) return false;
    // Genuine backend revalidates app eligibility and owns original-tab
    // reparenting/native launch. It may destroy contents synchronously.
    helper->ShowIntentPickerBubbleOrLaunchApp(token->url, /*always_show=*/true);
    return true;
  }
  void ShowBookmarkEditor(const GURL& url, bool) override {
    [binding_.client nativeBrowser:binding_
                       bookmarkURL:[NSURL URLWithString:base::SysUTF8ToNSString(
                                                            PublicInternalURL(url).spec())]];
  }
  void ConfirmCloseWithDownloads(
      int count,
      DownloadCloseType type,
      base::OnceCallback<void(bool)> callback) override {
    if (draining_ || tearing_down_) {
      std::move(callback).Run(false);
      return;
    }
    auto weak = weak_factory_.GetWeakPtr();
    PCNativeHostDecision* decision = ShowNativeDownloadCloseDecision(
        window_, count, type, std::move(callback));
    if (weak && !draining_ && !tearing_down_) {
      decisions_.push_back({decision});
    } else {
      CancelNativeHostDecision(decision);
    }
  }
  void ShowProfilePicker(bool) override {
    [binding_.client nativeBrowserShowProfiles:binding_];
  }
  std::unique_ptr<content::EyeDropper> OpenEyeDropper(
      content::RenderFrameHost* frame,
      content::EyeDropperListener* listener) override {
    if (draining_ || tearing_down_ || !frame || !listener ||
        !frame->IsActive()) {
      return nullptr;
    }
    auto* contents = content::WebContents::FromRenderFrameHost(frame);
    if (!contents || !ValidActionPage(*contents) || !window_.isKeyWindow ||
        window_.attachedSheet || PCNativeWindowHasSecurityReservation(window_)) {
      return nullptr;
    }
    //
    // calls showSamplerWithSelectionHandler:. Chromium's macOS factory uses
    // that same system magnifier and selection/Escape interaction, without a
    // BrowserView. The requesting document owns the returned EyeDropper;
    // its listener receives the real color or cancellation. Keep Chromium's
    // weak callback and delayed sampler release on macOS Tahoe intact.
    return ::ShowEyeDropper(frame, listener);
  }
  void ShowCaretBrowsingDialog() override {
    if (draining_ || tearing_down_) {
      return;
    }
    auto weak = weak_factory_.GetWeakPtr();
    PCNativeHostDecision* decision = ShowNativeCaretDecision(browser_, window_);
    if (weak && !draining_ && !tearing_down_) {
      decisions_.push_back({decision});
    } else {
      CancelNativeHostDecision(decision);
    }
  }
  void ShowTabSearch() override {
    [binding_.client nativeBrowserShowTabSearch:binding_];
  }
  void CloseTabSearch() override {
    [binding_.client nativeBrowserCloseTabSearch:binding_];
  }
  void ShowIncognitoClearBrowsingDataDialog() override {
    ShowPrivateProfileDecision(false);
  }
  void ShowIncognitoHistoryDisclaimerDialog() override {
    ShowPrivateProfileDecision(true);
  }
  void ShowPrivateProfileDecision(bool history_information) {
    if (draining_ || tearing_down_ || !selected()) return;
    auto weak = weak_factory_.GetWeakPtr();
    PCNativeHostDecision* decision = ShowNativePrivateProfileDecision(
        browser_, window_, history_information);
    if (weak && !draining_ && !tearing_down_) {
      if (decision) decisions_.push_back({decision});
    } else {
      CancelNativeHostDecision(decision);
    }
  }
  void HandleDragEnded() override { Synchronize(); }
  void RequestFullscreen(
      bool enter,
      const url::Origin& origin,
      ExclusiveAccessBubbleType type,
      FullscreenTabParams params,
      base::OnceCallback<void(FullscreenRequestResult)> callback) override {
    auto weak = weak_factory_.GetWeakPtr();
    if (!selected() || !window_ || window_.attachedSheet) {
      std::move(callback).Run(FullscreenRequestResult::kRejected);
      return;
    }
    // FullscreenController already validated the requesting frame's actual
    // WINDOW_MANAGEMENT permission before supplying an explicit display ID.
    // Preserve its ownership of permission, nesting, and the prior display.
    // Acceptance is distinct from the final real native settlement.
    if (browser_.GetType() == BrowserWindowInterface::TYPE_PICTURE_IN_PICTURE) {
      // Preserve the accepted PiP path; it does not use this window controller.
      if (params.display_id != display::kInvalidDisplayId) {
        std::move(callback).Run(FullscreenRequestResult::kRejected);
        return;
      }
      if (enter != ((window_.styleMask & NSWindowStyleMaskFullScreen) != 0))
        [window_ toggleFullScreen:nil];
    } else if (!RequestNativeFullscreen(window_, enter, params.display_id)) {
      if (weak) std::move(callback).Run(FullscreenRequestResult::kRejected);
      return;
    }
    if (!weak) {
      return;
    }
    if (enter) {
      ExclusiveAccessBubbleParams warning;
      warning.origin = origin;
      warning.type = type;
      UpdateExclusiveAccessBubble(warning, {});
    }
    std::move(callback).Run(FullscreenRequestResult::kAccepted);
  }
  void UpdateUIForTabFullscreen() override {
    auto* controller =
        ExclusiveAccessManager::From(&browser_)->fullscreen_controller();
    PCNativePage* page =
        controller->IsTabFullscreen()
            ? ExistingNativePage(
                  browser_.GetTabStripModel()->GetActiveWebContents())
            : nil;
    [binding_.client nativeBrowser:binding_ setTabFullscreenPage:page];
  }
  void UpdateExclusiveAccessBubble(
      const ExclusiveAccessBubbleParams& params,
      ExclusiveAccessBubbleHideCallback callback) override {
    auto weak = weak_factory_.GetWeakPtr();
    const uint64_t generation = ++exclusive_generation_;
    auto previous = std::move(exclusive_);
    previous.reset();
    if (!weak || tearing_down_ || draining_ ||
        generation != exclusive_generation_) {
      if (callback) {
        std::move(callback).Run(ExclusiveAccessBubbleHideReason::kNotShown);
      }
      return;
    }
    auto next = NativeExclusiveAccess::Replace(nullptr, window_, params,
                                               std::move(callback));
    if (weak && !tearing_down_ && !draining_ &&
        generation == exclusive_generation_) {
      exclusive_ = std::move(next);
    }
  }
  bool IsExclusiveAccessBubbleDisplayed() const override {
    return exclusive_ && exclusive_->visible();
  }
  void OnExclusiveAccessUserInput() override {
    if (exclusive_) {
      exclusive_->OnUserInput();
    }
  }
  bool CanUserEnterFullscreen() const override {
    return selected() && window_ && !window_.attachedSheet &&
           (window_.styleMask & NSWindowStyleMaskResizable) &&
           !(window_.collectionBehavior & NSWindowCollectionBehaviorFullScreenNone);
  }
  bool CanUserExitFullscreen() const override { return window_ && selected(); }

  NSWindow* PopupParentWindow() const override { return window_; }
  PCExtensionPopupAnchor* PopupAnchor() const override {
    id<PCNativeBrowserWindowClient> client = binding_.client;
    if ([client
            respondsToSelector:@selector(nativeBrowserExtensionPopupAnchor:)]) {
      PCNativeExtensionPopupAnchor* anchor =
          [client nativeBrowserExtensionPopupAnchor:binding_];
      if (anchor.kind == PCNativeExtensionPopupAnchorFocusedView &&
          anchor.focusedView && anchor.focusedView.window == window_) {
        return [PCExtensionPopupAnchor focusedViewAnchor:anchor.focusedView];
      }
      if (anchor.kind == PCNativeExtensionPopupAnchorSidebar &&
          std::isfinite(anchor.sidebarWidth) && anchor.sidebarWidth >= 0 &&
          anchor.sidebarWidth <= NSWidth(window_.contentView.bounds)) {
        return
            [PCExtensionPopupAnchor sidebarAnchorWithWidth:anchor.sidebarWidth];
      }
    }
    return [PCExtensionPopupAnchor windowAnchor];
  }
  bool IsSelectedBrowser() const override { return selected(); }
  bool HasVisibleBrowserSecurityUI() const override {
    return window_.attachedSheet ||
           PCNativeWindowHasSecurityReservation(window_);
  }
  bool HasVisibleBrowserSecurityUIExcluding(
      NSWindow* owned_sheet,
      PCNativeWindowSecurityReservation* owned_reservation) const override {
    if (!window_ ||
        (window_.attachedSheet && window_.attachedSheet != owned_sheet)) {
      return true;
    }
    if (owned_reservation) {
      return owned_reservation.window != window_ ||
             !owned_reservation.isOnlyReservation;
    }
    return PCNativeWindowHasSecurityReservation(window_);
  }
  bool HandlePopupMenuKey(content::WebContents*,
                          const input::NativeWebKeyboardEvent& event) override {
    return MenuKey(event);
  }
  bool InspectPopup(content::WebContents* contents) override {
    if (!contents || contents->GetBrowserContext() != browser_.GetProfile()) {
      return false;
    }
    // Keep the supplied ExtensionViewHost contents; it need not be a CEF tab.
    return RequestAppKitDevtools(*contents);
  }
  bool ShowActionContextMenu(ExtensionActionViewModel& model) override {
    return !tearing_down_ && context_menu_->Show(model);
  }
  void CloseExtensionsMenu() override {
    NSMenu* menu = extensions_menu_;
    extensions_menu_ = nil;
    [menu cancelTracking];
  }
  bool ToggleExtensionsMenu() override {
    if (extensions_menu_) {
      CloseExtensionsMenu();
      return true;
    }
    if (!selected() || !window_.isVisible || HasVisibleBrowserSecurityUI()) {
      return false;
    }
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Extensions"];
    menu.autoenablesItems = NO;
    auto weak = weak_factory_.GetWeakPtr();
    PCNativePage* page = [binding_.client selectedNativePage];
    auto* contents = ContentsForNativePage(page);
    if (!contents || !ValidActionPage(*contents))
      return false;
    NSArray<PCNativeExtensionAction*>* values =
        action_bridge_->Snapshot(*contents, page.identifier, page.profilePath);
    PCNativeMenuTarget* target = [PCNativeMenuTarget new];
    // Retain immutable snapshots, never a raw model pointer across AppKit's
    // nested tracking loop. Every selection revalidates original ownership.
    target.invoke = ^(NSString* identifier) {
      if (!weak || !weak->selected())
        return;
      auto* current = ContentsForNativePage(page);
      if (!current || !weak->ValidActionPage(*current))
        return;
      for (PCNativeExtensionAction* value in values) {
        if ([value.identifier isEqualToString:identifier]) {
          weak->action_bridge_->Execute(value, *current, true);
          return;
        }
      }
    };
    for (PCNativeExtensionAction* value in values) {
      NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:value.name
                                                    action:@selector(perform:)
                                             keyEquivalent:@""];
      item.target = target;
      item.representedObject = value.identifier;
      item.image = value.icon;
      if (@available(macOS 27, *)) {
        item.preferredImageVisibility = NSMenuItemImageVisibilityVisible;
      }
      [menu addItem:item];
    }
    if (!menu.numberOfItems) {
      return false;
    }
    extensions_menu_ = menu;
    [menu popUpMenuPositioningItem:nil
                        atLocation:NSMakePoint(12, 12)
                            inView:window_.contentView];
    if (weak && weak->extensions_menu_ == menu) {
      weak->extensions_menu_ = nil;
    }
    return true;
  }
  void ExtensionActionsChanged() override {
    auto weak = weak_factory_.GetWeakPtr();
    CloseExtensionsMenu();
    if (weak && action_bridge_)
      action_bridge_->Changed();
  }
  bool ValidActionPage(content::WebContents& contents) const {
    PCNativePage* page = ExistingNativePage(&contents);
    auto cef = ChromeBrowserHostImpl::GetBrowserForContents(&contents);
    return selected() && window_ && window_.visible && !window_.miniaturized &&
           Owns(contents) && cef && cef->browser() == &browser_ && page &&
           !page.closed && page.nativeView.window == window_ &&
           !page.nativeView.hiddenOrHasHiddenAncestor &&
           [binding_.client selectedNativePage] == page;
  }
  bool CanShowPaymentEntry() const override {
    return payment_entry_ && !draining_ && !tearing_down_ &&
           [binding_.client respondsToSelector:@selector
                            (nativeBrowserPaymentActionsDidChange:)];
  }
  void PaymentEntryChanged(content::WebContents&) override {
    if (payment_entry_)
      payment_entry_->Changed();
  }
  NativePaymentEntry* PaymentEntry(content::WebContents& contents) {
    return ValidActionPage(contents) ? payment_entry_.get() : nullptr;
  }
  void NotifyPaymentChanges() {
    if (CanShowPaymentEntry())
      [binding_.client nativeBrowserPaymentActionsDidChange:binding_];
  }
  NativeExtensionActionBridge* ActionBridge(content::WebContents& contents) {
    return ValidActionPage(contents) ? action_bridge_.get() : nullptr;
  }
  void NotifyActionChanges() {
    if (draining_ || tearing_down_)
      return;
    id<PCNativeBrowserWindowClient> client = binding_.client;
    if ([client respondsToSelector:@selector
                (nativeBrowserExtensionActionsDidChange:)]) {
      [client nativeBrowserExtensionActionsDidChange:binding_];
    }
  }
  void ExtensionCapabilityUnavailable(const std::string&,
                                      const char* capability) override {
    Unavailable(base::SysUTF8ToNSString(capability));
  }
  std::optional<NativeAutofillPageContext> GetAutofillPageContext(
      content::WebContents& contents) override {
    PCNativePage* page = ExistingNativePage(&contents);
    if (tearing_down_ || !Owns(contents) || page.nativeView.window != window_) {
      return std::nullopt;
    }
    return NativeAutofillPageContext{gfx::NativeView(page.nativeView),
                                     gfx::NativeWindow(window_)};
  }
  NativeFindBarContext GetFindBarContext(
      content::WebContents* contents) override {
    PCNativePage* page = ExistingNativePage(contents);
    if (!contents || !Owns(*contents) || !selected() ||
        page.nativeView.window != window_) {
      return {};
    }
    auto found = pages_.find(contents);
    if (found == pages_.end() || !found->second.pane) {
      return {};
    }
    return {found->second.pane->find_anchor(), focus_,
            [page.identifier stringByAppendingString:@".find"], page.identifier,
            10};
  }
  void CloseFindOverlappingBubbles() override {
    actions_->HideActivePopup();
    CloseExtensionsMenu();
  }
  bool CloseExtensionSidePanel() {
    if (!selected() || !window_.keyWindow || binding_.window != window_ ||
        [binding_.client nativeBrowserWindow] != window_ || !side_panel_ ||
        !side_panel_->IsSidePanelShowing())
      return false;
    // The service detaches synchronously but drains real hosts out of callback
    // stacks. Do not access this host after Close can reenter its owner.
    side_panel_->Close();
    return true;
  }
  NSWindow* SidePanelWindow() const override { return window_; }
  NSView* SidePanelContainer() const override {
    return [binding_.client nativeBrowserSidePanelContainer:binding_];
  }
  NSView* SidePanelFocusScope() const override {
    id<PCNativeBrowserWindowClient> client = binding_.client;
    if ([client respondsToSelector:@selector(nativeBrowserSidePanelFocusScope:)])
      return [client nativeBrowserSidePanelFocusScope:binding_];
    return SidePanelContainer();
  }
  bool IsSidePanelBrowserSelected() const override { return selected(); }
  bool SetSidePanelVisible(bool visible) override {
    return [binding_.client nativeBrowser:binding_ setSidePanelVisible:visible];
  }
  bool HandleSidePanelKey(content::WebContents*,
                          const input::NativeWebKeyboardEvent& event) override {
    return MenuKey(event);
  }

  NSView* ContainerFor(PCNativePage* page) const {
    auto* contents = ContentsForNativePage(page);
    auto found = pages_.find(contents);
    return found != pages_.end() && found->second.page == page
               ? found->second.container
               : nil;
  }
  bool UpdateDevtools(content::WebContents* contents, bool update_contents) {
    if (draining_ || tearing_down_) {
      return false;
    }
    auto found = pages_.find(contents);
    if (found == pages_.end()) {
      return false;
    }
    auto pane = found->second.pane;
    return pane && pane->Refresh(update_contents);
  }
  void SetDevtoolsScrim(content::WebContents* tools, bool visible) {
    for (auto& [contents, entry] : pages_) {
      if (entry.pane && entry.pane->tools() == tools) {
        auto pane = entry.pane;
        pane->SetBlocked(visible);
        return;
      }
    }
  }
  void DetachDevtools() {
    // Feature teardown happens after native service drain. Page bindings own
    // presentation until their ordinary detach, so no tools objects are freed.
    std::vector<std::shared_ptr<NativeDevToolsPane>> snapshot;
    for (auto& [contents, entry] : pages_) {
      if (entry.pane) {
        snapshot.push_back(entry.pane);
      }
    }
    for (auto& pane : snapshot) {
      pane->Detach();
    }
  }
  // Never deliver shell adoption from SetBrowser/TabStripModel mutation stacks.
  // External creation binds its exact returned WebContents before this task;
  // internal creation is adopted only after model and CEF ownership agree.
  void Synchronize() {
    if (tearing_down_ || draining_) {
      return;
    }
    // Even a coalesced newer shell request supersedes visibility work that is
    // currently inside a callback-capable native show/hide operation.
    ++synchronize_generation_;
    if (synchronize_pending_) {
      return;
    }
    synchronize_pending_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<AppKitBrowserHost> self) {
                         if (!self) {
                           return;
                         }
                         self->synchronize_pending_ = false;
                         self->ReconcilePages();
                       },
                       weak_factory_.GetWeakPtr()));
  }
  bool AttachPage(content::WebContents& contents,
                  PCNativePage* page,
                  NSView* container) {
    if (tearing_down_ || draining_ || !window_ || !Owns(contents) ||
        ContentsForNativePage(page) != &contents ||
        container.window != window_) {
      return false;
    }
    auto cef = ChromeBrowserHostImpl::GetBrowserForContents(&contents);
    if (!cef || cef->browser() != &browser_ ||
        !GetNativeRoute(*browser_.GetProfile())) {
      return false;
    }
    auto* platform =
        static_cast<NativeChromePlatformDelegate*>(cef->platform_delegate());
    auto found = pages_.find(&contents);
    if (found != pages_.end() && found->second.container == container &&
        found->second.pane &&
        found->second.pane->view().superview == container &&
        page.nativeView.superview == found->second.pane->view()) {
      const auto weak = weak_factory_.GetWeakPtr();
      const auto contents_weak = contents.GetWeakPtr();
      auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
      const auto tab_weak =
          tab ? tab->GetWeakPtr() : base::WeakPtr<tabs::TabInterface>();
      const bool attached = platform->PageHostDidAttach();
      if (attached && weak) {
        weak->visibility_retries_ = 0;
        weak->Synchronize();
      }
      return attached && weak && contents_weak && tab_weak &&
             !weak->draining_ && !weak->tearing_down_ &&
             weak->Owns(*contents_weak) &&
             tab_weak.get() == tabs::TabInterface::MaybeGetFromContents(
                                   contents_weak.get()) &&
             tab_weak->GetBrowserWindowInterface() == &weak->browser_ &&
             container.window == weak->window_ &&
             weak->pages_.contains(contents_weak.get()) &&
             weak->pages_.at(contents_weak.get()).pane &&
             weak->pages_.at(contents_weak.get()).pane->view().superview ==
                 container &&
             page.nativeView.superview ==
                 weak->pages_.at(contents_weak.get()).pane->view();
    }
    auto weak = weak_factory_.GetWeakPtr();
    auto contents_weak = contents.GetWeakPtr();
    Detach(contents);
    if (!weak || !contents_weak || !Owns(*contents_weak) || draining_ ||
        tearing_down_ || container.window != window_) {
      return false;
    }
    // A detach callback may have moved a still-live contents to another host.
    cef = ChromeBrowserHostImpl::GetBrowserForContents(contents_weak.get());
    if (!cef || cef->browser() != &browser_) {
      return false;
    }
    platform =
        static_cast<NativeChromePlatformDelegate*>(cef->platform_delegate());
    return Attach(*contents_weak, page, container, *platform);
  }
  void ReconcilePages() {
    if (tearing_down_ || draining_ || !window_) {
      return;
    }
    auto weak = weak_factory_.GetWeakPtr();
    std::vector<base::WeakPtr<content::WebContents>> snapshot;
    for (int index = 0; index < browser_.GetTabStripModel()->count(); ++index) {
      snapshot.push_back(
          browser_.GetTabStripModel()->GetWebContentsAt(index)->GetWeakPtr());
    }
    for (auto contents : snapshot) {
      if (!contents || !Owns(*contents)) {
        continue;
      }
      auto cef = ChromeBrowserHostImpl::GetBrowserForContents(contents.get());
      if (!cef || cef->browser() != &browser_) {
        continue;
      }
      auto* platform =
          static_cast<NativeChromePlatformDelegate*>(cef->platform_delegate());
      PCNativePage* page =
          GetOrCreateNativePage(*contents, *platform, profile_path_);
      if (!pages_.contains(contents.get())) {
        // The Easel owner may park/reparent its existing view. Never convert
        // this auxiliary content into a saved tab after a detach or refusal.
        if (page.isEmbedded) continue;
        // This describes the actual destination Browser. The incoming page is
        // still the same Chromium-created WebContents; never reload its URL.
        const bool popup = browser_.GetType() == BrowserWindowInterface::TYPE_POPUP ||
                           browser_.GetType() == BrowserWindowInterface::TYPE_APP_POPUP;
        const auto ordinary_disposition = popup ? PCNativePageDispositionPopup :
            contents.get() ==
                    browser_.GetTabStripModel()->GetActiveWebContents()
                ? PCNativePageDispositionForegroundTab
                : PCNativePageDispositionBackgroundTab;
        const auto disposition =
            NativeCreatedPageDisposition(*contents, ordinary_disposition);
        if (!weak || tearing_down_ || draining_) return;
        if (!contents || !Owns(*contents)) continue;
        NSView* container = [binding_.client nativeBrowser:binding_
                                          containerForPage:page
                                               disposition:disposition];
        if (!weak || tearing_down_ || draining_) {
          return;
        }
        if (!contents || !Owns(*contents)) continue;
        if (!container && (disposition == PCNativePageDispositionPeek ||
                           disposition == PCNativePageDispositionSplitTab)) {
          // A document/selection change or shell refusal consumes only the
          // presentation request. Adopt the original created page normally.
          AbandonNativeCreatedPagePresentation(*contents);
          container = [binding_.client nativeBrowser:binding_
                                  containerForPage:page
                                       disposition:ordinary_disposition];
          if (!weak || tearing_down_ || draining_) return;
        }
        if (!contents || !Owns(*contents) || container.window != window_) {
          continue;
        }
        if (!AttachPage(*contents, page, container)) {
          continue;
        }
        if (!weak) {
          return;
        }
      }
    }
    //
    // This current-engine selection observation is delivered only after the
    // TabStrip mutation unwinds, including nested native event loops. Layout
    // must not turn the shell's previously selected page into a new command.
    auto selected_contents = selected_page_pending_;
    if (selected_contents && selected() && Owns(*selected_contents) &&
        browser_.GetTabStripModel()->GetActiveWebContents() ==
            selected_contents.get()) {
      PCNativePage* page = ExistingNativePage(selected_contents.get());
      const auto found = pages_.find(selected_contents.get());
      if (page && found != pages_.end() && found->second.page == page &&
          page.nativeView.window == window_ && binding_.window == window_) {
        PCNativePage* shell_selected = [binding_.client selectedNativePage];
        if (!weak || tearing_down_ || draining_ || !selected_contents ||
            !selected() || !Owns(*selected_contents) ||
            browser_.GetTabStripModel()->GetActiveWebContents() !=
                selected_contents.get() || page.nativeView.window != window_ ||
            binding_.window != window_ ||
            !pages_.contains(selected_contents.get()) ||
            pages_.at(selected_contents.get()).page != page) {
          return;
        }
        selected_page_pending_.reset();
        // An explicit shell selection has already updated its own state. Do
        // not echo that command back or steal focus from its address field.
        if (shell_selected != page) {
          [binding_.client nativeBrowser:binding_ didSelectPage:page];
        }
        if (!weak || tearing_down_ || draining_ || !selected_contents ||
            !selected() || !Owns(*selected_contents) ||
            browser_.GetTabStripModel()->GetActiveWebContents() !=
                selected_contents.get() || page.nativeView.window != window_ ||
            binding_.window != window_) {
          return;
        }
      }
    }
    SynchronizeVisibility(snapshot);
  }
  // The shell has already rearranged its panes when it asks for layout or
  // selection, so the pages it now shows join their compositors and unhide in
  // the same Core Animation commit as the new arrangement. A queued pass can
  // run only after AppKit's run loop has exited and committed that arrangement
  // with the incoming page still hidden, showing the pane's backing.
  void SynchronizeVisibilityNow() {
    if (tearing_down_ || draining_ || !window_) {
      return;
    }
    if (synchronizing_visibility_) {
      Synchronize();
      return;
    }
    std::vector<base::WeakPtr<content::WebContents>> snapshot;
    for (int index = 0; index < browser_.GetTabStripModel()->count(); ++index) {
      snapshot.push_back(
          browser_.GetTabStripModel()->GetWebContentsAt(index)->GetWeakPtr());
    }
    SynchronizeVisibility(snapshot);
  }
  // A pass a native callback asks for during another becomes a queued full
  // pass, which supersedes the outer one.
  void SynchronizeVisibility(
      const std::vector<base::WeakPtr<content::WebContents>>& snapshot) {
    if (tearing_down_ || draining_ || !window_) {
      return;
    }
    if (synchronizing_visibility_) {
      Synchronize();
      return;
    }
    auto weak = weak_factory_.GetWeakPtr();
    const uint64_t visibility_generation = synchronize_generation_;
    synchronizing_visibility_ = true;
    pass_visible_ = nil;
    ApplyVisibility(snapshot);
    if (weak) {
      synchronizing_visibility_ = false;
      // Also after a pass that stopped early without queueing a newer one.
      if (pass_visible_ && !tearing_down_ && !draining_ &&
          visibility_generation == synchronize_generation_) {
        RetryUnsettledVisibility(pass_visible_, pass_occluded_);
      }
      pass_visible_ = nil;
      SchedulePictureCheck();
    }
  }
  void ApplyVisibility(
      const std::vector<base::WeakPtr<content::WebContents>>& snapshot) {
    auto weak = weak_factory_.GetWeakPtr();
    const uint64_t visibility_generation = synchronize_generation_;
    // Occlusion is read fresh. The cached flag only marks a window that has
    // stayed covered for a second; a window back on screen whose notification
    // has not arrived (or never will) shows its pages instead of leaving a
    // newly attached one occluded and white.
    if (window_occluded_ && !WindowCurrentlyOccluded()) {
      occlusion_timer_.Stop();
      window_occluded_ = false;
    }
    const bool occluded = window_occluded_;
    NSArray<PCNativePage*>* visible = [binding_.client visibleNativePages];
    if (!weak || tearing_down_ || draining_ ||
        visibility_generation != synchronize_generation_) {
      return;
    }
    pass_visible_ = visible;
    pass_occluded_ = occluded;
    // Actual shell pane visibility, not TabStripModel's single active index,
    // determines compositor visibility for independently displayed split pages.
    for (auto contents : snapshot) {
      if (!contents || !Owns(*contents)) {
        continue;
      }
      PCNativePage* page = ExistingNativePage(contents.get());
      auto found = pages_.find(contents.get());
      if (!page || found == pages_.end() || found->second.page != page ||
          !found->second.pane) {
        continue;
      }
      auto pane = found->second.pane;
      NSView* container = found->second.container;
      PCNativePageHost* page_host =
          base::apple::ObjCCast<PCNativePageHost>(page.nativeView);
      NSWindow* window = window_;
      auto attached_here = [&] {
        if (!weak || !contents || weak->tearing_down_ || weak->draining_ ||
            weak->synchronize_generation_ != visibility_generation ||
            !weak->Owns(*contents) || !page_host || !window ||
            weak->window_ != window || weak->binding_.window != window ||
            ContentsForNativePage(page) != contents.get() ||
            page.nativeView != page_host || page_host.window != window ||
            container.window != window || pane->view().superview != container ||
            page_host.superview != pane->view() ||
            page_host.contentView !=
                contents->GetNativeView().GetNativeNSView()) {
          return false;
        }
        auto current = weak->pages_.find(contents.get());
        if (current == weak->pages_.end() || current->second.page != page ||
            current->second.container != container ||
            current->second.pane != pane) {
          return false;
        }
        auto cef = ChromeBrowserHostImpl::GetBrowserForContents(contents.get());
        return cef && cef->browser() == &weak->browser_ &&
               static_cast<NativeChromePlatformDelegate*>(
                   cef->platform_delegate())->HasAttachedPage();
      };
      if (!attached_here()) {
        continue;
      }
      const bool shown = [visible containsObject:page] &&
                         page.nativeView.window == window_ &&
                         !page.nativeView.hiddenOrHasHiddenAncestor &&
                         window_.visible && !window_.miniaturized;
      // Keep Chromium paint visibility tied to shell attachment only. Mapping
      // resign-active to WasOccluded blanked the live page while the window
      // stayed on screen. Auto-PiP still treats resign-active as occluded via
      // the shell visibility passed below — without freezing the compositor.
      // A page joins one of the window's persistent compositors before it
      // appears, so it replaces the previous page's last frame instead of a
      //
      if (shown) {
        const auto compositor = ShowInPaneCompositor(*contents, window,
                                                     PaneRole::kPage);
        if (!attached_here()) {
          return;
        }
        // A hand-off was mid-flight in a native callback: run the pass again
        // rather than unhide a page that may have nothing to draw through.
        if (compositor == PaneCompositorShow::kBusy) {
          Synchronize();
          return;
        }
      }
      const bool native_visibility_applied =
          [page_host setContentVisible:shown inWindow:window];
      if (!attached_here()) {
        return;
      }
      if (!native_visibility_applied) {
        continue;
      }
      NSArray<PCNativePage*>* current_visible =
          [binding_.client visibleNativePages];
      if (!attached_here()) {
        return;
      }
      const bool still_shown = [current_visible containsObject:page] &&
                               !page_host.hiddenOrHasHiddenAncestor &&
                               window.visible && !window.miniaturized;
      if (still_shown != shown) {
        Synchronize();
        return;
      }
      if (!shown) {
        HidePaneCompositor(*contents);
      }
      // Read before WasShown re-embeds: a page already VISIBLE is never told
      // to draw again, and one whose frame was evicted has nothing to show.
      const bool was_visible =
          contents->GetVisibility() == content::Visibility::VISIBLE;
      content::RenderWidgetHostViewMac* widget = PageWidgetView(*contents);
      const bool frame_evicted = widget && !widget->HasSavedCompositorFrame();
      // A shown page in a covered window, on another Space or behind
      // sleeping displays is OCCLUDED, as in Chrome: it stops painting and
      // its timers throttle. Chromium's own view tracking ignores a page until
      // it has seen it shown and re-reads only on its own triggers
      // (PageVisibilityWatch), so without this they rendered at full rate
      // unseen.
      if (shown && !occluded &&
          contents->GetVisibility() != content::Visibility::VISIBLE) {
        contents->WasShown();
      } else if (shown && occluded &&
                 contents->GetVisibility() != content::Visibility::OCCLUDED) {
        contents->WasOccluded();
      } else if (!shown &&
                 contents->GetVisibility() != content::Visibility::HIDDEN) {
        contents->WasHidden();
      }
      // A page that joined a compositor or was shown again draws onto a new
      // surface when it was already VISIBLE (WasShown returns early, so its
      // renderer never draws for the new compositor) or its frame was evicted
      // while hidden. A page that kept its frame shows it at once, so an
      // ordinary switch does not wait for a new surface.
      // Every show, attachment or compositor change also asks for the
      // outcome: the compositor's next frame reaching the screen.
      if (attached_here() && shown && !occluded &&
          contents->GetVisibility() == content::Visibility::VISIBLE &&
          !contents->IsLoading() && TakePaneCompositorRenewal(*contents)) {
        if (was_visible || frame_evicted) {
          RenewPageSurface(*contents);
          if (!attached_here()) {
            return;
          }
        }
        WatchPicture(*contents, window);
      }
      const auto pip_visibility =
          !shown ? parc::BackgroundPipVisibility::kHidden
                 : (NSApp.isActive ? parc::BackgroundPipVisibility::kVisible
                                   : parc::BackgroundPipVisibility::kOccluded);
      parc::SyncBackgroundPictureInPicture(contents.get(), pip_visibility);
      if (!attached_here()) {
        return;
      }
      UpdateDevtools(contents.get(), true);
      if (!weak || draining_) {
        return;
      }
    }
    if (side_panel_) {
      side_panel_->HostStateChanged();
    }
  }
  // Every page the shell shows in an on-screen window must end a pass drawing
  // (or occluded with its window). One that did not — skipped while still
  // attaching, refused by its host — gets a few short delayed passes, so a
  // trigger missed on any path corrects itself. A page that can never attach
  // stops retrying until a clean pass or a new attachment resets the budget.
  void RetryUnsettledVisibility(NSArray<PCNativePage*>* visible,
                                bool occluded) {
    bool unsettled = false;
    if (window_ && window_.visible && !window_.miniaturized) {
      for (PCNativePage* page in visible) {
        content::WebContents* contents = ContentsForNativePage(page);
        // A host the shell itself hid is meant to stay hidden.
        if (!contents || page.isEmbedded || !Owns(*contents) ||
            (page.nativeView.window == window_ &&
             page.nativeView.hiddenOrHasHiddenAncestor)) {
          continue;
        }
        const auto visibility = contents->GetVisibility();
        if (occluded ? visibility == content::Visibility::HIDDEN
                     : visibility != content::Visibility::VISIBLE) {
          unsettled = true;
          break;
        }
      }
    }
    if (!unsettled) {
      visibility_retries_ = 0;
      visibility_retry_timer_.Stop();
      return;
    }
    if (visibility_retries_ >= kVisibilityRetryLimit ||
        visibility_retry_timer_.IsRunning()) {
      return;
    }
    ++visibility_retries_;
    visibility_retry_timer_.Start(
        FROM_HERE, base::Milliseconds(50 << visibility_retries_), this,
        &AppKitBrowserHost::Synchronize);
  }
  // A page can be VISIBLE to Chromium with nothing on screen: its compositor
  // stopped, off its view, sized for another place or never presenting, or
  // its renderer with no frame for the surface it is embedded at (evicted
  // while hidden, a lost visual-properties update, a stale size). Only a
  // resize repaired those, since only a resize re-places the compositor and
  // gives the page a new surface the renderer must draw. Every pass is
  // followed by a check of the pages the window shows, and one without a
  // picture gets that same re-sync, a few times per arrangement of pages.
  // A shown page's confirmation: its current surface activated, then a
  // presentation requested after that answered.
  struct PresentationWatch {
    enum Stage { kAwaitingSurface, kAwaitingPresentation };
    uint64_t serial = 0;
    Stage stage = kAwaitingSurface;
    bool presented = false;
  };
  void SchedulePictureCheck() {
    if (tearing_down_ || draining_ || !window_) {
      return;
    }
    picture_check_timer_.Start(FROM_HERE,
                               kPictureCheckDelay *
                                   (1 << picture_repairs_),
                               this, &AppKitBrowserHost::CheckPictures);
  }
  void CheckPictures() {
    NSWindow* window = window_;
    if (tearing_down_ || draining_ || !window || synchronizing_visibility_) {
      return;
    }
    if (!window.visible || window.miniaturized || window_occluded_ ||
        displays_asleep_) {
      return;
    }
    auto weak = weak_factory_.GetWeakPtr();
    NSArray<PCNativePage*>* visible = [binding_.client visibleNativePages];
    if (!weak || tearing_down_ || draining_ || window_ != window) {
      return;
    }
    if (!picture_pages_ || ![picture_pages_ isEqualToArray:visible ?: @[]]) {
      picture_pages_ = [visible copy] ?: @[];
      picture_repairs_ = 0;
    }
    std::vector<base::WeakPtr<content::WebContents>> missing;
    std::set<const content::WebContents*> checked;
    picture_confirmation_pending_ = false;
    for (PCNativePage* page in visible) {
      content::WebContents* contents = ContentsForNativePage(page);
      // Pages not yet VISIBLE are the visibility retries' (overlay 330).
      if (!contents || page.isEmbedded || !Owns(*contents) ||
          page.nativeView.window != window ||
          page.nativeView.hiddenOrHasHiddenAncestor ||
          contents->GetVisibility() != content::Visibility::VISIBLE) {
        continue;
      }
      checked.insert(contents);
      if (MissingPictureCause(*contents, window)) {
        missing.push_back(contents->GetWeakPtr());
      }
    }
    // Watches of pages no longer shown here (or destroyed) are dropped.
    std::erase_if(presentation_watches_, [&](const auto& entry) {
      return !checked.contains(entry.first);
    });
    if (missing.empty()) {
      picture_repairs_ = 0;
      // A page whose surface just activated waits for its presentation.
      if (picture_confirmation_pending_) {
        SchedulePictureCheck();
      }
      return;
    }
    if (picture_repairs_ >= kPictureRepairLimit) {
      return;
    }
    ++picture_repairs_;
    for (const auto& contents : missing) {
      if (contents && weak && !tearing_down_ && !draining_ &&
          window_ == window && Owns(*contents)) {
        RepairPicture(*contents, window);
        if (weak && contents && !tearing_down_ && !draining_ &&
            window_ == window) {
          WatchPicture(*contents, window);
        }
      }
      if (!weak) {
        return;
      }
    }
    if (!tearing_down_ && !draining_ && window_ == window) {
      // Also unhides a page whose WebContents view a pass left hidden.
      Synchronize();
      SchedulePictureCheck();
    }
  }
  static content::RenderWidgetHostViewMac* PageWidgetView(
      content::WebContents& contents) {
    auto* view = static_cast<content::RenderWidgetHostViewBase*>(
        contents.GetRenderWidgetHostView());
    if (!view || view->IsRenderWidgetHostViewChildFrame() || !view->host() ||
        view->host()->auto_resize_enabled() ||
        !static_cast<content::RenderWidgetHostViewMac*>(view)
             ->BrowserCompositor() ||
        ![view->GetNativeView().GetNativeNSView()
            isKindOfClass:NSClassFromString(@"RenderWidgetHostViewCocoa")]) {
      return nullptr;
    }
    return static_cast<content::RenderWidgetHostViewMac*>(view);
  }
  // Its renderers draw into the compositor the page is attached to; one left
  // drawing into another (or its own, after a detach) shows nothing here.
  static bool DrawsIntoPaneCompositor(content::RenderWidgetHostViewMac& view,
                                      const content::WebContents& contents,
                                      NSWindow* window) {
    ui::Layer* layer = PaneCompositorLayer(contents, window);
    return layer && layer->GetCompositor() &&
           view.BrowserCompositor()->GetRootFrameSinkId() ==
               layer->GetCompositor()->frame_sink_id();
  }
  // The renderer view's bounds as its Cocoa view reports them to the host
  // (-[RenderWidgetHostViewCocoa sendViewBoundsInWindowToHost]).
  static gfx::Rect ViewBoundsInWindow(NSView* view, bool* attached) {
    NSWindow* window = view.window;
    *attached = window != nil;
    if (!window) {
      return gfx::Rect(NSRectToCGRect(view.bounds));
    }
    gfx::Rect bounds(NSRectToCGRect([view convertRect:view.bounds toView:nil]));
    bounds.set_y(NSHeight(window.frame) - bounds.bottom());
    return bounds;
  }
  // Why a shown page has no picture, or nullptr when it has one.
  const char* MissingPictureCause(content::WebContents& contents,
                                  NSWindow* window) {
    // A loading page shows the loading bar and Chromium's own first-frame
    // timeout; a crashed or hung renderer cannot draw whatever is re-sent.
    if (contents.IsBeingDestroyed() || contents.IsLoading() ||
        contents.IsCrashed()) {
      return nullptr;
    }
    switch (PaneCompositorPicture(contents, window)) {
      case PanePicture::kBusy:
        return nullptr;
      case PanePicture::kPresenting:
        break;
      case PanePicture::kNotAttached:
        return "compositor not attached";
      case PanePicture::kNotDrawing:
        return "compositor not drawing";
      case PanePicture::kNoFrame:
        return "compositor has no current frame";
    }
    content::RenderWidgetHostViewMac* view = PageWidgetView(contents);
    content::RenderWidgetHostImpl* host = view ? view->host() : nullptr;
    if (!host || !host->GetProcess()->IsInitializedAndNotDead() ||
        host->IsCurrentlyUnresponsive()) {
      return nullptr;
    }
    if (host->IsHidden()) {
      return "widget hidden";
    }
    if (!DrawsIntoPaneCompositor(*view, contents, window)) {
      return "renderer not parented to compositor";
    }
    // The page's own layer, as the compositor draws it: in this compositor's
    // tree, every ancestor visible, not transparent, not empty.
    const ui::Layer* layer =
        view->BrowserCompositor()->GetDelegatedFrameHostLayer();
    ui::Layer* pane_layer = PaneCompositorLayer(contents, window);
    if (!layer || !pane_layer ||
        layer->GetCompositor() != pane_layer->GetCompositor() ||
        !layer->IsVisible() || layer->GetCombinedOpacity() <= 0 ||
        layer->bounds().IsEmpty()) {
      return "page layer not drawn";
    }
    NSView* native = view->GetNativeView().GetNativeNSView();
    bool attached = false;
    const gfx::Size size = ViewBoundsInWindow(native, &attached).size();
    if (!size.IsEmpty() && size != view->GetRequestedRendererSize()) {
      return "view size stale";
    }
    if (!RendererSurfaceActivated(*view)) {
      return "renderer surface stale";
    }
    // The outcome, in order: the page's current surface activated (checked
    // just above), then a frame of its compositor drawn after that reached
    // the screen, with the page's layer drawn in it.
    auto watch = presentation_watches_.find(&contents);
    if (watch != presentation_watches_.end()) {
      if (watch->second.stage == PresentationWatch::kAwaitingSurface) {
        RequestPresentation(contents, window, watch->second);
        picture_confirmation_pending_ = true;
        return nullptr;
      }
      if (!watch->second.presented) {
        return "no presentation";
      }
      presentation_watches_.erase(watch);
    }
    return nullptr;
  }
  // Viz accepted a renderer frame for exactly the surface the page embeds:
  // RenderFrameMetadata reports each new surface id only after activation,
  // and a discarded or evicted frame never activates.
  static bool RendererSurfaceActivated(content::RenderWidgetHostViewMac& view) {
    content::DelegatedFrameHost* frame_host =
        view.BrowserCompositor()->GetDelegatedFrameHost();
    const viz::SurfaceId embedded = frame_host->GetCurrentSurfaceId();
    const std::optional<viz::LocalSurfaceId>& drawn =
        view.host()
            ->render_frame_metadata_provider()
            ->LastRenderFrameMetadata()
            .local_surface_id;
    return frame_host->HasPrimarySurface() && embedded.is_valid() && drawn &&
           drawn->is_valid() &&
           drawn->IsSameOrNewerThan(embedded.local_surface_id());
  }
  // After a show, attachment, compositor change or repair: wait for the
  // page's current surface to activate, then for the screen.
  void WatchPicture(content::WebContents& contents, NSWindow* window) {
    if (!PaneCompositorLayer(contents, window)) {
      // The picture checks report a page without a compositor themselves.
      presentation_watches_.erase(&contents);
      return;
    }
    PresentationWatch& watch = presentation_watches_[&contents];
    watch.serial = ++presentation_serial_;
    watch.stage = PresentationWatch::kAwaitingSurface;
    watch.presented = false;
    content::RenderWidgetHostViewMac* view = PageWidgetView(contents);
    if (view && !view->host()->IsHidden() && RendererSurfaceActivated(*view)) {
      RequestPresentation(contents, window, watch);
    }
  }
  // Asks the page's compositor, once its surface has activated, to report
  // its next frame reaching the screen, and draws one. That frame embeds the
  // activated surface. Unanswered at the next check, it is a missing picture.
  void RequestPresentation(content::WebContents& contents,
                           NSWindow* window,
                           PresentationWatch& watch) {
    ui::Layer* layer = PaneCompositorLayer(contents, window);
    ui::Compositor* compositor = layer ? layer->GetCompositor() : nullptr;
    watch.serial = ++presentation_serial_;
    watch.stage = PresentationWatch::kAwaitingPresentation;
    watch.presented = false;
    if (!compositor) {
      return;
    }
    compositor->RequestSuccessfulPresentationTimeForNextFrame(base::BindOnce(
        [](base::WeakPtr<AppKitBrowserHost> self,
           const content::WebContents* key, uint64_t serial,
           const viz::FrameTimingDetails&) {
          if (!self) {
            return;
          }
          auto found = self->presentation_watches_.find(key);
          if (found != self->presentation_watches_.end() &&
              found->second.serial == serial) {
            found->second.presented = true;
          }
        },
        weak_factory_.GetWeakPtr(), &contents, watch.serial));
    compositor->ScheduleFullRedraw();
  }
  // What a resize does: the compositor re-placed and redrawn at the current
  // size, the renderer view's bounds re-read, a new surface embedded and the
  // visual properties re-sent, past any acknowledgement still pending from a
  // renderer that never drew.
  void RepairPicture(content::WebContents& contents, NSWindow* window) {
    auto weak = weak_factory_.GetWeakPtr();
    auto weak_contents = contents.GetWeakPtr();
    const PanePicture picture = PaneCompositorPicture(contents, window);
    if (picture == PanePicture::kNotAttached ||
        picture == PanePicture::kNotDrawing) {
      ShowInPaneCompositor(contents, window, PaneRole::kPage);
      if (!weak || !weak_contents || tearing_down_ || draining_) {
        return;
      }
    }
    RefreshPaneCompositor(*weak_contents);
    content::RenderWidgetHostViewMac* view = PageWidgetView(*weak_contents);
    if (!view || !view->host()->GetProcess()->IsInitializedAndNotDead()) {
      return;
    }
    const base::WeakPtr<content::RenderWidgetHostViewBase> weak_view =
        view->GetWeakPtr();
    // What WebContentsViewMac::ViewsHostableAttach does for each renderer
    // view; a no-op when it is already parented there.
    if (!DrawsIntoPaneCompositor(*view, *weak_contents, window)) {
      if (ui::Layer* layer = PaneCompositorLayer(*weak_contents, window)) {
        view->SetParentUiLayer(layer);
        if (!weak || !weak_contents || !weak_view) {
          return;
        }
      }
    }
    if (view->host()->IsHidden() &&
        weak_contents->GetVisibility() == content::Visibility::VISIBLE) {
      view->ShowWithVisibility(content::PageVisibilityState::kVisible);
      if (!weak || !weak_contents || !weak_view) {
        return;
      }
    }
    bool attached = false;
    const gfx::Rect bounds = ViewBoundsInWindow(
        view->GetNativeView().GetNativeNSView(), &attached);
    if (!bounds.IsEmpty() &&
        bounds.size() != view->GetRequestedRendererSize()) {
      view->OnBoundsInWindowChanged(bounds, attached);
      if (!weak || !weak_contents || !weak_view) {
        return;
      }
    }
    RenewPageSurface(*weak_contents);
  }
  // A new surface id embedded and sent with the visual properties, past any
  // acknowledgement still pending from a renderer that never drew.
  static void RenewPageSurface(content::WebContents& contents) {
    content::RenderWidgetHostViewMac* view = PageWidgetView(contents);
    if (!view || view->host()->IsHidden() ||
        !view->host()->GetProcess()->IsInitializedAndNotDead()) {
      return;
    }
    const base::WeakPtr<content::RenderWidgetHostViewBase> weak_view =
        view->GetWeakPtr();
    view->RequestRepaintOnNewSurface();
    if (weak_view && view->host()) {
      view->host()->SynchronizeVisualPropertiesIgnoringPendingAck();
    }
  }
  bool RequestPageFocus(content::WebContents& contents) {
    const auto weak = weak_factory_.GetWeakPtr();
    const auto original = contents.GetWeakPtr();
    if (!ValidActionPage(contents) || !weak || !original ||
        ![PCNativeBrowserApplication canUseWindowUndoInWindow:window_] ||
        contents.IsBeingDestroyed() || contents.IsShowingContextMenu()) {
      return false;
    }
    PCNativePage* page = ExistingNativePage(&contents);
    const auto found = pages_.find(&contents);
    if (!page || found == pages_.end() || found->second.page != page ||
        !found->second.focus || binding_.window != window_ ||
        browser_.GetTabStripModel()->GetActiveWebContents() != &contents) {
      return false;
    }
    // Keep the existing manager through AppKit/KVO callbacks, not a Browser,
    // WebContents or host that a responder callback may retire.
    PCNativeFocusManager* manager = focus_;
    return [manager requestFocusForKey:page.identifier] !=
           PCNativeFocusRequestRejected;
  }
  void FocusPage() {
    auto* contents = browser_.GetTabStripModel()->GetActiveWebContents();
    PCNativePage* page = ExistingNativePage(contents);
    if (selected() && page.nativeView.window == window_) {
      if (FocusNativeRendererCrash(contents)) {
        return;
      }
      [focus_ requestFocusForKey:page.identifier];
    }
  }
  void RotateFocus(bool forward) {
    if (selected()) {
      [binding_.client nativeBrowser:binding_ rotateFocusForward:forward];
    }
  }
  bool FocusPopup() {
    if (!selected()) {
      return false;
    }
    // AppKit child windows are real presentations. Do not invent a Views
    // widget or use a different physical window's popup.
    for (NSWindow* child in window_.childWindows) {
      if (child.isVisible && child.canBecomeKeyWindow && !child.isKeyWindow) {
        [child makeKeyWindow];
        return child.isKeyWindow;
      }
    }
    return FocusNativeConfirmInfoBar(
        browser_.GetTabStripModel()->GetActiveWebContents());
  }
  void PageWillDetach(content::WebContents& contents) { Detach(contents); }
  void SetWebsiteTheme(NSString* stylesheet) {
    if (tearing_down_ || draining_ || !window_) return;
    website_theme_ = stylesheet ? base::SysNSStringToUTF8(stylesheet) : std::string();
    for (const auto& [contents, entry] : pages_)
      if (entry.theme) entry.theme->SetStylesheet(website_theme_);
  }

 private:
  bool Owns(content::WebContents& contents) const {
    return contents.GetBrowserContext() == browser_.GetProfile() &&
           browser_.GetTabStripModel()->GetIndexOfWebContents(&contents) !=
               TabStripModel::kNoTab;
  }
  void Unavailable(NSString* capability) {
    [binding_.client nativeBrowser:binding_ capabilityUnavailable:capability];
  }
  void HostChanged() {
    if (tearing_down_ || draining_) {
      return;
    }
    auto weak = weak_factory_.GetWeakPtr();
    if (!selected()) {
      if (auto* contents = browser_.GetTabStripModel()->GetActiveWebContents()) {
        auto contents_weak = contents->GetWeakPtr();
        CloseNativeIntentPicker(*contents);
        if (!weak || !contents_weak) return;
        CancelNativeCapturePicker(*contents);
      }
      if (!weak || draining_ || tearing_down_)
        return;
    }
    actions_->HostStateChanged();
    if (!weak || draining_ || tearing_down_)
      return;
    action_bridge_->Changed();
    payment_entry_->Changed();
    context_menu_->HostStateChanged();
    if (!weak || draining_ || tearing_down_)
      return;
    if (side_panel_) {
      side_panel_->HostStateChanged();
    }
  }
  struct PageBinding {
    PCNativePage* __strong page;
    NSView* __weak container;
    std::shared_ptr<NativeDevToolsPane> pane;
    PCNativeFocusRegistration* __strong focus;
    base::CallbackListSubscription detach;
    base::CallbackListSubscription discard;
    std::unique_ptr<NativeWebsiteTheme> theme;
    std::unique_ptr<PageVisibilityWatch> visibility;
  };
  bool Attach(content::WebContents& contents,
              PCNativePage* page,
              NSView* container,
              NativeChromePlatformDelegate& platform) {
    auto* initial_tab = tabs::TabInterface::MaybeGetFromContents(&contents);
    if (!initial_tab || initial_tab->GetBrowserWindowInterface() != &browser_) {
      return false;
    }
    const auto tab = initial_tab->GetWeakPtr();
    const auto weak = weak_factory_.GetWeakPtr();
    const auto contents_weak = contents.GetWeakPtr();
    NSView* view = page.nativeView;
    NSView* presentation = nil;
    auto valid = [&]() {
      if (!weak || !contents_weak || !tab || weak->draining_ ||
          weak->tearing_down_ || !weak->window_ ||
          container.window != weak->window_ || !weak->Owns(*contents_weak) ||
          tab.get() !=
              tabs::TabInterface::MaybeGetFromContents(contents_weak.get()) ||
          tab->GetContents() != contents_weak.get() ||
          tab->GetBrowserWindowInterface() != &weak->browser_ ||
          ContentsForNativePage(page) != contents_weak.get()) {
        return false;
      }
      auto bound = weak->pages_.find(contents_weak.get());
      if (bound != weak->pages_.end() &&
          (!presentation || bound->second.page != page ||
           bound->second.container != container || !bound->second.pane ||
           bound->second.pane->view() != presentation)) {
        // A native callback installed a newer presentation for these same
        // contents. The older attachment must not replace that binding.
        return false;
      }
      auto current =
          ChromeBrowserHostImpl::GetBrowserForContents(contents_weak.get());
      return current && current->browser() == &weak->browser_ &&
             current->platform_delegate() == &platform;
    };
    platform.PageHostWillDetach();
    if (!valid()) {
      return false;
    }
    [view removeFromSuperview];
    if (!valid()) {
      return false;
    }
    auto pane = NativeDevToolsPane::Create(contents, view);
    presentation = pane->view();
    if (!valid()) {
      return false;
    }
    presentation.frame = container.bounds;
    if (!valid()) {
      return false;
    }
    [container addSubview:presentation];
    auto attached_here = [&] {
      return presentation.superview == container &&
             view.superview == presentation;
    };
    if (!valid() || !attached_here()) {
      return false;
    }
    const bool attached = platform.PageHostDidAttach();
    if (!valid() || !attached_here() || !attached) {
      return false;
    }
    autofill_->PageHostDidAttach(*contents_weak);
    if (!valid() || !attached_here()) {
      return false;
    }
    PageBinding entry;
    entry.page = page;
    entry.container = container;
    entry.pane = pane;
    entry.focus = [focus_ registerResponder:view
                                     forKey:page.identifier
                                  didBecome:^{
                                    if (weak) {
                                      weak->focus_.fallbackKey =
                                          page.identifier;
                                    }
                                  }
                                  didResign:nil];
    if (!valid() || !attached_here()) {
      [entry.focus invalidate];
      return false;
    }
    entry.detach = tab->RegisterWillDetach(base::BindRepeating(
        [](base::WeakPtr<AppKitBrowserHost> host, tabs::TabInterface* tab,
           tabs::TabInterface::DetachReason) {
          if (host) {
            host->Detach(*tab->GetContents());
          }
        },
        weak));
    entry.discard = tab->RegisterWillDiscardContents(base::BindRepeating(
        [](base::WeakPtr<AppKitBrowserHost> host, tabs::TabInterface*,
           content::WebContents* old, content::WebContents*) {
          if (host) {
            host->Detach(*old);
          }
        },
        weak));
    entry.theme = std::make_unique<NativeWebsiteTheme>(contents,
        base::BindRepeating([](base::WeakPtr<AppKitBrowserHost> host,
                               base::WeakPtr<content::WebContents> page) {
          if (!host || !page || host->tearing_down_ || host->draining_ ||
              !host->window_ || host->binding_.window != host->window_ ||
              !host->binding_.client || !host->Owns(*page)) return false;
          auto found = host->pages_.find(page.get());
          return found != host->pages_.end() &&
              found->second.page.nativeView.window == host->window_;
        }, weak, contents_weak));
    entry.visibility = std::make_unique<PageVisibilityWatch>(
        contents,
        base::BindRepeating(&AppKitBrowserHost::PageVisibilityChanged, weak));
    pages_.emplace(&contents, std::move(entry));
    pages_.at(&contents).theme->SetStylesheet(website_theme_);
    action_bridge_->Changed();
    payment_entry_->Changed();
    __weak PCNativeBrowserWindow* binding = binding_;
    __weak PCNativePage* weak_page = page;
    SetNativePageClosedCallback(page, base::BindOnce(^{
                                  PCNativeBrowserWindow* current = binding;
                                  PCNativePage* closed_page = weak_page;
                                  if (current && closed_page) {
                                    [current.client nativeBrowser:current
                                                     didClosePage:closed_page];
                                  }
                                }));
    pane->Refresh(true);
    // A page is created hidden. Whatever attached it (the shell's own adoption
    // included), a full pass follows and shows it if its pane is on screen.
    visibility_retries_ = 0;
    Synchronize();
    return valid() && attached_here();
  }
  void Detach(content::WebContents& contents) {
    auto found = pages_.find(&contents);
    if (found == pages_.end()) {
      return;
    }
    PageBinding entry = std::move(found->second);
    pages_.erase(found);
    entry.theme.reset();  // Revoke before callback-capable owner detachment.
    entry.visibility.reset();
    // Even reattaching this exact page later cannot revive a snapshot captured
    // before its native ownership boundary was removed.
    action_bridge_->Changed();
    payment_entry_->Changed();
    // Docking detaches the real tools tab without destroying its page. The
    // auxiliary client is itself that page's observer; release only its exact
    // observation before another auxiliary owner can adopt the same page.
    if (browser_.GetType() == BrowserWindowInterface::TYPE_DEVTOOLS &&
        entry.page.observer == (id)binding_.client) {
      entry.page.observer = nil;
    }
    auto weak = weak_factory_.GetWeakPtr();
    auto contents_weak = contents.GetWeakPtr();
    CloseNativeIntentPicker(contents);
    if (!weak || !contents_weak) return;
    CancelNativeCapturePicker(contents);
    if (!weak || !contents_weak) {
      return;
    }
    [entry.focus invalidate];
    if (!weak || !contents_weak) {
      return;
    }
    HideNativePasswordPrompt(&contents);
    if (!weak || !contents_weak) {
      return;
    }
    autofill_->PageHostWillDetach(contents);
    if (!weak || !contents_weak) {
      return;
    }
    auto cef =
        ChromeBrowserHostImpl::GetBrowserForContents(contents_weak.get());
    if (cef && cef->browser() == &browser_) {
      static_cast<NativeChromePlatformDelegate*>(cef->platform_delegate())
          ->PageHostWillDetach();
    }
    if (!weak || !contents_weak) {
      return;
    }
    // A cancellation callback may already have adopted this same live view
    // into another host. Remove only the hierarchy owned by this old entry.
    if (entry.pane) {
      entry.pane->Detach();
    }
  }
  void DetachAllPages() {
    auto weak = weak_factory_.GetWeakPtr();
    while (weak && !pages_.empty()) {
      Detach(*pages_.begin()->first);
    }
  }
  void InstallAppActivityObservers() {
    if (app_activity_observers_) return;
    app_activity_observers_ = [NSMutableArray array];
    auto weak = weak_factory_.GetWeakPtr();
    for (NSNotificationName name in @[
           NSApplicationDidBecomeActiveNotification,
           NSApplicationDidResignActiveNotification
         ]) {
      id observer = [NSNotificationCenter.defaultCenter
          addObserverForName:name
                      object:nil
                       queue:nil
                  usingBlock:^(NSNotification*) {
                    if (auto* self = weak.get()) {
                      if (!self->tearing_down_ && !self->draining_) {
                        // Activation changes whether the key window counts
                        // as in front (WindowCurrentlyOccluded).
                        self->WindowOcclusionChanged();
                        self->Synchronize();
                      }
                    }
                  }];
      [app_activity_observers_ addObject:observer];
    }
    // Key changes anywhere in the app count: an extension popup or sheet
    // becoming key keeps its parent window in front (WindowCurrentlyOccluded).
    for (NSNotificationName name in @[
           NSWindowDidChangeOcclusionStateNotification,
           NSWindowDidBecomeKeyNotification,
           NSWindowDidResignKeyNotification
         ]) {
      const bool any_window =
          name != NSWindowDidChangeOcclusionStateNotification;
      id occlusion = [NSNotificationCenter.defaultCenter
          addObserverForName:name
                      object:any_window ? nil : window_
                       queue:nil
                  usingBlock:^(NSNotification*) {
                    if (auto* self = weak.get()) {
                      self->WindowOcclusionChanged();
                      // A window coming on screen gets a pass even when it was
                      // never marked occluded: a pass that ran while it was
                      // off screen hid its pages, and one ordered in without
                      // becoming key (a restored background window) gets no
                      // other. Chromium's checker posts this notification for
                      // the window too whenever its own flag changes.
                      if (!any_window && !self->WindowCurrentlyOccluded()) {
                        self->Synchronize();
                      }
                    }
                  }];
      [app_activity_observers_ addObject:occlusion];
    }
    id settled = [NSNotificationCenter.defaultCenter
        addObserverForName:kNativeFullscreenSettledNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto* self = weak.get()) {
                    self->WindowOcclusionChanged();
                  }
                }];
    [app_activity_observers_ addObject:settled];
    workspace_observers_ = [NSMutableArray array];
    for (NSNotificationName name in @[
           NSWorkspaceScreensDidSleepNotification,
           NSWorkspaceScreensDidWakeNotification
         ]) {
      const bool asleep = name == NSWorkspaceScreensDidSleepNotification;
      id observer = [NSWorkspace.sharedWorkspace.notificationCenter
          addObserverForName:name
                      object:nil
                       queue:nil
                  usingBlock:^(NSNotification*) {
                    if (auto* self = weak.get()) {
                      self->displays_asleep_ = asleep;
                      self->WindowOcclusionChanged();
                    }
                  }];
      [workspace_observers_ addObject:observer];
    }
    WindowOcclusionChanged();
  }
  void RemoveAppActivityObservers() {
    occlusion_timer_.Stop();
    visibility_retry_timer_.Stop();
    visibility_retries_ = 0;
    picture_check_timer_.Stop();
    picture_repairs_ = 0;
    picture_pages_ = nil;
    presentation_watches_.clear();
    window_occluded_ = false;
    displays_asleep_ = false;
    for (id observer in workspace_observers_) {
      [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
    }
    workspace_observers_ = nil;
    if (!app_activity_observers_) return;
    for (id observer in app_activity_observers_) {
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
    app_activity_observers_ = nil;
  }
  // A native fullscreen transition reports spurious occlusion (Chromium's
  // checker ignores it too, crbug.com/1081229); its settlement re-checks.
  bool WindowCurrentlyOccluded() const {
    if (!window_ || NativeFullscreenTransitioning(window_)) {
      return false;
    }
    if (displays_asleep_) {
      return true;
    }
    // The active app's key window is in front, and so is the window an
    // extension popup or sheet that is key belongs to. A link from another app
    // activates Parc with its new page already attached to a window that was
    // covered; the occlusion notification only follows the window server's
    // next draw, so the page started occluded (no paint, background priority)
    // and stayed white. A window covered by other apps or behind another
    // Parc window is not in the key window's chain and still goes occluded.
    if (InActiveKeyChain()) {
      return false;
    }
    return !(window_.occlusionState & NSWindowOcclusionStateVisible);
  }
  bool InActiveKeyChain() const {
    if (!window_ || !NSApp.isActive) {
      return false;
    }
    for (NSWindow* key = NSApp.keyWindow; key;
         key = key.sheetParent ?: key.parentWindow) {
      if (key == window_) {
        return true;
      }
    }
    return false;
  }
  // Uncovering shows pages at once. Covering waits a second, like Chromium's
  // WebContentsViewCocoa, so a window dragged across does not hide and
  // reshow them.
  void WindowOcclusionChanged() {
    if (tearing_down_ || draining_) {
      return;
    }
    if (!WindowCurrentlyOccluded()) {
      // A cover cancelled before the timer may still have let Chromium
      // occlude a page (PageVisibilityChanged leaves that to the timer).
      const bool covering = occlusion_timer_.IsRunning();
      occlusion_timer_.Stop();
      if (window_occluded_ || covering) {
        window_occluded_ = false;
        Synchronize();
      }
      return;
    }
    if (!window_occluded_ && !occlusion_timer_.IsRunning()) {
      occlusion_timer_.Start(FROM_HERE, base::Seconds(1), this,
                             &AppKitBrowserHost::ApplyWindowOcclusion);
    }
  }
  // A visibility change no pass made (PageVisibilityWatch) is followed by a
  // pass, which applies Parc's decision again. Chromium's occlusion stands
  // unless the window is in the active key window's chain: one Parc also
  // counts as covered is left to the occlusion timer, and one covered by
  // another of the app's windows stays occluded.
  void PageVisibilityChanged(content::Visibility visibility) {
    if (synchronizing_visibility_ || tearing_down_ || draining_ || !window_) {
      return;
    }
    if (visibility == content::Visibility::OCCLUDED) {
      if (WindowCurrentlyOccluded()) {
        WindowOcclusionChanged();
        return;
      }
      if (!InActiveKeyChain()) {
        return;
      }
    }
    Synchronize();
  }
  void ApplyWindowOcclusion() {
    if (tearing_down_ || draining_ || window_occluded_ ||
        !WindowCurrentlyOccluded()) {
      return;
    }
    window_occluded_ = true;
    Synchronize();
  }
  void OnTabStripModelChanged(TabStripModel*,
                              const TabStripModelChange&,
                              const TabStripSelectionChange& selection) override {
    if (selection.active_tab_changed()) {
      selected_page_pending_ = selection.new_contents
                                   ? selection.new_contents->GetWeakPtr()
                                   : nullptr;
    }
    action_bridge_->Changed();
    payment_entry_->Changed();
    Synchronize();
  }
  void OnTabCloseCancelled(const tabs::TabInterface* tab) override {
    NotifyNativePageCloseCancelled(tab->GetContents());
  }
  void OnTabStripModelDestroyed(TabStripModel*) override { BeginTeardown(); }
  BrowserWindowInterface& browser_;
  PCNativeBrowserWindow* __strong binding_;
  NSString* __strong profile_path_;
  NSWindow* __weak window_;
  PCNativeFocusManager* __strong focus_;
  std::unique_ptr<NativePaneCompositorClaim> pane_compositors_;
  std::map<content::WebContents*, PageBinding> pages_;
  std::string website_theme_;
  std::unique_ptr<NativeAutofillBubbleHandler> autofill_;
  std::unique_ptr<NativeExtensionActionContainer> actions_;
  std::unique_ptr<NativeExtensionActionBridge> action_bridge_;
  std::unique_ptr<NativePaymentEntry> payment_entry_;
  std::unique_ptr<NativeExtensionContextMenu> context_menu_;
  std::unique_ptr<NativeExtensionSidePanel> side_panel_;
  std::unique_ptr<NativeExclusiveAccess> exclusive_;
  struct DecisionLease {
    PCNativeHostDecision* __strong value;
  };
  std::vector<DecisionLease> decisions_;
  NSMenu* __strong extensions_menu_;
  NSMutableArray* __strong app_activity_observers_;
  NSMutableArray* __strong workspace_observers_;
  base::OneShotTimer occlusion_timer_;
  static constexpr int kVisibilityRetryLimit = 4;
  base::OneShotTimer visibility_retry_timer_;
  int visibility_retries_ = 0;
  // A missed case shows at most a brief blank: 200 ms, then 0.4, 0.8 and
  // 1.6 s after each repair. A check reads a few values per shown page; a
  // repair of a renderer still drawing costs it one frame, its in-flight
  // frame showing meanwhile as the fallback.
  static constexpr base::TimeDelta kPictureCheckDelay = base::Milliseconds(200);
  static constexpr int kPictureRepairLimit = 4;
  base::OneShotTimer picture_check_timer_;
  int picture_repairs_ = 0;
  NSArray<PCNativePage*>* __strong picture_pages_;
  bool picture_confirmation_pending_ = false;
  // Keys are compared only; a destroyed page's entry is pruned at a check.
  std::map<const content::WebContents*, PresentationWatch>
      presentation_watches_;
  uint64_t presentation_serial_ = 0;
  NSArray<PCNativePage*>* __strong pass_visible_;
  bool pass_occluded_ = false;
  bool window_occluded_ = false;
  bool displays_asleep_ = false;
  NSInteger attention_ = 0;
  uint64_t exclusive_generation_ = 0;
  bool selected_ = false;
  bool was_attached_ = false;
  bool tearing_down_ = false;
  bool draining_ = false;
  bool drained_ = false;
  size_t drains_pending_ = 0;
  std::vector<base::OnceClosure> deletion_completions_;
  bool synchronize_pending_ = false;
  bool synchronizing_visibility_ = false;
  uint64_t synchronize_generation_ = 0;
  base::WeakPtr<content::WebContents> selected_page_pending_;
  base::WeakPtrFactory<AppKitBrowserHost> weak_factory_{this};
};

class AppKitFocusController final : public BrowserFocusController {
 public:
  explicit AppKitFocusController(BrowserWindowInterface& browser)
      : BrowserFocusController(browser.GetWindow(),
                               browser.GetUnownedUserDataHost()),
        host_(Hosts().at(&browser)) {}
  void FocusWebContentsPane() override {
    if (host_) {
      host_->FocusPage();
    }
  }
  void RotatePaneFocus(bool forward) override {
    if (host_) {
      host_->RotateFocus(forward);
    }
  }
  void FocusInactivePopupForAccessibility() override {
    ActivateFirstInactiveBubbleForAccessibility();
  }
  bool ActivateFirstInactiveBubbleForAccessibility() override {
    return host_ && host_->FocusPopup();
  }

 private:
  base::WeakPtr<AppKitBrowserHost> host_;
};
class AppKitDevtoolsDelegate final
    : public DevtoolsUIController::NativeDelegate {
 public:
  explicit AppKitDevtoolsDelegate(BrowserWindowInterface& browser)
      : host_(Hosts().at(&browser)) {}
  bool Update(content::WebContents* contents, bool update) override {
    return host_ && host_->UpdateDevtools(contents, update);
  }
  void SetScrim(content::WebContents* tools, bool visible) override {
    if (host_) {
      host_->SetDevtoolsScrim(tools, visible);
    }
  }
  void TearDown() override {
    auto host = std::exchange(host_, {});
    if (host) {
      host->DetachDevtools();
    }
  }

 private:
  base::WeakPtr<AppKitBrowserHost> host_;
};
std::unique_ptr<DevtoolsUIController> CreateAppKitDevtoolsController(
    BrowserWindowInterface& browser) {
  return std::make_unique<DevtoolsUIController>(
      &browser, std::make_unique<AppKitDevtoolsDelegate>(browser));
}
bool RequestAppKitDevtools(content::WebContents& contents) {
  auto* profile = Profile::FromBrowserContext(contents.GetBrowserContext());
  if (!profile || !GetNativeRoute(*profile) ||
      !DevToolsWindow::AllowDevToolsFor(profile, &contents)) {
    return false;
  }
  auto weak = contents.GetWeakPtr();
  DevToolsWindow::OpenDevToolsWindow(&contents,
                                     DevToolsOpenedByAction::kUnknown);
  return weak && DevToolsWindow::GetInstanceForInspectedWebContents(weak.get());
}
bool HandleAppKitDevtoolsKey(content::WebContents* inspected,
                             content::WebContents& tools,
                             const input::NativeWebKeyboardEvent& event) {
  if (event.skip_if_unhandled) {
    return false;
  }
  NSWindow* window = tools.GetNativeView().GetNativeNSView().window;
  if (!window || !window.keyWindow) {
    return false;
  }
  auto tools_weak = tools.GetWeakPtr();
  auto inspected_weak = inspected ? inspected->GetWeakPtr() : nullptr;
  if (MenuKey(event)) {
    return true;
  }
  if (!tools_weak || !inspected_weak ||
      tools_weak->GetBrowserContext() != inspected_weak->GetBrowserContext()) {
    return false;
  }
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(
      inspected_weak.get());
  auto found = Hosts().find(browser);
  if (found == Hosts().end() || !found->second ||
      found->second->binding().window != window) {
    return false;
  }
  // Tools' own delegate has already handled frontend shortcuts. The ordinary
  // inspected-page Browser path still retains its separate DevTools-first
  // route.
  return BrowserWindow::FromBrowser(browser)->HandleKeyboardEvent(event);
}
NSView* AppKitPageContainer(BrowserWindowInterface& browser,
                            PCNativePage* page) {
  auto found = Hosts().find(&browser);
  return found != Hosts().end() && found->second
             ? found->second->ContainerFor(page)
             : nil;
}
std::unique_ptr<NativeBrowserWindowHost> CreateAppKitBrowserHost(
    BrowserWindowInterface& browser,
    PCNativeBrowserWindow* binding,
    NSString* path) {
  return std::make_unique<AppKitBrowserHost>(browser, binding, path);
}
std::unique_ptr<BrowserFocusController> CreateAppKitFocusController(
    BrowserWindowInterface& browser) {
  return std::make_unique<AppKitFocusController>(browser);
}
void AppKitPageOwnerChanged(BrowserWindowInterface* browser,
                            content::WebContents& contents) {
  // Ownership notifications are delivered while Chromium changes delegates.
  // Queue reconciliation; actual TabInterface WillDetach handles detachment.
  // An auxiliary lease never follows another Browser implicitly. Publish the
  // changed owner after this stack so its Easel can retire the exact child.
  PCNativePage* page = ExistingNativePage(&contents);
  if (page.isEmbedded) NotifyNativePageChanged(&contents);
  if (browser) {
    auto found = Hosts().find(browser);
    if (found != Hosts().end() && found->second) {
      found->second->Synchronize();
    }
  }
}
bool AttachAppKitPage(BrowserWindowInterface& browser,
                      PCNativePage* page,
                      NSView* container) {
  auto found = Hosts().find(&browser);
  auto* contents = ContentsForNativePage(page);
  return contents && found != Hosts().end() && found->second &&
         found->second->AttachPage(*contents, page, container);
}
void SetAppKitWebsiteTheme(BrowserWindowInterface& browser, NSString* stylesheet) {
  auto found = Hosts().find(&browser);
  if (found != Hosts().end() && found->second)
    found->second->SetWebsiteTheme(stylesheet);
}
void DetachAppKitPage(BrowserWindowInterface& browser, PCNativePage* page) {
  auto found = Hosts().find(&browser);
  auto* contents = ContentsForNativePage(page);
  if (contents && found != Hosts().end() && found->second) {
    found->second->PageWillDetach(*contents);
  }
}
void SynchronizeAppKitBrowser(BrowserWindowInterface& browser) {
  auto found = Hosts().find(&browser);
  if (found != Hosts().end() && found->second) {
    found->second->Synchronize();
  }
}
void SynchronizeAppKitBrowserVisibility(BrowserWindowInterface& browser) {
  auto found = Hosts().find(&browser);
  if (found != Hosts().end() && found->second) {
    found->second->SynchronizeVisibilityNow();
  }
}
bool AppKitBrowserAcceptsNewPages(BrowserWindowInterface& browser) {
  auto found = Hosts().find(&browser);
  return found != Hosts().end() && found->second &&
         found->second->acceptsNewPages();
}
void PrepareAppKitBrowserForDeletion(BrowserWindowInterface& browser,
                                     base::OnceClosure completion) {
  auto found = Hosts().find(&browser);
  CHECK(found != Hosts().end() && found->second);
  found->second->PrepareForDeletion(std::move(completion));
}
void RequestAppKitBrowserClose(BrowserWindowInterface& browser) {
  browser.GetWindow()->Close();
}
PCNativeBrowserWindow* AppKitBindingForBrowser(
    const BrowserWindowInterface* browser) {
  auto found = Hosts().find(browser);
  return found == Hosts().end() || !found->second ? nil
                                                  : found->second->binding();
}
NativePaymentEntry* PaymentEntryForPage(PCNativeBrowserWindow* binding,
                                        PCNativePage* page) {
  auto* contents = ContentsForNativePage(page);
  if (!contents)
    return nullptr;
  auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  auto found = Hosts().find(browser);
  if (found == Hosts().end() || !found->second ||
      found->second->binding() != binding)
    return nullptr;
  return found->second->PaymentEntry(*contents);
}
bool CloseExtensionSidePanelForBinding(PCNativeBrowserWindow* binding) {
  for (const auto& [browser, host] : Hosts()) {
    if (host && host->binding() == binding && host->selected())
      return host->CloseExtensionSidePanel();
  }
  return false;
}
NativeExtensionActionBridge* ActionBridgeForPage(PCNativeBrowserWindow* binding,
                                                 PCNativePage* page) {
  auto* contents = ContentsForNativePage(page);
  if (!contents)
    return nullptr;
  auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  auto found = Hosts().find(browser);
  if (found == Hosts().end() || !found->second ||
      found->second->binding() != binding)
    return nullptr;
  return found->second->ActionBridge(*contents);
}
bool MaybeShowNativeIntentPickerForPage(
    BrowserWindowInterface& browser, content::WebContents& contents,
    std::vector<apps::IntentPickerAppInfo>& apps, bool stay, bool remember,
    IntentPickerResponse& callback) {
  CHECK(NSThread.isMainThread);
  auto found = Hosts().find(&browser);
  if (found == Hosts().end() || !found->second) return false;
  found->second->ShowIntentPickerForPage(&contents, std::move(apps), stay,
      remember, apps::IntentPickerBubbleType::kLinkCapturing, std::nullopt,
      std::move(callback));
  return true;
}
PCNativeOpenAppAction* OpenAppActionForBinding(PCNativeBrowserWindow* binding,
                                              PCNativePage* page) {
  auto* contents = ContentsForNativePage(page);
  auto* tab = contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  auto found = Hosts().find(browser);
  return contents && found != Hosts().end() && found->second &&
      found->second->binding() == binding
      ? found->second->OpenAppAction(*contents) : nil;
}
bool ExecuteOpenAppActionForBinding(PCNativeBrowserWindow* binding,
    PCNativePage* page, PCNativeOpenAppAction* action) {
  auto* contents = ContentsForNativePage(page);
  auto* tab = contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  auto found = Hosts().find(browser);
  return contents && found != Hosts().end() && found->second &&
      found->second->binding() == binding &&
      found->second->ExecuteOpenAppAction(action, *contents);
}

}  // namespace parc

@implementation PCNativeBrowserWindow (PageFocus)
- (BOOL)requestFocusForPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(page);
  if (!contents || page.closed) return NO;
  auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  auto found = parc::Hosts().find(browser);
  if (found == parc::Hosts().end() || !found->second ||
      found->second->binding() != self) return NO;
  return found->second->RequestPageFocus(*contents);
}
@end

@implementation PCNativeBrowserWindow (OpenAppActions)
- (PCNativeOpenAppAction*)openAppActionForPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  return parc::OpenAppActionForBinding(self, page);
}
- (BOOL)executeOpenAppAction:(PCNativeOpenAppAction*)action
                   forPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  return parc::ExecuteOpenAppActionForBinding(self, page, action);
}
@end

@implementation PCNativeBrowserWindow (PaymentActions)
- (NSArray<PCNativePaymentAction*>*)paymentActionsForPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* entry = parc::PaymentEntryForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return entry && contents ? entry->Snapshot(*contents) : @[];
}
- (BOOL)executePaymentAction:(PCNativePaymentAction*)action
                     forPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* entry = parc::PaymentEntryForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return entry && contents && entry->Execute(action, *contents);
}
- (BOOL)paymentFeedbackPresented:(PCNativePaymentAction*)action
                         forPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* entry = parc::PaymentEntryForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return entry && contents && entry->FeedbackPresented(action, *contents);
}
@end

@implementation PCNativeBrowserWindow (ExtensionActions)
- (NSArray<PCNativeEnabledExtension*>*)enabledExtensionsForPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* bridge = parc::ActionBridgeForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return bridge && contents ? bridge->EnabledSnapshot(*contents) : @[];
}
- (BOOL)executeEnabledExtension:(PCNativeEnabledExtension*)extension
                        forPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* bridge = parc::ActionBridgeForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return bridge && contents && bridge->ExecuteEnabled(extension, *contents);
}
- (BOOL)showEnabledExtensionContextMenu:(PCNativeEnabledExtension*)extension
                                forPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* bridge = parc::ActionBridgeForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return bridge && contents && bridge->ShowEnabledContextMenu(extension, *contents);
}
- (BOOL)hasEnabledExtensionsForPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* bridge = parc::ActionBridgeForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return bridge && contents && bridge->HasEnabledExtensions(*contents);
}
- (BOOL)closeExtensionSidePanel {
  CHECK(NSThread.isMainThread);
  return parc::CloseExtensionSidePanelForBinding(self);
}
- (NSArray<PCNativeExtensionAction*>*)extensionActionsForPage:
    (PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* bridge = parc::ActionBridgeForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return bridge && contents
             ? bridge->Snapshot(*contents, page.identifier, page.profilePath)
             : @[];
}
- (BOOL)executeExtensionAction:(PCNativeExtensionAction*)action
                       forPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* bridge = parc::ActionBridgeForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return bridge && contents &&
         [action.pageIdentifier isEqualToString:page.identifier] &&
         [action.profilePath isEqualToString:page.profilePath] &&
         bridge->Execute(action, *contents);
}
- (BOOL)showExtensionActionContextMenu:(PCNativeExtensionAction*)action
                               forPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* bridge = parc::ActionBridgeForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return bridge && contents &&
         [action.pageIdentifier isEqualToString:page.identifier] &&
         [action.profilePath isEqualToString:page.profilePath] &&
         bridge->ShowContextMenu(action, *contents);
}
- (BOOL)setExtensionAction:(PCNativeExtensionAction*)action
                    pinned:(BOOL)pinned
                   forPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* bridge = parc::ActionBridgeForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return bridge && contents &&
         [action.pageIdentifier isEqualToString:page.identifier] &&
         [action.profilePath isEqualToString:page.profilePath] &&
         bridge->SetPinned(action, *contents, pinned);
}
@end

namespace parc {
struct NativeFullscreenExitToken {
  base::WeakPtr<BrowserWindowInterface> browser;
  base::WeakPtr<content::WebContents> contents;
  content::WeakDocumentPtr document;
  PCNativeBrowserWindow* __weak binding;
  PCNativePage* __weak page;
  NSWindow* __weak window;
  content::FullscreenMode mode;
  bool consumed = false;

  FullscreenController* Current(bool executing) const {
    auto* b = browser.get();
    auto* c = contents.get();
    NSWindow* w = window;
    PCNativeBrowserWindow* owner = binding;
    PCNativePage* original = page;
    if (consumed || !b || !c || !w || !owner || !original || original.closed ||
        c->IsBeingDestroyed() || c->IsShowingContextMenu() || b->IsDeleteScheduled() || !NSApp.active ||
        !w.visible || w.miniaturized || w.attachedSheet ||
        (executing ? !w.keyWindow : !(w.keyWindow || w.mainWindow)) ||
        PCNativeWindowHasSecurityReservation(w) || NativeFullscreenTransitioning(w) ||
        AppKitBindingForBrowser(b) != owner || owner.window != w ||
        !AppKitBrowserAcceptsNewPages(*b) ||
        GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(c) != b ||
        b->GetTabStripModel()->GetActiveWebContents() != c ||
        [owner.client selectedNativePage] != original ||
        ContentsForNativePage(original) != c || original.nativeView.window != w ||
        original.nativeView.hiddenOrHasHiddenAncestor ||
        document.AsRenderFrameHostIfValid() != c->GetPrimaryMainFrame())
      return nullptr;
    auto* manager = ExclusiveAccessManager::From(b);
    auto* fullscreen = manager ? manager->fullscreen_controller() : nullptr;
    return fullscreen && manager->context()->CanUserExitFullscreen() &&
                   fullscreen->GetFullscreenState(c).target_mode == mode
               ? fullscreen : nullptr;
  }
};
}  // namespace parc
@interface PCNativeFullscreenExit () {
 @package
  std::shared_ptr<parc::NativeFullscreenExitToken> _token;
}
- (instancetype)initWithToken:(std::shared_ptr<parc::NativeFullscreenExitToken>)token;
@end
@implementation PCNativeFullscreenExit
- (instancetype)initWithToken:(std::shared_ptr<parc::NativeFullscreenExitToken>)token {
  if ((self = [super init])) _token = std::move(token);
  return self;
}
- (BOOL)isAvailable {
  CHECK(NSThread.isMainThread);
  return _token && _token->Current(false);
}
- (BOOL)perform {
  CHECK(NSThread.isMainThread);
  auto token = _token;
  auto* fullscreen = token ? token->Current(true) : nullptr;
  if (!fullscreen) return NO;
  token->consumed = true;  // Consume before Chromium can reenter the shell.
  fullscreen->ExitFullscreenModeForTab(token->contents.get());
  return YES;  // Accepted dispatch; native state/notifications are authoritative.
}
@end

@implementation PCNativeBrowserWindow (FullscreenEvents)
- (PCNativeFullscreenExit*)prepareFullscreenExitForPage:(PCNativePage*)page {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(page);
  auto* browser = contents ? GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) : nullptr;
  auto* manager = browser ? ExclusiveAccessManager::From(browser) : nullptr;
  auto* fullscreen = manager ? manager->fullscreen_controller() : nullptr;
  if (!contents || !fullscreen || !contents->GetPrimaryMainFrame()) return nil;
  const auto mode = fullscreen->GetFullscreenState(contents).target_mode;
  if (mode == content::FullscreenMode::kWindowed) return nil;
  auto token = std::make_shared<parc::NativeFullscreenExitToken>();
  token->browser = browser->GetWeakPtr(); token->contents = contents->GetWeakPtr();
  token->document = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
  token->binding = self; token->page = page; token->window = self.window; token->mode = mode;
  // A known content mode retains its identity even while unavailable. The
  // shell must not interpret a denied/transitioning page exit as permission to
  // toggle the enclosing browser window instead.
  return [[PCNativeFullscreenExit alloc] initWithToken:std::move(token)];
}
+ (void)prepareNativeWindowFullscreen:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  parc::InstallNativeFullscreenWindow(window);
}
+ (void)nativeWindowDidFailToEnterFullscreen:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  parc::NativeFullscreenFailedToEnter(window);
}
@end
