// Copyright 2026 Parc contributors.
#include "native_payment_consent_session.h"
#import <Cocoa/Cocoa.h>
#include <optional>
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/notreached.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/autofill/personal_data_manager_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/autofill/payments/mandatory_reauth_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/virtual_card_enroll_bubble_controller_impl.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/autofill/payments/mandatory_reauth_confirmation_bubble_view.h"
#include "chrome/browser/ui/views/autofill/payments/mandatory_reauth_opt_in_bubble_view.h"
#include "chrome/browser/ui/views/autofill/payments/save_payment_method_and_virtual_card_enroll_confirmation_bubble_views.h"
#include "chrome/browser/ui/views/autofill/payments/virtual_card_enroll_bubble_views.h"
#include "components/autofill/core/browser/data_manager/personal_data_manager.h"
#include "components/constrained_window/constrained_window_views.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "ui/base/mojom/ui_base_types.mojom-shared.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/views/bubble/bubble_dialog_delegate_view.h"
#include "ui/views/widget/widget.h"

namespace parc {
using autofill::MandatoryReauthBubbleType;
using autofill::PaymentsUiClosedReason;
using Confirmation =
    autofill::SavePaymentMethodAndVirtualCardEnrollConfirmationUiParams;
namespace {
autofill::PaymentsDataManager* Payments(content::WebContents& contents) {
  auto* data = autofill::PersonalDataManagerFactory::GetForBrowserContext(
      contents.GetBrowserContext());
  return data ? &data->payments_data_manager() : nullptr;
}
CoreAccountId PaymentAccount(content::WebContents& contents) {
  auto* data = Payments(contents);
  return data ? data->GetAccountInfoForPaymentsServer().account_id
              : CoreAccountId();
}
}  // namespace
struct NativePaymentConsentSession::Impl {
  BrowserWindowInterface* browser_identity = nullptr;  // Compare only.
  __weak NSView* host;
  __weak NSWindow* window;
  raw_ptr<autofill::VirtualCardEnrollBubbleControllerImpl> virtual_card =
      nullptr;
  raw_ptr<autofill::MandatoryReauthBubbleControllerImpl> reauth = nullptr;
  base::WeakPtr<autofill::BubbleControllerBase> lifetime;
  const void* model_identity =
      nullptr;  // Compare only; the model may be replaced.
  MandatoryReauthBubbleType reauth_type = MandatoryReauthBubbleType::kInactive;
  CoreAccountId account;
  base::OnceCallback<void(PaymentsUiClosedReason)> closed;
  std::optional<bool> presented;
  base::OnceCallback<void(bool)> presentation_callback;
  bool presentation_observer_registered = false;
  bool finishing = false;
  bool delete_scheduled = false;
  bool observing_widget = false;
  bool widget_destroying = false;
  int action_depth = 0;
  std::unique_ptr<VirtualController> virtual_adapter;
  std::unique_ptr<ReauthController> reauth_adapter;
  raw_ptr<autofill::AutofillLocationBarBubble> view = nullptr;
  // Concrete view destruction must precede adapter destruction.
  std::unique_ptr<views::Widget> widget;
};
class NativePaymentConsentSession::Action {
 public:
  explicit Action(NativePaymentConsentSession& session) : session_(session) {
    ++session_.impl_->action_depth;
  }
  ~Action() {
    --session_.impl_->action_depth;
    session_.ScheduleDestruction();
  }

 private:
  NativePaymentConsentSession& session_;
};
class NativePaymentConsentSession::VirtualController final
    : public autofill::VirtualCardEnrollBubbleController {
 public:
  VirtualController(base::WeakPtr<NativePaymentConsentSession> session,
                    autofill::VirtualCardEnrollBubbleControllerImpl& actual)
      : session_(session),
        source_(actual.GetVirtualCardEnrollmentBubbleSource()) {
    auto fields = actual.GetUiModel().enrollment_fields();
    if (fields.card_art_image) {
      image_ = *fields.card_art_image;
      fields.card_art_image = &*image_;
    }
    model_ = std::make_unique<autofill::VirtualCardEnrollUiModel>(fields);
    model_->SetEnrollmentProgress(actual.GetUiModel().enrollment_progress());
  }
  const autofill::VirtualCardEnrollUiModel& GetUiModel() const override {
    return *model_;
  }
  autofill::VirtualCardEnrollmentBubbleSource
  GetVirtualCardEnrollmentBubbleSource() const override {
    return source_;
  }
  autofill::AutofillBubbleBase* GetVirtualCardBubbleView() const override {
    return session_.get();
  }
  void HideIconAndBubble() override {
    auto session = session_;
    if (!session || !session->CanAct())
      return;
    Action action(*session);
    session->impl_->virtual_card->HideIconAndBubble();
  }
  bool IsEnrollmentInProgress() const override {
    return session_ && session_->CanAct() &&
           session_->impl_->virtual_card->IsEnrollmentInProgress();
  }
  bool IsEnrollmentComplete() const override {
    return session_ && session_->CanAct() &&
           session_->impl_->virtual_card->IsEnrollmentComplete();
  }
  bool IsIconVisible() const override {
    return session_ && session_->CanAct() &&
           session_->impl_->virtual_card->IsIconVisible();
  }
  void OnAcceptButton(bool loading) override {
    auto session = session_;
    if (!session)
      return;
    if (!session->CanAct()) {
      session->Hide();
      return;
    }
    if (decision_taken_ ||
        session->impl_->virtual_card->IsEnrollmentInProgress() ||
        session->impl_->virtual_card->IsEnrollmentComplete())
      return;
    decision_taken_ = true;
    Action action(*session);
    session->impl_->virtual_card->OnAcceptButton(loading);
  }
  void OnDeclineButton() override {
    auto session = session_;
    if (!session)
      return;
    if (!session->CanAct()) {
      session->Hide();
      return;
    }
    if (decision_taken_ ||
        session->impl_->virtual_card->IsEnrollmentInProgress() ||
        session->impl_->virtual_card->IsEnrollmentComplete())
      return;
    decision_taken_ = true;
    Action action(*session);
    session->impl_->widget->GetContentsView()->SetEnabled(false);
    session->impl_->virtual_card->OnDeclineButton();
  }
  void OnLinkClicked(autofill::VirtualCardEnrollmentLinkType type,
                     const GURL& url) override {
    auto session = session_;
    if (!session || !session->CanAct() || decision_taken_)
      return;
    Action action(*session);
    session->impl_->virtual_card->OnLinkClicked(type, url);
  }
  void OnBubbleClosed(PaymentsUiClosedReason reason) override {
    if (session_)
      session_->Finish(reason);
  }
  base::OnceCallback<void(PaymentsUiClosedReason)> GetOnBubbleClosedCallback()
      override {
    return base::BindOnce(&NativePaymentConsentSession::Finish, session_);
  }
  const Confirmation& GetConfirmationUiParams() const override { NOTREACHED(); }

 private:
  base::WeakPtr<NativePaymentConsentSession> session_;
  const autofill::VirtualCardEnrollmentBubbleSource source_;
  std::optional<gfx::ImageSkia> image_;
  std::unique_ptr<autofill::VirtualCardEnrollUiModel> model_;
  bool decision_taken_ = false;
};
class NativePaymentConsentSession::ReauthController final
    : public autofill::MandatoryReauthBubbleController {
 public:
  ReauthController(base::WeakPtr<NativePaymentConsentSession> session,
                   autofill::MandatoryReauthBubbleControllerImpl& actual)
      : session_(session),
        title_(actual.GetWindowTitle()),
        accept_(actual.GetAcceptButtonText()),
        cancel_(actual.GetCancelButtonText()),
        explanation_(actual.GetExplanationText()),
        type_(actual.GetMandatoryReauthBubbleType()) {}
  std::u16string GetWindowTitle() const override { return title_; }
  std::u16string GetAcceptButtonText() const override { return accept_; }
  std::u16string GetCancelButtonText() const override { return cancel_; }
  std::u16string GetExplanationText() const override { return explanation_; }
  void OnBubbleClosed(PaymentsUiClosedReason reason) override {
    if (session_)
      session_->Finish(reason);
  }
  autofill::AutofillBubbleBase* GetBubbleView() override {
    return session_.get();
  }
  bool IsIconVisible() override { return session_ && session_->CanAct(); }
  MandatoryReauthBubbleType GetMandatoryReauthBubbleType() const override {
    return type_;
  }
  bool CanOpenSettings() const override {
    return session_ && session_->CanAct();
  }

 private:
  base::WeakPtr<NativePaymentConsentSession> session_;
  const std::u16string title_, accept_, cancel_, explanation_;
  const MandatoryReauthBubbleType type_;
};
bool NativePaymentConsentSession::Supports(
    const autofill::VirtualCardEnrollBubbleControllerImpl& actual) {
  return actual.IsIconVisible();
}
bool NativePaymentConsentSession::Supports(
    const autofill::MandatoryReauthBubbleControllerImpl& actual) {
  const auto type = actual.GetMandatoryReauthBubbleType();
  return type == MandatoryReauthBubbleType::kOptIn ||
         type == MandatoryReauthBubbleType::kConfirmation;
}
NativePaymentConsentSession::NativePaymentConsentSession(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView host,
    gfx::NativeWindow window,
    autofill::VirtualCardEnrollBubbleControllerImpl* virtual_card,
    autofill::MandatoryReauthBubbleControllerImpl* reauth)
    : content::WebContentsObserver(&contents), impl_(std::make_unique<Impl>()) {
  CHECK((virtual_card != nullptr) != (reauth != nullptr));
  impl_->browser_identity = &browser;
  impl_->host = host.GetNativeNSView();
  impl_->window = window.GetNativeNSWindow();
  impl_->virtual_card = virtual_card;
  impl_->reauth = reauth;
  if (virtual_card) {
    impl_->lifetime = virtual_card->GetBubbleControllerBaseWeakPtr();
    impl_->model_identity = &virtual_card->GetUiModel();
    impl_->account = PaymentAccount(contents);
    impl_->closed = virtual_card->GetOnBubbleClosedCallback();
  } else {
    impl_->lifetime = reauth->GetBubbleControllerBaseWeakPtr();
    impl_->reauth_type = reauth->GetMandatoryReauthBubbleType();
    impl_->closed = base::BindOnce(
        [](base::WeakPtr<autofill::BubbleControllerBase> weak,
           PaymentsUiClosedReason reason) {
          if (weak)
            static_cast<autofill::MandatoryReauthBubbleControllerImpl*>(
                weak.get())
                ->OnBubbleClosed(reason);
        },
        impl_->lifetime);
  }
}

NativePaymentConsentSession::~NativePaymentConsentSession() {
  weak_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
  if (impl_->observing_widget) {
    impl_->widget->RemoveObserver(this);
  }
  impl_->view = nullptr;
  impl_->virtual_card = nullptr;
  impl_->reauth = nullptr;
  impl_->widget.reset();
}

NativePaymentConsentSession* NativePaymentConsentSession::Create(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView host,
    gfx::NativeWindow window,
    autofill::VirtualCardEnrollBubbleControllerImpl& actual) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(Supports(actual));
  CHECK(autofill::VirtualCardEnrollBubbleControllerImpl::FromWebContents(
            &contents) == &actual);
  auto* session = new NativePaymentConsentSession(browser, contents, host,
                                                  window, &actual, nullptr);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&NativePaymentConsentSession::Start,
                                session->GetWeakPtr()));
  return session;
}
NativePaymentConsentSession* NativePaymentConsentSession::Create(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView host,
    gfx::NativeWindow window,
    autofill::MandatoryReauthBubbleControllerImpl& actual) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(Supports(actual));
  CHECK(autofill::MandatoryReauthBubbleControllerImpl::FromWebContents(
            &contents) == &actual);
  auto* session = new NativePaymentConsentSession(browser, contents, host,
                                                  window, nullptr, &actual);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&NativePaymentConsentSession::Start,
                                session->GetWeakPtr()));
  return session;
}
bool NativePaymentConsentSession::IsCurrent() const {
  if (!web_contents() || !impl_->lifetime)
    return false;
  if (impl_->virtual_card) {
    auto* actual =
        autofill::VirtualCardEnrollBubbleControllerImpl::FromWebContents(
            web_contents());
    return actual == impl_->virtual_card &&
           &actual->GetUiModel() == impl_->model_identity &&
           actual->GetVirtualCardBubbleView() == this;
  }
  auto* actual = autofill::MandatoryReauthBubbleControllerImpl::FromWebContents(
      web_contents());
  return actual && actual == impl_->reauth &&
         actual->GetMandatoryReauthBubbleType() == impl_->reauth_type &&
         actual->GetBubbleView() == this;
}
bool NativePaymentConsentSession::CanAct() const {
  if (impl_->finishing || !IsCurrent()) {
    return false;
  }
  if (impl_->virtual_card &&
      (impl_->account.empty() ||
       PaymentAccount(*web_contents()) != impl_->account))
    return false;
  if (impl_->reauth_type == MandatoryReauthBubbleType::kConfirmation) {
    auto* data = Payments(*web_contents());
    if (!data || !data->IsPaymentMethodsMandatoryReauthEnabled())
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

void NativePaymentConsentSession::Start() {
  if (!CanAct()) {
    Finish(PaymentsUiClosedReason::kNotInteracted);
    return;
  }
  const views::BubbleAnchor anchor(static_cast<views::View*>(nullptr));
  bool loading = false;
  if (impl_->virtual_card) {
    if (impl_->virtual_card->IsEnrollmentComplete()) {
      impl_->view = new autofill::
          SavePaymentMethodAndVirtualCardEnrollConfirmationBubbleViews(
              anchor, web_contents(),
              base::BindOnce(&NativePaymentConsentSession::Finish,
                             GetWeakPtr()),
              impl_->virtual_card->GetConfirmationUiParams());
    } else {
      impl_->virtual_adapter = std::make_unique<VirtualController>(
          GetWeakPtr(), *impl_->virtual_card);
      impl_->view = new autofill::VirtualCardEnrollBubbleViews(
          anchor, web_contents(), impl_->virtual_adapter.get());
      loading = impl_->virtual_card->IsEnrollmentInProgress();
    }
  } else {
    impl_->reauth_adapter =
        std::make_unique<ReauthController>(GetWeakPtr(), *impl_->reauth);
    if (impl_->reauth_type == MandatoryReauthBubbleType::kOptIn)
      impl_->view = new autofill::MandatoryReauthOptInBubbleView(
          anchor, web_contents(), impl_->reauth_adapter.get());
    else
      impl_->view = new autofill::MandatoryReauthConfirmationBubbleView(
          anchor, web_contents(), impl_->reauth_adapter.get());
  }
  auto* view = impl_->view.get();
  view->SetModalType(ui::mojom::ModalType::kChild);
  view->SetArrow(views::BubbleBorder::NONE);
  view->set_close_on_deactivate(false);
  view->set_parent_window(gfx::NativeView(impl_->host));
  impl_->widget = views::BubbleDialogDelegate::CreateBubble(view);
  if (loading)
    static_cast<autofill::VirtualCardEnrollBubbleViews*>(view)
        ->SwitchToLoadingState();
  impl_->widget->AddObserver(this);
  impl_->observing_widget = true;
  auto weak = GetWeakPtr();
  constrained_window::ShowModalDialog(impl_->widget->GetNativeWindow(),
                                      web_contents());
  if (weak && !weak->impl_->finishing && weak->impl_->widget->IsVisible())
    weak->ReportPresentation(true);
}
void NativePaymentConsentSession::Finish(PaymentsUiClosedReason reason) {
  if (impl_->finishing) {
    return;
  }
  // Reauthentication acceptance is the real security callback. A stale view
  // must never turn a late widget close reason into consent.
  if (!CanAct() && (reason == PaymentsUiClosedReason::kAccepted ||
                    reason == PaymentsUiClosedReason::kCancelled ||
                    reason == PaymentsUiClosedReason::kClosed))
    reason = PaymentsUiClosedReason::kNotInteracted;
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
  if (IsCurrent() && closed) {
    Action action(*this);
    std::move(closed).Run(reason);
  }
  impl_->virtual_card = nullptr;
  impl_->reauth = nullptr;
  Observe(nullptr);
  ScheduleDestruction();
}

void NativePaymentConsentSession::ScheduleDestruction() {
  if (!impl_->finishing || impl_->delete_scheduled || impl_->action_depth) {
    return;
  }
  impl_->delete_scheduled = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](NativePaymentConsentSession* session) { delete session; },
          base::Unretained(this)));
}

void NativePaymentConsentSession::Hide() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  Finish(PaymentsUiClosedReason::kNotInteracted);
}
bool NativePaymentConsentSession::IsMouseHovered() const {
  return impl_->view && impl_->view->IsMouseHovered();
}
bool NativePaymentConsentSession::IsPresented() const {
  return impl_->presented.value_or(false);
}
void NativePaymentConsentSession::SetPresentationCallback(
    base::OnceCallback<void(bool)> callback) {
  CHECK(!impl_->presentation_observer_registered);
  impl_->presentation_observer_registered = true;
  impl_->presentation_callback = std::move(callback);
  if (impl_->presented && impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativePaymentConsentSession::ReportPresentation(bool presented) {
  if (impl_->presented) {
    return;
  }
  impl_->presented = presented && CanAct();
  if (impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativePaymentConsentSession::WebContentsDestroyed() {
  Hide();
}
void NativePaymentConsentSession::PrimaryPageChanged(content::Page&) {
  Hide();
}
void NativePaymentConsentSession::OnVisibilityChanged(
    content::Visibility visibility) {
  if (visibility == content::Visibility::HIDDEN) {
    Hide();
  }
}
void NativePaymentConsentSession::OnWidgetVisibilityChanged(
    views::Widget* widget,
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
void NativePaymentConsentSession::OnWidgetDestroying(views::Widget* widget) {
  if (widget != impl_->widget.get()) {
    return;
  }
  widget->RemoveObserver(this);
  impl_->observing_widget = false;
  impl_->widget_destroying = true;
  impl_->view = nullptr;
  Hide();
}
base::WeakPtr<NativePaymentConsentSession>
NativePaymentConsentSession::GetWeakPtr() {
  return weak_factory_.GetWeakPtr();
}
}  // namespace parc
