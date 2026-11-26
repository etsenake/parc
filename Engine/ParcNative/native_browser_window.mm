// Copyright 2026 Parc contributors.
#include "native_browser_window.h"
#include "native_shortcuts.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <optional>
#include <type_traits>
#include <utility>
#include <vector>

#include "base/auto_reset.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/observer_list.h"
#include "base/task/bind_post_task.h"
#include "base/task/single_thread_task_runner.h"
#include "browser_window.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_init_state.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/desktop_browser_window_capabilities.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "extension_install.h"
#include "extension_keybinding_registry.h"
#include "extension_uninstall.h"
#include "location_bar.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/color/color_provider_manager.h"
#include "ui/color/color_provider_utils.h"
#include "ui/color/parc_color_changes.h"
#include "ui/gfx/geometry/size_conversions.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/native_theme/native_theme.h"

namespace {
void RequireUIThread() {
  CHECK(NSThread.isMainThread);
}
using NativeEventCallback =
    base::RepeatingCallback<void(PCNativeWindowEvent, gfx::NativeWindow)>;
}

@interface PCBrowserWindowEventSink
    : NSObject <PCNativeWindowAssociationObserver>
- (instancetype)initWithCallback:(NativeEventCallback)callback;
- (void)invalidate;
@end
@implementation PCBrowserWindowEventSink {
  NativeEventCallback _callback;
}
- (instancetype)initWithCallback:(NativeEventCallback)callback {
  self = [super init];
  if (self) {
    _callback = std::move(callback);
  }
  return self;
}
- (void)invalidate {
  _callback.Reset();
}
- (void)nativeWindowAssociation:(PCNativeWindowAssociation*)association
                didReceiveEvent:(PCNativeWindowEvent)event
                         window:(NSWindow*)window {
  NativeEventCallback callback = _callback;
  if (callback) {
    callback.Run(event, gfx::NativeWindow(window));
  }
}
@end

namespace parc {

static_assert(!std::is_abstract_v<NativeBrowserWindow>,
              "Implement every required BrowserWindow and color-source method");

class NativeBrowserWindow::Impl final
    : public NativeModalDialogHostDelegate {
 public:
  class ExclusiveContext final : public ExclusiveAccessContext {
   public:
    explicit ExclusiveContext(Impl& impl) : impl_(impl) {}
    Profile* GetProfile() override { return impl_.browser_->GetProfile(); }
    bool IsFullscreen() const override { return fullscreen_; }
    void UpdateUIForTabFullscreen() override {
      impl_.host_->UpdateUIForTabFullscreen();
    }
    void EnterFullscreen(const url::Origin&,
                         ExclusiveAccessBubbleType,
                         FullscreenTabParams params) override {
      fullscreen_ = true;
      impl_.RequestFullscreen(true, params);
    }
    void ExitFullscreen() override {
      fullscreen_ = false;
      impl_.RequestFullscreen(false, {});
    }
    void UpdateExclusiveAccessBubble(
        const ExclusiveAccessBubbleParams&,
        ExclusiveAccessBubbleHideCallback callback) override {
      if (callback) {
        std::move(callback).Run(ExclusiveAccessBubbleHideReason::kNotShown);
      }
    }
    bool IsExclusiveAccessBubbleDisplayed() const override { return false; }
    void OnExclusiveAccessUserInput() override {}
    content::WebContents* GetWebContentsForExclusiveAccess() override {
      return impl_.ActiveContents();
    }
    bool CanUserEnterFullscreen() const override {
      return impl_.selected_ && impl_.host_->CanUserEnterFullscreen();
    }
    bool CanUserExitFullscreen() const override {
      return impl_.host_->CanUserExitFullscreen();
    }
    void SetNativeState(bool value) { fullscreen_ = value; }

   private:
    Impl& impl_;
    bool fullscreen_ = false;
  };

  Impl(NativeBrowserWindow& owner,
       BrowserWindowInterface& browser,
       std::unique_ptr<NativeBrowserWindowHost> host)
      : owner_(owner),
        browser_(&browser),
        host_(std::move(host)),
        modal_(*this),
        exclusive_(*this) {
    RequireUIThread();
    CHECK(host_);
    sink_ = [[PCBrowserWindowEventSink alloc]
        initWithCallback:base::BindRepeating(&Impl::OnNativeEvent,
                                             weak_factory_.GetWeakPtr())];
    association_ = [[PCNativeWindowAssociation alloc] initWithObserver:sink_];
    location_bar_ = std::make_unique<NativeLocationBar>(browser);
    extension_registry_ = std::make_unique<NativeExtensionKeybindingRegistry>(
        browser,
        base::BindRepeating(
            [](base::WeakPtr<Impl> self, const ui::Accelerator& accelerator) {
              return self && self->DispatchExtensionAction(accelerator);
            },
            weak_factory_.GetWeakPtr()));
    extension_install_ = std::make_unique<NativeExtensionInstallService>(
        browser, host_->GetExtensionActionHost());
    extension_uninstall_ = std::make_unique<NativeExtensionUninstallService>(
        browser, host_->GetExtensionActionHost());
    closed_subscription_ = browser.RegisterBrowserDidClose(base::BindRepeating(
        &Impl::OnBrowserClosed, weak_factory_.GetWeakPtr()));
    cancelled_subscription_ =
        browser.RegisterBrowserCloseCancelled(base::BindRepeating(
            &Impl::OnBrowserCloseCancelled, weak_factory_.GetWeakPtr()));
    auto& manager = ui::ColorProviderManager::Get();
    auto& colors = ColorObservers();
    if (!colors.windows) {
      colors.manager = &manager;
      colors.windows.emplace();
      parc_hooks::SetColorChangeNotifier(&Impl::ColorChanged);
    }
    colors.windows->AddObserver(this);
    Registry().push_back(weak_factory_.GetWeakPtr());
  }

  ~Impl() override {
    RequireUIThread();
    CHECK(teardown_finished_);
  }

  static std::vector<base::WeakPtr<Impl>>& Registry() {
    static base::NoDestructor<std::vector<base::WeakPtr<Impl>>> windows;
    return *windows;
  }

  content::WebContents* ActiveContents() const {
    return browser_ ? browser_->GetTabStripModel()->GetActiveWebContents()
                    : nullptr;
  }

  gfx::NativeView GetActivePageHostView() const override {
    RequireUIThread();
    content::WebContents* contents = ActiveContents();
    NSView* page = contents ? contents->GetNativeView().GetNativeNSView() : nil;
    return gfx::NativeView(page.superview);
  }
  gfx::Size GetBrowserWindowSize() const override {
    return owner_.GetBounds().size();
  }
  gfx::Size GetContentsSize() const override {
    return owner_.GetContentsSize();
  }

  void SetSelected(bool selected) {
    RequireUIThread();
    if (tearing_down_ ||
        (selected && (!association_.window || browser_->IsDeleteScheduled()))) {
      return;
    }
    if (selected) {
      for (const auto& peer : Registry()) {
        if (peer && peer.get() != this &&
            peer->association_.window == association_.window) {
          peer->selected_ = false;
          peer->activation_pending_ = true;
        }
      }
    }
    selected_ = selected;
    activation_pending_ = true;
    DrainActivationChanges();
  }

  static void DrainActivationChanges() {
    RequireUIThread();
    const auto activation_peers = Registry();
    for (const auto& peer : activation_peers) {
      if (peer && peer->extension_registry_) {
        peer->extension_registry_->OnHostActivationChanged(
            !peer->tearing_down_ && peer->selected_ &&
            peer->association_.window.isKeyWindow);
      }
    }
    static bool draining = false;
    if (draining) {
      return;
    }
    base::AutoReset<bool> guard(&draining, true);
    bool had_work;
    do {
      had_work = false;
      const auto peers = Registry();
      for (const auto& peer : peers) {
        if (!peer || peer->tearing_down_ || !peer->activation_pending_) {
          continue;
        }
        had_work = true;
        peer->activation_pending_ = false;
        peer->UpdateActivation();
        if (!peer || peer->tearing_down_ || peer->activation_pending_) {
          continue;
        }
        if (peer->notified_selected_ != peer->selected_) {
          peer->notified_selected_ = peer->selected_;
          peer->host_->DidChangeSelectedBrowser(peer->selected_);
          if (peer && !peer->tearing_down_ && peer->extension_install_) {
            peer->extension_install_->HostStateChanged();
          }
          if (peer && !peer->tearing_down_ && peer->extension_uninstall_) {
            peer->extension_uninstall_->HostStateChanged();
          }
        }
      }
    } while (had_work);
  }

  void UpdateActivation() {
    if (!browser_) {
      return;
    }
    auto* manager = BrowserActiveStateManager::From(browser_);
    CHECK(manager);
    if (selected_ && association_.window.isKeyWindow) {
      manager->DidBecomeActive();
    } else {
      manager->DidBecomeInactive();
    }
  }

  bool DispatchExtensionAction(const ui::Accelerator& accelerator) {
    RequireUIThread();
    if (tearing_down_ || !selected_ || !association_.window.isKeyWindow) {
      return false;
    }
    return host_->DispatchExtensionActionAccelerator(accelerator);
  }

  void OnNativeEvent(PCNativeWindowEvent event, gfx::NativeWindow window) {
    RequireUIThread();
    if (tearing_down_) {
      return;
    }
    const auto self = weak_factory_.GetWeakPtr();
    switch (event) {
      case PCNativeWindowEventWillClose:
        ClearPendingWindowState();
        SetSelected(false);
        if (!self || tearing_down_) {
          return;
        }
        modal_.NotifyPositionRequiresUpdate();
        if (!self || tearing_down_) {
          return;
        }
        host_->DidDetachWindow(window);
        return;
      case PCNativeWindowEventDidBecomeKey:
      case PCNativeWindowEventDidResignKey:
        activation_pending_ = true;
        DrainActivationChanges();
        return;
      case PCNativeWindowEventWillEnterFullScreen:
      case PCNativeWindowEventWillExitFullScreen:
        return;
      case PCNativeWindowEventDidEnterFullScreen:
      case PCNativeWindowEventDidExitFullScreen:
      case PCNativeWindowEventFullscreenDidSettle:
        exclusive_.SetNativeState(
            event == PCNativeWindowEventFullscreenDidSettle
                ? (window.GetNativeNSWindow().styleMask &
                   NSWindowStyleMaskFullScreen) != 0
                : event == PCNativeWindowEventDidEnterFullScreen);
        NotifyFullscreenStateChanged();
        if (!self || tearing_down_) {
          return;
        }
        modal_.NotifyPositionRequiresUpdate();
        if (self && !tearing_down_) {
          base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
              FROM_HERE, base::BindOnce(&Impl::DrainPendingWindowState, self));
        }
        return;
    }
  }

  bool CanChangeWindowState() const {
    return !tearing_down_ && browser_ && !browser_->IsDeleteScheduled() &&
           association_.window && !DesktopBrowserWindowCapabilities::IsDocumentPictureInPicture(browser_);
  }

  void ClearPendingWindowState() {
    pending_show_state_.reset();
    pending_bounds_.reset();
    state_window_ = nil;
    state_generation_ = 0;
  }

  void ChangeWindowState(std::optional<ui::mojom::WindowShowState> state,
                         std::optional<gfx::Rect> bounds = std::nullopt) {
    RequireUIThread();
    if (!CanChangeWindowState()) {
      return;
    }
    NSWindow* const window = association_.window;
    if (state_window_ != window ||
        state_generation_ != association_.stateRequestGeneration) {
      ClearPendingWindowState();
    }
    state_window_ = window;
    state_generation_ = [association_ beginStateRequest];
    if (state) {
      pending_show_state_ = state;
    }
    if (bounds) {
      pending_bounds_ = bounds;
    }
    DrainPendingWindowState();
  }

  void DrainPendingWindowState() {
    RequireUIThread();
    if (!state_generation_) {
      return;
    }
    if (!CanChangeWindowState() || state_window_ != association_.window ||
        state_generation_ != association_.stateRequestGeneration) {
      ClearPendingWindowState();
      return;
    }
    if (association_.fullscreenTransitioning) {
      return;
    }
    if (owner_.IsFullscreen()) {
      if (pending_show_state_) {
        ExclusiveAccessManager::From(browser_)->fullscreen_controller()
            ->ToggleBrowserFullscreenMode(false);
      }
      return;
    }
    const auto self = weak_factory_.GetWeakPtr();
    NSWindow* const window = association_.window;
    const NSUInteger generation = state_generation_;
    const auto state = pending_show_state_;
    const auto bounds = pending_bounds_;
    ClearPendingWindowState();
    const auto current = [&] {
      return self && self->CanChangeWindowState() &&
             self->association_.window == window &&
             self->association_.stateRequestGeneration == generation;
    };
    if (state == ui::mojom::WindowShowState::kMinimized) {
      if (!window.isMiniaturized) {
        [window miniaturize:nil];
      }
    } else if (state == ui::mojom::WindowShowState::kMaximized ||
               state == ui::mojom::WindowShowState::kNormal) {
      if (window.isMiniaturized) {
        [window deminiaturize:nil];
        if (!current()) {
          return;
        }
      }
      const bool maximize = state == ui::mojom::WindowShowState::kMaximized;
      if (window.isZoomed != maximize) {
        [window performZoom:nil];
      }
    }
    if (!current()) {
      return;
    }
    if (bounds) {
      host_->SetWindowBounds(gfx::NativeWindow(window), *bounds);
      if (!current()) {
        return;
      }
    }
    modal_.NotifyPositionRequiresUpdate();
  }

  void RequestFullscreen(bool enter, FullscreenTabParams params) {
    RequireUIThread();
    const uint64_t request = ++fullscreen_request_;
    host_->RequestFullscreen(enter, params,
                             base::BindPostTaskToCurrentDefault(base::BindOnce(
                                 &Impl::OnFullscreenRequestResult,
                                 weak_factory_.GetWeakPtr(), request)));
  }

  void OnFullscreenRequestResult(
      uint64_t request,
      NativeBrowserWindowHost::FullscreenRequestResult result) {
    RequireUIThread();
    if (tearing_down_ || request != fullscreen_request_) {
      return;
    }
    if (result == NativeBrowserWindowHost::FullscreenRequestResult::kRejected) {
      ClearPendingWindowState();
      exclusive_.SetNativeState(owner_.IsFullscreen());
      NotifyFullscreenStateChanged();
    }
  }

  void NotifyFullscreenStateChanged() {
    RequireUIThread();
    auto* manager = ExclusiveAccessManager::From(browser_);
    CHECK(manager);
    manager->fullscreen_controller()->WindowFullscreenStateChanged();
  }

  void OnBrowserClosed(BrowserWindowInterface* browser) {
    RequireUIThread();
    CHECK_EQ(browser_.get(), browser);
    const auto self = weak_factory_.GetWeakPtr();
    SetSelected(false);
    if (!self || tearing_down_) {
      return;
    }
    host_->BrowserCloseApproved();
  }
  void OnBrowserCloseCancelled(BrowserWindowInterface* browser,
                               BrowserWindowInterface::ClosingStatus status) {
    RequireUIThread();
    CHECK_EQ(browser_.get(), browser);
    host_->BrowserCloseCancelled(status);
  }

  struct ColorSubscriptions {
    raw_ptr<ui::ColorProviderManager> manager = nullptr;
    std::optional<base::ObserverList<Impl>::UncheckedAndDanglingUntriaged> windows;
  };

  static ColorSubscriptions& ColorObservers() {
    static base::NoDestructor<ColorSubscriptions> subscriptions;
    return *subscriptions;
  }

  static void ColorChanged(ui::ColorProviderManager& manager,
                           parc_hooks::ColorChange change) {
    auto& colors = ColorObservers();
    if (colors.manager != &manager)
      return;
    if (change == parc_hooks::ColorChange::kRetire) {
      colors.manager = nullptr;
      colors.windows.reset();
      return;
    }
    for (Impl& window : *colors.windows)
      window.QueueColorChange();
  }

  void QueueColorChange() {
    RequireUIThread();
    if (tearing_down_ || color_change_pending_) {
      return;
    }
    color_change_pending_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&Impl::DeliverColorChange, weak_factory_.GetWeakPtr()));
  }
  void DeliverColorChange() {
    RequireUIThread();
    color_change_pending_ = false;
    if (!tearing_down_) {
      owner_.NotifyColorProviderChanged();
    }
  }

  void TearDown() {
    RequireUIThread();
    CHECK(!tearing_down_);
    tearing_down_ = true;
    selected_ = false;
    activation_pending_ = false;
    extension_registry_->SetShortcutHandlingSuspended(true);
    extension_registry_->OnHostActivationChanged(false);
    extension_registry_.reset();
    extension_install_->Shutdown();
    extension_install_.reset();
    extension_uninstall_->Shutdown();
    extension_uninstall_.reset();
    UpdateActivation();
    if (notified_selected_) {
      notified_selected_ = false;
      host_->DidChangeSelectedBrowser(false);
    }
    host_->BeginTeardown();
    browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
    weak_factory_.InvalidateWeakPtrs();
    std::erase_if(Registry(), [](const auto& value) { return !value; });
    auto& manager = ui::ColorProviderManager::Get();
    auto& colors = ColorObservers();
    if (colors.manager == &manager)
      colors.windows->RemoveObserver(this);
    closed_subscription_ = {};
    cancelled_subscription_ = {};
    modal_.Invalidate();
    [sink_ invalidate];
    [association_ invalidate];
    location_bar_.reset();
    host_.reset();
    browser_ = nullptr;
    teardown_finished_ = true;
  }

  NativeBrowserWindow& owner_;
  raw_ptr<BrowserWindowInterface> browser_;
  std::unique_ptr<NativeBrowserWindowHost> host_;
  PCBrowserWindowEventSink* __strong sink_;
  PCNativeWindowAssociation* __strong association_;
  NativeModalDialogHost modal_;
  ExclusiveContext exclusive_;
  std::unique_ptr<NativeLocationBar> location_bar_;
  std::unique_ptr<NativeExtensionKeybindingRegistry> extension_registry_;
  std::unique_ptr<NativeExtensionInstallService> extension_install_;
  std::unique_ptr<NativeExtensionUninstallService> extension_uninstall_;
  base::CallbackListSubscription closed_subscription_;
  base::CallbackListSubscription cancelled_subscription_;
  NSWindow* __weak state_window_ = nil;
  NSUInteger state_generation_ = 0;
  std::optional<ui::mojom::WindowShowState> pending_show_state_;
  std::optional<gfx::Rect> pending_bounds_;
  bool has_been_shown_ = false;
  bool selected_ = false;
  bool notified_selected_ = false;
  bool activation_pending_ = false;
  bool tab_strip_editable_ = true;
  bool tearing_down_ = false;
  bool teardown_finished_ = false;
  bool color_change_pending_ = false;
  uint64_t fullscreen_request_ = 0;
  base::WeakPtrFactory<Impl> weak_factory_{this};
};

std::optional<std::string> PrepareNativeWindowStateUpdate(
    BrowserWindowInterface& browser,
    ui::mojom::WindowShowState state,
    const gfx::Rect* bounds) {
  RequireUIThread();
  if (DesktopBrowserWindowCapabilities::IsDocumentPictureInPicture(&browser)) {
    return std::nullopt;
  }
  for (const auto& entry : NativeBrowserWindow::Impl::Registry()) {
    if (!entry || entry->browser_ != &browser) {
      continue;
    }
    if (!entry->CanChangeWindowState()) {
      return "The native browser window is closing.";
    }
    NSWindow* const window = entry->association_.window;
    const auto* initial = BrowserInitState::From(&browser);
    if (bounds && initial && !initial->create_params().can_resize &&
        bounds->size() != entry->owner_.GetRestoredBounds().size()) {
      return "This native browser window cannot be resized.";
    }
    if (state == ui::mojom::WindowShowState::kMaximized &&
        (initial && !initial->create_params().can_maximize)) {
      return "This native browser window cannot be maximized.";
    }
    if (state == ui::mojom::WindowShowState::kMaximized &&
        (!(window.styleMask & NSWindowStyleMaskResizable) ||
         ![window standardWindowButton:NSWindowZoomButton].enabled)) {
      return "This native browser window cannot be maximized.";
    }
    const bool entering_fullscreen =
        state == ui::mojom::WindowShowState::kFullscreen &&
        !entry->owner_.IsFullscreen();
    if (entering_fullscreen &&
        ((initial && !initial->create_params().can_fullscreen) ||
         !entry->host_->CanUserEnterFullscreen())) {
      return "This native browser window cannot enter fullscreen.";
    }
    if (entry->owner_.IsFullscreen() &&
        state != ui::mojom::WindowShowState::kDefault &&
        state != ui::mojom::WindowShowState::kFullscreen &&
        (!entry->host_->CanUserExitFullscreen() || window.attachedSheet)) {
      return "This native browser window cannot leave fullscreen.";
    }
    if (state != ui::mojom::WindowShowState::kDefault || bounds) {
      entry->ClearPendingWindowState();
      [entry->association_ beginStateRequest];
    }
    return std::nullopt;
  }
  return std::nullopt;
}

NativeBrowserWindow::NativeBrowserWindow(
    BrowserWindowInterface& browser,
    std::unique_ptr<NativeBrowserWindowHost> host)
    : impl_(std::make_unique<Impl>(*this, browser, std::move(host))) {}

NativeBrowserWindow::~NativeBrowserWindow() = default;

bool NativeBrowserWindow::AttachToNativeWindow(gfx::NativeWindow window) {
  RequireUIThread();
  if (impl_->tearing_down_ || !window.GetNativeNSWindow()) {
    return false;
  }
  bool registered = false;
  ProfileBrowserCollection::GetForProfile(impl_->browser_->GetProfile())
      ->ForEach([&](BrowserWindowInterface* b) {
        registered = b == impl_->browser_;
        return !registered;
      });
  CHECK(registered) << "Attach after BrowserManager registration";
  NSWindow* previous = impl_->association_.window;
  if (![impl_->association_ attachToWindow:window.GetNativeNSWindow()]) {
    return false;
  }
  if (!previous) {
    impl_->exclusive_.SetNativeState(IsFullscreen());
    const auto impl = impl_->weak_factory_.GetWeakPtr();
    impl_->host_->DidAttachWindow(window);
    if (!impl || impl->tearing_down_) {
      return false;
    }
    impl_->modal_.NotifyPositionRequiresUpdate();
  }
  return true;
}

void NativeBrowserWindow::SetSelectedForNativeWindow(bool selected) {
  impl_->SetSelected(selected);
}
void NativeBrowserWindow::NotifyActiveHostGeometryChanged() {
  RequireUIThread();
  if (!impl_->tearing_down_) {
    impl_->modal_.NotifyPositionRequiresUpdate();
  }
}

bool NativeBrowserWindow::IsActive() const {
  RequireUIThread();
  return impl_->selected_ && impl_->association_.window.isKeyWindow;
}
bool NativeBrowserWindow::IsMinimized() const {
  RequireUIThread();
  return impl_->association_.window.isMiniaturized;
}
bool NativeBrowserWindow::IsFullscreen() const {
  RequireUIThread();
  return (impl_->association_.window.styleMask & NSWindowStyleMaskFullScreen) !=
         0;
}
gfx::NativeWindow NativeBrowserWindow::GetNativeWindow() const {
  RequireUIThread();
  return gfx::NativeWindow(impl_->association_.window);
}
gfx::Rect NativeBrowserWindow::GetBounds() const {
  RequireUIThread();
  return impl_->association_.window
             ? impl_->host_->GetWindowBounds(GetNativeWindow())
             : gfx::Rect();
}
void NativeBrowserWindow::SetBounds(const gfx::Rect& bounds) {
  RequireUIThread();
  if (!impl_->tearing_down_ && impl_->browser_ && !bounds.IsEmpty()) {
    if (DesktopBrowserWindowCapabilities::IsDocumentPictureInPicture(impl_->browser_)) {
      if (impl_->association_.window) {
        impl_->host_->SetWindowBounds(GetNativeWindow(), bounds);
      }
      return;
    }
    impl_->ChangeWindowState(std::nullopt, bounds);
  }
}
void NativeBrowserWindow::Show() {
  RequireUIThread();
  const auto impl = impl_->weak_factory_.GetWeakPtr();
  SetSelectedForNativeWindow(true);
  if (!impl || impl->tearing_down_ || !impl->selected_) {
    return;
  }
  NSWindow* const window = impl->association_.window;
  const bool initial = !std::exchange(impl->has_been_shown_, true);
  if (initial && !DesktopBrowserWindowCapabilities::IsDocumentPictureInPicture(impl->browser_)) {
    const auto* state = BrowserInitState::From(impl->browser_);
    const auto show_state = state ? state->initial_show_state()
                                 : ui::mojom::WindowShowState::kDefault;
    const auto current = [&] {
      return impl && !impl->tearing_down_ && impl->selected_ &&
             impl->association_.window == window;
    };
    if (show_state == ui::mojom::WindowShowState::kInactive) {
      [window orderFront:nil];
      return;
    }
    if (show_state == ui::mojom::WindowShowState::kMinimized) {
      [window orderFront:nil];
      if (current()) {
        [window miniaturize:nil];
      }
      return;
    }
    if (show_state == ui::mojom::WindowShowState::kMaximized &&
        state->create_params().can_maximize && !window.isZoomed) {
      [window zoom:nil];
      if (!current()) {
        return;
      }
    }
    if (show_state == ui::mojom::WindowShowState::kFullscreen &&
        state->create_params().can_fullscreen &&
        !(window.styleMask & NSWindowStyleMaskFullScreen)) {
      [window makeKeyAndOrderFront:nil];
      if (current()) {
        [window toggleFullScreen:nil];
      }
      return;
    }
  }
  [window makeKeyAndOrderFront:nil];
}
bool NativeBrowserWindow::IsVisible() const {
  RequireUIThread();
  return impl_->association_.window.isVisible;
}
void NativeBrowserWindow::Close() {
  RequireUIThread();
  if (!impl_->tearing_down_ && !impl_->browser_->IsDeleteScheduled()) {
    UnloadController::From(impl_->browser_)->OnWindowClosing();
  }
}
void NativeBrowserWindow::Activate() {
  RequireUIThread();
  const auto impl = impl_->weak_factory_.GetWeakPtr();
  NSWindow* const window = impl->association_.window;
  const auto current = [&] {
    return impl && !impl->tearing_down_ && impl->selected_ && window &&
           impl->association_.window == window && impl->browser_ &&
           !impl->browser_->IsDeleteScheduled();
  };
  SetSelectedForNativeWindow(true);
  if (!current()) {
    return;
  }
  [NSApp activateIgnoringOtherApps:YES];
  if (!current()) {
    return;
  }
  if (window.isMiniaturized) {
    [window deminiaturize:nil];
    if (!current()) {
      return;
    }
  }
  [window makeKeyAndOrderFront:nil];
}
void NativeBrowserWindow::Deactivate() {
  SetSelectedForNativeWindow(false);
}
void NativeBrowserWindow::FlashFrame(bool flash) {
  RequireUIThread();
  if (impl_->association_.window) {
    impl_->host_->FlashWindow(GetNativeWindow(), flash);
  }
}

ui::NativeTheme* NativeBrowserWindow::GetNativeTheme() {
  RequireUIThread();
  return impl_->browser_ ? ui::NativeTheme::GetInstanceForNativeUi() : nullptr;
}
const ui::ThemeProvider* NativeBrowserWindow::GetThemeProvider() const {
  RequireUIThread();
  return impl_->browser_ ? &ThemeService::GetThemeProviderForProfile(
                               impl_->browser_->GetProfile())
                         : nullptr;
}
ui::ColorProviderKey NativeBrowserWindow::GetColorProviderKey() const {
  RequireUIThread();
  return ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(nullptr,
                                                                        true);
}
const ui::ColorProvider* NativeBrowserWindow::GetColorProvider() const {
  RequireUIThread();
  return impl_->browser_ ? ui::ColorProviderManager::Get().GetColorProviderFor(
                               GetColorProviderKey())
                         : nullptr;
}
ui::RendererColorMap NativeBrowserWindow::GetRendererColorMap(
    ui::ColorProviderKey::ColorMode mode,
    ui::ColorProviderKey::ForcedColors forced) const {
  auto key = GetColorProviderKey();
  key.color_mode = mode;
  key.forced_colors = forced;
  return ui::CreateRendererColorMap(
      *ui::ColorProviderManager::Get().GetColorProviderFor(key));
}
gfx::Size NativeBrowserWindow::GetContentsSize() const {
  RequireUIThread();
  content::WebContents* contents = impl_->ActiveContents();
  NSView* page = contents ? contents->GetNativeView().GetNativeNSView() : nil;
  if (page && page.bounds.size.width > 0 && page.bounds.size.height > 0) {
    return gfx::ToFlooredSize(
        gfx::SizeF(page.bounds.size.width, page.bounds.size.height));
  }
  return GetBounds().size();
}
void NativeBrowserWindow::OnActiveTabChanged(content::WebContents* old_contents,
                                             content::WebContents* new_contents,
                                             int index,
                                             int reason) {
  NotifyActiveHostGeometryChanged();
}
void NativeBrowserWindow::OnTabDetached(content::WebContents* contents,
                                        bool was_active) {
  NotifyActiveHostGeometryChanged();
}
LocationBar* NativeBrowserWindow::GetLocationBar() const {
  return impl_->location_bar_.get();
}
ExclusiveAccessContext* NativeBrowserWindow::GetExclusiveAccessContext() {
  return &impl_->exclusive_;
}
web_modal::WebContentsModalDialogHost*
NativeBrowserWindow::GetWebContentsModalDialogHost() {
  return &impl_->modal_;
}
web_modal::WebContentsModalDialogHost*
NativeBrowserWindow::GetWebContentsModalDialogHostFor(
    content::WebContents* contents) {
  return &impl_->modal_;
}
autofill::AutofillBubbleHandler*
NativeBrowserWindow::GetAutofillBubbleHandler() {
  return &impl_->host_->GetAutofillBubbleHandler();
}
ui::AcceleratorProvider* NativeBrowserWindow::GetAcceleratorProvider() {
  return &impl_->host_->GetAcceleratorProvider();
}
std::vector<StatusBubble*> NativeBrowserWindow::GetStatusBubbles() {
  return {};
}
std::unique_ptr<FindBar> NativeBrowserWindow::CreateFindBar() {
  auto find = impl_->host_->CreateFindBar();
  CHECK(find);
  return find;
}
content::KeyboardEventProcessingResult
NativeBrowserWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  RequireUIThread();
  if (impl_->tearing_down_ || !impl_->browser_ || !IsActive())
    return content::KeyboardEventProcessingResult::NOT_HANDLED;
  return PreHandleNativeShortcut(*impl_->browser_, event);
}
bool NativeBrowserWindow::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  RequireUIThread();
  if (impl_->tearing_down_ || !IsActive() || !impl_->extension_registry_) {
    return false;
  }
  return impl_->extension_registry_->DispatchKeyboardEvent(event);
}
bool NativeBrowserWindow::IsTabStripEditable() const {
  return impl_->tab_strip_editable_;
}
void NativeBrowserWindow::DisableTabStripEditingForTesting() {
  impl_->tab_strip_editable_ = false;
}
bool NativeBrowserWindow::IsToolbarVisible() const {
  return impl_->host_->IsToolbarAvailable();
}
PinnedToolbarActions* NativeBrowserWindow::GetPinnedToolbarActions() {
  return nullptr;
}

void NativeBrowserWindow::ShowIntentPickerBubble(
    std::vector<apps::IntentPickerAppInfo> apps,
    bool stay,
    bool remember,
    apps::IntentPickerBubbleType type,
    const std::optional<url::Origin>& origin,
    IntentPickerResponse callback) {
  impl_->host_->ShowIntentPicker(std::move(apps), stay, remember, type, origin,
                                 std::move(callback));
}
void NativeBrowserWindow::ShowBookmarkBubble(const GURL& url,
                                             bool already_bookmarked) {
  impl_->host_->ShowBookmarkEditor(url, already_bookmarked);
}
ShowTranslateBubbleResult NativeBrowserWindow::ShowTranslateBubble(
    content::WebContents*,
    translate::TranslateStep,
    const std::string&,
    const std::string&,
    translate::TranslateErrors,
    bool) {
  return ShowTranslateBubbleResult::kBrowserWindowNotValid;
}
void NativeBrowserWindow::ConfirmBrowserCloseWithPendingDownloads(
    int count,
    DownloadCloseType type,
    base::OnceCallback<void(bool)> callback) {
  impl_->host_->ConfirmCloseWithDownloads(count, type, std::move(callback));
}
void NativeBrowserWindow::ShowAvatarBubbleFromAvatarButton(bool accelerator) {
  impl_->host_->ShowProfilePicker(accelerator);
}
std::unique_ptr<content::EyeDropper> NativeBrowserWindow::OpenEyeDropper(
    content::RenderFrameHost* frame,
    content::EyeDropperListener* listener) {
  return impl_->host_->OpenEyeDropper(frame, listener);
}
void NativeBrowserWindow::ShowCaretBrowsingDialog() {
  impl_->host_->ShowCaretBrowsingDialog();
}
void NativeBrowserWindow::CreateTabSearchBubble() {
  impl_->host_->ShowTabSearch();
}
void NativeBrowserWindow::CloseTabSearchBubble() {
  impl_->host_->CloseTabSearch();
}
void NativeBrowserWindow::ShowIncognitoClearBrowsingDataDialog() {
  impl_->host_->ShowIncognitoClearBrowsingDataDialog();
}
void NativeBrowserWindow::ShowIncognitoHistoryDisclaimerDialog() {
  impl_->host_->ShowIncognitoHistoryDisclaimerDialog();
}
void NativeBrowserWindow::HandleDragEnded() {
  impl_->host_->HandleDragEnded();
}
void NativeBrowserWindow::ShowEmojiPanel() {
  RequireUIThread();
  [NSApp orderFrontCharacterPalette:nil];
}
void NativeBrowserWindow::ShowHatsDialog(
    const std::string& site_id,
    const std::optional<std::string>& histogram,
    std::optional<uint64_t> ukm,
    base::OnceClosure success,
    base::OnceClosure failure,
    const SurveyBitsData& bits,
    const SurveyStringData& strings) {
  if (failure) {
    std::move(failure).Run();
  }
}

bool NativeBrowserWindow::IsMaximized() const {
  RequireUIThread();
  return impl_->browser_ && !DesktopBrowserWindowCapabilities::IsDocumentPictureInPicture(impl_->browser_) &&
         !IsFullscreen() && impl_->association_.window.isZoomed;
}
gfx::Rect NativeBrowserWindow::GetRestoredBounds() const {
  RequireUIThread();
  if (!impl_->browser_ || DesktopBrowserWindowCapabilities::IsDocumentPictureInPicture(impl_->browser_)) {
    return {};
  }
  return impl_->association_.window
             ? gfx::ScreenRectFromNSRect(impl_->association_.restoredFrame)
             : gfx::Rect();
}
ui::mojom::WindowShowState NativeBrowserWindow::GetRestoredState() const {
  if (!impl_->browser_ || DesktopBrowserWindowCapabilities::IsDocumentPictureInPicture(impl_->browser_)) {
    return ui::mojom::WindowShowState::kNormal;
  }
  return GetWindowShowState();
}
void NativeBrowserWindow::Hide() {
  RequireUIThread();
  if (impl_->CanChangeWindowState()) {
    impl_->ClearPendingWindowState();
    [impl_->association_ beginStateRequest];
    [impl_->association_.window orderOut:nil];
  }
}
void NativeBrowserWindow::ShowInactive() {
  RequireUIThread();
  if (DesktopBrowserWindowCapabilities::IsDocumentPictureInPicture(impl_->browser_)) {
    return;
  }
  const auto impl = impl_->weak_factory_.GetWeakPtr();
  SetSelectedForNativeWindow(true);
  if (!impl || impl->tearing_down_ || !impl->selected_) {
    return;
  }
  NSWindow* const window = impl->association_.window;
  const bool initial = !std::exchange(impl->has_been_shown_, true);
  const auto* state = BrowserInitState::From(impl->browser_);
  const auto show_state = initial && state ? state->initial_show_state()
                                          : ui::mojom::WindowShowState::kDefault;
  const auto current = [&] {
    return impl && !impl->tearing_down_ && impl->selected_ &&
           impl->association_.window == window;
  };
  if (show_state == ui::mojom::WindowShowState::kMaximized &&
      state->create_params().can_maximize && !window.isZoomed) {
    [window zoom:nil];
    if (!current()) {
      return;
    }
  }
  [window orderFront:nil];
  if (!current()) {
    return;
  }
  if (show_state == ui::mojom::WindowShowState::kMinimized) {
    [window miniaturize:nil];
  } else if (show_state == ui::mojom::WindowShowState::kFullscreen &&
             state->create_params().can_fullscreen &&
             !(window.styleMask & NSWindowStyleMaskFullScreen)) {
    [window toggleFullScreen:nil];
  }
}
void NativeBrowserWindow::Maximize() {
  impl_->ChangeWindowState(ui::mojom::WindowShowState::kMaximized);
}
void NativeBrowserWindow::Minimize() {
  impl_->ChangeWindowState(ui::mojom::WindowShowState::kMinimized);
}
void NativeBrowserWindow::Restore() {
  impl_->ChangeWindowState(ui::mojom::WindowShowState::kNormal);
}
ui::ZOrderLevel NativeBrowserWindow::GetZOrderLevel() const {
  return ui::ZOrderLevel::kNormal;
}
void NativeBrowserWindow::SetZOrderLevel(ui::ZOrderLevel order) {}
bool NativeBrowserWindow::IsOnCurrentWorkspace() const {
  return true;
}
bool NativeBrowserWindow::IsVisibleOnScreen() const {
  return true;
}
void NativeBrowserWindow::SetTopControlsShownRatio(
    content::WebContents* contents,
    float ratio) {}
bool NativeBrowserWindow::DoBrowserControlsShrinkRendererSize(
    const content::WebContents* contents) const {
  return false;
}
int NativeBrowserWindow::GetTopControlsHeight() const {
  return 0;
}
void NativeBrowserWindow::SetTopControlsGestureScrollInProgress(bool value) {
}
void NativeBrowserWindow::UpdateTitleBar() {}
void NativeBrowserWindow::UpdateLoadingAnimations(bool visible) {}
void NativeBrowserWindow::SetContentsSize(const gfx::Size& size) {
}
void NativeBrowserWindow::SetFocusToLocationBar(bool user_initiated) {
}
void NativeBrowserWindow::UpdateReloadStopState(bool loading, bool force) {
}
void NativeBrowserWindow::UpdateToolbar(content::WebContents* contents) {
}
bool NativeBrowserWindow::UpdateToolbarSecurityState() {
  return false;
}
void NativeBrowserWindow::UpdateCustomTabBarVisibility(bool visible,
                                                       bool animate) {
}
void NativeBrowserWindow::ResetToolbarTabState(content::WebContents* contents) {
}
void NativeBrowserWindow::FocusToolbar() {}
void NativeBrowserWindow::ToolbarSizeChanged(bool animating) {}
void NativeBrowserWindow::TabDraggingStatusChanged(bool dragging) {
}
void NativeBrowserWindow::LinkOpeningFromGesture(
    WindowOpenDisposition disposition) {}
void NativeBrowserWindow::FocusAppMenu() {}
bool NativeBrowserWindow::IsToolbarShowing() const {
  return false;
}
bool NativeBrowserWindow::IsLocationBarVisible() const {
  return false;
}
void NativeBrowserWindow::ShowUpdateChromeDialog() {
}
DownloadBubbleUIController*
NativeBrowserWindow::GetDownloadBubbleUIController() {
  return nullptr;
}
void NativeBrowserWindow::ShowAppMenu() {}
void NativeBrowserWindow::PreHandleDragUpdate(const content::DropData& data,
                                              const gfx::PointF& point) {
}
void NativeBrowserWindow::PreHandleDragExit() {}
std::string NativeBrowserWindow::GetWorkspace() const {
  return {};
}
bool NativeBrowserWindow::IsVisibleOnAllWorkspaces() const {
  return false;
}
bool NativeBrowserWindow::IsUnframedModeEnabled() const {
  return false;
}
bool NativeBrowserWindow::GetCanResize() {
  return false;
}
ui::mojom::WindowShowState NativeBrowserWindow::GetWindowShowState() const {
  RequireUIThread();
  if (!impl_->browser_ || DesktopBrowserWindowCapabilities::IsDocumentPictureInPicture(impl_->browser_)) {
    return ui::mojom::WindowShowState::kNormal;
  }
  if (IsFullscreen()) {
    return ui::mojom::WindowShowState::kFullscreen;
  }
  if (IsMinimized()) {
    return ui::mojom::WindowShowState::kMinimized;
  }
  if (IsMaximized()) {
    return ui::mojom::WindowShowState::kMaximized;
  }
  return ui::mojom::WindowShowState::kNormal;
}
void NativeBrowserWindow::ShowChromeLabs() {}
BrowserView* NativeBrowserWindow::AsBrowserView() {
  return nullptr;
}

void NativeBrowserWindow::DeleteBrowserWindow() {
  RequireUIThread();
  if (impl_->tearing_down_) {
    return;
  }
  impl_->TearDown();
  base::SingleThreadTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE,
                                                                this);
}

}
