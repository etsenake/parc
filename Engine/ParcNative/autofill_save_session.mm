#include "autofill_save_session.h"

#include <utility>

#import "autofill_save_presenter.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/ptr_util.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/autofill/personal_data_manager_factory.h"
#include "chrome/browser/autofill/ui/ui_util.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/autofill/address_bubbles_controller.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/update_address_bubble_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/autofill/save_address_profile_view.h"
#include "chrome/browser/ui/views/autofill/update_address_profile_view.h"
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
#include "chrome/browser/signin/account_consistency_mode_manager.h"
#include "chrome/browser/signin/identity_manager_factory.h"
#include "chrome/browser/signin/signin_promo_util.h"
#include "chrome/browser/signin/signin_util.h"
#include "chrome/browser/ui/signin/promos/bubble_signin_promo_delegate.h"
#include "chrome/browser/ui/views/autofill/address_sign_in_promo_view.h"
#include "components/signin/public/identity_manager/identity_manager.h"
#endif
#include "components/autofill/core/browser/data_manager/personal_data_manager.h"
#include "components/constrained_window/constrained_window_views.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "ui/base/mojom/ui_base_types.mojom-shared.h"
#include "ui/views/bubble/bubble_border.h"
#include "ui/views/widget/widget.h"

namespace parc {
using autofill::AutofillClient;
using autofill::PaymentsBubbleType;
using autofill::PaymentsUiClosedReason;

namespace {
bool AccountAddressStorageIsEligible(content::WebContents& contents) {
  auto* pdm = autofill::PersonalDataManagerFactory::GetForBrowserContext(
      contents.GetBrowserContext());
  return pdm &&
         pdm->address_data_manager().IsEligibleForAddressAccountStorage();
}

// Account-specific strings and images are captured from the real controller
// while its account is valid. Theme/layout queries must not dereference a
// primary account that was subsequently removed. Actions still use the owned
// production controller and revalidate that original account.
class NativeSaveAddressController final
    : public autofill::SaveAddressBubbleController {
 public:
  NativeSaveAddressController(
      content::WebContents* contents,
      std::unique_ptr<autofill::SaveAddressBubbleController> controller,
      base::RepeatingCallback<bool()> can_act,
      base::RepeatingCallback<bool()> is_current,
      base::OnceClosure closed)
      : SaveAddressBubbleController({},
                                    contents,
                                    controller->GetAutofillProfile(),
                                    controller->GetSaveAddressBubbleType()),
        controller_(std::move(controller)),
        can_act_(std::move(can_act)),
        is_current_(std::move(is_current)),
        closed_(std::move(closed)),
        title_(controller_->GetWindowTitle()),
        images_(controller_->GetHeaderImages()),
        body_(controller_->GetBodyText()),
        summary_(controller_->GetAddressSummary()),
        email_(controller_->GetProfileEmail()),
        phone_(controller_->GetProfilePhone()),
        ok_(controller_->GetOkButtonLabel()),
        cancel_(controller_->GetCancelCallbackValue()),
        footer_(controller_->GetFooterMessage()),
        editor_footer_(controller_->GetEditorFooterMessage()) {}

  std::u16string GetWindowTitle() const override { return title_; }
  std::optional<HeaderImages> GetHeaderImages() const override {
    return images_;
  }
  std::u16string GetBodyText() const override { return body_; }
  std::u16string GetAddressSummary() const override { return summary_; }
  std::u16string GetProfileEmail() const override { return email_; }
  std::u16string GetProfilePhone() const override { return phone_; }
  std::u16string GetOkButtonLabel() const override { return ok_; }
  AutofillClient::AddressPromptUserDecision GetCancelCallbackValue()
      const override {
    return cancel_;
  }
  std::u16string GetFooterMessage() const override { return footer_; }
  std::u16string GetEditorFooterMessage() const override {
    return editor_footer_;
  }
  void OnUserDecision(
      AutofillClient::AddressPromptUserDecision decision,
      base::optional_ref<const autofill::AutofillProfile> profile) override {
    if (controller_ && can_act_.Run()) {
      controller_->OnUserDecision(decision, profile);
    }
  }
  void OnEditButtonClicked() override {
    if (controller_ && can_act_.Run()) {
      controller_->OnEditButtonClicked();
    }
  }
  void OnBubbleClosed() override {
    if (!controller_) {
      return;
    }
    auto controller = std::move(controller_);
    auto closed = std::move(closed_);
    if (is_current_.Run()) {
      controller->OnBubbleClosed();
    }
    if (closed) {
      std::move(closed).Run();
    }
  }

 private:
  std::unique_ptr<autofill::SaveAddressBubbleController> controller_;
  base::RepeatingCallback<bool()> can_act_;
  base::RepeatingCallback<bool()> is_current_;
  base::OnceClosure closed_;
  const std::u16string title_;
  const std::optional<HeaderImages> images_;
  const std::u16string body_;
  const std::u16string summary_;
  const std::u16string email_;
  const std::u16string phone_;
  const std::u16string ok_;
  const AutofillClient::AddressPromptUserDecision cancel_;
  const std::u16string footer_;
  const std::u16string editor_footer_;
};

#if BUILDFLAG(ENABLE_DICE_SUPPORT)
class NativeAddressSignInDelegate final
    : public BubbleSignInPromoForSyncableDataTypeDelegate {
 public:
  NativeAddressSignInDelegate(content::WebContents& contents,
                              const autofill::AutofillProfile& profile,
                              base::RepeatingCallback<bool()> can_act)
      : BubbleSignInPromoForSyncableDataTypeDelegate(
            contents,
            signin_metrics::AccessPoint::kAddressBubble,
            syncer::LocalDataItemModel::DataId(profile.guid())),
        can_act_(std::move(can_act)) {}
  bool CanSignIn() const override { return can_act_.Run(); }

 private:
  base::RepeatingCallback<bool()> can_act_;
};

// Retain the complete upstream account picker, artwork and layout, replacing
// only close bookkeeping so an old native view cannot clear a newer request.
class NativeAddressSignInView final : public autofill::AddressSignInPromoView {
 public:
  NativeAddressSignInView(content::WebContents* contents,
                          const autofill::AutofillProfile& profile,
                          std::unique_ptr<BubbleSignInPromoDelegate> delegate,
                          base::RepeatingCallback<bool()> is_current,
                          base::OnceClosure closed)
      : AddressSignInPromoView(
            views::BubbleAnchor(static_cast<views::View*>(nullptr)),
            contents,
            profile,
            std::move(delegate)),
        is_current_(std::move(is_current)),
        closed_(std::move(closed)) {}
  void Hide() override {
    AddressSignInPromoView::Hide();
    Finish();
  }
  void WindowClosing() override { Finish(); }

 private:
  void Finish() {
    if (!closed_) {
      return;
    }
    auto closed = std::move(closed_);
    if (is_current_.Run()) {
      autofill::AddressBubblesController::FromWebContents(web_contents())
          ->OnBubbleClosed();
    }
    std::move(closed).Run();
  }
  base::RepeatingCallback<bool()> is_current_;
  base::OnceClosure closed_;
};
#endif

// Retain the genuine diff/edit controller and its original request ownership.
class NativeUpdateController final
    : public autofill::UpdateAddressBubbleController {
 public:
  NativeUpdateController(
      content::WebContents* contents,
      std::unique_ptr<autofill::UpdateAddressBubbleController> controller,
      base::RepeatingCallback<bool()> can_act,
      base::RepeatingCallback<bool()> is_current,
      base::OnceClosure closed)
      : UpdateAddressBubbleController({},
                                      contents,
                                      controller->GetProfileToSave(),
                                      controller->GetOriginalProfile()),
        controller_(std::move(controller)),
        can_act_(std::move(can_act)),
        is_current_(std::move(is_current)),
        closed_(std::move(closed)),
        footer_(controller_->GetFooterMessage()) {}

  std::u16string GetWindowTitle(bool empty) const override {
    return controller_->GetWindowTitle(empty);
  }
  std::u16string GetFooterMessage() const override { return footer_; }
  std::u16string GetPositiveButtonText(bool empty) const override {
    return controller_->GetPositiveButtonText(empty);
  }
  std::u16string GetNegativeButtonText(bool empty) const override {
    return controller_->GetNegativeButtonText(empty);
  }
  const autofill::AutofillProfile& GetProfileToSave() const override {
    return controller_->GetProfileToSave();
  }
  const autofill::AutofillProfile& GetOriginalProfile() const override {
    return controller_->GetOriginalProfile();
  }
  void OnUserDecision(
      AutofillClient::AddressPromptUserDecision decision,
      base::optional_ref<const autofill::AutofillProfile> profile) override {
    if (controller_ && can_act_.Run()) {
      controller_->OnUserDecision(decision, profile);
    }
  }
  void OnEditButtonClicked() override {
    if (controller_ && can_act_.Run()) {
      controller_->OnEditButtonClicked();
    }
  }
  void OnBubbleClosed() override {
    if (!controller_) {
      return;
    }
    // Retire first. Controller callbacks can hide this request and install a
    // replacement; this old view must never clear that replacement's pointer.
    auto controller = std::move(controller_);
    auto closed = std::move(closed_);
    const bool current = is_current_.Run();
    if (current) {
      controller->OnBubbleClosed();
    }
    if (closed) {
      std::move(closed).Run();
    }
  }

 private:
  std::unique_ptr<autofill::UpdateAddressBubbleController> controller_;
  base::RepeatingCallback<bool()> can_act_;
  base::RepeatingCallback<bool()> is_current_;
  base::OnceClosure closed_;
  const std::u16string footer_;
};
}  // namespace

struct NativeAutofillSaveSession::Impl {
  BrowserWindowInterface* browser_identity = nullptr;  // Compare, never own.
  __weak NSView* page_host;
  __weak NSWindow* window;
  PCAutofillSavePresenter* __strong presenter;
  std::optional<bool> presentation;
  bool observer_registered = false;
  base::OnceCallback<void(bool)> presentation_callback;
  std::unique_ptr<autofill::SaveAddressBubbleController> address;
  bool address_update = false;
  bool account_address = false;
  std::optional<CoreAccountId> account_identity;
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  std::optional<autofill::AutofillProfile> sign_in_profile;
  std::optional<CoreAccountId> sign_in_account;
  std::optional<signin_util::SignedInState> sign_in_state;
#endif
  std::unique_ptr<autofill::UpdateAddressBubbleController> update;
  std::unique_ptr<views::Widget> address_widget;
  bool observing_address_widget = false;
  raw_ptr<autofill::AddressBubbleBaseView> address_view = nullptr;
  autofill::SaveCardBubbleControllerImpl* card = nullptr;
  base::WeakPtr<autofill::BubbleControllerBase> card_lifetime;
  base::OnceCallback<void(PaymentsUiClosedReason)> card_closed;
  bool interrupted = false;
  bool completing = false;
  bool accepting_card = false;
};

bool NativeAutofillSaveSession::SupportsLocalCard(
    const autofill::SaveCardBubbleControllerImpl& controller) {
  return controller.GetPaymentsBubbleType() == PaymentsBubbleType::kLocalSave &&
         !controller.IsUploadSave() &&
         !controller.ShouldRequestNameFromUser() &&
         !controller.ShouldRequestExpirationDateFromUser() &&
         controller.GetLegalMessageLines().empty();
}
bool NativeAutofillSaveSession::SupportsLocalAddress(
    const autofill::SaveAddressBubbleController& controller) {
  return controller.GetSaveAddressBubbleType() ==
             AutofillClient::SaveAddressBubbleType::kSave &&
         !controller.GetAutofillProfile().IsAccountProfile() &&
         controller.GetCancelCallbackValue() ==
             AutofillClient::AddressPromptUserDecision::kDeclined;
}

bool NativeAutofillSaveSession::SupportsAccountAddress(
    const autofill::SaveAddressBubbleController& controller) {
  using Type = AutofillClient::SaveAddressBubbleType;
  const bool account_mode =
      (controller.GetSaveAddressBubbleType() == Type::kSave &&
       controller.GetAutofillProfile().IsAccountProfile()) ||
      controller.GetSaveAddressBubbleType() == Type::kMigrateToAccount ||
      controller.GetSaveAddressBubbleType() == Type::kHomeWorkNameEmailMerge;
  // Upstream migration/account footer getters require a real primary account.
  // Availability never creates one or changes the importer's eligibility.
  if (!account_mode || !controller.web_contents()) {
    return false;
  }
  auto account = autofill::GetPrimaryAccountInfoFromBrowserContext(
      controller.web_contents()->GetBrowserContext());
  return account && !account->IsEmpty() && !account->GetAccountId().empty() &&
         !account->GetEmail().empty() &&
         AccountAddressStorageIsEligible(*controller.web_contents());
}

NativeAutofillSaveSession::NativeAutofillSaveSession(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView page_host,
    gfx::NativeWindow window)
    : content::WebContentsObserver(&contents), impl_(std::make_unique<Impl>()) {
  DCHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
  CHECK(tab && tab->GetBrowserWindowInterface() == &browser);
  CHECK(contents.GetBrowserContext() == browser.GetProfile());
  impl_->browser_identity = &browser;
  impl_->page_host = page_host.GetNativeNSView();
  impl_->window = window.GetNativeNSWindow();
}
NativeAutofillSaveSession::~NativeAutofillSaveSession() {
  DCHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  weak_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
  [impl_->presenter invalidate];
  if (impl_->observing_address_widget) {
    impl_->address_widget->RemoveObserver(this);
    impl_->observing_address_widget = false;
  }
}

NativeAutofillSaveSession* NativeAutofillSaveSession::CreateLocalCard(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView page_host,
    gfx::NativeWindow window,
    autofill::SaveCardBubbleControllerImpl& controller) {
  DCHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  CHECK(SupportsLocalCard(controller));
  CHECK(autofill::SaveCardBubbleControllerImpl::FromWebContents(&contents) ==
        &controller);
  auto* session =
      new NativeAutofillSaveSession(browser, contents, page_host, window);
  session->impl_->card = &controller;
  session->impl_->card_lifetime = controller.GetBubbleControllerBaseWeakPtr();
  session->impl_->card_closed = controller.GetOnBubbleClosedCallback();
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&NativeAutofillSaveSession::Start, session->GetWeakPtr()));
  return session;
}
NativeAutofillSaveSession* NativeAutofillSaveSession::CreateLocalAddress(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView page_host,
    gfx::NativeWindow window,
    std::unique_ptr<autofill::SaveAddressBubbleController> controller) {
  DCHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  CHECK(controller && SupportsLocalAddress(*controller));
  CHECK(controller->web_contents() == &contents);
  auto* session =
      new NativeAutofillSaveSession(browser, contents, page_host, window);
  session->impl_->address = std::move(controller);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&NativeAutofillSaveSession::Start, session->GetWeakPtr()));
  return session;
}

NativeAutofillSaveSession* NativeAutofillSaveSession::CreateAddressUpdate(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView page_host,
    gfx::NativeWindow window,
    std::unique_ptr<autofill::UpdateAddressBubbleController> controller) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(controller && controller->web_contents() == &contents);
  std::optional<CoreAccountId> account_identity;
  if (controller->GetProfileToSave().IsAccountProfile()) {
    auto account = autofill::GetPrimaryAccountInfoFromBrowserContext(
        contents.GetBrowserContext());
    if (!account || account->IsEmpty() || account->GetAccountId().empty() ||
        account->GetEmail().empty() ||
        !AccountAddressStorageIsEligible(contents)) {
      return nullptr;
    }
    account_identity = account->GetAccountId();
  }
  auto* session =
      new NativeAutofillSaveSession(browser, contents, page_host, window);
  session->impl_->account_identity = std::move(account_identity);
  session->impl_->address_update = true;
  session->impl_->update = std::move(controller);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&NativeAutofillSaveSession::Start, session->GetWeakPtr()));
  return session;
}

NativeAutofillSaveSession* NativeAutofillSaveSession::CreateAccountAddress(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView page_host,
    gfx::NativeWindow window,
    std::unique_ptr<autofill::SaveAddressBubbleController> controller) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(controller && SupportsAccountAddress(*controller));
  CHECK(controller->web_contents() == &contents);
  auto* session =
      new NativeAutofillSaveSession(browser, contents, page_host, window);
  session->impl_->account_address = true;
  session->impl_->account_identity =
      autofill::GetPrimaryAccountInfoFromBrowserContext(
          contents.GetBrowserContext())
          ->GetAccountId();
  session->impl_->address = std::move(controller);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&NativeAutofillSaveSession::Start, session->GetWeakPtr()));
  return session;
}

#if BUILDFLAG(ENABLE_DICE_SUPPORT)
NativeAutofillSaveSession* NativeAutofillSaveSession::CreateAddressSignInPromo(
    BrowserWindowInterface& browser,
    content::WebContents& contents,
    gfx::NativeView page_host,
    gfx::NativeWindow window,
    const autofill::AutofillProfile& profile) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* session =
      new NativeAutofillSaveSession(browser, contents, page_host, window);
  session->impl_->sign_in_profile = profile;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&NativeAutofillSaveSession::Start, session->GetWeakPtr()));
  return session;
}
#endif

bool NativeAutofillSaveSession::ContextIsValid() const {
  if (impl_->interrupted || !web_contents()) {
    return false;
  }
  NSView* host = impl_->page_host;
  NSWindow* window = impl_->window;
  NSView* content = web_contents()->GetNativeView().GetNativeNSView();
  if (!host || !window || !content || host.window != window ||
      content.window != window ||
      (content != host && ![content isDescendantOf:host])) {
    return false;
  }
  auto* tab = tabs::TabInterface::MaybeGetFromContents(web_contents());
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  const bool native_address = impl_->address_update || impl_->account_address
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
                              || impl_->sign_in_profile.has_value()
#endif
      ;
  if (native_address &&
      (!tab || !tab->IsActivated() ||
       web_contents()->GetVisibility() == content::Visibility::HIDDEN ||
       content.isHiddenOrHasHiddenAncestor ||
       host.isHiddenOrHasHiddenAncestor || !window.isVisible ||
       window.isMiniaturized)) {
    return false;
  }
  if (impl_->account_identity) {
    auto account = autofill::GetPrimaryAccountInfoFromBrowserContext(
        web_contents()->GetBrowserContext());
    if (!account || account->IsEmpty() ||
        account->GetAccountId() != *impl_->account_identity ||
        !AccountAddressStorageIsEligible(*web_contents())) {
      return false;
    }
  }
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  if (impl_->sign_in_account) {
    auto* profile =
        Profile::FromBrowserContext(web_contents()->GetBrowserContext());
    auto* identity = IdentityManagerFactory::GetForProfile(profile);
    if (!identity ||
        identity->GetPrimaryAccountId(signin::ConsentLevel::kSignin) !=
            *impl_->sign_in_account ||
        signin_util::GetSignedInState(identity) != *impl_->sign_in_state ||
        !AccountConsistencyModeManager::IsDiceEnabledForProfile(profile) ||
        !signin::CanOfferSignInForPromos(*profile)) {
      return false;
    }
  }
#endif
  return browser && browser == impl_->browser_identity &&
         web_contents()->GetBrowserContext() == browser->GetProfile() &&
         browser->GetWindow() &&
         browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window;
}
bool NativeAutofillSaveSession::CardIsCurrent() const {
  return impl_->card_lifetime && web_contents() &&
         autofill::SaveCardBubbleControllerImpl::FromWebContents(
             web_contents()) == impl_->card &&
         impl_->card->GetPaymentBubbleView() == this;
}
bool NativeAutofillSaveSession::AddressIsCurrent() const {
  auto* parent =
      web_contents()
          ? autofill::AddressBubblesController::FromWebContents(web_contents())
          : nullptr;
  return parent && parent->GetBubbleView() == this;
}
void NativeAutofillSaveSession::Start() {
  DCHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  if (!ContextIsValid() ||
      (impl_->card ? !CardIsCurrent() : !AddressIsCurrent())) {
    Complete(PCAutofillSaveInterrupted);
    return;
  }
  const bool card = impl_->card != nullptr;
  if (impl_->address_update) {
    StartAddressUpdate();
    return;
  }
  if (impl_->account_address) {
    StartAccountAddress();
    return;
  }
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  if (impl_->sign_in_profile) {
    StartAddressSignInPromo();
    return;
  }
#endif
  // Current156 local-save can include CVC. Preserve its actual disclosure;
  //
  NSString* message =
      card ? base::SysUTF16ToNSString(impl_->card->GetExplanatoryMessage())
           : @"Saved addresses will appear in auto-fill next time you order "
             @"something.";
  auto weak = GetWeakPtr();
  impl_->presenter =
      [[PCAutofillSavePresenter alloc] initWithPageView:impl_->page_host
          window:impl_->window
          title:card ? @"Save this card?" : @"Save Address?"
          message:message
          saveLabel:@"Save"
          declineLabel:card ? @"Not Now" : @"No Thanks"
          validateContext:^{
            return weak && weak->ContextIsValid() &&
                   (weak->impl_->card ? weak->CardIsCurrent()
                                      : weak->AddressIsCurrent());
          }
          completion:^(PCAutofillSaveOutcome outcome) {
            if (weak) {
              weak->Complete(outcome);
            }
          }];
  impl_->presenter.onPresented = ^{
    if (weak) {
      weak->ReportPresentation(true);
    }
  };
  [impl_->presenter start];
}

void NativeAutofillSaveSession::StartAddressUpdate() {
  auto weak = GetWeakPtr();
  auto controller = std::make_unique<NativeUpdateController>(
      web_contents(), std::move(impl_->update),
      base::BindRepeating([](base::WeakPtr<NativeAutofillSaveSession> session) {
        return session && !session->impl_->completing &&
               session->ContextIsValid() && session->AddressIsCurrent();
      }, weak),
      base::BindRepeating([](base::WeakPtr<NativeAutofillSaveSession> session) {
        return session && session->AddressIsCurrent();
      }, weak),
      base::BindOnce(&NativeAutofillSaveSession::Complete, weak,
                     PCAutofillSaveInterrupted));
  auto* view = new autofill::UpdateAddressProfileView(
      views::BubbleAnchor(static_cast<views::View*>(nullptr)),
      std::move(controller), web_contents());
  PresentAddressView(view);
}

void NativeAutofillSaveSession::StartAccountAddress() {
  auto weak = GetWeakPtr();
  auto controller = std::make_unique<NativeSaveAddressController>(
      web_contents(), std::move(impl_->address),
      base::BindRepeating(
          [](base::WeakPtr<NativeAutofillSaveSession> session) {
            const bool valid = session && !session->impl_->completing &&
                               session->ContextIsValid() &&
                               session->AddressIsCurrent();
            if (!valid && session) {
              session->Hide();
            }
            return valid;
          },
          weak),
      base::BindRepeating(
          [](base::WeakPtr<NativeAutofillSaveSession> session) {
            return session && session->AddressIsCurrent();
          },
          weak),
      base::BindOnce(&NativeAutofillSaveSession::Complete, weak,
                     PCAutofillSaveInterrupted));
  PresentAddressView(new autofill::SaveAddressProfileView(
      views::BubbleAnchor(static_cast<views::View*>(nullptr)),
      std::move(controller), web_contents()));
}

#if BUILDFLAG(ENABLE_DICE_SUPPORT)
void NativeAutofillSaveSession::StartAddressSignInPromo() {
  // The parent already applied this policy; repeat immediately before creating
  // the deferred view, since identity, policy or migration eligibility changed
  // while this request was queued. Do not reapply impression-count limits to
  // the click after this very view has recorded its impression.
  auto* profile =
      Profile::FromBrowserContext(web_contents()->GetBrowserContext());
  if (!AccountConsistencyModeManager::IsDiceEnabledForProfile(profile) ||
      !signin::ShouldShowAddressSignInPromo(*profile,
                                            *impl_->sign_in_profile)) {
    Complete(PCAutofillSaveInterrupted);
    return;
  }
  auto* identity = IdentityManagerFactory::GetForProfile(profile);
  impl_->sign_in_account =
      identity->GetPrimaryAccountId(signin::ConsentLevel::kSignin);
  impl_->sign_in_state = signin_util::GetSignedInState(identity);
  auto weak = GetWeakPtr();
  auto delegate = std::make_unique<NativeAddressSignInDelegate>(
      *web_contents(), *impl_->sign_in_profile,
      base::BindRepeating(
          [](base::WeakPtr<NativeAutofillSaveSession> session) {
            const bool valid = session && !session->impl_->completing &&
                               session->ContextIsValid() &&
                               session->AddressIsCurrent();
            if (!valid && session) {
              session->Hide();
            }
            return valid;
          },
          weak));
  PresentAddressView(new NativeAddressSignInView(
      web_contents(), *impl_->sign_in_profile, std::move(delegate),
      base::BindRepeating(
          [](base::WeakPtr<NativeAutofillSaveSession> session) {
            return session && session->AddressIsCurrent();
          },
          weak),
      base::BindOnce(&NativeAutofillSaveSession::Complete, weak,
                     PCAutofillSaveInterrupted)));
}
#endif

void NativeAutofillSaveSession::PresentAddressView(
    autofill::AddressBubbleBaseView* view) {
  auto weak = GetWeakPtr();
  impl_->address_view = view;
  //
  // ownership boundary: the exact page's Cocoa child modal, not a toolbar
  //
  view->SetModalType(ui::mojom::ModalType::kChild);
  view->SetArrow(views::BubbleBorder::NONE);
  view->set_close_on_deactivate(false);
  view->SetOwnershipOfNewWidget(views::Widget::InitParams::CLIENT_OWNS_WIDGET);
  impl_->address_widget = base::WrapUnique(
      constrained_window::CreateWebModalDialogViews(view, web_contents()));
  impl_->address_widget->AddObserver(this);
  impl_->observing_address_widget = true;
  constrained_window::ShowModalDialog(impl_->address_widget->GetNativeWindow(),
                                      web_contents());
  if (weak && !weak->impl_->completing &&
      weak->impl_->address_widget->IsVisible()) {
    weak->ReportPresentation(true);
  }
}
void NativeAutofillSaveSession::Complete(int outcome) {
  DCHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  if (impl_->completing) {
    return;
  }
  impl_->completing = true;
  // Pending failure is not an ignored/declined user decision. The observer
  // performs neutral controller cleanup before the legacy close path checks
  // current-view ownership, preventing a second result for this request.
  ReportPresentation(false);
  if (!ContextIsValid()) {
    outcome = PCAutofillSaveInterrupted;
  }
  [impl_->presenter invalidate];
  if (impl_->address_update || impl_->account_address
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
      || impl_->sign_in_profile.has_value()
#endif
  ) {
    // The actual view/controller delivered any explicit accept/decline/edit.
    // Closing or ownership loss only performs native and bubble bookkeeping.
    if (impl_->address_widget && impl_->address_widget->GetContentsView()) {
      impl_->address_widget->GetContentsView()->SetEnabled(false);
    }
    auto* view = impl_->address_view.get();
    impl_->address_view = nullptr;
    if (view) {
      view->Hide();
    }
    // This also covers refusal before construction and native widget teardown.
    // A replacement installed by a decision owns a different bubble pointer.
    if (AddressIsCurrent()) {
      autofill::AddressBubblesController::FromWebContents(web_contents())
          ->OnBubbleClosed();
    }
  } else if (impl_->address) {
    auto controller = std::move(impl_->address);
    const bool current = AddressIsCurrent();
    if (current && outcome == PCAutofillSaveAccepted) {
      controller->OnUserDecision(
          AutofillClient::AddressPromptUserDecision::kAccepted,
          controller->GetAutofillProfile());
    } else if (current && outcome == PCAutofillSaveDeclined) {
      controller->OnUserDecision(controller->GetCancelCallbackValue(),
                                 std::nullopt);
    }
    // Interruption is not an explicit decline. The parent controller retains
    // the pending backend decision and supplies Ignored on page destruction.
    // A decision can reentrantly install another bubble on this same parent.
    // Never let this old request clear a newer parent's bubble pointer.
    if (AddressIsCurrent()) {
      controller->OnBubbleClosed();
    }
  } else if (CardIsCurrent()) {
    if (outcome == PCAutofillSaveAccepted && SupportsLocalCard(*impl_->card)) {
      impl_->accepting_card = true;
      impl_->card->OnSaveButton({});
      impl_->accepting_card = false;
      // Save can destroy the page, hide this bubble or install another request.
      if (CardIsCurrent() && impl_->card_closed) {
        std::move(impl_->card_closed).Run(PaymentsUiClosedReason::kAccepted);
      }
    } else if (impl_->card_closed) {
      std::move(impl_->card_closed)
          .Run(outcome == PCAutofillSaveDeclined
                   ? PaymentsUiClosedReason::kCancelled
                   : PaymentsUiClosedReason::kNotInteracted);
    }
  }
  // No deletion task exists during user/backend callbacks, even if those spin
  // a nested run loop. All results are terminal before invoking them.
  Observe(nullptr);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce([](NativeAutofillSaveSession* session) { delete session; },
                     base::Unretained(this)));
}
void NativeAutofillSaveSession::Hide() {
  DCHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  impl_->interrupted = true;
  [impl_->presenter invalidate];
  if (impl_->address_widget && impl_->address_widget->GetContentsView()) {
    impl_->address_widget->GetContentsView()->SetEnabled(false);
  }
  // OnSaveButton can synchronously call upstream HideBubble, which clears its
  // view immediately after Hide returns. Finalize this accepted request while
  // it still owns that view. Otherwise a consumed local-save callback could be
  // left in LocalSave state. Moving the weak callback first prevents recursion;
  // replacement setup then happens after this old state is finalized.
  if (impl_->accepting_card && CardIsCurrent() && impl_->card_closed) {
    std::move(impl_->card_closed).Run(PaymentsUiClosedReason::kAccepted);
  }
  // Also covers Hide before Start without an inline engine callback.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&NativeAutofillSaveSession::Complete,
                                GetWeakPtr(), PCAutofillSaveInterrupted));
}
bool NativeAutofillSaveSession::IsMouseHovered() const {
  if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI)) {
    DCHECK(false) << "called on invalid thread";
    return false;
  }
  return impl_->address_view ? impl_->address_view->IsMouseHovered()
                             : impl_->presenter.isMouseHovered;
}
bool NativeAutofillSaveSession::IsPresented() const {
  return impl_->presentation.value_or(false);
}
void NativeAutofillSaveSession::SetPresentationCallback(
    base::OnceCallback<void(bool)> callback) {
  DCHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  CHECK(!impl_->observer_registered);
  impl_->observer_registered = true;
  impl_->presentation_callback = std::move(callback);
  if (impl_->presentation && impl_->presentation_callback) {
    auto ready = std::move(impl_->presentation_callback);
    std::move(ready).Run(*impl_->presentation);
  }
}
void NativeAutofillSaveSession::ReportPresentation(bool presented) {
  if (impl_->presentation) {
    return;
  }
  if (presented && (!ContextIsValid() ||
                    (impl_->card ? !CardIsCurrent() : !AddressIsCurrent()))) {
    presented = false;
  }
  impl_->presentation = presented;
  auto callback = std::move(impl_->presentation_callback);
  if (callback) {
    std::move(callback).Run(presented);
  }
}
void NativeAutofillSaveSession::PageHostWillDetach() {
  Hide();
}
void NativeAutofillSaveSession::WebContentsDestroyed() {
  Observe(nullptr);
  Hide();
}
void NativeAutofillSaveSession::OnVisibilityChanged(
    content::Visibility visibility) {
  if (visibility == content::Visibility::HIDDEN &&
      (impl_->address_update || impl_->account_address
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
       || impl_->sign_in_profile.has_value()
#endif
           )) {
    Hide();
  }
}
void NativeAutofillSaveSession::DidFinishNavigation(
    content::NavigationHandle* navigation) {
  if (navigation->HasCommitted() && navigation->IsInPrimaryMainFrame() &&
      !navigation->IsSameDocument()) {
    Hide();
  }
}
void NativeAutofillSaveSession::OnWidgetVisibilityChanged(
    views::Widget* widget,
    bool visible) {
  if (impl_->completing || widget != impl_->address_widget.get()) {
    return;
  }
  if (visible && ContextIsValid() && AddressIsCurrent()) {
    ReportPresentation(true);
  } else if (visible || impl_->presentation.value_or(false)) {
    Hide();
  }
}
void NativeAutofillSaveSession::OnWidgetDestroying(views::Widget* widget) {
  if (widget == impl_->address_widget.get()) {
    widget->RemoveObserver(this);
    impl_->observing_address_widget = false;
    impl_->address_view = nullptr;
    impl_->interrupted = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&NativeAutofillSaveSession::Complete,
                                  GetWeakPtr(), PCAutofillSaveInterrupted));
  }
}
base::WeakPtr<NativeAutofillSaveSession>
NativeAutofillSaveSession::GetWeakPtr() {
  if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI)) {
    DCHECK(false) << "called on invalid thread";
    return nullptr;
  }
  return weak_factory_.GetWeakPtr();
}
}  // namespace parc
