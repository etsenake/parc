// Copyright 2026 Parc contributors.
#include "native_appkit_host.h"
#include "parc/page_preferences.h"
#include "native_internal_urls.h"
#include "native_link_routing.h"

#include <cmath>
#include <cstdint>
#include <map>
#include <memory>
#include <optional>
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
#include "chrome/browser/devtools/devtools_ui_controller.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/accelerator_table.h"
#include "chrome/browser/ui/browser.h"
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
#include "content/browser/renderer_host/render_widget_host_view_base.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/render_frame_host.h"
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
#include "native_background_picture_in_picture_hold.h"
#include "native_browser_window.h"
#include "native_capture_picker.h"
#include "native_confirm_infobars.h"
#include "native_exclusive_access.h"
#include "native_fullscreen_window.h"
#include "native_host_route.h"
#include "native_page_binding.h"
#include "native_intent_picker.h"
#include "native_intent_picker_api.h"
#include "native_payment_entry.h"
#include "native_website_theme.h"
#include "page_host.h"
#include "pane_compositor.h"
#include "password_prompt.h"
#include "sad_tab.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "window_security_reservation.h"
#include "third_party/blink/public/common/web_preferences/web_preferences.h"

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

@interface PCNativeScreenLockObserver : NSObject
- (instancetype)initWithChange:(void (^)(BOOL locked))change;
- (void)invalidate;
@end
@implementation PCNativeScreenLockObserver {
  void (^_change)(BOOL);
}
- (instancetype)initWithChange:(void (^)(BOOL locked))change {
  if ((self = [super init])) {
    _change = [change copy];
    NSDistributedNotificationCenter* center =
        NSDistributedNotificationCenter.defaultCenter;
    [center addObserver:self
                  selector:@selector(screenLocked:)
                      name:@"com.apple.screenIsLocked"
                    object:nil
        suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [center addObserver:self
                  selector:@selector(screenUnlocked:)
                      name:@"com.apple.screenIsUnlocked"
                    object:nil
        suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
  }
  return self;
}
- (void)invalidate {
  [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
  _change = nil;
}
- (void)screenLocked:(NSNotification*)notification {
  if (_change) {
    _change(YES);
  }
}
- (void)screenUnlocked:(NSNotification*)notification {
  if (_change) {
    _change(NO);
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
constexpr uint32_t kShowDeadlineFrames = 60;
class ScopedShowDeadline final {
 public:
  explicit ScopedShowDeadline(content::WebContents* contents) {
    auto* view = contents ? static_cast<content::RenderWidgetHostViewBase*>(
                                contents->GetRenderWidgetHostView())
                          : nullptr;
    if (view) {
      view_ = view->GetWeakPtr();
      view->SetForceSpecifiedDeadline(kShowDeadlineFrames);
    }
  }
  ScopedShowDeadline(const ScopedShowDeadline&) = delete;
  ScopedShowDeadline& operator=(const ScopedShowDeadline&) = delete;
  ~ScopedShowDeadline() { Reset(); }
  void Reset() {
    if (view_) {
      view_->SetForceSpecifiedDeadline(std::nullopt);
    }
    view_.reset();
  }

 private:
  base::WeakPtr<content::RenderWidgetHostViewBase> view_;
};
bool ReportPresentedFrame(content::WebContents& contents, PCNativePage* page) {
  __weak PCNativePage* weak_page = page;
  return NotifyPaneCompositorPresented(contents, base::BindOnce(^{
                                  PCNativePage* presented = weak_page;
                                  id<PCNativePageObserver> observer =
                                      presented.observer;
                                  if (presented && !presented.isClosed &&
                                      [observer respondsToSelector:@selector
                                                (nativePageDidPresentFrame:)]) {
                                    [observer
                                        nativePageDidPresentFrame:presented];
                                  }
                                }));
}
double PrimaryScreenHeight() {
  return NSHeight(NSScreen.screens.firstObject.frame);
}
BackgroundPipRect CocoaScreenRect(NSRect frame, double primary_height) {
  return BackgroundPipRectFromCocoa(NSMinX(frame), NSMinY(frame), NSWidth(frame),
                                    NSHeight(frame), primary_height);
}
std::vector<BackgroundPipRect> WindowScreenRegions(NSWindow* window,
                                                   double primary_height) {
  const auto window_rect = CocoaScreenRect(window.frame, primary_height);
  std::vector<BackgroundPipRect> regions;
  for (NSScreen* screen in NSScreen.screens) {
    regions.push_back(BackgroundPipIntersection(
        CocoaScreenRect(screen.frame, primary_height), window_rect));
  }
  return regions;
}
BackgroundPipRect ViewScreenRect(NSView* view, double primary_height) {
  NSWindow* window = view.window;
  if (!window) {
    return {};
  }
  return CocoaScreenRect(
      [window convertRectToScreen:[view convertRect:view.bounds toView:nil]],
      primary_height);
}
std::optional<std::vector<BackgroundPipRect>> WindowsAbove(NSWindow* window) {
  if (window.windowNumber <= 0) {
    return std::nullopt;
  }
  NSArray* list = CFBridgingRelease(CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenAboveWindow,
      static_cast<CGWindowID>(window.windowNumber)));
  if (!list) {
    return std::nullopt;
  }
  std::vector<BackgroundPipWindowRecord> records;
  for (id item in list) {
    NSDictionary* record = base::apple::ObjCCast<NSDictionary>(item);
    if (!record) {
      return std::nullopt;
    }
    BackgroundPipWindowRecord entry;
    if (NSNumber* layer = base::apple::ObjCCast<NSNumber>(
            record[(__bridge NSString*)kCGWindowLayer])) {
      entry.layer = layer.intValue;
    }
    if (NSNumber* alpha = base::apple::ObjCCast<NSNumber>(
            record[(__bridge NSString*)kCGWindowAlpha])) {
      entry.alpha = alpha.doubleValue;
    }
    NSDictionary* bounds = base::apple::ObjCCast<NSDictionary>(
        record[(__bridge NSString*)kCGWindowBounds]);
    CGRect rect = CGRectNull;
    if (bounds && CGRectMakeWithDictionaryRepresentation(
                      (__bridge CFDictionaryRef)bounds, &rect)) {
      entry.bounds = BackgroundPipRectFromQuartz(
          CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetWidth(rect),
          CGRectGetHeight(rect));
    }
    records.push_back(entry);
  }
  return BackgroundPipCoveringWindows(records);
}
}

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
  bool acceptsNewPages() const {
    return !tearing_down_ && !draining_ && !browser_.IsDeleteScheduled();
  }
  void PictureInPictureEligibilityChanged() { UpdatePipHoldWatch(); }
  void DidAttachWindow(gfx::NativeWindow window) override {
    CHECK(window.GetNativeNSWindow() == binding_.window);
    window_ = window.GetNativeNSWindow();
    if (browser_.GetType() != BrowserWindowInterface::TYPE_PICTURE_IN_PICTURE)
      InstallNativeFullscreenWindow(window_);
    was_attached_ = true;
    focus_ = FocusManager(window_);
    pane_compositors_ = std::make_unique<NativePaneCompositorClaim>(window_);
    RegisterAppKitBrowser(binding_, browser_);
    side_panel_ = std::make_unique<NativeExtensionSidePanel>(browser_, *this);
    InstallAppActivityObservers();
    fullscreen_changed_ = ExclusiveAccessManager::From(&browser_)
                              ->fullscreen_controller()
                              ->RegisterOnFullscreenStateChanged(
                                  base::BindRepeating(
                                      &AppKitBrowserHost::UpdateUIForTabFullscreen,
                                      weak_factory_.GetWeakPtr()));
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
    fullscreen_changed_ = {};
    DetachAllPages();
    if (!weak) {
      return;
    }
    context_menu_->CancelAndWait(
        base::BindOnce(&AppKitBrowserHost::MenuDrained, weak));
  }
  void MenuDrained() {
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
    action_bridge_->BeginShutdown();
    payment_entry_->BeginShutdown();
    context_menu_->Cancel();
    CloseExtensionsMenu();
    actions_->Shutdown();
    autofill_->BeginTeardown();
    fullscreen_changed_ = {};
    DetachAllPages();
    pane_compositors_.reset();
    UnregisterAppKitBrowser(binding_, browser_);
    side_panel_.reset();
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
    helper->ShowIntentPickerBubbleOrLaunchApp(token->url, true);
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
      FullscreenTabParams params,
      base::OnceCallback<void(FullscreenRequestResult)> callback) override {
    auto weak = weak_factory_.GetWeakPtr();
    if (!selected() || !window_ || window_.attachedSheet) {
      std::move(callback).Run(FullscreenRequestResult::kRejected);
      return;
    }
    if (browser_.GetType() == BrowserWindowInterface::TYPE_PICTURE_IN_PICTURE) {
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
    std::move(callback).Run(FullscreenRequestResult::kAccepted);
  }
  void UpdateUIForTabFullscreen() override {
    if (tearing_down_) return;
    content::WebContents* contents = ExclusiveAccessManager::From(&browser_)
                                         ->fullscreen_controller()
                                         ->exclusive_access_tab();
    [binding_.client nativeBrowser:binding_
              setTabFullscreenPage:contents ? ExistingNativePage(contents)
                                            : nil];
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
    return RequestAppKitDevtools(*contents);
  }
  bool ShowActionContextMenu(ExtensionActionViewModel& model,
                             id<PCNativeMenuPresenter> presenter) override {
    return !tearing_down_ && context_menu_->Show(model, presenter);
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
    return selected() && window_ && window_.visible && !window_.miniaturized &&
           Owns(contents) && NativeBrowserForContents(&contents) == &browser_ &&
           page &&
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
  void Synchronize() {
    if (tearing_down_ || draining_) {
      return;
    }
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
    auto* platform = NativePageBinding::FromWebContents(&contents);
    if (!platform || platform->browser() != &browser_ ||
        !GetNativeRoute(*browser_.GetProfile())) {
      return false;
    }
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
    platform = NativePageBinding::FromWebContents(contents_weak.get());
    if (!platform || platform->browser() != &browser_) {
      return false;
    }
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
      auto* platform = NativePageBinding::FromWebContents(contents.get());
      if (!platform || platform->browser() != &browser_) {
        continue;
      }
      PCNativePage* page =
          GetOrCreateNativePage(*contents, *platform, profile_path_);
      if (!pages_.contains(contents.get())) {
        if (page.isEmbedded) continue;
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
      if (pass_visible_ && !tearing_down_ && !draining_ &&
          visibility_generation == synchronize_generation_) {
        RetryUnsettledVisibility(pass_visible_, pass_occluded_);
      }
      pass_visible_ = nil;
    }
  }
  void ApplyVisibility(
      const std::vector<base::WeakPtr<content::WebContents>>& snapshot) {
    auto weak = weak_factory_.GetWeakPtr();
    const uint64_t visibility_generation = synchronize_generation_;
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
        auto* platform = NativePageBinding::FromWebContents(contents.get());
        return platform && platform->browser() == &weak->browser_ &&
               platform->HasAttachedPage();
      };
      if (!attached_here()) {
        continue;
      }
      const bool in_window = [visible containsObject:page] &&
                             (window.visible || window.miniaturized);
      if (SetPageInWindow(*contents, in_window)) {
        if (!attached_here()) {
          return;
        }
      }
      const bool shown = [visible containsObject:page] &&
                         page.nativeView.window == window_ &&
                         !page.nativeView.hiddenOrHasHiddenAncestor &&
                         window_.visible && !window_.miniaturized;
      if (auto binding = pages_.find(contents.get());
          !shown && binding != pages_.end()) {
        binding->second.pip_hold = false;
      }
      const bool page_occluded = PageOccluded(*contents, occluded);
      const bool drawn = shown && !page_occluded;
      bool arriving = false;
      if (auto binding = pages_.find(contents.get()); binding != pages_.end()) {
        arriving = drawn && !binding->second.shown;
        if (!drawn) {
          binding->second.shown = false;
        }
      }
      ScopedShowDeadline show_deadline(arriving ? contents.get() : nullptr);
      if (shown && HasRestoredLoadPending(*contents)) {
        SizeRestoredPage(*pane, page_host);
        if (!attached_here()) {
          return;
        }
      }
      if (shown) {
        const auto compositor = ShowInPaneCompositor(*contents, window,
                                                     PaneRole::kPage);
        if (!attached_here()) {
          return;
        }
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
      } else if (HasRestoredLoadPending(*contents)) {
        LoadRestoredPageIfSized(*contents, *pane, page_host);
        if (!attached_here()) {
          return;
        }
      }
      if (shown && !page_occluded &&
          (arriving ||
           contents->GetVisibility() != content::Visibility::VISIBLE)) {
        contents->WasShown();
      } else if (shown && page_occluded &&
                 contents->GetVisibility() != content::Visibility::OCCLUDED) {
        contents->WasOccluded();
      } else if (!shown &&
                 contents->GetVisibility() != content::Visibility::HIDDEN) {
        contents->WasHidden();
      }
      show_deadline.Reset();
      if (drawn && attached_here()) {
        if (auto binding = pages_.find(contents.get());
            binding != pages_.end() && binding->second.page == page) {
          binding->second.shown = true;
          if (binding->second.report_frame) {
            if (ReportPresentedFrame(*contents, page)) {
              binding->second.report_frame = false;
            } else {
              Synchronize();
            }
          }
        }
      }
      const auto pip_visibility =
          !shown ? parc::BackgroundPipVisibility::kHidden
                 : ((parc::PageHandlesAutoPictureInPicture(contents.get())
                         ? page_occluded
                         : BackgroundPipFocusAwayOccludes(
                               FocusAway(), PictureInPictureHeld(*contents)))
                        ? parc::BackgroundPipVisibility::kOccluded
                        : parc::BackgroundPipVisibility::kVisible);
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
  bool PageOccluded(content::WebContents& contents, bool window_occluded) {
    return window_occluded ||
           (BackgroundPipFocusAwayOccludes(FocusAway(),
                                           PictureInPictureHeld(contents)) &&
            parc::PageHandlesAutoPictureInPicture(&contents));
  }
  bool WindowOcclusionVisible() const {
    return window_ && (window_.occlusionState & NSWindowOcclusionStateVisible);
  }
  bool PipHoldWindowGateOpen() const {
    return FocusAway() && WindowOcclusionVisible() && !displays_asleep_ &&
           !screen_locked_;
  }
  bool PageShownInWindow(PCNativePage* page) const {
    return window_ && page && page.nativeView.window == window_ &&
           !page.nativeView.hiddenOrHasHiddenAncestor && window_.visible &&
           !window_.miniaturized;
  }
  BackgroundPipHoldGate PipHoldGate(content::WebContents& contents,
                                    bool shown) const {
    return {
        .focus_away = FocusAway(),
        .page_shown = shown,
        .window_visible = WindowOcclusionVisible(),
        .displays_asleep = displays_asleep_,
        .screen_locked = screen_locked_,
        .picture_in_picture_open = contents.HasPictureInPictureVideo() ||
                                   contents.HasPictureInPictureDocument(),
    };
  }
  bool PictureInPictureHeld(content::WebContents& contents) {
    const auto found = pages_.find(&contents);
    if (found == pages_.end() || !found->second.pip_hold) {
      return false;
    }
    if (!BackgroundPipHoldGateOpen(
            PipHoldGate(contents, PageShownInWindow(found->second.page)))) {
      found->second.pip_hold = false;
      return false;
    }
    return true;
  }
  bool ClearPipHolds() {
    pip_hold_timer_.Stop();
    StopPipHoldWatch();
    bool released = false;
    for (auto& [contents, binding] : pages_) {
      released = released || binding.pip_hold;
      binding.pip_hold = false;
    }
    return released;
  }
  void EndPipHoldsUnlessGateOpen() {
    if (!PipHoldWindowGateOpen()) {
      ClearPipHolds();
    }
  }
  bool EvaluatePipHolds(BackgroundPipHoldPass pass) {
    if (tearing_down_ || draining_ || !window_) {
      return false;
    }
    const auto weak = weak_factory_.GetWeakPtr();
    NSWindow* window = window_;
    NSArray<PCNativePage*>* visible = [binding_.client visibleNativePages];
    if (!weak || tearing_down_ || draining_ || window_ != window) {
      return false;
    }
    const bool gate_open = PipHoldWindowGateOpen();
    const double primary_height = PrimaryScreenHeight();
    const auto regions = gate_open ? WindowScreenRegions(window, primary_height)
                                   : std::vector<BackgroundPipRect>();
    const auto covers = gate_open ? WindowsAbove(window) : std::nullopt;
    bool held = false;
    bool released = false;
    for (auto& [contents, binding] : pages_) {
      PCNativePage* page = binding.page;
      const bool shown =
          gate_open && PageShownInWindow(page) && [visible containsObject:page];
      const bool hold =
          shown && ShouldHoldBackgroundPip(
                       pass, binding.pip_hold, PipHoldGate(*contents, shown),
                       ViewScreenRect(page.nativeView, primary_height), regions,
                       covers);
      released = released || (binding.pip_hold && !hold);
      held = held || hold;
      binding.pip_hold = hold;
      if (!hold) {
        binding.pip_hold_below_half_since.reset();
      }
    }
    if (released) {
      Synchronize();
    }
    return held;
  }
  void HoldVisiblePictureInPicture() {
    pip_hold_timer_.Stop();
    StopPipHoldWatch();
    const auto weak = weak_factory_.GetWeakPtr();
    const bool held = EvaluatePipHolds(BackgroundPipHoldPass::kFocusLost);
    if (!weak) {
      return;
    }
    if (held) {
      pip_hold_timer_.Start(FROM_HERE, base::Milliseconds(250), this,
                            &AppKitBrowserHost::RecheckPipHolds);
    }
    UpdatePipHoldWatch();
  }
  void RecheckPipHolds() {
    const auto weak = weak_factory_.GetWeakPtr();
    EvaluatePipHolds(BackgroundPipHoldPass::kRecheck);
    if (weak) {
      UpdatePipHoldWatch();
    }
  }
  void UpdatePipHoldWatch() {
    if (tearing_down_ || draining_ || !window_ ||
        !BackgroundPipHoldWatchRuns(
            PipHoldWindowGateOpen(), pages_,
            [](const auto& entry) { return entry.second.pip_hold; },
            [](const auto& entry) {
              return parc::PageCanEnterAutoPictureInPicture(entry.first);
            })) {
      StopPipHoldWatch();
      return;
    }
    if (!pip_hold_watch_.IsRunning()) {
      pip_hold_watch_.Start(
          FROM_HERE, base::Milliseconds(kBackgroundPipHoldWatchIntervalMs),
          this, &AppKitBrowserHost::WatchPipHolds);
    }
  }
  void StopPipHoldWatch() {
    pip_hold_watch_.Stop();
    for (auto& [contents, binding] : pages_) {
      binding.pip_hold_below_half_since.reset();
    }
  }
  void WatchPipHolds() {
    if (tearing_down_ || draining_ || !window_) {
      StopPipHoldWatch();
      return;
    }
    if (!PipHoldWindowGateOpen()) {
      ClearPipHolds();
      return;
    }
    const auto weak = weak_factory_.GetWeakPtr();
    NSWindow* window = window_;
    NSArray<PCNativePage*>* visible = [binding_.client visibleNativePages];
    if (!weak || tearing_down_ || draining_ || window_ != window) {
      return;
    }
    const double primary_height = PrimaryScreenHeight();
    const auto regions = WindowScreenRegions(window, primary_height);
    const auto covers = WindowsAbove(window);
    const int64_t now_ms =
        (base::TimeTicks::Now() - base::TimeTicks()).InMilliseconds();
    bool released = false;
    for (auto& [contents, binding] : pages_) {
      if (!binding.pip_hold) {
        continue;
      }
      PCNativePage* page = binding.page;
      const bool shown =
          PageShownInWindow(page) && [visible containsObject:page];
      binding.pip_hold = KeepBackgroundPipHold(
          binding.pip_hold_below_half_since, PipHoldGate(*contents, shown),
          ViewScreenRect(page.nativeView, primary_height), regions, covers,
          now_ms);
      released = released || !binding.pip_hold;
    }
    UpdatePipHoldWatch();
    if (released) {
      Synchronize();
    }
  }
  void RetryUnsettledVisibility(NSArray<PCNativePage*>* visible,
                                bool occluded) {
    bool unsettled = false;
    if (window_ && window_.visible && !window_.miniaturized) {
      for (PCNativePage* page in visible) {
        content::WebContents* contents = ContentsForNativePage(page);
        if (!contents || page.isEmbedded || !Owns(*contents) ||
            (page.nativeView.window == window_ &&
             page.nativeView.hiddenOrHasHiddenAncestor)) {
          continue;
        }
        const auto visibility = contents->GetVisibility();
        if (PageOccluded(*contents, occluded)
                ? visibility == content::Visibility::HIDDEN
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
  bool ParkPage(content::WebContents& contents) {
    auto found = pages_.find(&contents);
    if (tearing_down_ || draining_ || found == pages_.end()) {
      return false;
    }
    PCNativePage* page = found->second.page;
    found->second.report_frame = false;
    if ([focus_.fallbackKey isEqualToString:page.identifier]) {
      focus_.fallbackKey = nil;
    }
    [found->second.focus invalidate];
    found->second.focus = RegisterFocus(page);
    auto weak = weak_factory_.GetWeakPtr();
    auto contents_weak = contents.GetWeakPtr();
    auto still_bound = [&] {
      if (!weak || !contents_weak || weak->tearing_down_ || weak->draining_) {
        return false;
      }
      auto current = weak->pages_.find(contents_weak.get());
      return current != weak->pages_.end() && current->second.page == page;
    };
    action_bridge_->Changed();
    payment_entry_->Changed();
    if (!still_bound()) return false;
    CloseNativeIntentPicker(contents);
    if (!still_bound()) return false;
    CancelNativeCapturePicker(*contents_weak);
    if (!still_bound()) return false;
    HideNativePasswordPrompt(contents_weak.get());
    if (!still_bound()) return false;
    autofill_->PageHostWillDetach(*contents_weak);
    if (!still_bound()) return false;
    auto platform = [&]() -> NativePageBinding* {
      auto* binding = NativePageBinding::FromWebContents(contents_weak.get());
      return binding && binding->browser() == &browser_ ? binding : nullptr;
    };
    if (auto* delegate = platform()) {
      delegate->PageHostWillDetach();
    }
    if (!still_bound()) return false;
    auto* delegate = platform();
    const bool attached = delegate && delegate->PageHostDidAttach();
    if (!still_bound()) return false;
    autofill_->PageHostDidAttach(*contents_weak);
    if (!still_bound()) return false;
    if (!attached) {
      Detach(*contents_weak);
      return false;
    }
    visibility_retries_ = 0;
    Synchronize();
    return true;
  }
  void ReportNextFrame(content::WebContents& contents) {
    auto found = pages_.find(&contents);
    if (tearing_down_ || draining_ || found == pages_.end()) {
      return;
    }
    found->second.report_frame = true;
    Synchronize();
  }
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
    bool shown = false;
    bool report_frame = false;
    bool pip_hold = false;
    std::optional<int64_t> pip_hold_below_half_since;
  };
  PCNativeFocusRegistration* RegisterFocus(PCNativePage* page) {
    auto weak = weak_factory_.GetWeakPtr();
    return [focus_ registerResponder:page.nativeView
                              forKey:page.identifier
                           didBecome:^{
                             if (weak) {
                               weak->focus_.fallbackKey = page.identifier;
                             }
                           }
                           didResign:nil];
  }
  bool Attach(content::WebContents& contents,
              PCNativePage* page,
              NSView* container,
              NativePageBinding& platform) {
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
        return false;
      }
      auto* current = NativePageBinding::FromWebContents(contents_weak.get());
      return current == &platform && current->browser() == &weak->browser_;
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
    if (HasRestoredLoadPending(*contents_weak)) {
      SizeRestoredPage(*pane, view);
      if (!valid()) {
        return false;
      }
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
    entry.focus = RegisterFocus(page);
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
    if (!valid() || !attached_here()) {
      return false;
    }
    LoadRestoredPageIfSized(*contents_weak, *pane, view);
    if (!valid() || !attached_here()) {
      return false;
    }
    visibility_retries_ = 0;
    Synchronize();
    return valid() && attached_here();
  }
  static void LoadRestoredPageIfSized(content::WebContents& contents,
                                      NativeDevToolsPane& pane,
                                      NSView* page_host) {
    if (!HasRestoredLoadPending(contents)) {
      return;
    }
    SizeRestoredPage(pane, page_host);
    NSView* native = contents.GetNativeView().GetNativeNSView();
    if (native.bounds.size.width < 1 || native.bounds.size.height < 1 ||
        !TakeRestoredLoadPending(contents)) {
      return;
    }
    contents.GetController().LoadIfNecessary();
  }
  static void SizeRestoredPage(NativeDevToolsPane& pane, NSView* page_host) {
    pane.Layout();
    page_host.needsLayout = YES;
    [page_host layoutSubtreeIfNeeded];
  }
  void Detach(content::WebContents& contents) {
    auto found = pages_.find(&contents);
    if (found == pages_.end()) {
      return;
    }
    PageBinding entry = std::move(found->second);
    pages_.erase(found);
    entry.theme.reset();
    entry.visibility.reset();
    action_bridge_->Changed();
    payment_entry_->Changed();
    if (browser_.GetType() == BrowserWindowInterface::TYPE_DEVTOOLS &&
        entry.page.observer == (id)binding_.client) {
      entry.page.observer = nil;
    }
    auto weak = weak_factory_.GetWeakPtr();
    auto contents_weak = contents.GetWeakPtr();
    if (SetPageInWindow(contents, false)) {
      if (!weak || !contents_weak) return;
    }
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
    auto* platform = NativePageBinding::FromWebContents(contents_weak.get());
    if (platform && platform->browser() == &browser_) {
      platform->PageHostWillDetach();
    }
    if (!weak || !contents_weak) {
      return;
    }
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
                    auto* self = weak.get();
                    if (!self || self->tearing_down_ || self->draining_) {
                      return;
                    }
                    self->WindowOcclusionChanged();
                    if (auto* host = weak.get()) {
                      host->FocusChanged();
                    }
                    if (auto* host = weak.get()) {
                      host->Synchronize();
                    }
                  }];
      [app_activity_observers_ addObject:observer];
    }
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
                    auto* self = weak.get();
                    if (!self) {
                      return;
                    }
                    self->WindowOcclusionChanged();
                    if (auto* host = weak.get(); host && any_window) {
                      host->FocusChanged();
                    }
                    if (auto* host = weak.get();
                        host &&
                        (any_window || !host->WindowCurrentlyOccluded())) {
                      host->Synchronize();
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
    screen_lock_observer_ = [[PCNativeScreenLockObserver alloc]
        initWithChange:^(BOOL locked) {
          auto* self = weak.get();
          if (!self) {
            return;
          }
          self->screen_locked_ = locked;
          if (locked && self->ClearPipHolds()) {
            self->Synchronize();
          }
        }];
    focus_away_ = FocusAway();
    WindowOcclusionChanged();
  }
  void RemoveAppActivityObservers() {
    occlusion_timer_.Stop();
    visibility_retry_timer_.Stop();
    visibility_retries_ = 0;
    window_occluded_ = false;
    displays_asleep_ = false;
    [screen_lock_observer_ invalidate];
    screen_lock_observer_ = nil;
    screen_locked_ = false;
    focus_away_ = false;
    ClearPipHolds();
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
  bool WindowCurrentlyOccluded() const {
    if (!window_ || NativeFullscreenTransitioning(window_)) {
      return false;
    }
    if (displays_asleep_) {
      return true;
    }
    if (InActiveKeyChain()) {
      return false;
    }
    return !(window_.occlusionState & NSWindowOcclusionStateVisible);
  }
  bool InActiveKeyChain() const {
    NSWindow* window = window_;
    NSWindow* key = NSApp.keyWindow;
    return BackgroundPipWindowInActiveKeyChain(
        static_cast<bool>(NSApp.isActive), key, window,
        [](NSWindow* candidate) -> NSWindow* {
          return candidate.sheetParent ?: candidate.parentWindow;
        });
  }
  bool FocusAway() const { return !InActiveKeyChain(); }
  void FocusChanged() {
    if (tearing_down_ || draining_ || !window_) {
      return;
    }
    const bool away = FocusAway();
    const auto change = BackgroundPipFocusTransition(focus_away_, away);
    focus_away_ = away;
    if (change == BackgroundPipFocusChange::kLost) {
      HoldVisiblePictureInPicture();
    } else if (change == BackgroundPipFocusChange::kRegained) {
      ClearPipHolds();
    }
  }
  void WindowOcclusionChanged() {
    if (tearing_down_ || draining_) {
      return;
    }
    EndPipHoldsUnlessGateOpen();
    if (!WindowCurrentlyOccluded()) {
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
  base::CallbackListSubscription fullscreen_changed_;
  struct DecisionLease {
    PCNativeHostDecision* __strong value;
  };
  std::vector<DecisionLease> decisions_;
  NSMenu* __strong extensions_menu_;
  NSMutableArray* __strong app_activity_observers_;
  NSMutableArray* __strong workspace_observers_;
  PCNativeScreenLockObserver* __strong screen_lock_observer_;
  base::OneShotTimer occlusion_timer_;
  base::OneShotTimer pip_hold_timer_;
  base::RepeatingTimer pip_hold_watch_;
  static constexpr int kVisibilityRetryLimit = 4;
  base::OneShotTimer visibility_retry_timer_;
  int visibility_retries_ = 0;
  NSArray<PCNativePage*>* __strong pass_visible_;
  bool pass_occluded_ = false;
  bool window_occluded_ = false;
  bool displays_asleep_ = false;
  bool screen_locked_ = false;
  bool focus_away_ = false;
  NSInteger attention_ = 0;
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
  void FocusInactivePopupForAccessibility() override {
    ActivateFirstInactiveBubbleForAccessibility();
  }
  bool ActivateFirstInactiveBubbleForAccessibility() override {
    return host_ && host_->FocusPopup();
  }

 private:
  base::WeakPtr<AppKitBrowserHost> host_;
};
namespace {
std::map<const DevtoolsUIController*, base::WeakPtr<AppKitBrowserHost>>&
DevtoolsHosts() {
  static base::NoDestructor<
      std::map<const DevtoolsUIController*, base::WeakPtr<AppKitBrowserHost>>>
      value;
  return *value;
}
}
std::unique_ptr<DevtoolsUIController> CreateAppKitDevtoolsController(
    BrowserWindowInterface& browser) {
  auto controller = std::make_unique<DevtoolsUIController>(
      &browser,
      std::vector<raw_ptr<ContentsContainerView, DanglingUntriaged>>());
  DevtoolsHosts().insert_or_assign(controller.get(), Hosts().at(&browser));
  return controller;
}
std::optional<bool> UpdateAppKitDevtools(DevtoolsUIController& controller,
                                         content::WebContents* contents,
                                         bool update_contents) {
  auto found = DevtoolsHosts().find(&controller);
  if (found == DevtoolsHosts().end()) {
    return std::nullopt;
  }
  return found->second &&
         found->second->UpdateDevtools(contents, update_contents);
}
bool SetAppKitDevtoolsScrim(DevtoolsUIController& controller,
                            content::WebContents* tools,
                            bool visible) {
  auto found = DevtoolsHosts().find(&controller);
  if (found == DevtoolsHosts().end()) {
    return false;
  }
  if (found->second) {
    found->second->SetDevtoolsScrim(tools, visible);
  }
  return true;
}
void TearDownAppKitDevtools(DevtoolsUIController& controller) {
  auto found = DevtoolsHosts().find(&controller);
  if (found == DevtoolsHosts().end()) {
    return;
  }
  auto host = std::move(found->second);
  DevtoolsHosts().erase(found);
  if (host) {
    host->DetachDevtools();
  }
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
bool RotateAppKitPaneFocus(ui::BaseWindow* window, bool forward) {
  for (const auto& [browser, host] : Hosts()) {
    if (host && browser->GetWindow() == window) {
      host->RotateFocus(forward);
      return true;
    }
  }
  return false;
}
void AppKitPageOwnerChanged(BrowserWindowInterface* browser,
                            content::WebContents& contents) {
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
bool ParkAppKitPage(BrowserWindowInterface& browser, PCNativePage* page) {
  auto found = Hosts().find(&browser);
  auto* contents = ContentsForNativePage(page);
  return contents && found != Hosts().end() && found->second &&
         found->second->ParkPage(*contents);
}
void ReportAppKitPageFrame(BrowserWindowInterface& browser,
                           PCNativePage* page) {
  auto found = Hosts().find(&browser);
  auto* contents = ContentsForNativePage(page);
  if (contents && found != Hosts().end() && found->second) {
    found->second->ReportNextFrame(*contents);
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
void AutoPictureInPictureEligibilityChanged(content::WebContents& contents) {
  auto* browser =
      GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(&contents);
  auto found = Hosts().find(browser);
  if (found != Hosts().end() && found->second) {
    found->second->PictureInPictureEligibilityChanged();
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

}

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
  return [self showExtensionActionContextMenu:action
                                      forPage:page
                                    presenter:nil];
}
- (BOOL)showExtensionActionContextMenu:(PCNativeExtensionAction*)action
                               forPage:(PCNativePage*)page
                             presenter:
                                 (nullable id<PCNativeMenuPresenter>)presenter {
  CHECK(NSThread.isMainThread);
  auto* bridge = parc::ActionBridgeForPage(self, page);
  auto* contents = parc::ContentsForNativePage(page);
  return bridge && contents &&
         [action.pageIdentifier isEqualToString:page.identifier] &&
         [action.profilePath isEqualToString:page.profilePath] &&
         bridge->ShowContextMenu(action, *contents, presenter);
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
}
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
  token->consumed = true;
  fullscreen->ExitFullscreenModeForTab(token->contents.get());
  return YES;
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
