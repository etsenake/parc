// Copyright 2026 Parc contributors.
#include "native_iban_session.h"

#import <Cocoa/Cocoa.h>

#include <optional>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/notreached.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/autofill/payments/iban_bubble_controller_impl.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/autofill/payments/manage_saved_iban_bubble_view.h"
#include "chrome/browser/ui/views/autofill/payments/save_iban_bubble_view.h"
#include "chrome/browser/ui/views/autofill/payments/save_payment_method_and_virtual_card_enroll_confirmation_bubble_views.h"
#include "components/constrained_window/constrained_window_views.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "ui/base/mojom/ui_base_types.mojom-shared.h"
#include "ui/views/bubble/bubble_dialog_delegate_view.h"
#include "ui/views/widget/widget.h"

namespace parc {
using autofill::IbanBubbleType;
using autofill::PaymentsUiClosedReason;
using Confirmation =
    autofill::SavePaymentMethodAndVirtualCardEnrollConfirmationUiParams;

struct NativeIbanSession::Impl {
  BrowserWindowInterface* browser_identity = nullptr;  // Compare only.
  __weak NSView* host;
  __weak NSWindow* window;
  raw_ptr<autofill::IbanBubbleControllerImpl> actual = nullptr;
  base::WeakPtr<autofill::BubbleControllerBase> lifetime;
  base::OnceCallback<void(PaymentsUiClosedReason)> closed;
  std::optional<bool> presented;
  base::OnceCallback<void(bool)> presentation_callback;
  bool presentation_observer_registered = false;
  bool finishing = false;
  bool delete_scheduled = false;
  bool observing_widget = false;
  bool widget_destroying = false;
  int action_depth = 0;
  bool controller_closes_manage = false;
  std::optional<CoreAccountId> upload_account;
  std::optional<PaymentsUiClosedReason> accepted_close;
  std::unique_ptr<Controller> controller;
  raw_ptr<autofill::AutofillLocationBarBubble> view = nullptr;
  // Destroy the view before its controller adapter.
  std::unique_ptr<views::Widget> widget;
};

// The view never borrows the WebContents-owned controller directly. Immutable
// presentation data remain valid during close; every action revalidates the
// exact request and the actual controller lifetime before forwarding.
class NativeIbanSession::Controller final
    : public autofill::IbanBubbleController {
 public:
  Controller(base::WeakPtr<NativeIbanSession> session,
             autofill::IbanBubbleController& actual)
      : session_(session),
        title_(actual.GetWindowTitle()),
        message_(actual.GetExplanatoryMessage()),
        accept_(actual.GetAcceptButtonText()),
        decline_(actual.GetIbanBubbleType() == IbanBubbleType::kManageSavedIban
                     ? std::u16string()
                     : actual.GetDeclineButtonText()),
        iban_(actual.GetIban()),
        legal_(actual.GetLegalMessageLines()),
        type_(actual.GetIbanBubbleType()),
        upload_(actual.IsUploadSave()) {}
  std::u16string GetWindowTitle() const override { return title_; }
  std::u16string GetExplanatoryMessage() const override { return message_; }
  std::u16string GetAcceptButtonText() const override { return accept_; }
  std::u16string GetDeclineButtonText() const override { return decline_; }
  AccountInfo GetAccountInfo() override {
    return session_ && session_->CanAct()
               ? session_->impl_->actual->GetAccountInfo()
               : AccountInfo();
  }
  const autofill::Iban& GetIban() const override { return iban_; }
  const autofill::LegalMessageLines& GetLegalMessageLines() const override {
    return legal_;
  }
  bool IsUploadSave() const override { return upload_; }
  IbanBubbleType GetIbanBubbleType() const override { return type_; }
  const Confirmation& GetConfirmationUiParams() const override {
    NOTREACHED();  // Confirmation uses its actual parameters, not this adapter.
  }
  base::OnceCallback<void(PaymentsUiClosedReason)> GetOnBubbleClosedCallback()
      override {
    return base::BindOnce(&NativeIbanSession::Finish, session_);
  }
  autofill::AutofillBubbleBase* GetPaymentBubbleView() const override {
    return session_.get();
  }
  void OnBubbleClosed(PaymentsUiClosedReason reason) override {
    if (session_)
      session_->Finish(reason);
  }
  void OnAcceptButton(std::u16string_view nickname) override {
    auto session = session_;
    if (!session || !session->CanAct())
      return;
    const auto type = session->impl_->actual->GetIbanBubbleType();
    if (type != IbanBubbleType::kLocalSave &&
        type != IbanBubbleType::kUploadSave)
      return;
    if (type == IbanBubbleType::kLocalSave) {
      session->impl_->accepted_close = PaymentsUiClosedReason::kAccepted;
      session->impl_->widget->GetContentsView()->SetEnabled(false);
    }
    ++session->impl_->action_depth;
    session->impl_->actual->OnAcceptButton(nickname);
    --session->impl_->action_depth;
    session->ScheduleDestruction();
  }
  void OnLegalMessageLinkClicked(const GURL& url) override {
    auto session = session_;
    if (!session || !session->CanAct())
      return;
    ++session->impl_->action_depth;
    session->impl_->actual->OnLegalMessageLinkClicked(url);
    --session->impl_->action_depth;
    session->ScheduleDestruction();
  }
  void OnManageSavedIbanExtraButtonClicked() override {
    auto session = session_;
    if (!session || !session->CanAct() ||
        session->impl_->actual->GetIbanBubbleType() !=
            IbanBubbleType::kManageSavedIban)
      return;
    ++session->impl_->action_depth;
    // The real method opens profile payment settings and closes its own slot.
    // A synchronous tab switch must not deliver a second native close first.
    session->impl_->controller_closes_manage = true;
    session->impl_->actual->OnManageSavedIbanExtraButtonClicked();
    session->impl_->controller_closes_manage = false;
    --session->impl_->action_depth;
    session->Finish(PaymentsUiClosedReason::kClosed);
    session->ScheduleDestruction();
  }

 private:
  base::WeakPtr<NativeIbanSession> session_;
  const std::u16string title_, message_, accept_, decline_;
  const autofill::Iban iban_;
  const autofill::LegalMessageLines legal_;
  const IbanBubbleType type_;
  const bool upload_;
};

bool NativeIbanSession::Supports(
    const autofill::IbanBubbleControllerImpl& actual) {
  const autofill::IbanBubbleController& controller = actual;
  if (!controller.IsUploadSave() && !controller.GetLegalMessageLines().empty())
    return false;
  switch (controller.GetIbanBubbleType()) {
    case IbanBubbleType::kLocalSave:
    case IbanBubbleType::kUploadSave:
    case IbanBubbleType::kUploadInProgress:
    case IbanBubbleType::kManageSavedIban:
    case IbanBubbleType::kUploadCompleted:
      return true;
    case IbanBubbleType::kInactive:
      return false;
  }
}

NativeIbanSession::NativeIbanSession(BrowserWindowInterface& browser,
                                     content::WebContents& contents,
                                     gfx::NativeView page_host,
                                     gfx::NativeWindow window,
                                     autofill::IbanBubbleControllerImpl& actual)
    : content::WebContentsObserver(&contents), impl_(std::make_unique<Impl>()) {
  impl_->browser_identity = &browser;
  impl_->host = page_host.GetNativeNSView();
  impl_->window = window.GetNativeNSWindow();
  impl_->actual = &actual;
  impl_->lifetime = actual.GetBubbleControllerBaseWeakPtr();
  impl_->closed = actual.GetOnBubbleClosedCallback();
  if (static_cast<autofill::IbanBubbleController&>(actual).IsUploadSave()) {
    impl_->upload_account = actual.GetAccountInfo().GetAccountId();
  }
}

NativeIbanSession::~NativeIbanSession() {
  weak_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
  if (impl_->observing_widget) {
    impl_->widget->RemoveObserver(this);
  }
  impl_->view = nullptr;
  impl_->actual = nullptr;
  impl_->widget.reset();
}

NativeIbanSession* NativeIbanSession::Create(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView page_host,
    gfx::NativeWindow window,
    autofill::IbanBubbleControllerImpl& actual) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(Supports(actual));
  CHECK(autofill::IbanBubbleControllerImpl::FromWebContents(&contents) ==
        &actual);
  auto* session =
      new NativeIbanSession(browser, contents, page_host, window, actual);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&NativeIbanSession::Start, session->GetWeakPtr()));
  return session;
}

bool NativeIbanSession::IsCurrent() const {
  return web_contents() && impl_->lifetime &&
         autofill::IbanBubbleControllerImpl::FromWebContents(web_contents()) ==
             impl_->actual &&
         impl_->actual->GetPaymentBubbleView() == this;
}

bool NativeIbanSession::CanAct() const {
  if (impl_->finishing || !IsCurrent()) {
    return false;
  }
  if (impl_->upload_account &&
      (impl_->upload_account->empty() ||
       impl_->actual->GetAccountInfo().GetAccountId() !=
           *impl_->upload_account)) {
    return false;
  }
  auto* tab = tabs::TabInterface::MaybeGetFromContents(web_contents());
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  NSView* page = web_contents()->GetNativeView().GetNativeNSView();
  NSView* host = impl_->host;
  NSWindow* window = impl_->window;
  return tab && tab->IsActivated() && browser &&
         browser == impl_->browser_identity && browser->GetWindow() &&
         web_contents()->GetBrowserContext() == browser->GetProfile() &&
         browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() ==
             window &&
         page && host && window && page.window == window &&
         host.window == window &&
         (page == host || [page isDescendantOf:host]) &&
         !page.isHiddenOrHasHiddenAncestor &&
         !host.isHiddenOrHasHiddenAncestor && window.isVisible &&
         !window.isMiniaturized &&
         web_contents()->GetVisibility() != content::Visibility::HIDDEN;
}

void NativeIbanSession::Start() {
  if (!CanAct()) {
    Finish(PaymentsUiClosedReason::kNotInteracted);
    return;
  }
  const auto type = impl_->actual->GetIbanBubbleType();
  const views::BubbleAnchor anchor(static_cast<views::View*>(nullptr));
  if (type == IbanBubbleType::kUploadCompleted) {
    impl_->view = new autofill::
        SavePaymentMethodAndVirtualCardEnrollConfirmationBubbleViews(
            anchor, web_contents(),
            base::BindOnce(&NativeIbanSession::Finish, GetWeakPtr()),
            impl_->actual->GetConfirmationUiParams());
  } else {
    impl_->controller =
        std::make_unique<Controller>(GetWeakPtr(), *impl_->actual);
    if (type == IbanBubbleType::kManageSavedIban) {
      impl_->view = new autofill::ManageSavedIbanBubbleView(
          anchor, web_contents(), impl_->controller.get());
    } else {
      impl_->view = new autofill::SaveIbanBubbleView(anchor, web_contents(),
                                                     impl_->controller.get());
    }
  }
  auto* view = impl_->view.get();
  view->SetModalType(ui::mojom::ModalType::kChild);
  view->SetArrow(views::BubbleBorder::NONE);
  view->set_close_on_deactivate(false);
  view->set_parent_window(gfx::NativeView(impl_->host));
  // Use the genuine bubble factory so each concrete view's Init() builds its
  // fields, legal links, footnote and loading state before native attachment.
  // The existing native modal bridge then uses this exact page's Cocoa owner.
  impl_->widget = views::BubbleDialogDelegate::CreateBubble(view);
  impl_->widget->AddObserver(this);
  impl_->observing_widget = true;
  auto weak = GetWeakPtr();
  constrained_window::ShowModalDialog(impl_->widget->GetNativeWindow(),
                                      web_contents());
  if (weak && !weak->impl_->finishing && weak->impl_->widget->IsVisible()) {
    weak->ReportPresentation(true);
  }
}

void NativeIbanSession::Finish(PaymentsUiClosedReason reason) {
  if (impl_->finishing) {
    return;
  }
  impl_->finishing = true;
  ReportPresentation(false);
  auto* view = impl_->view.get();
  impl_->view = nullptr;
  if (!impl_->widget_destroying && impl_->widget) {
    if (impl_->widget->GetContentsView()) {
      impl_->widget->GetContentsView()->SetEnabled(false);
    }
    if (view) {
      view->Hide();
    }
  }
  // The real controller may already have installed a replacement, especially
  // upload confirmation. Never send an old close into that new bubble slot.
  auto closed = std::move(impl_->closed);
  if (!impl_->controller_closes_manage && IsCurrent() && closed) {
    std::move(closed).Run(impl_->accepted_close.value_or(reason));
  }
  impl_->actual = nullptr;
  Observe(nullptr);
  ScheduleDestruction();
}

void NativeIbanSession::ScheduleDestruction() {
  if (!impl_->finishing || impl_->delete_scheduled || impl_->action_depth) {
    return;
  }
  impl_->delete_scheduled = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce([](NativeIbanSession* session) { delete session; },
                     base::Unretained(this)));
}

void NativeIbanSession::Hide() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  Finish(PaymentsUiClosedReason::kNotInteracted);
}
bool NativeIbanSession::IsMouseHovered() const {
  return impl_->view && impl_->view->IsMouseHovered();
}
bool NativeIbanSession::IsPresented() const {
  return impl_->presented.value_or(false);
}
void NativeIbanSession::SetPresentationCallback(
    base::OnceCallback<void(bool)> callback) {
  CHECK(!impl_->presentation_observer_registered);
  impl_->presentation_observer_registered = true;
  impl_->presentation_callback = std::move(callback);
  if (impl_->presented && impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativeIbanSession::ReportPresentation(bool presented) {
  if (impl_->presented) {
    return;
  }
  impl_->presented = presented && CanAct();
  if (impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativeIbanSession::WebContentsDestroyed() {
  Hide();
}
void NativeIbanSession::PrimaryPageChanged(content::Page&) {
  Hide();
}
void NativeIbanSession::OnVisibilityChanged(content::Visibility visibility) {
  if (visibility == content::Visibility::HIDDEN) {
    Hide();
  }
}
void NativeIbanSession::OnWidgetVisibilityChanged(views::Widget* widget,
                                                  bool visible) {
  if (impl_->finishing || widget != impl_->widget.get()) {
    return;
  }
  if (visible && CanAct()) {
    ReportPresentation(true);
  } else if (visible || IsPresented()) {
    Hide();
  }
}
void NativeIbanSession::OnWidgetDestroying(views::Widget* widget) {
  if (widget != impl_->widget.get()) {
    return;
  }
  widget->RemoveObserver(this);
  impl_->observing_widget = false;
  impl_->widget_destroying = true;
  impl_->view = nullptr;
  Hide();
}
base::WeakPtr<NativeIbanSession> NativeIbanSession::GetWeakPtr() {
  return weak_factory_.GetWeakPtr();
}
}  // namespace parc
