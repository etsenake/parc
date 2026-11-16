// Copyright 2026 Parc contributors.
#include "constrained_dialog.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <utility>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "components/constrained_window/constrained_window_views.h"
#include "components/web_modal/single_web_contents_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/views/view.h"
#include "ui/views/widget/native_widget.h"
#include "ui/views/widget/native_widget_mac.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_delegate.h"
#include "ui/views/widget/widget_observer.h"
#include "ui/views/window/dialog_delegate.h"
#include "ui/views/window/frame_view.h"
#include "ui/views/window/non_client_view.h"
#import "window_security_reservation.h"

namespace parc {
namespace {

using ShowState = ui::mojom::WindowShowState;

class Presenter;

class PresentedWidget final : public views::NativeWidgetMac {
 public:
  PresentedWidget(views::Widget* widget, base::WeakPtr<Presenter> presenter)
      : NativeWidgetMac(widget), presenter_(std::move(presenter)) {}
  void InitModalType(ui::mojom::ModalType) override {}
  void Show(ShowState state, const gfx::Rect& restore) override;
  void Hide() override;
  void Activate() override;
  void ShowAttached(ShowState state, const gfx::Rect& restore) {
    NativeWidgetMac::Show(state, restore);
  }
  void HideAttached() { NativeWidgetMac::Hide(); }
  void ActivateAttached() { NativeWidgetMac::Activate(); }

 private:
  base::WeakPtr<Presenter> presenter_;
};

bool Usable(NSView* view, NSWindow* window) {
  return view && view.window == window && !view.hiddenOrHasHiddenAncestor &&
         NSWidth(view.bounds) > 0 && NSHeight(view.bounds) > 0;
}

bool WindowIsActive(NSWindow* window) {
  return window && NSApp.active && (window.keyWindow || window.mainWindow);
}

class Presenter final : public views::WidgetObserver,
                        public web_modal::ModalDialogHostObserver,
                        public std::enable_shared_from_this<Presenter> {
 public:
  Presenter(content::WebContents* contents, NSWindow* parent)
      : contents_(contents ? contents->GetWeakPtr() : nullptr),
        web_modal_(contents != nullptr),
        window_(parent),
        window_observers_([NSMutableArray array]) {}
  ~Presenter() override {
    ClearHost();
    RemoveObservers();
    [reservation_ invalidate];
  }

  base::WeakPtr<Presenter> GetWeakPtr() { return weak_factory_.GetWeakPtr(); }

  void Bind(views::Widget* widget, PresentedWidget* native) {
    widget_ = widget->GetWeakPtr();
    dialog_ = widget->GetNativeWindow();
    native_ = native;
    keep_alive_ = shared_from_this();
    widget->AddObserver(this);
    widget->set_movement_disabled(true);
    if (!web_modal_) {
      BindWindow(window_);
    }
    widget->SetNativeWindowProperty(
        views::kWidgetIdentifierKey,
        const_cast<void*>(
            constrained_window::kConstrainedWindowWidgetIdentifier));
    if (auto* delegate = widget->widget_delegate()) {
      delegate->set_desired_bounds_delegate(base::BindRepeating(
          [](base::WeakPtr<Presenter> self) {
            return self ? self->Bounds() : gfx::Rect();
          },
          GetWeakPtr()));
    }
  }

  void Register(web_modal::WebContentsModalDialogManager* manager) {
    auto keep = shared_from_this();
    manager_ = manager;
    registered_ = registering_ = true;
    manager->ShowDialogWithManager(dialog_, MakeModal());
    registering_ = false;
    if (!registered_) {
      CloseSoon();
    } else if (closing_) {
      RemoveModal();
    }
  }

  void BindBrowserHost(gfx::NativeWindow parent) {
    if (auto* browser =
            GlobalBrowserCollection::GetInstance()->FindBrowserWithWindow(
                parent)) {
      ChangeHost(browser->GetWebContentsModalDialogHostForWindow());
    }
  }

  void RequestShow(ShowState state, const gfx::Rect& restore) {
    auto keep = shared_from_this();
    if (Finished()) {
      return;
    }
    wanted_ = true;
    state_ = state;
    restore_ = restore;
    if (!attached_) {
      TryAttach();
      return;
    }
    if (state != ShowState::kInactive && native_) {
      native_->ShowAttached(state, restore);
    }
    Position();
  }

  void RequestHide() {
    auto keep = shared_from_this();
    wanted_ = false;
    Detach(true);
  }

  void RequestActivate() {
    auto keep = shared_from_this();
    if (Finished()) {
      return;
    }
    if (attached_ && native_) {
      native_->ActivateAttached();
      return;
    }
    wanted_ = true;
    state_ = ShowState::kNormal;
    TryAttach();
  }

  void ShowFromManager() {
    auto keep = shared_from_this();
    if (Finished() || !widget_) {
      return;
    }
    EnsureHost();
    if (host_ && host_->ShouldActivateDialog() && WindowIsActive(HostWindow())) {
      widget_->Show();
      FocusInitialView();
    } else {
      widget_->ShowInactive();
    }
  }

  void HideFromManager() {
    if (widget_) {
      widget_->Hide();
    }
  }

  void FocusFromManager() {
    auto keep = shared_from_this();
    if (!attached_ || !widget_) {
      return;
    }
    widget_->Activate();
    FocusInitialView();
  }

  void CloseFromManager() {
    auto keep = shared_from_this();
    if (widget_ && !widget_->IsClosed()) {
      widget_->Close();
    }
    if (registered_) {
      wanted_ = false;
      Detach(true);
      RemoveModal();
    }
  }

  void ChangeHost(web_modal::WebContentsModalDialogHost* host) {
    auto keep = shared_from_this();
    ClearHost();
    if (closing_ || !host || !host->GetHostView()) {
      if (web_modal_) {
        Detach(true);
        BindWindow(nil);
      }
      return;
    }
    host_ = host;
    host_->AddObserver(this);
    if (web_modal_ && HostWindow() != window_) {
      Detach(true);
      BindWindow(HostWindow());
    }
    if (attached_) {
      Position();
    } else {
      TryAttach();
    }
  }

  void ModalDestroyed() {
    registered_ = false;
    manager_ = nullptr;
  }

  gfx::NativeWindow dialog() const { return dialog_; }
  bool IsActive() const { return widget_ && widget_->IsActive(); }

  void OnPositionRequiresUpdate() override {
    auto keep = shared_from_this();
    if (attached_) {
      Position();
    } else {
      TryAttach();
    }
  }

  void OnHostDestroying() override {
    auto keep = shared_from_this();
    ClearHost();
    Detach(true);
    CloseSoon();
  }

  void OnWidgetClosing(views::Widget*) override {
    auto keep = shared_from_this();
    closing_ = true;
    EndPresentation();
  }

  void OnWidgetDestroying(views::Widget* widget) override {
    auto keep = shared_from_this();
    closing_ = true;
    EndPresentation();
    widget->RemoveObserver(this);
    widget_.reset();
    native_ = nullptr;
    RemoveObservers();
    keep_alive_.reset();
  }

 private:
  std::unique_ptr<web_modal::SingleWebContentsDialogManager> MakeModal();

  bool Finished() const { return closing_ || close_posted_; }

  NSWindow* HostWindow() const {
    if (!web_modal_) {
      return window_;
    }
    return host_ ? host_->GetHostView().GetNativeNSView().window : nil;
  }

  void EnsureHost() {
    if (!web_modal_ || host_ || !registered_ || !manager_ || !contents_ ||
        !manager_->delegate()) {
      return;
    }
    ChangeHost(manager_->delegate()->GetWebContentsModalDialogHost(
        contents_.get()));
  }

  NSView* Anchor(NSWindow* window) const {
    if (contents_ && !contents_->IsBeingDestroyed()) {
      NSView* page = contents_->GetNativeView().GetNativeNSView();
      if (Usable(page, window)) {
        return page;
      }
    }
    NSView* host = host_ ? host_->GetHostView().GetNativeNSView() : nil;
    if (Usable(host, window)) {
      return host;
    }
    return window.contentView;
  }

  gfx::Rect Bounds() const {
    NSWindow* window = window_;
    if (!attached_ || !widget_ || !window) {
      return gfx::Rect();
    }
    NSView* anchor = Anchor(window);
    if (!anchor) {
      return gfx::Rect();
    }
    gfx::Size size = widget_->GetRootView()->GetPreferredSize({});
    int inset = 0;
    if (auto* client = widget_->non_client_view();
        client && client->frame_view()) {
      inset = client->frame_view()->GetInsets().top();
    }
    if (web_modal_ && host_) {
      gfx::Size limit = host_->GetMaximumDialogSize();
      if (!limit.IsEmpty()) {
        limit.Enlarge(0, inset);
        size.SetToMin(limit);
      }
    }
    const NSRect area = [window
        convertRectToScreen:[anchor convertRect:anchor.bounds toView:nil]];
    NSRect frame =
        NSMakeRect(std::round(NSMidX(area) - size.width() / 2.0),
                   NSMaxY(area) + inset - size.height(), size.width(),
                   size.height());
    if (NSScreen* screen = window.screen) {
      const NSRect visible = screen.visibleFrame;
      frame.origin.x = std::clamp(
          frame.origin.x, NSMinX(visible),
          std::max(NSMinX(visible), NSMaxX(visible) - NSWidth(frame)));
      frame.origin.y = std::clamp(
          frame.origin.y, NSMinY(visible),
          std::max(NSMinY(visible), NSMaxY(visible) - NSHeight(frame)));
    }
    return gfx::ScreenRectFromNSRect(frame);
  }

  void Position() {
    if (!attached_ || !widget_ || widget_->HasCapture()) {
      return;
    }
    const gfx::Rect bounds = Bounds();
    if (!bounds.IsEmpty() && bounds != widget_->GetWindowBoundsInScreen()) {
      widget_->SetBounds(bounds);
    }
  }

  void TryAttach() {
    auto keep = shared_from_this();
    if (!wanted_ || attached_ || Finished() || !widget_ || !native_) {
      return;
    }
    EnsureHost();
    NSWindow* window = HostWindow();
    if (window != window_) {
      BindWindow(window);
    }
    if (!window || !window.visible || window.miniaturized ||
        window.attachedSheet || attached_ || !wanted_ || Finished()) {
      return;
    }
    if (!reservation_) {
      if (PCNativeWindowHasSecurityReservation(window)) {
        return;
      }
      acquiring_ = true;
      PCNativeWindowSecurityReservation* reservation =
          [PCNativeWindowSecurityReservation acquireForWindow:window];
      acquiring_ = false;
      reservation_ = reservation;
      if (!reservation_.isOnlyReservation || !wanted_ || attached_ ||
          Finished() || !widget_ || !native_ || window_ != window) {
        Release();
        return;
      }
    }
    __attribute__((objc_precise_lifetime)) NSWindow* child =
        dialog_.GetNativeNSWindow();
    const bool activate =
        state_ != ShowState::kInactive &&
        (!web_modal_ || WindowIsActive(window));
    attached_ = true;
    Position();
    if (activate) {
      [window addChildWindow:child ordered:NSWindowAbove];
      native_->ShowAttached(state_, restore_);
    } else {
      native_->ShowAttached(ShowState::kInactive, restore_);
      [window addChildWindow:child ordered:NSWindowAbove];
    }
    if (!attached_ || !widget_ || child.parentWindow != window) {
      return;
    }
    Position();
    ObserveAnchor(Anchor(window));
  }

  void Detach(bool hide) {
    auto keep = shared_from_this();
    const bool was_attached = attached_;
    attached_ = false;
    StopObservingAnchor();
    NSWindow* child = dialog_.GetNativeNSWindow();
    if (child.parentWindow) {
      [child.parentWindow removeChildWindow:child];
    }
    if (hide && native_ && (was_attached || child.visible)) {
      native_->HideAttached();
    }
    Release();
  }

  void Release() {
    if (!reservation_) {
      return;
    }
    releasing_ = true;
    [reservation_ invalidate];
    reservation_ = nil;
    releasing_ = false;
  }

  void EndPresentation() {
    auto keep = shared_from_this();
    NSWindow* child = dialog_.GetNativeNSWindow();
    const bool was_key = attached_ && child.keyWindow;
    wanted_ = false;
    Detach(false);
    if (was_key) {
      RestoreFocus();
    }
    ClearHost();
    RemoveModal();
  }

  void RestoreFocus() {
    NSWindow* window = window_;
    if (!window || !window.visible || window.miniaturized || !NSApp.active ||
        !window.canBecomeKeyWindow ||
        PCNativeWindowHasSecurityReservation(window)) {
      return;
    }
    [window makeKeyWindow];
    if (contents_ && !contents_->IsBeingDestroyed() &&
        Usable(contents_->GetNativeView().GetNativeNSView(), window)) {
      contents_->Focus();
    }
  }

  void FocusInitialView() {
    if (!widget_) {
      return;
    }
    if (auto* delegate = widget_->widget_delegate()) {
      if (auto* view = delegate->GetInitiallyFocusedView()) {
        view->RequestFocus();
      }
    }
  }

  void RemoveModal() {
    if (!registered_ || registering_ || !manager_) {
      return;
    }
    auto* manager = manager_.get();
    registered_ = false;
    manager_ = nullptr;
    manager->WillClose(dialog_);
  }

  void CloseSoon() {
    if (Finished()) {
      return;
    }
    close_posted_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE,
        base::BindOnce(
            [](std::weak_ptr<Presenter> weak) {
              auto self = weak.lock();
              if (self && self->widget_ && !self->widget_->IsClosed()) {
                self->widget_->Close();
              }
            },
            weak_from_this()));
  }

  void SecurityChanged() {
    auto keep = shared_from_this();
    if (acquiring_ || releasing_) {
      return;
    }
    if (!reservation_) {
      TryAttach();
      return;
    }
    if (!reservation_.active) {
      Detach(true);
      CloseSoon();
    } else if (!reservation_.isOnlyReservation) {
      Detach(true);
    }
  }

  void BindWindow(NSWindow* window) {
    RemoveWindowObservers();
    window_ = window;
    if (!window) {
      return;
    }
    std::weak_ptr<Presenter> weak = weak_from_this();
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [window_observers_
        addObject:[center addObserverForName:NSWindowWillCloseNotification
                                      object:window
                                       queue:nil
                                  usingBlock:^(NSNotification*) {
                                    if (auto self = weak.lock()) {
                                      self->Detach(true);
                                      self->CloseSoon();
                                    }
                                  }]];
    [window_observers_
        addObject:[center
                      addObserverForName:PCNativeWindowSecurityStateChanged
                                  object:window
                                   queue:nil
                              usingBlock:^(NSNotification*) {
                                if (auto self = weak.lock()) {
                                  self->SecurityChanged();
                                }
                              }]];
    [window_observers_
        addObject:[center addObserverForName:NSWindowDidResizeNotification
                                      object:window
                                       queue:nil
                                  usingBlock:^(NSNotification*) {
                                    if (auto self = weak.lock()) {
                                      self->Position();
                                    }
                                  }]];
    for (NSNotificationName name in @[
           NSWindowDidEndSheetNotification, NSWindowDidDeminiaturizeNotification,
           NSWindowDidBecomeKeyNotification, NSWindowDidBecomeMainNotification
         ]) {
      [window_observers_
          addObject:[center addObserverForName:name
                                        object:window
                                         queue:nil
                                    usingBlock:^(NSNotification*) {
                                      if (auto self = weak.lock()) {
                                        self->TryAttach();
                                      }
                                    }]];
    }
  }

  void ObserveAnchor(NSView* anchor) {
    StopObservingAnchor();
    if (!anchor) {
      return;
    }
    std::weak_ptr<Presenter> weak = weak_from_this();
    anchor_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSViewFrameDidChangeNotification
                    object:anchor
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock()) {
                    self->Position();
                  }
                }];
  }

  void StopObservingAnchor() {
    if (anchor_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:anchor_observer_];
      anchor_observer_ = nil;
    }
  }

  void RemoveWindowObservers() {
    for (id observer in window_observers_) {
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
    [window_observers_ removeAllObjects];
  }

  void RemoveObservers() {
    StopObservingAnchor();
    RemoveWindowObservers();
  }

  void ClearHost() {
    auto* host = host_.get();
    host_ = nullptr;
    if (host) {
      host->RemoveObserver(this);
    }
  }

  std::shared_ptr<Presenter> keep_alive_;
  base::WeakPtr<content::WebContents> contents_;
  const bool web_modal_;
  raw_ptr<web_modal::WebContentsModalDialogManager> manager_ = nullptr;
  raw_ptr<web_modal::WebContentsModalDialogHost> host_ = nullptr;
  base::WeakPtr<views::Widget> widget_;
  raw_ptr<PresentedWidget> native_ = nullptr;
  gfx::NativeWindow dialog_;
  __weak NSWindow* window_;
  NSMutableArray* window_observers_;
  id anchor_observer_;
  PCNativeWindowSecurityReservation* reservation_;
  ShowState state_ = ShowState::kNormal;
  gfx::Rect restore_;
  bool wanted_ = false, attached_ = false, closing_ = false;
  bool close_posted_ = false, acquiring_ = false, releasing_ = false;
  bool registered_ = false, registering_ = false;
  base::WeakPtrFactory<Presenter> weak_factory_{this};
};

class WebModal final : public web_modal::SingleWebContentsDialogManager {
 public:
  explicit WebModal(std::shared_ptr<Presenter> presenter)
      : presenter_(std::move(presenter)) {}
  ~WebModal() override { presenter_->ModalDestroyed(); }
  void Show() override {
    auto presenter = presenter_;
    presenter->ShowFromManager();
  }
  void Hide() override {
    auto presenter = presenter_;
    presenter->HideFromManager();
  }
  void Close() override {
    auto presenter = presenter_;
    presenter->CloseFromManager();
  }
  void Focus() override {
    auto presenter = presenter_;
    presenter->FocusFromManager();
  }
  void Pulse() override {}
  void HostChanged(web_modal::WebContentsModalDialogHost* host) override {
    auto presenter = presenter_;
    presenter->ChangeHost(host);
  }
  gfx::NativeWindow dialog() override { return presenter_->dialog(); }
  bool IsActive() const override { return presenter_->IsActive(); }

 private:
  const std::shared_ptr<Presenter> presenter_;
};

std::unique_ptr<web_modal::SingleWebContentsDialogManager>
Presenter::MakeModal() {
  return std::make_unique<WebModal>(shared_from_this());
}

void PresentedWidget::Show(ShowState state, const gfx::Rect& restore) {
  if (presenter_) {
    presenter_->RequestShow(state, restore);
  } else {
    NativeWidgetMac::Show(state, restore);
  }
}

void PresentedWidget::Hide() {
  if (presenter_) {
    presenter_->RequestHide();
  } else {
    NativeWidgetMac::Hide();
  }
}

void PresentedWidget::Activate() {
  if (presenter_) {
    presenter_->RequestActivate();
  } else {
    NativeWidgetMac::Activate();
  }
}

views::Widget* CreateWidget(views::WidgetDelegate* dialog,
                            const std::shared_ptr<Presenter>& presenter) {
  auto* widget = new views::Widget;
  auto params = views::DialogDelegate::GetDialogWidgetInitParams(
      dialog, gfx::NativeWindow(), gfx::NativeView(), gfx::Rect());
  auto* native = new PresentedWidget(widget, presenter->GetWeakPtr());
  params.native_widget = native;
  widget->Init(std::move(params));
  presenter->Bind(widget, native);
  return widget;
}

}

views::Widget* PresentNativeWebModal(views::WidgetDelegate* dialog,
                                     content::WebContents* contents) {
  auto* manager =
      contents ? web_modal::WebContentsModalDialogManager::FromWebContents(
                     contents)
               : nullptr;
  auto* host = manager && manager->delegate()
                   ? manager->delegate()->GetWebContentsModalDialogHost(
                         contents)
                   : nullptr;
  if (!dialog || !host || !host->GetHostView() ||
      views::Widget::GetWidgetForNativeView(host->GetHostView())) {
    return nullptr;
  }
  auto presenter = std::make_shared<Presenter>(contents, nil);
  auto* widget = CreateWidget(dialog, presenter);
  presenter->Register(manager);
  return widget;
}

views::Widget* CreateNativeBrowserModal(views::DialogDelegate* dialog,
                                        gfx::NativeWindow parent) {
  NSWindow* window = parent.GetNativeNSWindow();
  if (!dialog || !window || views::Widget::GetWidgetForNativeWindow(parent)) {
    return nullptr;
  }
  auto presenter = std::make_shared<Presenter>(nullptr, window);
  auto* widget = CreateWidget(dialog, presenter);
  presenter->BindBrowserHost(parent);
  return widget;
}

}
