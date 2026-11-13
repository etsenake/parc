// Copyright 2024 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include "webauthn.h"

#import <AppKit/AppKit.h>

#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/extensions/security_dialog_tracker.h"
#include "chrome/browser/ui/views/webauthn/authenticator_request_dialog_view.h"
#include "chrome/browser/ui/webauthn/ambient/ambient_signin_controller.h"
#include "chrome/browser/ui/views/webauthn/authenticator_request_sheet_view.h"
#include "chrome/browser/ui/views/webauthn/sheet_view_factory.h"
#include "chrome/browser/ui/webauthn/authenticator_request_dialog_view_controller.h"
#include "chrome/browser/webauthn/authenticator_request_dialog_model.h"
#include "chrome/browser/webauthn/authenticator_request_scheduler.h"
#include "chrome/browser/webauthn/chrome_authenticator_request_delegate.h"
#include "chrome/browser/webauthn/native_authenticator_request_context.h"
#include "components/tabs/public/tab_interface.h"
#include "components/web_modal/single_web_contents_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/base/base_window.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/views/widget/native_widget_mac.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"
#include "base/callback_list.h"
#include "chrome/browser/ui/passwords/ui_utils.h"
#include "chrome/browser/ui/views/controls/hover_button.h"
#include "chrome/browser/ui/webauthn/webauthn_ui_helpers.h"
#include "chrome/grit/generated_resources.h"
#include "components/strings/grit/components_strings.h"
#include "components/vector_icons/vector_icons.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/models/image_model.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/base/ui_base_features.h"
#include "ui/color/color_id.h"
#include "ui/gfx/font_list.h"
#include "ui/views/bubble/bubble_border.h"
#include "ui/views/bubble/bubble_dialog_delegate_view.h"
#include "ui/views/controls/image_view.h"
#include "ui/views/layout/box_layout.h"
#include "ui/views/layout/layout_provider.h"
#include "ui/views/layout/layout_types.h"
#include "ui/views/style/typography.h"
#include "ui/views/style/typography_provider.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
class Context;
class Dialog;
class Ambient;
class WindowLease;
class Guard final : public content::WebContentsObserver,
                    public AuthenticatorRequestDialogModel::Observer,
                    public std::enable_shared_from_this<Guard> {
 public:
  Guard(content::RenderFrameHost& frame,
        base::WeakPtr<ChromeAuthenticatorRequestDelegate> request)
      : WebContentsObserver(content::WebContents::FromRenderFrameHost(&frame)),
        request_(request),
        document_(frame.GetWeakDocumentPtr()) {
    CaptureOwner();
  }
  Guard(content::RenderFrameHost& frame, AuthenticatorRequestDialogModel& model)
      : WebContentsObserver(content::WebContents::FromRenderFrameHost(&frame)),
        document_(frame.GetWeakDocumentPtr()), settings_model_(&model),
        ready_(true) {
    model_observation_.Observe(&model);
    CaptureOwner();
  }
  void CaptureOwner() {
    auto* tab = tabs::TabInterface::MaybeGetFromContents(web_contents());
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    if (browser && browser->GetWindow()) {
      browser_ = browser->GetWeakPtr();
      profile_ = browser->GetProfile()->GetWeakPtr();
      window_ = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
      page_ = web_contents()->GetNativeView().GetNativeNSView();
    }
  }
  ~Guard() override {
    if (window_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:window_observer_];
    }
  }
  void ObserveWindow() {
    if (!window_) {
      return;
    }
    std::weak_ptr<Guard> weak = shared_from_this();
    window_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock()) {
                    self->Cancel();
                  }
                }];
  }
  bool Matches(
      base::WeakPtr<ChromeAuthenticatorRequestDelegate> request) const {
    return request_ && request && request_.get() == request.get();
  }
  bool Matches(AuthenticatorRequestDialogModel& model) const {
    return (request_ && request_->dialog_model() == &model) ||
           settings_model_ == &model;
  }
  bool HasModel() const { return request_ || settings_model_; }
  bool Valid(bool visible) const;
  void OnModelDestroyed(AuthenticatorRequestDialogModel*) override {
    model_observation_.Reset();
    settings_model_ = nullptr;
    cancelled_ = true;
    ready_ = false;
  }
  class Operation {
   public:
    explicit Operation(std::shared_ptr<Guard> guard)
        : guard_(std::move(guard)) {
      ++guard_->operations_;
    }
    ~Operation() {
      if (--guard_->operations_ == 0 && guard_->cancelled_ && guard_->ready_) {
        guard_->CancelSoon();
      }
    }

   private:
    const std::shared_ptr<Guard> guard_;
  };
  void Ready() {
    ready_ = true;

    if (!Valid(false)) {
      CancelSoon();
    }
  }
  void CancelSoon() {
    cancelled_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(&Guard::Cancel, shared_from_this()));
  }
  void Cancel() {
    auto keep = shared_from_this();
    cancelled_ = true;
    if (!ready_ || operations_) {
      return;
    }
    ready_ = false;
    auto request = std::exchange(request_, {});

    if (request) {
      request->OnCancelRequest();
    } else if (settings_model_) {

      scoped_refptr<AuthenticatorRequestDialogModel> model(settings_model_);
      model->CancelAuthenticatorRequest();
    }
  }
  void DidStartNavigation(content::NavigationHandle* nav) override {

    auto* frame = document_.AsRenderFrameHostIfValid();
    if (!nav->IsSameDocument() &&
        (nav->IsInPrimaryMainFrame() ||
         (frame && nav->GetFrameTreeNodeId() == frame->GetFrameTreeNodeId()))) {
      Cancel();
    }
  }
  void DidFinishNavigation(content::NavigationHandle*) override {
    if (!Valid(false)) {
      Cancel();
    }
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (os_window_requested_ && visibility == content::Visibility::HIDDEN) {
      Cancel();
    }
  }
  void MarkOSWindowRequested() { os_window_requested_ = true; }
  void WebContentsDestroyed() override {

    cancelled_ = true;
    ready_ = false;
    request_.reset();
    settings_model_ = nullptr;
    model_observation_.Reset();
  }
  NSWindow* window() const { return window_; }
  NSView* page() const { return page_; }
  content::WebContents* contents() const { return web_contents(); }

 private:
  base::WeakPtr<ChromeAuthenticatorRequestDelegate> request_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr document_;
  raw_ptr<AuthenticatorRequestDialogModel> settings_model_ = nullptr;
  base::ScopedObservation<AuthenticatorRequestDialogModel,
                          AuthenticatorRequestDialogModel::Observer>
      model_observation_{this};
  __weak NSWindow* window_;
  __weak NSView* page_;
  id window_observer_;
  int operations_ = 0;
  bool os_window_requested_ = false;
  bool ready_ = false;
  bool cancelled_ = false;
};
class Context final : public NativeAuthenticatorRequestContext {
 public:
  Context();
  ~Context() override;
  void Created(
      content::RenderFrameHost& frame,
      base::WeakPtr<ChromeAuthenticatorRequestDelegate> request) override {

    if (guard_ && guard_->HasModel()) {
      guard_->CancelSoon();
    }
    guard_ = std::make_shared<Guard>(frame, request);
    guard_->ObserveWindow();
  }
  void Ready(
      base::WeakPtr<ChromeAuthenticatorRequestDelegate> request) override {
    if (guard_ && guard_->Matches(request)) {
      guard_->Ready();
    }
  }
  gfx::NativeWindow AuthenticatorWindow(
      base::WeakPtr<ChromeAuthenticatorRequestDelegate> request) override {
    if (guard_ && guard_->Matches(request) && guard_->Valid(true) &&
        !guard_->window().attachedSheet &&
        !PCNativeWindowHasSecurityReservation(guard_->window())) {
      guard_->MarkOSWindowRequested();
      return gfx::NativeWindow(guard_->window());
    }
    if (guard_ && guard_->Matches(request)) {
      guard_->CancelSoon();
    }
    return gfx::NativeWindow();
  }
  std::unique_ptr<AuthenticatorRequestDialogViewController> CreateDialog(
      AuthenticatorRequestDialogModel& model) override;
  bool BeginSettings(content::RenderFrameHost&,
                     AuthenticatorRequestDialogModel&) override;
  void PrepareForStepChange(AuthenticatorRequestDialogModel&) override;
  base::WeakPtr<WindowLease> recovery_window_;
  std::shared_ptr<Guard> GuardForModel(AuthenticatorRequestDialogModel&);
  std::unique_ptr<NativeAuthenticatorRequestWindow> CreateWindow(
      AuthenticatorRequestDialogModel&) override;
  void ShowAmbient(
      AuthenticatorRequestDialogModel&,
      base::WeakPtr<ambient_signin::AmbientSigninController>) override;
  void HideAmbient() override;
  std::unique_ptr<Ambient> ambient_;
  bool attached = false;
  std::shared_ptr<Guard> guard_;
};
Context* GetContext(content::WebContents* contents) {
  return static_cast<Context*>(
      NativeAuthenticatorRequestContext::Get(contents));
}
bool Guard::Valid(bool visible) const {
  auto* contents = web_contents();
  auto* context = GetContext(contents);
  auto* frame = document_.AsRenderFrameHostIfValid();
  if (cancelled_ || !HasModel() || !contents || !context || !context->attached ||
      context->guard_.get() != this || !frame || !frame->IsActive() ||
      content::WebContents::FromRenderFrameHost(frame) != contents ||
      !browser_ || !profile_ || browser_->IsDeleteScheduled() ||
      contents->GetBrowserContext() != profile_.get() ||
      browser_->GetProfile() != profile_.get() || !browser_->GetWindow() ||
      !window_ || !page_ || page_.window != window_ ||
      browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() != window_) {
    return false;
  }
  auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  return tab && tab->GetBrowserWindowInterface() == browser_.get() &&
         (!visible ||
          (tab->IsActivated() && window_.visible && !window_.miniaturized &&
           !page_.hiddenOrHasHiddenAncestor &&
           contents->GetVisibility() != content::Visibility::HIDDEN));
}

class AuthenticatorWidget final : public views::NativeWidgetMac {
 public:
  explicit AuthenticatorWidget(views::Widget* widget)
      : NativeWidgetMac(widget) {}
  void InitModalType(ui::mojom::ModalType type) override {
    CHECK_EQ(type, ui::mojom::ModalType::kChild);
  }
};
class NativeModal final : public web_modal::SingleWebContentsDialogManager {
 public:
  explicit NativeModal(std::shared_ptr<Dialog> dialog)
      : dialog_(std::move(dialog)) {}
  ~NativeModal() override;
  void Show() override;
  void Hide() override;
  void Close() override;
  void Focus() override;
  void Pulse() override;
  void HostChanged(web_modal::WebContentsModalDialogHost*) override;
  gfx::NativeWindow dialog() override;
  bool IsActive() const override;

 private:
  const std::shared_ptr<Dialog> dialog_;
};
class Dialog final : public views::WidgetObserver,
                     public web_modal::ModalDialogHostObserver,
                     public std::enable_shared_from_this<Dialog> {
 public:
  explicit Dialog(std::shared_ptr<Guard> guard) : guard_(std::move(guard)) {}
  ~Dialog() override { CHECK(finished_); }
  bool Valid() const {
    return !finished_ && !aborting_ && guard_->Valid(true) &&
           !guard_->window().attachedSheet &&
           (reservation_
                ? reservation_.isOnlyReservation
                : !PCNativeWindowHasSecurityReservation(guard_->window()));
  }
  bool Build(views::Widget& widget) {
    Guard::Operation operation(guard_);
    auto keep = shared_from_this();
    auto* manager = web_modal::WebContentsModalDialogManager::FromWebContents(
        guard_->contents());
    if (!Valid() || !manager || !manager->delegate() ||
        manager->IsDialogActive()) {
      return false;
    }
    widget_ = widget.GetWeakPtr();
    native_window_ = widget.GetNativeWindow();
    widget.AddObserver(this);
    std::weak_ptr<Dialog> weak = keep;
    security_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:guard_->window()
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock();
                      self && !self->acquiring_ && !self->releasing_ &&
                      !self->finished_ && !self->Valid()) {
                    self->AbortSoon();
                  }
                }];
    acquiring_ = true;
    auto* lease =
        [PCNativeWindowSecurityReservation acquireForWindow:guard_->window()];
    acquiring_ = false;
    reservation_ = lease;
    if (!Valid()) {
      return false;
    }
    registered_ = registering_ = true;
    manager->ShowDialogWithManager(native_window_,
                                   std::make_unique<NativeModal>(keep));
    registering_ = false;
    if (finished_) {
      RemoveModal();
    }
    return Valid();
  }
  void ReadyToShow() { ready_ = true; }
  bool MayShow() const {
    return ready_ && Valid() && registered_ && widget_ && host_ &&
           native_window_.GetNativeNSWindow().parentWindow == guard_->window();
  }
  void Show() {
    Guard::Operation operation(guard_);
    auto keep = shared_from_this();
    if (!ready_) {
      return;
    }
    if (!Valid() || !widget_ || !host_) {
      AbortSoon();
      return;
    }
    __attribute__((objc_precise_lifetime)) NSWindow* parent = guard_->window();
    __attribute__((objc_precise_lifetime)) NSWindow* child =
        native_window_.GetNativeNSWindow();
    Position();
    if (!Valid() || !widget_ || !child) {
      AbortSoon();
      return;
    }
    [parent addChildWindow:child ordered:NSWindowAbove];
    if (!MayShow()) {
      AbortSoon();
      return;
    }
    widget_->Show();
    if (!MayShow() || !child.visible) {
      AbortSoon();
    }
  }
  void Focus() {
    if (MayShow()) {
      widget_->Activate();
    }
  }
  bool Active() const { return MayShow() && widget_->IsActive(); }
  gfx::NativeWindow Window() const { return native_window_; }
  void ChangeHost(web_modal::WebContentsModalDialogHost* host) {
    auto keep = shared_from_this();
    ClearHost();
    if (!host || !Valid() ||
        host->GetHostView().GetNativeNSView().window != guard_->window()) {
      AbortSoon();
      return;
    }
    host_ = host;
    host_->AddObserver(this);
    Position();
  }
  void Position() {
    if (!host_ || !widget_ || finished_) {
      return;
    }
    NSView* view = host_->GetHostView().GetNativeNSView();
    if (!Valid() || !view || view.window != guard_->window()) {
      AbortSoon();
      return;
    }
    const auto size = widget_->GetWindowBoundsInScreen().size();
    const auto origin = host_->GetDialogPosition(size);
    CGFloat y = view.flipped
                    ? origin.y()
                    : NSHeight(view.bounds) - origin.y() - size.height();
    NSRect rect = [guard_->window()
        convertRectToScreen:[view convertRect:NSMakeRect(origin.x(), y,
                                                         size.width(),
                                                         size.height())
                                       toView:nil]];
    [native_window_.GetNativeNSWindow() setFrame:rect display:NO];
  }
  void AbortSoon() {
    if (finished_ || aborting_) {
      return;
    }

    aborting_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(&Dialog::Finish, shared_from_this()));
    guard_->CancelSoon();
  }
  void CloseFromManager() {

    auto guard = guard_;
    Finish();
    guard->CancelSoon();
  }
  void Finish() {
    Guard::Operation operation(guard_);
    auto keep = shared_from_this();
    if (finished_) {
      return;
    }
    finished_ = true;
    if (security_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_observer_];
      security_observer_ = nil;
    }
    ClearHost();
    if (widget_) {
      widget_->RemoveObserver(this);
      widget_->Hide();
    }
    NSWindow* child = native_window_.GetNativeNSWindow();
    [child.parentWindow removeChildWindow:child];
    RemoveModal();
    releasing_ = true;
    [reservation_ invalidate];
    reservation_ = nil;
    releasing_ = false;
  }
  void ModalDestroyed() { registered_ = false; }
  void OnPositionRequiresUpdate() override { Position(); }
  void OnHostDestroying() override {
    ClearHost();
    AbortSoon();
  }
  void OnWidgetBoundsChanged(views::Widget*, const gfx::Rect&) override {

  }
  void OnWidgetClosing(views::Widget*) override { AbortSoon(); }
  void OnWidgetDestroying(views::Widget* widget) override {
    widget->RemoveObserver(this);
    widget_.reset();
    AbortSoon();
  }

 private:
  void ClearHost() {
    auto* host = host_.get();
    host_ = nullptr;
    if (host) {
      host->RemoveObserver(this);
    }
  }
  void RemoveModal() {
    if (!registered_ || registering_) {
      return;
    }
    registered_ = false;
    if (auto* contents = guard_->contents()) {
      if (auto* manager =
              web_modal::WebContentsModalDialogManager::FromWebContents(
                  contents)) {
        manager->WillClose(native_window_);
      }
    }
  }
  const std::shared_ptr<Guard> guard_;
  base::WeakPtr<views::Widget> widget_;
  gfx::NativeWindow native_window_;
  raw_ptr<web_modal::WebContentsModalDialogHost> host_ = nullptr;
  PCNativeWindowSecurityReservation* reservation_;
  id security_observer_;
  bool ready_ = false;
  bool finished_ = false;
  bool aborting_ = false;
  bool registered_ = false;
  bool registering_ = false;
  bool acquiring_ = false;
  bool releasing_ = false;
};
NativeModal::~NativeModal() {
  dialog_->ModalDestroyed();
}
void NativeModal::Show() {
  auto keep = dialog_;
  keep->Show();
}
void NativeModal::Hide() {
  auto keep = dialog_;
  keep->AbortSoon();
}
void NativeModal::Close() {
  auto keep = dialog_;
  keep->CloseFromManager();
}
void NativeModal::Focus() {
  auto keep = dialog_;
  keep->Focus();
}
void NativeModal::Pulse() {
  Focus();
}
void NativeModal::HostChanged(web_modal::WebContentsModalDialogHost* host) {
  auto keep = dialog_;
  keep->ChangeHost(host);
}
gfx::NativeWindow NativeModal::dialog() {
  return dialog_->Window();
}
bool NativeModal::IsActive() const {
  return dialog_->Active();
}

class Controller final : public AuthenticatorRequestDialogViewController,
                         public AuthenticatorRequestDialogModel::Observer {
 public:
  Controller(AuthenticatorRequestDialogModel& model,
             std::shared_ptr<Guard> guard)
      : model_(model), dialog_(std::make_shared<Dialog>(guard)) {
    view_ = new AuthenticatorRequestDialogView(guard->contents(), &model);
    std::weak_ptr<Dialog> weak = dialog_;
    view_->SetNativePresentationValidation(base::BindRepeating(
        [](std::weak_ptr<Dialog> weak) {
          auto self = weak.lock();
          return self && self->MayShow();
        },
        weak));
    widget_ = std::make_unique<views::Widget>();
    Guard::Operation operation(guard);
    auto params = views::DialogDelegate::GetDialogWidgetInitParams(
        view_, gfx::NativeWindow(), gfx::NativeView(), gfx::Rect());
    params.ownership = views::Widget::InitParams::CLIENT_OWNS_WIDGET;
    params.native_widget = new AuthenticatorWidget(widget_.get());
    widget_->Init(std::move(params));
    extensions::SecurityDialogTracker::GetInstance()->AddSecurityDialog(
        widget_.get());
    if (!dialog_->Build(*widget_)) {
      dialog_->AbortSoon();
    }
    observation_.Observe(&model);
  }
  ~Controller() override {
    observation_.Reset();
    dialog_->Finish();
  }
  void OnStepTransition() override {
    auto weak = weak_factory_.GetWeakPtr();
    auto dialog = dialog_;
    if (!dialog->Valid()) {
      return;
    }
    view_->ReplaceCurrentSheetWith(
        CreateSheetViewForCurrentStepOf(&model_.get()));
    if (!weak || !dialog->Valid()) {
      return;
    }
    dialog->ReadyToShow();
    dialog->Show();
  }
  void OnSheetModelChanged() override {
    auto weak = weak_factory_.GetWeakPtr();
    auto dialog = dialog_;
    if (!dialog->Valid()) {
      return;
    }
    view_->UpdateUIForCurrentSheet();
    if (weak) {
      dialog->Position();
    }
  }
  void OnButtonsStateChanged() override {
    if (dialog_->Valid()) {
      view_->DialogModelChanged();
    }
  }

 private:
  const raw_ref<AuthenticatorRequestDialogModel> model_;
  const std::shared_ptr<Dialog> dialog_;
  std::unique_ptr<views::Widget> widget_;
  raw_ptr<AuthenticatorRequestDialogView> view_ = nullptr;
  base::ScopedObservation<AuthenticatorRequestDialogModel,
                          AuthenticatorRequestDialogModel::Observer>
      observation_{this};
  base::WeakPtrFactory<Controller> weak_factory_{this};
};

class WindowLease final : public NativeAuthenticatorRequestWindow {
 public:
  explicit WindowLease(std::shared_ptr<Guard> guard) : guard_(std::move(guard)) {}
  ~WindowLease() override { Release(); }
  base::WeakPtr<WindowLease> GetWeakPtr() { return weak_factory_.GetWeakPtr(); }
  bool IsValid() const override {

    return !released_ && guard_->Valid(true) && child_ &&
           reservation_.isOnlyReservation;
  }
  bool Attach(content::WebContents& page, gfx::NativeWindow window) override {
    Guard::Operation operation(guard_);
    if (!guard_->Valid(true)) { Cancel(); return false; }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(&page);
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    auto* profile = Profile::FromBrowserContext(guard_->contents()->GetBrowserContext());
    if (released_ || !guard_->Valid(true) || !browser || !browser->GetWindow() ||
        browser->GetWindow()->GetNativeWindow() != window ||
        page.GetBrowserContext() != profile->GetOriginalProfile() ||
        guard_->window().attachedSheet ||
        PCNativeWindowHasSecurityReservation(guard_->window())) {
      Cancel();
      return false;
    }
    child_ = window.GetNativeNSWindow();
    reservation_ = [PCNativeWindowSecurityReservation acquireForWindow:guard_->window()];
    if (!guard_->Valid(true) || !reservation_.isOnlyReservation) {
      Cancel();
      return false;
    }
    auto weak = weak_factory_.GetWeakPtr();
    security_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:guard_->window() queue:nil
                usingBlock:^(NSNotification*) {
                  if (weak && !weak->released_ &&
                      !weak->reservation_.isOnlyReservation) {
                    weak->Cancel();
                  }
                }];
    guard_->MarkOSWindowRequested();
    [guard_->window() addChildWindow:child_ ordered:NSWindowAbove];
    return guard_->Valid(true) && reservation_.isOnlyReservation;
  }
  void Cancel() override {
    Release();
    guard_->CancelSoon();
  }
  void Release() {
    if (released_) return;
    released_ = true;
    if (security_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_];
      security_ = nil;
    }

    [child_ orderOut:nil];
    [child_.parentWindow removeChildWindow:child_];
    [reservation_ invalidate];
    reservation_ = nil;
  }
 private:
  const std::shared_ptr<Guard> guard_;
  __weak NSWindow* child_;
  PCNativeWindowSecurityReservation* reservation_;
  id security_;
  bool released_ = false;
  base::WeakPtrFactory<WindowLease> weak_factory_{this};
};

class NativeAmbientSigninBubble final : public views::BubbleDialogDelegateView {
  METADATA_HEADER(NativeAmbientSigninBubble, views::BubbleDialogDelegateView)
 public:
  NativeAmbientSigninBubble(
      gfx::NativeView parent, const gfx::Rect& anchor,
      const std::string& relying_party_id,
      base::RepeatingCallback<bool()> validation,
      base::RepeatingCallback<void(size_t)> selected)
      : BubbleDialogDelegateView(views::BubbleAnchor(),
                                 views::BubbleBorder::Arrow::TOP_RIGHT),
        validation_(std::move(validation)), selected_(std::move(selected)) {
    set_parent_window(parent);
    SetAnchorRect(anchor);
    SetShowCloseButton(true);
    UseCompactMargins();
    set_close_on_deactivate(false);
    SetShowIcon(true);
    SetIcon(ui::ImageModel::FromVectorIcon(GooglePasswordManagerVectorIcon()));
    SetShowTitle(true);
    auto* layout_provider = views::LayoutProvider::Get();
    const int title_width = layout_provider->GetDistanceMetric(
                                views::DISTANCE_BUBBLE_PREFERRED_WIDTH) -
                            layout_provider->GetInsetsMetric(
                                views::INSETS_DIALOG).width() -
                            layout_provider->GetInsetsMetric(
                                views::INSETS_DIALOG_TITLE).width();
    SetTitle(l10n_util::GetStringFUTF16(
        IDS_WEBAUTHN_SIGN_IN_TO_WEBSITE_DIALOG_TITLE,
        webauthn_ui_helpers::RpIdToElidedHost(
            relying_party_id, title_width,
            views::TypographyProvider::Get().GetFont(
                views::style::CONTEXT_DIALOG_TITLE,
                views::style::STYLE_PRIMARY))));
    auto layout = std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kVertical);
    layout->set_cross_axis_alignment(views::LayoutAlignment::kStretch);
    SetLayoutManager(std::move(layout));
  }
  base::WeakPtr<NativeAmbientSigninBubble> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }
  void ShowCredentials(
      const std::vector<AuthenticatorRequestDialogModel::Mechanism>& mechanisms,
      const std::vector<size_t>& indices) {
    const bool single = indices.size() == 1;
    for (size_t i = 0; i < indices.size(); ++i) {
      const auto& mechanism = mechanisms.at(indices.at(i));
      std::unique_ptr<views::ImageView> secondary;
      if (!single) {
        secondary = std::make_unique<views::ImageView>(
            ui::ImageModel::FromVectorIcon(
                features::IsRoundedIconsEnabled()
                    ? vector_icons::kKeyboardArrowRightFlippableIcon
                    : vector_icons::kSubmenuArrowChromeRefreshOldIcon,
                ui::kColorIcon, 20));
      }
      AddChildView(std::make_unique<HoverButton>(
          base::BindRepeating(
              [](base::WeakPtr<NativeAmbientSigninBubble> self, size_t index,
                 const ui::Event&) {
                if (self) self->SelectCredential(index);
              }, weak_factory_.GetWeakPtr(), i),
          std::make_unique<views::ImageView>(ui::ImageModel::FromVectorIcon(
              *mechanism.icon, ui::kColorIcon, 20)),
          mechanism.name, mechanism.description, std::move(secondary)));
    }
    SetButtons(single ? static_cast<int>(ui::mojom::DialogButton::kCancel) |
                            static_cast<int>(ui::mojom::DialogButton::kOk)
                      : static_cast<int>(ui::mojom::DialogButton::kNone));
    if (single) {
      SetButtonLabel(ui::mojom::DialogButton::kCancel,
                     l10n_util::GetStringUTF16(IDS_NOT_NOW));
      SetCancelCallback(base::BindOnce(&NativeAmbientSigninBubble::Disconnect,
                                       weak_factory_.GetWeakPtr()));
      SetButtonLabel(ui::mojom::DialogButton::kOk,
                     l10n_util::GetStringUTF16(
                         IDS_PASSWORD_MANAGER_ACCOUNT_CHOOSER_SIGN_IN));
      SetAcceptCallback(base::BindOnce(
          &NativeAmbientSigninBubble::SelectCredential,
          weak_factory_.GetWeakPtr(), 0));
    }
    set_fixed_width(320);
    widget_ = views::BubbleDialogDelegate::CreateBubbleDeprecated(
                  this, views::Widget::InitParams::NATIVE_WIDGET_OWNS_WIDGET)
                  ->GetWeakPtr();
    widget_->Show();
  }
  void Disconnect() {
    validation_.Reset();
    selected_.Reset();
    if (widget_) widget_->Close();
  }
 private:
  void SelectCredential(size_t index) {
    const auto validation = validation_;
    if (!validation || !validation.Run()) return;
    auto selected = selected_;
    if (widget_) widget_->Hide();
    if (selected) selected.Run(index);
  }
  base::RepeatingCallback<bool()> validation_;
  base::RepeatingCallback<void(size_t)> selected_;
  base::WeakPtr<views::Widget> widget_;
  base::WeakPtrFactory<NativeAmbientSigninBubble> weak_factory_{this};
};
BEGIN_METADATA(NativeAmbientSigninBubble)
END_METADATA

class Ambient final : public content::WebContentsObserver,
                      public AuthenticatorRequestDialogModel::Observer {
 public:
  Ambient(AuthenticatorRequestDialogModel& model, std::shared_ptr<Guard> guard,
          base::WeakPtr<ambient_signin::AmbientSigninController> controller)
      : WebContentsObserver(guard->contents()), model_(&model),
        guard_(std::move(guard)), controller_(controller) {
    observation_.Observe(&model);
    if (auto* tab = tabs::TabInterface::MaybeGetFromContents(guard_->contents())) {
      subscriptions_.push_back(tab->RegisterWillDeactivate(base::BindRepeating(
          [](base::WeakPtr<Ambient> self, tabs::TabInterface*) {
            if (self) self->Hide();
          }, weak_factory_.GetWeakPtr())));
      subscriptions_.push_back(tab->RegisterDidActivate(base::BindRepeating(
          [](base::WeakPtr<Ambient> self, tabs::TabInterface*) {
            if (self) self->Reshow();
          }, weak_factory_.GetWeakPtr())));
    }
  }
  ~Ambient() override { Hide(); }
  bool Matches(AuthenticatorRequestDialogModel& model) const { return model_ == &model; }
  bool MayShow() const {
    return model_ && controller_ && guard_->Valid(true) && !guard_->window().attachedSheet &&
           !PCNativeWindowHasSecurityReservation(guard_->window());
  }
  bool MaySelect() const {
    return !selection_made_ && MayShow() &&
           model_->step() == AuthenticatorRequestDialogModel::Step::kPasskeyAutofill;
  }
  void Reshow() {
    if (MaySelect()) Show();
  }
  void Show() {
    if (!MayShow()) return;
    selection_made_ = false;
    Hide();
    indices_.clear();
    for (size_t i = 0; i < model_->mechanisms.size(); ++i) {
      const auto& type = model_->mechanisms[i].type;
      if (std::holds_alternative<AuthenticatorRequestDialogModel::Mechanism::Credential>(type) ||
          std::holds_alternative<AuthenticatorRequestDialogModel::Mechanism::Password>(type)) {
        indices_.push_back(i);
      }
    }
    if (indices_.empty()) return;
    const auto bounds = guard_->contents()->GetContainerBounds();
    auto* bubble = new NativeAmbientSigninBubble(
        guard_->contents()->GetNativeView(),
        gfx::Rect(bounds.right() - 24, bounds.y() + 8, 1, 1),
        model_->relying_party_id,
        base::BindRepeating([](base::WeakPtr<Ambient> self) {
          return self && self->MaySelect();
        }, weak_factory_.GetWeakPtr()),
        base::BindRepeating(&Ambient::SelectCredential,
                            weak_factory_.GetWeakPtr(), generation_));
    bubble_ = bubble->GetWeakPtr();
    auto weak = weak_factory_.GetWeakPtr();
    security_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged object:guard_->window()
                    queue:nil usingBlock:^(NSNotification*) {
                      if (weak && !weak->MayShow()) weak->Hide();
                    }];
    bubble->ShowCredentials(model_->mechanisms, indices_);
  }
  void Hide() {
    ++generation_;
    if (security_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_];
      security_ = nil;
    }
    auto bubble = std::exchange(bubble_, {});
    if (bubble) bubble->Disconnect();
  }
  void SelectCredential(uint64_t generation, size_t index) {
    if (generation != generation_ || !MaySelect() || index >= indices_.size()) return;
    auto callback = model_->mechanisms.at(indices_.at(index)).callback;
    selection_made_ = true;
    Hide();
    callback.Run();
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) {
      Hide();
    } else if (!bubble_) {
      Reshow();
    }
  }
  void OnStepTransition() override {
    if (model_ && model_->step() != AuthenticatorRequestDialogModel::Step::kPasskeyAutofill)
      Hide();
  }
  void OnRequestComplete() override {
    observation_.Reset();
    model_ = nullptr;
    Hide();
  }
  void OnModelDestroyed(AuthenticatorRequestDialogModel*) override {
    observation_.Reset();
    model_ = nullptr;
    Hide();
  }
 private:
  raw_ptr<AuthenticatorRequestDialogModel> model_;
  const std::shared_ptr<Guard> guard_;
  base::WeakPtr<ambient_signin::AmbientSigninController> controller_;
  base::WeakPtr<NativeAmbientSigninBubble> bubble_;
  std::vector<size_t> indices_;
  uint64_t generation_ = 0;
  bool selection_made_ = false;
  std::vector<base::CallbackListSubscription> subscriptions_;
  base::ScopedObservation<AuthenticatorRequestDialogModel,
                          AuthenticatorRequestDialogModel::Observer> observation_{this};
  id security_;
  base::WeakPtrFactory<Ambient> weak_factory_{this};
};
Context::Context() = default;
Context::~Context() = default;
void Context::PrepareForStepChange(AuthenticatorRequestDialogModel& model) {
  if (guard_ && guard_->Matches(model) && recovery_window_) {
    recovery_window_->Release();
  }
}
std::unique_ptr<NativeAuthenticatorRequestWindow> Context::CreateWindow(
    AuthenticatorRequestDialogModel& model) {
  auto guard = GuardForModel(model);
  if (!guard || !guard->Valid(true)) {
    if (guard) guard->CancelSoon();
    return {};
  }
  auto lease = std::make_unique<WindowLease>(guard);
  recovery_window_ = lease->GetWeakPtr();
  return lease;
}
void Context::ShowAmbient(AuthenticatorRequestDialogModel& model,
    base::WeakPtr<ambient_signin::AmbientSigninController> controller) {
  auto guard = GuardForModel(model);
  if (!guard || !guard->Valid(false)) return;
  if (!ambient_ || !ambient_->Matches(model)) {
    ambient_ = std::make_unique<Ambient>(model, guard, controller);
  }
  ambient_->Show();
}
void Context::HideAmbient() { if (ambient_) ambient_->Hide(); }

void CancelModelSoon(AuthenticatorRequestDialogModel& model) {
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
      FROM_HERE, base::BindOnce(
          [](scoped_refptr<AuthenticatorRequestDialogModel> model) {
            model->CancelAuthenticatorRequest();
          }, base::WrapRefCounted(&model)));
}
bool Context::BeginSettings(content::RenderFrameHost& frame,
                            AuthenticatorRequestDialogModel& model) {

  if (guard_ && !guard_->Matches(model) && guard_->HasModel() && guard_->Valid(false))
    return false;
  if (!frame.IsActive() ||
      GetContext(content::WebContents::FromRenderFrameHost(&frame)) != this)
    return false;
  guard_ = std::make_shared<Guard>(frame, model);
  guard_->ObserveWindow();
  return guard_->Valid(true);
}
std::shared_ptr<Guard> Context::GuardForModel(
    AuthenticatorRequestDialogModel& model) {
  if (guard_ && guard_->Matches(model)) {
    return guard_;
  }
  CancelModelSoon(model);
  return {};
}
std::unique_ptr<AuthenticatorRequestDialogViewController> Context::CreateDialog(
    AuthenticatorRequestDialogModel& model) {
  auto guard = GuardForModel(model);
  if (!guard || !guard->Valid(true)) {
    if (guard) {
      guard->CancelSoon();
    }
    return nullptr;
  }
  Guard::Operation operation(guard);
  return std::make_unique<Controller>(model, guard);
}
}
std::unique_ptr<ChromeAuthenticatorRequestDelegate>
CreateWebAuthenticationRequestDelegate(
    content::RenderFrameHost* render_frame_host) {
  auto request =
      AuthenticatorRequestScheduler::CreateRequestDelegate(render_frame_host);
  if (request) {
    if (auto* native = NativeAuthenticatorRequestContext::Get(
            content::WebContents::FromRenderFrameHost(render_frame_host))) {
      native->Created(*render_frame_host, request->AsWeakPtr());
    }
  }
  return request;
}
void InstallNativeWebAuthn(content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!NativeAuthenticatorRequestContext::Get(&contents)) {
    NativeAuthenticatorRequestContext::Set(contents,
                                           std::make_unique<Context>());
  }
}
void SetNativeWebAuthnAttached(content::WebContents& contents, bool attached) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* context = GetContext(&contents);
  if (!context) {
    return;
  }
  context->attached = attached;
  if (!attached) {
    auto guard = context->guard_;
    if (guard) {
      guard->Cancel();
    }
  }
}
}
