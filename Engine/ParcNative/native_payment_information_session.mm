// Copyright 2026 Parc contributors.
#include "native_payment_information_session.h"
#import <Cocoa/Cocoa.h>
#include <array>
#include <optional>
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/autofill/payments/filled_card_information_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/offer_notification_bubble_controller_impl.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/autofill/payments/filled_card_information_bubble_views.h"
#include "chrome/browser/ui/views/autofill/payments/offer_notification_bubble_views.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "ui/views/bubble/bubble_dialog_delegate_view.h"
#include "ui/views/widget/widget.h"
#include "url/origin.h"

namespace parc {
using autofill::PaymentsUiClosedReason;
using Field = autofill::FilledCardInformationBubbleField;
struct NativePaymentInformationSession::Impl {
  BrowserWindowInterface* browser_identity = nullptr;
  __weak NSView* host;
  __weak NSWindow* window;
  raw_ptr<autofill::OfferNotificationBubbleControllerImpl> offer = nullptr;
  raw_ptr<autofill::FilledCardInformationBubbleControllerImpl> filled = nullptr;
  base::WeakPtr<autofill::BubbleControllerBase> lifetime;
  uint64_t request_id = 0;
  bool user_gesture = false;
  std::optional<bool> presented;
  base::OnceCallback<void(bool)> presentation_callback;
  bool presentation_observer_registered = false;
  bool finishing = false;
  bool delete_scheduled = false;
  bool observing_widget = false;
  bool widget_destroying = false;
  int action_depth = 0;
  std::unique_ptr<OfferController> offer_adapter;
  std::unique_ptr<FilledController> filled_adapter;
  raw_ptr<autofill::AutofillLocationBarBubble> view = nullptr;
  std::unique_ptr<views::Widget> widget;
};
class NativePaymentInformationSession::Action {
 public:
  explicit Action(NativePaymentInformationSession& session)
      : session_(session) {
    ++session_.impl_->action_depth;
  }
  ~Action() {
    --session_.impl_->action_depth;
    session_.ScheduleDestruction();
  }

 private:
  NativePaymentInformationSession& session_;
};
class NativePaymentInformationSession::OfferController final
    : public autofill::OfferNotificationBubbleController {
 public:
  OfferController(base::WeakPtr<NativePaymentInformationSession> session,
                  autofill::OfferNotificationBubbleControllerImpl& actual)
      : session_(session),
        offer_(*actual.GetOffer()),
        title_(actual.GetWindowTitle()) {}
  std::u16string GetWindowTitle() const override { return title_; }
  autofill::AutofillBubbleBase* GetOfferNotificationBubbleView()
      const override {
    return session_.get();
  }
  const autofill::AutofillOfferData* GetOffer() const override {
    return &offer_;
  }
  bool IsIconVisible() const override { return session_ && session_->CanAct(); }
  bool CanOpenOfferDetails() const override {
    return session_ && session_->CanAct();
  }
  void OnBubbleClosed(PaymentsUiClosedReason reason) override {
    if (session_)
      session_->Finish(reason);
  }

 private:
  base::WeakPtr<NativePaymentInformationSession> session_;
  const autofill::AutofillOfferData offer_;
  std::u16string title_;
};
class NativePaymentInformationSession::FilledController final
    : public autofill::FilledCardInformationBubbleController {
 public:
  FilledController(base::WeakPtr<NativePaymentInformationSession> session,
                   autofill::FilledCardInformationBubbleControllerImpl& actual)
      : session_(session),
        options_(actual.GetBubbleOptions()),
        title_(actual.GetBubbleTitleText()),
        indicator_(actual.GetCardIndicatorLabel()),
        explanation_(actual.GetEducationalBodyLabel()),
        number_label_(actual.GetCardNumberFieldLabel()),
        expiry_label_(actual.GetExpirationDateFieldLabel()),
        name_label_(actual.GetCardholderNameFieldLabel()),
        cvc_label_(actual.GetCvcFieldLabel()),
        pay_icon_(actual.ShouldShowGooglePayIconInTitle()),
        masked_name_(actual.GetMaskedCardNameForDescriptionView()),
        images_(actual.GetCardImageForDescriptionView()),
        has_link_(actual.EducationalBodyHasLearnMoreLink()) {
    if (has_link_)
      link_ = actual.GetLearnMoreLinkText();
    for (size_t i = 0; i < values_.size(); ++i) {
      values_[i] = actual.GetValueForField(static_cast<Field>(i));
      tooltips_[i] = actual.GetFieldButtonTooltip(static_cast<Field>(i));
    }
  }
  autofill::AutofillBubbleBase* GetBubble() const override {
    return session_.get();
  }
  std::u16string GetBubbleTitleText() const override { return title_; }
  const autofill::FilledCardInformationBubbleOptions& GetBubbleOptions()
      const override {
    return options_;
  }
  std::u16string GetCardIndicatorLabel() const override { return indicator_; }
  std::u16string GetLearnMoreLinkText() const override { return link_; }
  std::u16string GetEducationalBodyLabel() const override {
    return explanation_;
  }
  std::u16string GetCardNumberFieldLabel() const override {
    return number_label_;
  }
  std::u16string GetExpirationDateFieldLabel() const override {
    return expiry_label_;
  }
  std::u16string GetCardholderNameFieldLabel() const override {
    return name_label_;
  }
  std::u16string GetCvcFieldLabel() const override { return cvc_label_; }
  std::u16string GetValueForField(Field field) const override {
    return values_.at(static_cast<size_t>(field));
  }
  std::u16string GetFieldButtonTooltip(Field field) const override {
    return session_ && session_->CanAct()
               ? session_->impl_->filled->GetFieldButtonTooltip(field)
               : tooltips_.at(static_cast<size_t>(field));
  }
  bool ShouldIconBeVisible() const override {
    return session_ && session_->CanAct();
  }
  void OnBubbleClosed(PaymentsUiClosedReason reason) override {
    if (session_)
      session_->Finish(reason);
  }
  void OnLinkClicked() override {
    auto session = session_;
    if (!session || !session->CanAct())
      return;
    Action action(*session);
    session->impl_->filled->OnLinkClicked();
  }
  void OnFieldClicked(Field field) override {
    auto session = session_;
    if (!session || !session->CanAct())
      return;
    Action action(*session);
    session->impl_->filled->OnFieldClicked(field);
  }
  bool ShouldShowGooglePayIconInTitle() const override { return pay_icon_; }
  std::u16string GetMaskedCardNameForDescriptionView() const override {
    return masked_name_;
  }
  std::pair<ui::ImageModel, std::optional<ui::ImageModel>>
  GetCardImageForDescriptionView() const override {
    return images_;
  }
  bool EducationalBodyHasLearnMoreLink() const override { return has_link_; }

 private:
  base::WeakPtr<NativePaymentInformationSession> session_;
  const autofill::FilledCardInformationBubbleOptions options_;
  const std::u16string title_, indicator_, explanation_, number_label_,
      expiry_label_, name_label_, cvc_label_;
  const bool pay_icon_;
  const std::u16string masked_name_;
  const std::pair<ui::ImageModel, std::optional<ui::ImageModel>> images_;
  const bool has_link_;
  std::u16string link_;
  std::array<std::u16string, 5> values_, tooltips_;
};
bool NativePaymentInformationSession::Supports(
    const autofill::OfferNotificationBubbleControllerImpl& actual) {
  const auto* offer = actual.GetOffer();
  return actual.IsIconVisible() && offer &&
         offer->GetOfferType() == autofill::AutofillOfferData::OfferType::WALLET_DIRECT_OFFER &&
         offer->GetOfferDetailsUrl().is_valid();
}
bool NativePaymentInformationSession::Supports(
    const autofill::FilledCardInformationBubbleControllerImpl& actual) {
  return actual.ShouldIconBeVisible() && actual.GetBubbleOptions().IsValid();
}
NativePaymentInformationSession::NativePaymentInformationSession(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView host,
    gfx::NativeWindow window,
    autofill::OfferNotificationBubbleControllerImpl* offer,
    autofill::FilledCardInformationBubbleControllerImpl* filled,
    bool user_gesture)
    : content::WebContentsObserver(&contents), impl_(std::make_unique<Impl>()) {
  CHECK((offer != nullptr) != (filled != nullptr));
  impl_->browser_identity = &browser;
  impl_->host = host.GetNativeNSView();
  impl_->window = window.GetNativeNSWindow();
  impl_->offer = offer;
  impl_->filled = filled;
  impl_->user_gesture = user_gesture;
  impl_->lifetime = offer ? offer->GetBubbleControllerBaseWeakPtr()
                          : filled->GetBubbleControllerBaseWeakPtr();
  impl_->request_id =
      offer ? offer->GetNativeRequestId() : filled->GetNativeRequestId();
}
NativePaymentInformationSession::~NativePaymentInformationSession() {
  weak_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
  if (impl_->observing_widget) {
    impl_->widget->RemoveObserver(this);
  }
  impl_->view = nullptr;
  impl_->offer = nullptr;
  impl_->filled = nullptr;
  impl_->widget.reset();
}

NativePaymentInformationSession* NativePaymentInformationSession::Create(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView host,
    gfx::NativeWindow window,
    autofill::OfferNotificationBubbleControllerImpl& actual,
    bool user_gesture) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(Supports(actual));
  CHECK(autofill::OfferNotificationBubbleControllerImpl::FromWebContents(
            &contents) == &actual);
  auto* session = new NativePaymentInformationSession(
      browser, contents, host, window, &actual, nullptr, user_gesture);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&NativePaymentInformationSession::Start,
                                session->GetWeakPtr()));
  return session;
}
NativePaymentInformationSession* NativePaymentInformationSession::Create(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView host,
    gfx::NativeWindow window,
    autofill::FilledCardInformationBubbleControllerImpl& actual,
    bool user_gesture) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(Supports(actual));
  CHECK(autofill::FilledCardInformationBubbleControllerImpl::FromWebContents(
            &contents) == &actual);
  auto* session = new NativePaymentInformationSession(
      browser, contents, host, window, nullptr, &actual, user_gesture);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&NativePaymentInformationSession::Start,
                                session->GetWeakPtr()));
  return session;
}
bool NativePaymentInformationSession::IsCurrent() const {
  if (!web_contents() || !impl_->lifetime)
    return false;
  if (impl_->offer) {
    auto* actual =
        autofill::OfferNotificationBubbleControllerImpl::FromWebContents(
            web_contents());
    return actual == impl_->offer &&
           actual->GetNativeRequestId() == impl_->request_id &&
           actual->GetOfferNotificationBubbleView() == this;
  }
  auto* actual =
      autofill::FilledCardInformationBubbleControllerImpl::FromWebContents(
          web_contents());
  return actual && actual == impl_->filled &&
         actual->GetNativeRequestId() == impl_->request_id &&
         actual->GetBubble() == this;
}
bool NativePaymentInformationSession::CanAct() const {
  if (impl_->finishing || !IsCurrent())
    return false;
  if (impl_->offer &&
      (!Supports(*impl_->offer) ||
       !impl_->offer->GetOffer()->IsActiveAndEligibleForOrigin(
           url::Origin::Create(web_contents()->GetLastCommittedURL())
               .GetURL())))
    return false;
  if (impl_->filled && !Supports(*impl_->filled))
    return false;
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
void NativePaymentInformationSession::Start() {
  if (!CanAct()) {
    Finish(PaymentsUiClosedReason::kNotInteracted);
    return;
  }
  const views::BubbleAnchor anchor(static_cast<views::View*>(nullptr));
  if (impl_->offer) {
    impl_->offer_adapter =
        std::make_unique<OfferController>(GetWeakPtr(), *impl_->offer);
    impl_->view = new autofill::OfferNotificationBubbleViews(
        anchor, web_contents(), impl_->offer_adapter.get());
  } else {
    impl_->filled_adapter =
        std::make_unique<FilledController>(GetWeakPtr(), *impl_->filled);
    impl_->view = new autofill::FilledCardInformationBubbleViews(
        anchor, web_contents(), impl_->filled_adapter.get());
  }
  auto* view = impl_->view.get();
  view->set_parent_window(gfx::NativeView(impl_->host));
  view->set_close_on_deactivate(false);
  impl_->widget = views::BubbleDialogDelegate::CreateBubble(view);
  view->AdjustForFullscreen(web_contents()->GetContainerBounds());
  impl_->widget->AddObserver(this);
  impl_->observing_widget = true;
  auto weak = GetWeakPtr();
  view->ShowForReason(impl_->user_gesture
                          ? LocationBarBubbleDelegateView::USER_GESTURE
                          : LocationBarBubbleDelegateView::AUTOMATIC,
                      false);
  if (weak && !weak->impl_->finishing && weak->impl_->widget->IsVisible())
    weak->ReportPresentation(true);
}
void NativePaymentInformationSession::Finish(PaymentsUiClosedReason reason) {
  if (impl_->finishing)
    return;
  if (!CanAct())
    reason = PaymentsUiClosedReason::kNotInteracted;
  impl_->finishing = true;
  ReportPresentation(false);
  auto* view = impl_->view.get();
  impl_->view = nullptr;
  if (!impl_->widget_destroying && impl_->widget) {
    if (impl_->widget->GetContentsView())
      impl_->widget->GetContentsView()->SetEnabled(false);
    if (view)
      view->Hide();
  }
  if (IsCurrent()) {
    Action action(*this);
    if (impl_->offer)
      impl_->offer->OnBubbleClosed(reason);
    else
      impl_->filled->OnBubbleClosed(reason);
  }
  impl_->offer = nullptr;
  impl_->filled = nullptr;
  Observe(nullptr);
  ScheduleDestruction();
}
void NativePaymentInformationSession::ScheduleDestruction() {
  if (!impl_->finishing || impl_->delete_scheduled || impl_->action_depth) {
    return;
  }
  impl_->delete_scheduled = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](NativePaymentInformationSession* session) { delete session; },
          base::Unretained(this)));
}

void NativePaymentInformationSession::Hide() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  Finish(PaymentsUiClosedReason::kNotInteracted);
}
bool NativePaymentInformationSession::IsMouseHovered() const {
  return impl_->view && impl_->view->IsMouseHovered();
}
bool NativePaymentInformationSession::IsPresented() const {
  return impl_->presented.value_or(false);
}
void NativePaymentInformationSession::SetPresentationCallback(
    base::OnceCallback<void(bool)> callback) {
  CHECK(!impl_->presentation_observer_registered);
  impl_->presentation_observer_registered = true;
  impl_->presentation_callback = std::move(callback);
  if (impl_->presented && impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativePaymentInformationSession::ReportPresentation(bool presented) {
  if (impl_->presented) {
    return;
  }
  impl_->presented = presented && CanAct();
  if (impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativePaymentInformationSession::WebContentsDestroyed() {
  Hide();
}
void NativePaymentInformationSession::PrimaryPageChanged(content::Page&) {
  Hide();
}
void NativePaymentInformationSession::OnVisibilityChanged(
    content::Visibility visibility) {
  if (visibility == content::Visibility::HIDDEN) {
    Hide();
  }
}
void NativePaymentInformationSession::OnWidgetVisibilityChanged(
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
void NativePaymentInformationSession::OnWidgetDestroying(
    views::Widget* widget) {
  if (widget != impl_->widget.get()) {
    return;
  }
  widget->RemoveObserver(this);
  impl_->observing_widget = false;
  impl_->widget_destroying = true;
  impl_->view = nullptr;
  Hide();
}
base::WeakPtr<NativePaymentInformationSession>
NativePaymentInformationSession::GetWeakPtr() {
  return weak_factory_.GetWeakPtr();
}
}
