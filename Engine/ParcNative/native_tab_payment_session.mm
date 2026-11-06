// Copyright 2026 Parc contributors.
#include "native_tab_payment_session.h"
#import <Cocoa/Cocoa.h>
#include <optional>
#include <utility>
#include "base/check.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/autofill/personal_data_manager_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/autofill/payments/omnibox_autofill_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/payments_churned_users_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/wallet_reminder_notice_bubble_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/autofill/payments/omnibox_autofill_bubble_view.h"
#include "chrome/browser/ui/views/autofill/payments/payments_churned_users_bubble_view.h"
#include "chrome/browser/ui/views/autofill/payments/save_payment_method_and_virtual_card_enroll_confirmation_bubble_views.h"
#include "chrome/browser/ui/views/autofill/payments/wallet_reminder_notice_bubble_view.h"
#include "components/autofill/core/browser/data_manager/personal_data_manager.h"
#include "components/autofill/core/common/autofill_payments_features.h"
#include "components/autofill/core/common/autofill_prefs.h"
#include "components/constrained_window/constrained_window_views.h"
#include "components/prefs/pref_service.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "ui/base/mojom/ui_base_types.mojom-shared.h"
#include "ui/views/bubble/bubble_dialog_delegate_view.h"
#include "ui/views/widget/widget.h"
namespace parc {
using autofill::PaymentsUiClosedReason;
namespace {
CoreAccountId PaymentAccount(content::WebContents& contents) {
  auto* data = autofill::PersonalDataManagerFactory::GetForBrowserContext(
      contents.GetBrowserContext());
  return data ? data->payments_data_manager()
                    .GetAccountInfoForPaymentsServer()
                    .account_id
              : CoreAccountId();
}
}  // namespace
struct NativeTabPaymentSession::Impl {
  Kind kind;
  BrowserWindowInterface* browser_identity = nullptr;
  base::WeakPtr<tabs::TabInterface> tab;
  content::WeakDocumentPtr document;
  __weak NSView* host;
  __weak NSWindow* window;
  base::WeakPtr<autofill::OmniboxAutofillBubbleController> omnibox;
  base::WeakPtr<autofill::PaymentsChurnedUsersBubbleController> churned;
  base::WeakPtr<autofill::WalletReminderNoticeBubbleController> wallet;
  uint64_t request_id = 0;
  CoreAccountId account;
  bool user_gesture = false;
  base::OnceCallback<void(PaymentsUiClosedReason)> closed;
  std::optional<bool> presented;
  base::OnceCallback<void(bool)> presentation_callback;
  bool presentation_observer_registered = false;
  bool finishing = false;
  bool delete_scheduled = false;
  bool observing_widget = false;
  bool widget_destroying = false;
  int action_depth = 0;
  raw_ptr<autofill::AutofillLocationBarBubble> view = nullptr;
  std::unique_ptr<views::Widget> widget;
};
class NativeTabPaymentSession::Action {
 public:
  explicit Action(NativeTabPaymentSession& session) : session_(session) {
    ++session_.impl_->action_depth;
  }
  ~Action() {
    --session_.impl_->action_depth;
    session_.ScheduleDestruction();
  }

 private:
  NativeTabPaymentSession& session_;
};
bool NativeTabPaymentSession::Supports(content::WebContents& contents,
                                       Kind kind) {
  auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
  if (!tab)
    return false;
  switch (kind) {
    case Kind::kOmnibox: {
      auto* actual = autofill::OmniboxAutofillBubbleController::From(*tab);
      return actual && actual->IsNativeRequestCurrent() &&
             actual->GetNativeRequestId() && !actual->GetSuggestions().empty();
    }
    case Kind::kChurnedOffer:
    case Kind::kChurnedConfirmation: {
      auto* actual = autofill::PaymentsChurnedUsersBubbleController::From(*tab);
      return actual && actual->IsNativeRequestCurrent() &&
             actual->GetNativeRequestId() && actual->IsIconVisible() &&
             !actual->GetAccountInfo().IsEmpty() &&
             (actual->GetNativePhase() == 2) ==
                 (kind == Kind::kChurnedConfirmation) &&
             base::FeatureList::IsEnabled(
                 autofill::features::kAutofillEnableResurrectingPaymentsUsers);
    }
    case Kind::kWallet: {
      auto* actual = autofill::WalletReminderNoticeBubbleController::From(*tab);
      return actual && actual->IsNativeRequestCurrent() &&
             actual->GetNativeRequestId() &&
             !actual->GetLegalMessageLines().empty();
    }
  }
}
NativeTabPaymentSession::NativeTabPaymentSession(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView host,
    gfx::NativeWindow window,
    Kind kind,
    bool user_gesture)
    : content::WebContentsObserver(&contents), impl_(std::make_unique<Impl>()) {
  impl_->kind = kind;
  impl_->browser_identity = &browser;
  auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
  CHECK(tab);
  impl_->tab = tab->GetWeakPtr();
  impl_->document = contents.GetPrimaryMainFrame()->GetWeakDocumentPtr();
  impl_->host = host.GetNativeNSView();
  impl_->window = window.GetNativeNSWindow();
  impl_->user_gesture = user_gesture;
  if (kind == Kind::kOmnibox) {
    impl_->omnibox =
        autofill::OmniboxAutofillBubbleController::From(*tab)->GetWeakPtr();
    impl_->request_id = impl_->omnibox->GetNativeRequestId();
    impl_->closed = base::BindOnce(
        &autofill::OmniboxAutofillBubbleController::OnBubbleClosed,
        impl_->omnibox);
  } else if (kind == Kind::kWallet) {
    impl_->wallet = autofill::WalletReminderNoticeBubbleController::From(*tab)
                        ->GetWeakPtr();
    impl_->request_id = impl_->wallet->GetNativeRequestId();
    impl_->account = PaymentAccount(contents);
    impl_->closed = base::BindOnce(
        [](base::WeakPtr<autofill::WalletReminderNoticeBubbleController> actual,
           PaymentsUiClosedReason) {
          if (actual)
            actual->OnBubbleClosed();
        },
        impl_->wallet);
  } else {
    impl_->churned = autofill::PaymentsChurnedUsersBubbleController::From(*tab)
                         ->GetWeakPtr();
    impl_->request_id = impl_->churned->GetNativeRequestId();
    impl_->account = impl_->churned->GetAccountInfo().GetAccountId();
    impl_->closed =
        kind == Kind::kChurnedConfirmation
            ? impl_->churned->GetConfirmationBubbleClosedCallback()
            : base::BindOnce(&autofill::PaymentsChurnedUsersBubbleController::
                                 OnBubbleClosed,
                             impl_->churned);
  }
}
NativeTabPaymentSession::~NativeTabPaymentSession() {
  weak_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
  if (impl_->observing_widget)
    impl_->widget->RemoveObserver(this);
  impl_->view = nullptr;
  impl_->widget.reset();
}
NativeTabPaymentSession* NativeTabPaymentSession::Create(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView host,
    gfx::NativeWindow window,
    Kind kind,
    bool user_gesture) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(Supports(contents, kind));
  auto* session = new NativeTabPaymentSession(browser, contents, host, window,
                                              kind, user_gesture);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&NativeTabPaymentSession::Start, session->GetWeakPtr()));
  return session;
}
// Closure ownership survives document invalidation so the old controller can
// release its exact bubble slot. User actions separately require the document.
bool NativeTabPaymentSession::IsCurrent() const {
  if (!web_contents() || !impl_->tab ||
      impl_->tab->GetContents() != web_contents())
    return false;
  if (impl_->omnibox)
    return autofill::OmniboxAutofillBubbleController::From(*impl_->tab) ==
               impl_->omnibox.get() &&
           impl_->omnibox->GetNativeRequestId() == impl_->request_id &&
           impl_->omnibox->GetBubbleView() == this;
  if (impl_->wallet)
    return autofill::WalletReminderNoticeBubbleController::From(*impl_->tab) ==
               impl_->wallet.get() &&
           impl_->wallet->GetNativeRequestId() == impl_->request_id &&
           impl_->wallet->GetBubbleView() == this;
  return impl_->churned &&
         autofill::PaymentsChurnedUsersBubbleController::From(*impl_->tab) ==
             impl_->churned.get() &&
         impl_->churned->GetNativeRequestId() == impl_->request_id &&
         impl_->churned->GetBubbleView() == this &&
         (impl_->churned->GetNativePhase() == 2) ==
             (impl_->kind == Kind::kChurnedConfirmation);
}
bool NativeTabPaymentSession::OwnsVisiblePage() const {
  if (!IsCurrent() || impl_->document.AsRenderFrameHostIfValid() !=
                          web_contents()->GetPrimaryMainFrame())
    return false;
  auto* browser = impl_->tab->GetBrowserWindowInterface();
  NSView* page = web_contents()->GetNativeView().GetNativeNSView();
  NSView* host = impl_->host;
  NSWindow* window = impl_->window;
  return impl_->tab->IsActivated() && browser &&
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
bool NativeTabPaymentSession::CanAct() const {
  if (impl_->finishing || !OwnsVisiblePage())
    return false;
  if (impl_->omnibox)
    return impl_->omnibox->CanBeReshown();
  if (impl_->account.empty() ||
      PaymentAccount(*web_contents()) != impl_->account)
    return false;
  if (impl_->churned) {
    auto* profile =
        Profile::FromBrowserContext(web_contents()->GetBrowserContext());
    auto* pref = profile->GetPrefs()->FindPreference(
        autofill::prefs::kAutofillCreditCardEnabled);
    if (!pref || profile->IsOffTheRecord())
      return false;
    return impl_->churned->GetNativePhase() == 0
               ? pref->IsUserControlled() && !pref->GetValue()->GetBool()
               : pref->GetValue()->GetBool();
  }
  return true;
}
void NativeTabPaymentSession::Start() {
  if (!CanAct()) {
    Finish(PaymentsUiClosedReason::kNotInteracted);
    return;
  }
  const views::BubbleAnchor anchor(static_cast<views::View*>(nullptr));
  auto can_act = base::BindRepeating(
      [](base::WeakPtr<NativeTabPaymentSession> session) {
        return session && session->CanAct();
      },
      GetWeakPtr());
  auto closed = base::BindOnce(&NativeTabPaymentSession::Finish, GetWeakPtr());
  switch (impl_->kind) {
    case Kind::kOmnibox:
      impl_->view = new autofill::OmniboxAutofillBubbleView(
          anchor, web_contents(), impl_->omnibox.get(), std::move(can_act),
          std::move(closed));
      break;
    case Kind::kWallet:
      impl_->view = new autofill::WalletReminderNoticeBubbleView(
          anchor, web_contents(), impl_->wallet.get(), std::move(can_act),
          base::BindOnce(&NativeTabPaymentSession::Finish, GetWeakPtr(),
                         PaymentsUiClosedReason::kClosed));
      break;
    case Kind::kChurnedOffer:
      impl_->view = new autofill::PaymentsChurnedUsersBubbleView(
          anchor, web_contents(), impl_->churned.get(), std::move(can_act),
          std::move(closed));
      break;
    case Kind::kChurnedConfirmation: {
      auto params = impl_->churned->GetConfirmationUiParams();
      if (params.description_text_link_range_and_callback) {
        auto& callback =
            std::get<2>(*params.description_text_link_range_and_callback);
        callback = base::BindRepeating(
            [](base::WeakPtr<NativeTabPaymentSession> session,
               base::RepeatingClosure original) {
              if (!session || !session->CanAct())
                return;
              Action action(*session);
              original.Run();
            },
            GetWeakPtr(), callback);
      }
      impl_->view = new autofill::
          SavePaymentMethodAndVirtualCardEnrollConfirmationBubbleViews(
              anchor, web_contents(), std::move(closed), std::move(params));
      break;
    }
  }
  auto* view = impl_->view.get();
  view->set_parent_window(gfx::NativeView(impl_->host));
  view->set_close_on_deactivate(false);
  const bool consent = !!impl_->churned;
  if (consent) {
    view->SetModalType(ui::mojom::ModalType::kChild);
    view->SetArrow(views::BubbleBorder::NONE);
  } else {
    view->AdjustForFullscreen(web_contents()->GetContainerBounds());
  }
  impl_->widget = views::BubbleDialogDelegate::CreateBubble(view);
  impl_->widget->AddObserver(this);
  impl_->observing_widget = true;
  auto weak = GetWeakPtr();
  if (consent) {
    constrained_window::ShowModalDialog(impl_->widget->GetNativeWindow(),
                                        web_contents());
  } else {
    view->AdjustForFullscreen(web_contents()->GetContainerBounds());
    auto reason = impl_->user_gesture
                      ? LocationBarBubbleDelegateView::USER_GESTURE
                      : LocationBarBubbleDelegateView::AUTOMATIC;
    if (impl_->omnibox)
      static_cast<autofill::OmniboxAutofillBubbleView*>(view)->Show(reason);
    else
      view->ShowForReason(reason, /*allow_refocus_alert=*/false);
  }
  if (weak && !weak->impl_->finishing && weak->impl_->widget->IsVisible())
    weak->ReportPresentation(true);
}
void NativeTabPaymentSession::Finish(PaymentsUiClosedReason reason) {
  if (impl_->finishing)
    return;
  // A successful fill may legitimately hide its chip before the widget closes.
  // Ownership, rather than post-action eligibility, determines that close.
  if (!OwnsVisiblePage())
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
  auto closed = std::move(impl_->closed);
  if (IsCurrent() && closed) {
    Action action(*this);
    std::move(closed).Run(reason);
  }
  Observe(nullptr);
  ScheduleDestruction();
}
void NativeTabPaymentSession::ScheduleDestruction() {
  if (!impl_->finishing || impl_->delete_scheduled || impl_->action_depth) {
    return;
  }
  impl_->delete_scheduled = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce([](NativeTabPaymentSession* session) { delete session; },
                     base::Unretained(this)));
}

void NativeTabPaymentSession::Hide() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  Finish(PaymentsUiClosedReason::kNotInteracted);
}
bool NativeTabPaymentSession::IsMouseHovered() const {
  return impl_->view && impl_->view->IsMouseHovered();
}
bool NativeTabPaymentSession::IsPresented() const {
  return impl_->presented.value_or(false);
}
void NativeTabPaymentSession::SetPresentationCallback(
    base::OnceCallback<void(bool)> callback) {
  CHECK(!impl_->presentation_observer_registered);
  impl_->presentation_observer_registered = true;
  impl_->presentation_callback = std::move(callback);
  if (impl_->presented && impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativeTabPaymentSession::ReportPresentation(bool presented) {
  if (impl_->presented) {
    return;
  }
  impl_->presented = presented && CanAct();
  if (impl_->presentation_callback) {
    std::move(impl_->presentation_callback).Run(*impl_->presented);
  }
}
void NativeTabPaymentSession::WebContentsDestroyed() {
  Hide();
}
void NativeTabPaymentSession::PrimaryPageChanged(content::Page&) {
  Hide();
}
void NativeTabPaymentSession::OnVisibilityChanged(
    content::Visibility visibility) {
  if (visibility == content::Visibility::HIDDEN) {
    Hide();
  }
}
void NativeTabPaymentSession::OnWidgetVisibilityChanged(views::Widget* widget,
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
void NativeTabPaymentSession::OnWidgetDestroying(views::Widget* widget) {
  if (widget != impl_->widget.get()) {
    return;
  }
  widget->RemoveObserver(this);
  impl_->observing_widget = false;
  impl_->widget_destroying = true;
  impl_->view = nullptr;
  Hide();
}
base::WeakPtr<NativeTabPaymentSession> NativeTabPaymentSession::GetWeakPtr() {
  return weak_factory_.GetWeakPtr();
}
}  // namespace parc
