// Copyright 2026 Parc contributors.
#include "native_card_save_session.h"

#import <Cocoa/Cocoa.h>

#include <optional>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller_impl.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/autofill/payments/save_card_manage_cards_bubble_views.h"
#include "chrome/browser/ui/views/autofill/payments/save_card_offer_bubble_views.h"
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
using autofill::PaymentsBubbleType;
using autofill::PaymentsUiClosedReason;
using CardDetails =
    autofill::payments::PaymentsAutofillClient::UserProvidedCardDetails;
using Confirmation =
    autofill::SavePaymentMethodAndVirtualCardEnrollConfirmationUiParams;

struct NativeCardSaveSession::Impl {
  BrowserWindowInterface* browser_identity = nullptr;
  __weak NSView* host;
  __weak NSWindow* window;
  raw_ptr<autofill::SaveCardBubbleControllerImpl> actual = nullptr;
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
  std::optional<PaymentsUiClosedReason> accepted_close;
  std::unique_ptr<Controller> controller;
  raw_ptr<autofill::AutofillLocationBarBubble> view = nullptr;

  std::unique_ptr<views::Widget> widget;
};

class NativeCardSaveSession::Controller final
    : public autofill::SaveCardBubbleController {
 public:
  Controller(base::WeakPtr<NativeCardSaveSession> session,
             autofill::SaveCardBubbleControllerImpl& actual)
      : session_(session),
        title_(actual.GetWindowTitle()),
        message_(actual.GetExplanatoryMessage()),
        accept_(actual.GetAcceptButtonText()),
        decline_(actual.GetDeclineButtonText()),
        account_(actual.GetAccountInfo()),
        card_(actual.GetCard()),
        image_(actual.GetCreditCardImage()),
        legal_(actual.GetLegalMessageLines()),
        type_(actual.GetPaymentsBubbleType()),
        upload_(actual.IsUploadSave()),
        request_name_(actual.ShouldRequestNameFromUser()),
        request_expiration_(actual.ShouldRequestExpirationDateFromUser()),
        transport_(actual.IsPaymentsSyncTransportEnabledWithoutSyncFeature()) {
    if (type_ == PaymentsBubbleType::kUploadComplete) {
      confirmation_ = actual.GetConfirmationUiParams();
    }
  }
  std::u16string GetWindowTitle() const override { return title_; }
  std::u16string GetExplanatoryMessage() const override { return message_; }
  std::u16string GetAcceptButtonText() const override { return accept_; }
  std::u16string GetDeclineButtonText() const override { return decline_; }
  AccountInfo GetAccountInfo() override {
    return session_ && session_->CanAct()
               ? session_->impl_->actual->GetAccountInfo()
               : account_;
  }
  Profile* GetProfile() const override {
    return session_ && session_->CanAct()
               ? session_->impl_->actual->GetProfile()
               : nullptr;
  }
  const autofill::CreditCard& GetCard() const override { return card_; }
  const Confirmation& GetConfirmationUiParams() const override {
    CHECK(confirmation_);
    return *confirmation_;
  }
  bool ShouldRequestNameFromUser() const override { return request_name_; }
  bool ShouldRequestExpirationDateFromUser() const override {
    return request_expiration_;
  }
  ui::ImageModel GetCreditCardImage() const override { return image_; }
  const autofill::LegalMessageLines& GetLegalMessageLines() const override {
    return legal_;
  }
  bool IsUploadSave() const override { return upload_; }
  bool IsPaymentsSyncTransportEnabledWithoutSyncFeature() const override {
    return transport_;
  }
  PaymentsBubbleType GetPaymentsBubbleType() const override {
    const auto type = session_ && session_->CanAct()
                          ? session_->impl_->actual->GetPaymentsBubbleType()
                          : type_;
    return type == PaymentsBubbleType::kUploadCardholderNameUpdate
               ? PaymentsBubbleType::kUploadSave
               : type;
  }
  base::OnceCallback<void(PaymentsUiClosedReason)>
  GetOnBubbleClosedCallback() override {
    return base::BindOnce(&NativeCardSaveSession::Finish, session_);
  }
  void OnBubbleClosed(PaymentsUiClosedReason reason) override {
    if (session_) {
      session_->Finish(reason);
    }
  }
  void OnSaveButton(const CardDetails& details) override {
    auto session = session_;
    if (!session || !session->CanAct() || session->impl_->accepted_close) {
      return;
    }

    const auto type = session->impl_->actual->GetPaymentsBubbleType();
    if (type == PaymentsBubbleType::kUploadInProgress ||
        type == PaymentsBubbleType::kUploadComplete ||
        type == PaymentsBubbleType::kInactive) {
      return;
    }
    if (type != PaymentsBubbleType::kUploadSave &&
        type != PaymentsBubbleType::kUploadCardholderNameUpdate) {
      session->impl_->accepted_close = PaymentsUiClosedReason::kAccepted;
      session->impl_->widget->GetContentsView()->SetEnabled(false);
    }
    ++session->impl_->action_depth;
    session->impl_->actual->OnSaveButton(details);
    --session->impl_->action_depth;
    session->ScheduleDestruction();
  }
  void OnLegalMessageLinkClicked(const GURL& url) override {
    auto session = session_;
    if (!session || !session->CanAct()) {
      return;
    }
    ++session->impl_->action_depth;
    session->impl_->actual->OnLegalMessageLinkClicked(url);
    --session->impl_->action_depth;
    session->ScheduleDestruction();
  }
  void OnManageCardsClicked() override {
    auto session = session_;
    if (!session || !session->CanAct()) {
      return;
    }
    ++session->impl_->action_depth;
    session->impl_->actual->OnManageCardsClicked();
    --session->impl_->action_depth;
    session->ScheduleDestruction();
  }
  void HideSaveCardBubble() override {
    if (session_) {
      session_->Hide();
    }
  }

 private:
  base::WeakPtr<NativeCardSaveSession> session_;
  const std::u16string title_, message_, accept_, decline_;
  const AccountInfo account_;
  const autofill::CreditCard card_;
  const ui::ImageModel image_;
  const autofill::LegalMessageLines legal_;
  const PaymentsBubbleType type_;
  const bool upload_, request_name_, request_expiration_, transport_;
  std::optional<Confirmation> confirmation_;
};

bool NativeCardSaveSession::Supports(
    const autofill::SaveCardBubbleControllerImpl& controller) {
  const bool name = controller.ShouldRequestNameFromUser();
  const bool expiration = controller.ShouldRequestExpirationDateFromUser();
  const auto type = controller.GetPaymentsBubbleType();

  if ((name && expiration) ||
      (expiration &&
       type == PaymentsBubbleType::kUploadCardholderNameUpdate) ||
      ((name || expiration) &&
       (type != PaymentsBubbleType::kUploadSave &&
        type != PaymentsBubbleType::kUploadCardholderNameUpdate &&
        type != PaymentsBubbleType::kUploadInProgress &&
        type != PaymentsBubbleType::kUploadComplete)) ||
      (!controller.IsUploadSave() &&
       !controller.GetLegalMessageLines().empty())) {
    return false;
  }
  switch (controller.GetPaymentsBubbleType()) {
    case PaymentsBubbleType::kLocalSave:
    case PaymentsBubbleType::kLocalCvcSave:
    case PaymentsBubbleType::kUploadSave:
    case PaymentsBubbleType::kUploadCardholderNameUpdate:
    case PaymentsBubbleType::kUploadCvcSave:
    case PaymentsBubbleType::kUploadInProgress:
    case PaymentsBubbleType::kManageCards:
    case PaymentsBubbleType::kUploadComplete:
      return true;
    case PaymentsBubbleType::kInactive:
      return false;
  }
}

NativeCardSaveSession::NativeCardSaveSession(
    BrowserWindowInterface& browser, content::WebContents& contents,
    gfx::NativeView page_host, gfx::NativeWindow window,
    autofill::SaveCardBubbleControllerImpl& actual)
    : content::WebContentsObserver(&contents), impl_(std::make_unique<Impl>()) {
  impl_->browser_identity = &browser;
  impl_->host = page_host.GetNativeNSView();
  impl_->window = window.GetNativeNSWindow();
  impl_->actual = &actual;
  impl_->lifetime = actual.GetBubbleControllerBaseWeakPtr();
  impl_->closed = actual.GetOnBubbleClosedCallback();
}

NativeCardSaveSession::~NativeCardSaveSession() {
  weak_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
  if (impl_->observing_widget) {
    impl_->widget->RemoveObserver(this);
  }
  impl_->view = nullptr;
  impl_->actual = nullptr;
  impl_->widget.reset();
}

NativeCardSaveSession* NativeCardSaveSession::Create(
    BrowserWindowInterface& browser, content::WebContents& contents,
    gfx::NativeView page_host, gfx::NativeWindow window,
    autofill::SaveCardBubbleControllerImpl& actual) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(Supports(actual));
  CHECK(autofill::SaveCardBubbleControllerImpl::FromWebContents(&contents) ==
        &actual);
  auto* session =
      new NativeCardSaveSession(browser, contents, page_host, window, actual);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&NativeCardSaveSession::Start,
                                session->GetWeakPtr()));
  return session;
}

bool NativeCardSaveSession::IsCurrent() const {
  return web_contents() && impl_->lifetime &&
         autofill::SaveCardBubbleControllerImpl::FromWebContents(
             web_contents()) == impl_->actual &&
         impl_->actual->GetPaymentBubbleView() == this;
}

bool NativeCardSaveSession::CanAct() const {
  if (impl_->finishing || !IsCurrent()) {
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
         browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window &&
         page && host && window && page.window == window &&
         host.window == window &&
         (page == host || [page isDescendantOf:host]) &&
         !page.isHiddenOrHasHiddenAncestor &&
         !host.isHiddenOrHasHiddenAncestor && window.isVisible &&
         !window.isMiniaturized &&
         web_contents()->GetVisibility() != content::Visibility::HIDDEN;
}

void NativeCardSaveSession::Start() {
  if (!CanAct()) {
    Finish(PaymentsUiClosedReason::kNotInteracted);
    return;
  }
  const auto type = impl_->actual->GetPaymentsBubbleType();
  const views::BubbleAnchor anchor(static_cast<views::View*>(nullptr));
  if (type == PaymentsBubbleType::kUploadComplete) {
    impl_->view = new autofill::
        SavePaymentMethodAndVirtualCardEnrollConfirmationBubbleViews(
            anchor, web_contents(),
            base::BindOnce(&NativeCardSaveSession::Finish, GetWeakPtr()),
            impl_->actual->GetConfirmationUiParams());
  } else {
    impl_->controller =
        std::make_unique<Controller>(GetWeakPtr(), *impl_->actual);
    if (type == PaymentsBubbleType::kManageCards) {
      impl_->view = new autofill::SaveCardManageCardsBubbleViews(
          anchor, web_contents(), impl_->controller.get());
    } else {
      impl_->view = new autofill::SaveCardOfferBubbleViews(
          anchor, web_contents(), impl_->controller.get());
    }
  }
  auto* view = impl_->view.get();
  view->SetModalType(ui::mojom::ModalType::kChild);
  view->SetArrow(views::BubbleBorder::NONE);
  view->set_close_on_deactivate(false);
  view->set_parent_window(gfx::NativeView(impl_->host));

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

void NativeCardSaveSession::Finish(PaymentsUiClosedReason reason) {
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

  auto closed = std::move(impl_->closed);
  if (IsCurrent() && closed) {
    std::move(closed).Run(impl_->accepted_close.value_or(reason));
  }
  impl_->actual = nullptr;
  Observe(nullptr);
  ScheduleDestruction();
}

void NativeCardSaveSession::ScheduleDestruction() {
  if (!impl_->finishing || impl_->delete_scheduled || impl_->action_depth) {
    return;
  }
  impl_->delete_scheduled = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce([](NativeCardSaveSession* session) { delete session; },
                     base::Unretained(this)));
}

void NativeCardSaveSession::Hide() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  Finish(PaymentsUiClosedReason::kNotInteracted);
}
bool NativeCardSaveSession::IsMouseHovered() const {
  return impl_->view && impl_->view->IsMouseHovered();
}
bool NativeCardSaveSession::IsPresented() const {
  return impl_->presented.value_or(false);
}
void NativeCardSaveSession::SetPresentationCallback(
    base::OnceCallback<void(bool)> callback) {
  CHECK(!impl_->presentation_observer_registered);
  impl_->presentation_observer_registered = true;
  impl_->presentation_callback = std::move(callback);
  if (impl_->presented && impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativeCardSaveSession::ReportPresentation(bool presented) {
  if (impl_->presented) {
    return;
  }
  impl_->presented = presented && CanAct();
  if (impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativeCardSaveSession::WebContentsDestroyed() {
  Hide();
}
void NativeCardSaveSession::PrimaryPageChanged(content::Page&) {
  Hide();
}
void NativeCardSaveSession::OnVisibilityChanged(content::Visibility visibility) {
  if (visibility == content::Visibility::HIDDEN) {
    Hide();
  }
}
void NativeCardSaveSession::OnWidgetVisibilityChanged(views::Widget* widget,
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
void NativeCardSaveSession::OnWidgetDestroying(views::Widget* widget) {
  if (widget != impl_->widget.get()) {
    return;
  }
  widget->RemoveObserver(this);
  impl_->observing_widget = false;
  impl_->widget_destroying = true;
  impl_->view = nullptr;
  Hide();
}
base::WeakPtr<NativeCardSaveSession> NativeCardSaveSession::GetWeakPtr() {
  return weak_factory_.GetWeakPtr();
}
}
