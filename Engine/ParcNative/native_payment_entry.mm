// Copyright 2026 Parc contributors.
#include "native_payment_entry.h"
#include <utility>
#include <vector>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/autofill/payments/filled_card_information_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/iban_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/mandatory_reauth_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/offer_notification_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/omnibox_autofill_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/omnibox_autofill_page_action_controller.h"
#include "chrome/browser/ui/autofill/payments/payments_churned_users_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/virtual_card_enroll_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/wallet_reminder_notice_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/wallet_reminder_notice_page_action_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "native_card_save_session.h"
#include "native_iban_session.h"
#include "native_payment_consent_session.h"
#include "native_payment_information_session.h"
#include "native_tab_payment_session.h"
#include "ui/base/l10n/l10n_util.h"
namespace parc {
enum class PaymentKind {
  kCard,
  kIban,
  kVirtualCard,
  kReauth,
  kOffer,
  kFilled,
  kOmnibox,
  kChurned,
  kWallet
};
struct NativePaymentActionToken {
  base::WeakPtr<NativePaymentEntry> owner;
  base::WeakPtr<autofill::BubbleControllerBase> controller;
  base::WeakPtr<tabs::TabInterface> tab;
  content::WeakDocumentPtr document;
  uint64_t generation;
  PaymentKind kind;
  int phase;
  const void* model_identity = nullptr;  // Compare only, never dereference.
  uint64_t request_id = 0;
  uint64_t entry_generation = 0;
};
}  // namespace parc
@interface PCNativePaymentAction () {
 @package
  std::shared_ptr<parc::NativePaymentActionToken> _token;
}
@property(nonatomic, readwrite, copy) NSString* title;
@property(nonatomic, readwrite, copy) NSString* symbolName;
@property(nonatomic, readwrite, copy) NSString* savedLabel;
@property(nonatomic, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, readwrite) BOOL requiresPresentationAcknowledgment;
- (instancetype)initWithToken:
    (std::shared_ptr<parc::NativePaymentActionToken>)token;
@end
@implementation PCNativePaymentAction
@synthesize title = _title, symbolName = _symbolName, savedLabel = _savedLabel,
            enabled = _enabled,
            requiresPresentationAcknowledgment =
                _requiresPresentationAcknowledgment;
- (instancetype)initWithToken:
    (std::shared_ptr<parc::NativePaymentActionToken>)token {
  if ((self = [super init]))
    _token = std::move(token);
  return self;
}
@end
namespace parc {
struct NativePaymentEntry::DispatchState {
  size_t active = 0;
  bool stopped = false;
  std::vector<base::OnceClosure> ready;
  void Flush() {
    if (active || !stopped)
      return;
    auto callbacks = std::move(ready);
    for (auto& callback : callbacks)
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
          FROM_HERE, std::move(callback));
  }
};
class NativePaymentEntry::Operation {
 public:
  explicit Operation(std::shared_ptr<DispatchState> state)
      : state_(std::move(state)) {
    CHECK(!state_->stopped);
    ++state_->active;
  }
  ~Operation() {
    CHECK(state_->active);
    --state_->active;
    state_->Flush();
  }

 private:
  std::shared_ptr<DispatchState> state_;
};
NativePaymentEntry::NativePaymentEntry(
    BrowserWindowInterface& browser,
    base::RepeatingCallback<bool(content::WebContents&)> validate,
    base::RepeatingClosure changed)
    : browser_(browser),
      validate_(std::move(validate)),
      changed_(std::move(changed)),
      dispatch_(std::make_shared<DispatchState>()) {
  CHECK(validate_ && changed_);
}
NativePaymentEntry::~NativePaymentEntry() {
  BeginShutdown();
}
bool NativePaymentEntry::ValidPage(content::WebContents& contents) const {
  if (stopped_ || contents.IsBeingDestroyed() ||
      !contents.GetPrimaryMainFrame() ||
      contents.GetBrowserContext() != browser_.GetProfile())
    return false;
  auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
  return tab && tab->IsActivated() &&
         tab->GetBrowserWindowInterface() == &browser_ &&
         validate_.Run(contents);
}
NSArray<PCNativePaymentAction*>* NativePaymentEntry::Snapshot(
    content::WebContents& contents) {
  if (!ValidPage(contents))
    return @[];
  auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
  NSMutableArray<PCNativePaymentAction*>* result = [NSMutableArray array];
  auto append = [&](auto* controller, bool iban, int phase, bool supported,
                    bool confirmation) {
    if (!controller || !supported || !controller->IsIconVisible())
      return;
    auto token =
        std::make_shared<NativePaymentActionToken>(NativePaymentActionToken{
            weak_factory_.GetWeakPtr(),
            controller->GetBubbleControllerBaseWeakPtr(), tab->GetWeakPtr(),
            contents.GetPrimaryMainFrame()->GetWeakDocumentPtr(), generation_,
            iban ? PaymentKind::kIban : PaymentKind::kCard, phase});
    PCNativePaymentAction* item =
        [[PCNativePaymentAction alloc] initWithToken:std::move(token)];
    auto title = controller->GetSavePaymentIconTooltipText();
    // Confirmation/progress intentionally have no standard tooltip. The
    // genuine view title remains meaningful without exposing account data.
    if (title.empty()) {
      if (confirmation)
        title = controller->GetConfirmationUiParams().title_text;
      else
        title = controller->GetWindowTitle();
    }
    item.title = base::SysUTF16ToNSString(title);
    item.symbolName = iban ? @"banknote" : @"creditcard";
    item.enabled = controller->CanBeReshown();
    item.savedLabel = controller->ShouldShowPaymentSavedLabelAnimation()
                          ? base::SysUTF16ToNSString(l10n_util::GetStringUTF16(
                                controller->GetSaveSuccessAnimationStringId()))
                          : @"";
    [result addObject:item];
  };
  auto* card =
      autofill::SaveCardBubbleControllerImpl::FromWebContents(&contents);
  if (card)
    append(card, false, static_cast<int>(card->GetPaymentsBubbleType()),
           NativeCardSaveSession::Supports(*card),
           card->GetPaymentsBubbleType() ==
               autofill::PaymentsBubbleType::kUploadComplete);
  auto* iban = autofill::IbanBubbleControllerImpl::FromWebContents(&contents);
  if (iban)
    append(iban, true, static_cast<int>(iban->GetIbanBubbleType()),
           NativeIbanSession::Supports(*iban),
           iban->GetIbanBubbleType() ==
               autofill::IbanBubbleType::kUploadCompleted);
  auto append_consent = [&](auto* controller, PaymentKind kind, int phase,
                            std::u16string title, NSString* symbol,
                            const void* model) {
    auto token =
        std::make_shared<NativePaymentActionToken>(NativePaymentActionToken{
            weak_factory_.GetWeakPtr(),
            controller->GetBubbleControllerBaseWeakPtr(), tab->GetWeakPtr(),
            contents.GetPrimaryMainFrame()->GetWeakDocumentPtr(), generation_,
            kind, phase, model});
    PCNativePaymentAction* item =
        [[PCNativePaymentAction alloc] initWithToken:std::move(token)];
    item.title = base::SysUTF16ToNSString(title);
    item.symbolName = symbol;
    item.savedLabel = @"";
    item.enabled = controller->CanBeReshown();
    [result addObject:item];
  };
  auto* virtual_card =
      autofill::VirtualCardEnrollBubbleControllerImpl::FromWebContents(
          &contents);
  if (virtual_card && NativePaymentConsentSession::Supports(*virtual_card)) {
    const bool complete = virtual_card->IsEnrollmentComplete();
    append_consent(
        virtual_card, PaymentKind::kVirtualCard,
        complete ? 2 : (virtual_card->IsEnrollmentInProgress() ? 1 : 0),
        complete ? virtual_card->GetConfirmationUiParams().title_text
                 : virtual_card->GetUiModel().window_title(),
        @"creditcard", &virtual_card->GetUiModel());
  }
  auto* reauth =
      autofill::MandatoryReauthBubbleControllerImpl::FromWebContents(&contents);
  if (reauth && NativePaymentConsentSession::Supports(*reauth) &&
      (reauth->GetMandatoryReauthBubbleType() ==
           autofill::MandatoryReauthBubbleType::kOptIn ||
       (reauth->GetBubbleView() && reauth->GetBubbleView()->IsPresented()))) {
    // The controller enters confirmation state before OS authentication
    // returns. A status label must not imply success until its genuine result
    // is shown.
    append_consent(reauth, PaymentKind::kReauth,
                   static_cast<int>(reauth->GetMandatoryReauthBubbleType()),
                   reauth->GetWindowTitle(), @"lock.shield", nullptr);
  }
  auto append_information = [&](auto* controller, PaymentKind kind,
                                std::u16string title, NSString* symbol) {
    if (!controller ||
        !NativePaymentInformationSession::Supports(*controller) ||
        !controller->CanBeReshown())
      return;
    auto token =
        std::make_shared<NativePaymentActionToken>(NativePaymentActionToken{
            weak_factory_.GetWeakPtr(),
            controller->GetBubbleControllerBaseWeakPtr(), tab->GetWeakPtr(),
            contents.GetPrimaryMainFrame()->GetWeakDocumentPtr(), generation_,
            kind, 0, nullptr, controller->GetNativeRequestId()});
    PCNativePaymentAction* item =
        [[PCNativePaymentAction alloc] initWithToken:std::move(token)];
    item.title = base::SysUTF16ToNSString(title);
    item.symbolName = symbol;
    item.enabled = YES;
    item.savedLabel = @"";
    [result addObject:item];
  };
  auto* offer =
      autofill::OfferNotificationBubbleControllerImpl::FromWebContents(
          &contents);
  if (offer && NativePaymentInformationSession::Supports(*offer))
    append_information(offer, PaymentKind::kOffer, offer->GetWindowTitle(),
                       @"tag");
  auto* filled =
      autofill::FilledCardInformationBubbleControllerImpl::FromWebContents(
          &contents);
  if (filled && NativePaymentInformationSession::Supports(*filled))
    append_information(filled, PaymentKind::kFilled,
                       filled->GetBubbleTitleText(), @"creditcard");
  auto append_tab = [&](auto* controller, PaymentKind kind, int phase,
                        std::u16string title, NSString* symbol,
                        uint64_t entry_generation, bool acknowledge) {
    auto token =
        std::make_shared<NativePaymentActionToken>(NativePaymentActionToken{
            weak_factory_.GetWeakPtr(),
            controller->GetBubbleControllerBaseWeakPtr(), tab->GetWeakPtr(),
            contents.GetPrimaryMainFrame()->GetWeakDocumentPtr(), generation_,
            kind, phase, nullptr, controller->GetNativeRequestId(),
            entry_generation});
    PCNativePaymentAction* item =
        [[PCNativePaymentAction alloc] initWithToken:std::move(token)];
    item.title = base::SysUTF16ToNSString(title);
    item.symbolName = symbol;
    item.enabled = controller->CanBeReshown();
    item.savedLabel = @"";
    item.requiresPresentationAcknowledgment = acknowledge;
    [result addObject:item];
  };
  auto* omnibox = autofill::OmniboxAutofillBubbleController::From(*tab);
  auto* omnibox_entry =
      autofill::OmniboxAutofillPageActionController::From(*tab);
  if (omnibox && omnibox_entry && omnibox->CanBeReshown() &&
      NativeTabPaymentSession::Supports(
          contents, NativeTabPaymentSession::Kind::kOmnibox))
    append_tab(omnibox, PaymentKind::kOmnibox, 0, omnibox->GetWindowTitle(),
               @"creditcard", omnibox_entry->GetNativeEntryGeneration(),
               omnibox_entry->NeedsNativePresentationAcknowledgment());
  auto* churned = autofill::PaymentsChurnedUsersBubbleController::From(*tab);
  if (churned) {
    const int phase = churned->GetNativePhase();
    if (NativeTabPaymentSession::Supports(
            contents, phase == 2
                          ? NativeTabPaymentSession::Kind::kChurnedConfirmation
                          : NativeTabPaymentSession::Kind::kChurnedOffer))
      append_tab(churned, PaymentKind::kChurned, phase,
                 phase == 2 ? churned->GetConfirmationUiParams().title_text
                            : churned->GetWindowTitle(),
                 @"creditcard", 0, false);
  }
  auto* wallet = autofill::WalletReminderNoticeBubbleController::From(*tab);
  auto* wallet_entry =
      autofill::WalletReminderNoticePageActionController::From(*tab);
  if (wallet && wallet_entry && wallet_entry->IsNativeEntryVisible() &&
      NativeTabPaymentSession::Supports(contents,
                                        NativeTabPaymentSession::Kind::kWallet))
    append_tab(wallet, PaymentKind::kWallet, 0, wallet->GetWindowTitle(),
               @"wallet.pass", wallet_entry->GetNativeEntryGeneration(), false);
  return [result copy];
}
autofill::BubbleControllerBase* NativePaymentEntry::Validate(
    PCNativePaymentAction* item,
    content::WebContents& contents) const {
  if (!item || !item->_token || !ValidPage(contents))
    return nullptr;
  const auto& token = *item->_token;
  if (token.owner.get() != this || token.generation != generation_ ||
      !token.controller || !token.tab ||
      token.tab.get() != tabs::TabInterface::MaybeGetFromContents(&contents) ||
      token.document.AsRenderFrameHostIfValid() !=
          contents.GetPrimaryMainFrame())
    return nullptr;
  if (token.kind == PaymentKind::kOmnibox) {
    auto* actual = autofill::OmniboxAutofillBubbleController::From(*token.tab);
    auto* entry =
        autofill::OmniboxAutofillPageActionController::From(*token.tab);
    return actual && entry &&
                   actual->GetBubbleControllerBaseWeakPtr().get() ==
                       token.controller.get() &&
                   actual->GetNativeRequestId() == token.request_id &&
                   entry->GetNativeEntryGeneration() ==
                       token.entry_generation &&
                   entry->IsNativeEntryVisible() && actual->CanBeReshown() &&
                   NativeTabPaymentSession::Supports(
                       contents, NativeTabPaymentSession::Kind::kOmnibox)
               ? actual
               : nullptr;
  }
  if (token.kind == PaymentKind::kChurned) {
    auto* actual =
        autofill::PaymentsChurnedUsersBubbleController::From(*token.tab);
    return actual &&
                   actual->GetBubbleControllerBaseWeakPtr().get() ==
                       token.controller.get() &&
                   actual->GetNativeRequestId() == token.request_id &&
                   actual->GetNativePhase() == token.phase &&
                   NativeTabPaymentSession::Supports(
                       contents,
                       token.phase == 2
                           ? NativeTabPaymentSession::Kind::kChurnedConfirmation
                           : NativeTabPaymentSession::Kind::kChurnedOffer)
               ? actual
               : nullptr;
  }
  if (token.kind == PaymentKind::kWallet) {
    auto* actual =
        autofill::WalletReminderNoticeBubbleController::From(*token.tab);
    auto* entry =
        autofill::WalletReminderNoticePageActionController::From(*token.tab);
    return actual && entry &&
                   actual->GetBubbleControllerBaseWeakPtr().get() ==
                       token.controller.get() &&
                   actual->GetNativeRequestId() == token.request_id &&
                   entry->IsNativeEntryVisible() &&
                   entry->GetNativeEntryGeneration() ==
                       token.entry_generation &&
                   NativeTabPaymentSession::Supports(
                       contents, NativeTabPaymentSession::Kind::kWallet)
               ? actual
               : nullptr;
  }
  if (token.kind == PaymentKind::kOffer) {
    auto* actual =
        autofill::OfferNotificationBubbleControllerImpl::FromWebContents(
            &contents);
    return actual &&
                   actual->GetBubbleControllerBaseWeakPtr().get() ==
                       token.controller.get() &&
                   actual->GetNativeRequestId() == token.request_id &&
                   NativePaymentInformationSession::Supports(*actual) &&
                   actual->CanBeReshown()
               ? actual
               : nullptr;
  }
  if (token.kind == PaymentKind::kFilled) {
    auto* actual =
        autofill::FilledCardInformationBubbleControllerImpl::FromWebContents(
            &contents);
    return actual &&
                   actual->GetBubbleControllerBaseWeakPtr().get() ==
                       token.controller.get() &&
                   actual->GetNativeRequestId() == token.request_id &&
                   NativePaymentInformationSession::Supports(*actual) &&
                   actual->CanBeReshown()
               ? actual
               : nullptr;
  }
  if (token.kind == PaymentKind::kIban) {
    auto* actual =
        autofill::IbanBubbleControllerImpl::FromWebContents(&contents);
    return actual &&
                   actual->GetBubbleControllerBaseWeakPtr().get() ==
                       token.controller.get() &&
                   static_cast<int>(actual->GetIbanBubbleType()) ==
                       token.phase &&
                   actual->IsIconVisible() &&
                   NativeIbanSession::Supports(*actual)
               ? actual
               : nullptr;
  }
  if (token.kind == PaymentKind::kVirtualCard) {
    auto* actual =
        autofill::VirtualCardEnrollBubbleControllerImpl::FromWebContents(
            &contents);
    if (!actual ||
        actual->GetBubbleControllerBaseWeakPtr().get() !=
            token.controller.get() ||
        &actual->GetUiModel() != token.model_identity ||
        !NativePaymentConsentSession::Supports(*actual))
      return nullptr;
    const int phase = actual->IsEnrollmentComplete()
                          ? 2
                          : (actual->IsEnrollmentInProgress() ? 1 : 0);
    return phase == token.phase ? actual : nullptr;
  }
  if (token.kind == PaymentKind::kReauth) {
    auto* actual =
        autofill::MandatoryReauthBubbleControllerImpl::FromWebContents(
            &contents);
    return actual &&
                   actual->GetBubbleControllerBaseWeakPtr().get() ==
                       token.controller.get() &&
                   static_cast<int>(actual->GetMandatoryReauthBubbleType()) ==
                       token.phase &&
                   NativePaymentConsentSession::Supports(*actual)
               ? actual
               : nullptr;
  }
  auto* actual =
      autofill::SaveCardBubbleControllerImpl::FromWebContents(&contents);
  return actual &&
                 actual->GetBubbleControllerBaseWeakPtr().get() ==
                     token.controller.get() &&
                 static_cast<int>(actual->GetPaymentsBubbleType()) ==
                     token.phase &&
                 actual->IsIconVisible() &&
                 NativeCardSaveSession::Supports(*actual)
             ? actual
             : nullptr;
}
bool NativePaymentEntry::Execute(PCNativePaymentAction* item,
                                 content::WebContents& contents) {
  auto* controller = Validate(item, contents);
  if (!controller || !item.isEnabled ||
      !item->_token->controller->CanBeReshown())
    return false;
  Operation operation(dispatch_);
  // No access to this service or the borrowed page follows upstream dispatch.
  switch (item->_token->kind) {
    case PaymentKind::kOmnibox:
      static_cast<autofill::OmniboxAutofillBubbleController*>(controller)
          ->QueueOrShowBubble(/*force_show=*/true);
      break;
    case PaymentKind::kChurned:
      static_cast<autofill::PaymentsChurnedUsersBubbleController*>(controller)
          ->ReshowBubble();
      break;
    case PaymentKind::kWallet:
      static_cast<autofill::WalletReminderNoticeBubbleController*>(controller)
          ->ReshowBubble();
      break;
    case PaymentKind::kOffer:
      static_cast<autofill::OfferNotificationBubbleControllerImpl*>(controller)
          ->ReshowBubble();
      break;
    case PaymentKind::kFilled:
      static_cast<autofill::FilledCardInformationBubbleControllerImpl*>(
          controller)
          ->ReshowBubble();
      break;
    case PaymentKind::kCard:
      static_cast<autofill::SaveCardBubbleControllerImpl*>(controller)
          ->ReshowBubble(true);
      break;
    case PaymentKind::kIban:
      static_cast<autofill::IbanBubbleControllerImpl*>(controller)
          ->ReshowBubble();
      break;
    case PaymentKind::kVirtualCard:
      static_cast<autofill::VirtualCardEnrollBubbleControllerImpl*>(controller)
          ->ReshowBubble();
      break;
    case PaymentKind::kReauth:
      static_cast<autofill::MandatoryReauthBubbleControllerImpl*>(controller)
          ->ReshowBubble();
      break;
  }
  return true;
}
bool NativePaymentEntry::FeedbackPresented(PCNativePaymentAction* item,
                                           content::WebContents& contents) {
  auto* actual = Validate(item, contents);
  if (!actual)
    return false;
  if (item->_token->kind == PaymentKind::kOmnibox &&
      item.requiresPresentationAcknowledgment) {
    auto token = item->_token;
    auto* entry =
        autofill::OmniboxAutofillPageActionController::From(*token->tab);
    if (!entry || !entry->NeedsNativePresentationAcknowledgment())
      return false;
    Operation operation(dispatch_);
    entry->OnNativeEntryPresented(token->entry_generation);
    return true;
  }
  if (item.savedLabel.length == 0)
    return false;
  autofill::SavePaymentIconController* controller = nullptr;
  if (item->_token->kind == PaymentKind::kCard)
    controller = static_cast<autofill::SaveCardBubbleControllerImpl*>(actual);
  else if (item->_token->kind == PaymentKind::kIban)
    controller = static_cast<autofill::IbanBubbleControllerImpl*>(actual);
  if (!controller || !controller->ShouldShowPaymentSavedLabelAnimation())
    return false;
  Operation operation(dispatch_);
  controller->OnAnimationEnded();
  return true;
}
void NativePaymentEntry::Changed() {
  if (stopped_)
    return;
  ++generation_;
  if (change_posted_)
    return;
  change_posted_ = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
      FROM_HERE, base::BindOnce(&NativePaymentEntry::DeliverChanged,
                                weak_factory_.GetWeakPtr()));
}
void NativePaymentEntry::DeliverChanged() {
  change_posted_ = false;
  if (stopped_)
    return;
  auto callback = changed_;
  callback.Run();  // Last operation: the shell may release this service.
}
void NativePaymentEntry::BeginShutdown() {
  if (stopped_)
    return;
  stopped_ = true;
  ++generation_;
  dispatch_->stopped = true;
  weak_factory_.InvalidateWeakPtrs();
  dispatch_->Flush();
}
void NativePaymentEntry::Shutdown(base::OnceClosure ready) {
  BeginShutdown();
  dispatch_->ready.push_back(std::move(ready));
  dispatch_->Flush();
}
}  // namespace parc
