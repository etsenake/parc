// Copyright 2026 Parc contributors.
#include "parc/native/autofill_bubble_handler.h"

#import <Cocoa/Cocoa.h>

#include <algorithm>

#include "base/check.h"
#include "chrome/browser/ui/autofill/payments/filled_card_information_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/iban_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/mandatory_reauth_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/offer_notification_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/omnibox_autofill_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/payments_churned_users_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/virtual_card_enroll_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/payments/wallet_reminder_notice_bubble_controller.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/update_address_bubble_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
namespace parc {
using Kind = autofill::AutofillUiPresentation;
NativeAutofillBubbleHandler::NativeAutofillBubbleHandler(
    BrowserWindowInterface& browser,
    NativeAutofillBubbleHost& host)
    : browser_(browser),
      host_(host),
      registration_(browser.GetUnownedUserDataHost(), *this) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
}
NativeAutofillBubbleHandler::~NativeAutofillBubbleHandler() {
  BeginTeardown();
}
bool NativeAutofillBubbleHandler::IsAutofillUiPresentationSupported(
    Kind kind) const {
  if (kind == Kind::kCardIcon || kind == Kind::kIbanSave ||
      kind == Kind::kIbanConfirmation || kind == Kind::kVirtualCardEnrollment ||
      kind == Kind::kVirtualCardConfirmation ||
      kind == Kind::kMandatoryReauthOptIn ||
      kind == Kind::kMandatoryReauthConfirmation ||
      kind == Kind::kOfferNotification ||
      kind == Kind::kFilledCardInformation || kind == Kind::kOmniboxAutofill ||
      kind == Kind::kPaymentsChurnedUsers ||
      kind == Kind::kPaymentsChurnedUsersConfirmation ||
      kind == Kind::kWalletReminder) {
    return !tearing_down_ && host_->CanShowPaymentEntry();
  }
  return !tearing_down_ &&
         (kind == Kind::kLocalCardSave || kind == Kind::kLocalAddressSave ||
          kind == Kind::kAddressUpdate || kind == Kind::kLocalCvcSave ||
          kind == Kind::kUploadCardSave || kind == Kind::kUploadCvcSave ||
          kind == Kind::kCardFixFlow || kind == Kind::kManageCards ||
          kind == Kind::kCardConfirmation ||
          kind == Kind::kAccountAddressSave ||
          kind == Kind::kAddressMigration || kind == Kind::kAddressMerge
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
          || kind == Kind::kAddressSignInPromo
#endif
         );
}
void NativeAutofillBubbleHandler::Track(content::WebContents& contents,
                                        NativePaymentConsentSession& session) {
  std::erase_if(consent_requests_,
                [](const ConsentRequest& request) { return !request.session; });
  consent_requests_.push_back({contents.GetWeakPtr(), session.GetWeakPtr()});
}
void NativeAutofillBubbleHandler::Track(
    content::WebContents& contents,
    NativePaymentInformationSession& session) {
  std::erase_if(information_requests_, [](const InformationRequest& request) {
    return !request.session;
  });
  information_requests_.push_back(
      {contents.GetWeakPtr(), session.GetWeakPtr()});
}
void NativeAutofillBubbleHandler::Track(content::WebContents& contents,
                                        NativeTabPaymentSession& session) {
  std::erase_if(tab_payment_requests_, [](const TabPaymentRequest& request) {
    return !request.session;
  });
  tab_payment_requests_.push_back(
      {contents.GetWeakPtr(), session.GetWeakPtr()});
}
void NativeAutofillBubbleHandler::OnPaymentStateChanged(
    content::WebContents* contents) {
  if (ContextFor(contents))
    host_->PaymentEntryChanged(*contents);
}
void NativeAutofillBubbleHandler::Track(content::WebContents& contents,
                                        NativeIbanSession& session) {
  std::erase_if(iban_requests_,
                [](const IbanRequest& request) { return !request.session; });
  iban_requests_.push_back({contents.GetWeakPtr(), session.GetWeakPtr()});
}
std::optional<NativeAutofillPageContext>
NativeAutofillBubbleHandler::ContextFor(content::WebContents* contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (tearing_down_ || !contents) {
    return std::nullopt;
  }
  if (std::ranges::any_of(detached_pages_, [contents](const auto& page) {
        return page.get() == contents;
      })) {
    return std::nullopt;
  }
  auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  if (!tab || tab->GetBrowserWindowInterface() != &browser_.get()) {
    return std::nullopt;
  }
  const auto page_identity = contents->GetWeakPtr();
  auto context = host_->GetAutofillPageContext(*contents);
  if (!page_identity || !context || tearing_down_ ||
      page_identity->IsBeingDestroyed()) {
    return std::nullopt;
  }
  contents = page_identity.get();
  if (std::ranges::any_of(detached_pages_, [contents](const auto& page) {
        return page.get() == contents;
      })) {
    return std::nullopt;
  }
  tab = tabs::TabInterface::MaybeGetFromContents(contents);
  if (!tab || tab->GetBrowserWindowInterface() != &browser_.get()) {
    return std::nullopt;
  }
  NSView* page = contents->GetNativeView().GetNativeNSView();
  NSView* host = context->page_host.GetNativeNSView();
  NSWindow* window = context->window.GetNativeNSWindow();
  if (!page || !host || !window || page.window != window ||
      host.window != window || !(page == host || [page isDescendantOf:host]) ||
      contents->IsBeingDestroyed()) {
    return std::nullopt;
  }
  return context;
}
void NativeAutofillBubbleHandler::Track(content::WebContents& contents,
                                        NativeAutofillSaveSession& session) {
  std::erase_if(requests_,
                [](const Request& request) { return !request.session; });
  requests_.push_back({contents.GetWeakPtr(), session.GetWeakPtr()});
}
void NativeAutofillBubbleHandler::Track(content::WebContents& contents,
                                        NativeCardSaveSession& session) {
  std::erase_if(card_requests_,
                [](const CardRequest& request) { return !request.session; });
  card_requests_.push_back({contents.GetWeakPtr(), session.GetWeakPtr()});
}
void NativeAutofillBubbleHandler::PageHostWillDetach(
    content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  detached_pages_.push_back(contents.GetWeakPtr());
  // Block this association and commit removal before callbacks; a reentrant new
  // request has its own identity and is not accidentally erased by this old
  // snapshot.
  std::vector<base::WeakPtr<NativeAutofillSaveSession>> pending;
  std::erase_if(requests_, [&](const Request& request) {
    if (request.contents.get() == &contents) {
      pending.push_back(request.session);
      return true;
    }
    return !request.session;
  });
  std::vector<base::WeakPtr<NativeCardSaveSession>> card_pending;
  std::erase_if(card_requests_, [&](const CardRequest& request) {
    if (request.contents.get() == &contents) {
      card_pending.push_back(request.session);
      return true;
    }
    return !request.session;
  });
  std::vector<base::WeakPtr<NativeIbanSession>> iban_pending;
  std::erase_if(iban_requests_, [&](const IbanRequest& request) {
    if (request.contents.get() == &contents) {
      iban_pending.push_back(request.session);
      return true;
    }
    return !request.session;
  });
  std::vector<base::WeakPtr<NativePaymentConsentSession>> consent_pending;
  std::erase_if(consent_requests_, [&](const ConsentRequest& request) {
    if (request.contents.get() == &contents) {
      consent_pending.push_back(request.session);
      return true;
    }
    return !request.session;
  });
  std::vector<base::WeakPtr<NativePaymentInformationSession>>
      information_pending;
  std::erase_if(information_requests_, [&](const InformationRequest& request) {
    if (request.contents.get() == &contents) {
      information_pending.push_back(request.session);
      return true;
    }
    return !request.session;
  });
  std::vector<base::WeakPtr<NativeTabPaymentSession>> tab_payment_pending;
  std::erase_if(tab_payment_requests_, [&](const TabPaymentRequest& request) {
    if (request.contents.get() == &contents) {
      tab_payment_pending.push_back(request.session);
      return true;
    }
    return !request.session;
  });
  for (auto session : tab_payment_pending) {
    if (session)
      session->Hide();
  }
  for (auto session : information_pending) {
    if (session)
      session->Hide();
  }
  for (auto session : consent_pending) {
    if (session)
      session->Hide();
  }
  for (auto session : iban_pending) {
    if (session)
      session->Hide();
  }
  for (auto session : pending) {
    if (session) {
      session->PageHostWillDetach();
    }
  }
  for (auto session : card_pending) {
    if (session) {
      session->Hide();
    }
  }
}
void NativeAutofillBubbleHandler::PageHostDidAttach(
    content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  std::erase_if(detached_pages_, [&contents](const auto& page) {
    return !page || page.get() == &contents;
  });
}
void NativeAutofillBubbleHandler::BeginTeardown() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (tearing_down_) {
    return;
  }
  tearing_down_ = true;
  auto pending = std::move(requests_);
  requests_.clear();
  auto card_pending = std::move(card_requests_);
  card_requests_.clear();
  auto iban_pending = std::move(iban_requests_);
  iban_requests_.clear();
  auto consent_pending = std::move(consent_requests_);
  consent_requests_.clear();
  auto information_pending = std::move(information_requests_);
  information_requests_.clear();
  auto tab_payment_pending = std::move(tab_payment_requests_);
  tab_payment_requests_.clear();
  for (auto& request : tab_payment_pending) {
    if (request.session)
      request.session->Hide();
  }
  for (auto& request : information_pending) {
    if (request.session)
      request.session->Hide();
  }
  for (auto& request : consent_pending) {
    if (request.session)
      request.session->Hide();
  }
  for (auto& request : iban_pending) {
    if (request.session)
      request.session->Hide();
  }
  for (auto& request : pending) {
    if (request.session) {
      request.session->PageHostWillDetach();
    }
  }
  for (auto& request : card_pending) {
    if (request.session) {
      request.session->Hide();
    }
  }
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowSaveCreditCardBubble(
    content::WebContents* web_contents,
    autofill::SaveCardBubbleController* controller,
    bool is_user_gesture) {
  auto context = ContextFor(web_contents);
  if (!context) {
    return nullptr;
  }
  auto* actual = web_contents
                     ? autofill::SaveCardBubbleControllerImpl::FromWebContents(
                           web_contents)
                     : nullptr;
  if (!actual || actual != controller ||
      !NativeCardSaveSession::Supports(*actual)) {
    return nullptr;
  }
  if (!NativeAutofillSaveSession::SupportsLocalCard(*actual)) {
    auto* session = NativeCardSaveSession::Create(
        browser_.get(), *web_contents, context->page_host, context->window,
        *actual);
    Track(*web_contents, *session);
    return session;
  }
  auto* session = NativeAutofillSaveSession::CreateLocalCard(
      browser_.get(), *web_contents, context->page_host, context->window,
      *actual);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase* NativeAutofillBubbleHandler::ShowIbanBubble(
    content::WebContents* web_contents,
    autofill::IbanBubbleController* controller,
    bool is_user_gesture,
    autofill::IbanBubbleType bubble_type) {
  auto context = ContextFor(web_contents);
  auto* actual =
      web_contents
          ? autofill::IbanBubbleControllerImpl::FromWebContents(web_contents)
          : nullptr;
  if (!context || !IsAutofillUiPresentationSupported(Kind::kIbanSave) ||
      !actual || actual != controller ||
      actual->GetIbanBubbleType() != bubble_type ||
      bubble_type == autofill::IbanBubbleType::kUploadCompleted ||
      !NativeIbanSession::Supports(*actual))
    return nullptr;
  auto* session =
      NativeIbanSession::Create(browser_.get(), *web_contents,
                                context->page_host, context->window, *actual);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowOfferNotificationBubble(
    content::WebContents* web_contents,
    autofill::OfferNotificationBubbleController* controller,
    bool is_user_gesture) {
  auto context = ContextFor(web_contents);
  auto* actual =
      web_contents
          ? autofill::OfferNotificationBubbleControllerImpl::FromWebContents(
                web_contents)
          : nullptr;
  if (!context || !actual || actual != controller ||
      !IsAutofillUiPresentationSupported(Kind::kOfferNotification) ||
      !NativePaymentInformationSession::Supports(*actual))
    return nullptr;
  auto* session = NativePaymentInformationSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      *actual, is_user_gesture);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowSaveAutofillAiDataBubble(
    content::WebContents* web_contents,
    autofill::AutofillAiImportDataController* controller) {
  // Typed unavailable result: the coherent caller/producer guards own neutral
  // completion. No bubble, acknowledgment, acceptance, or user cancellation.
  CHECK(!IsAutofillUiPresentationSupported(Kind::kAutofillAiImport));
  return nullptr;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowAutofillAiLocalSaveNotification(
    content::WebContents* web_contents,
    autofill::AutofillAiImportDataController* controller) {
  // Typed unavailable result: the coherent caller/producer guards own neutral
  // completion. No bubble, acknowledgment, acceptance, or user cancellation.
  CHECK(!IsAutofillUiPresentationSupported(Kind::kAutofillAiNotification));
  return nullptr;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowSaveAddressProfileBubble(
    content::WebContents* web_contents,
    std::unique_ptr<autofill::SaveAddressBubbleController> controller,
    bool is_user_gesture) {
  auto context = ContextFor(web_contents);
  if (!context || !controller || controller->web_contents() != web_contents) {
    return nullptr;
  }
  NativeAutofillSaveSession* session = nullptr;
  if (NativeAutofillSaveSession::SupportsLocalAddress(*controller)) {
    session = NativeAutofillSaveSession::CreateLocalAddress(
        browser_.get(), *web_contents, context->page_host, context->window,
        std::move(controller));
  } else if (NativeAutofillSaveSession::SupportsAccountAddress(*controller)) {
    session = NativeAutofillSaveSession::CreateAccountAddress(
        browser_.get(), *web_contents, context->page_host, context->window,
        std::move(controller));
  } else {
    return nullptr;
  }
  Track(*web_contents, *session);
  return session;
}
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowAddressSignInPromo(
    content::WebContents* web_contents,
    const autofill::AutofillProfile& autofill_profile) {
  auto context = ContextFor(web_contents);
  if (!context) {
    return nullptr;
  }
  auto* session = NativeAutofillSaveSession::CreateAddressSignInPromo(
      browser_.get(), *web_contents, context->page_host, context->window,
      autofill_profile);
  Track(*web_contents, *session);
  return session;
}
#endif
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowUpdateAddressProfileBubble(
    content::WebContents* web_contents,
    std::unique_ptr<autofill::UpdateAddressBubbleController> controller,
    bool is_user_gesture) {
  auto context = ContextFor(web_contents);
  if (!context || !controller || controller->web_contents() != web_contents) {
    return nullptr;
  }
  auto* session = NativeAutofillSaveSession::CreateAddressUpdate(
      browser_.get(), *web_contents, context->page_host, context->window,
      std::move(controller));
  if (!session) {
    return nullptr;
  }
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowFilledCardInformationBubble(
    content::WebContents* web_contents,
    autofill::FilledCardInformationBubbleController* controller,
    bool is_user_gesture) {
  auto context = ContextFor(web_contents);
  auto* actual = web_contents
                     ? autofill::FilledCardInformationBubbleControllerImpl::
                           FromWebContents(web_contents)
                     : nullptr;
  if (!context || !actual || actual != controller ||
      !IsAutofillUiPresentationSupported(Kind::kFilledCardInformation) ||
      !NativePaymentInformationSession::Supports(*actual))
    return nullptr;
  auto* session = NativePaymentInformationSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      *actual, is_user_gesture);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowVirtualCardEnrollBubble(
    content::WebContents* web_contents,
    autofill::VirtualCardEnrollBubbleController* controller,
    bool is_user_gesture) {
  auto context = ContextFor(web_contents);
  auto* actual =
      web_contents
          ? autofill::VirtualCardEnrollBubbleControllerImpl::FromWebContents(
                web_contents)
          : nullptr;
  if (!context ||
      !IsAutofillUiPresentationSupported(Kind::kVirtualCardEnrollment) ||
      !actual || actual != controller || actual->IsEnrollmentComplete() ||
      !NativePaymentConsentSession::Supports(*actual))
    return nullptr;
  auto* session = NativePaymentConsentSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      *actual);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowVirtualCardEnrollConfirmationBubble(
    content::WebContents* web_contents,
    autofill::VirtualCardEnrollBubbleController* controller) {
  auto context = ContextFor(web_contents);
  auto* actual =
      web_contents
          ? autofill::VirtualCardEnrollBubbleControllerImpl::FromWebContents(
                web_contents)
          : nullptr;
  if (!context ||
      !IsAutofillUiPresentationSupported(Kind::kVirtualCardConfirmation) ||
      !actual || actual != controller || !actual->IsEnrollmentComplete() ||
      !NativePaymentConsentSession::Supports(*actual))
    return nullptr;
  auto* session = NativePaymentConsentSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      *actual);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowMandatoryReauthBubble(
    content::WebContents* web_contents,
    autofill::MandatoryReauthBubbleController* controller,
    bool is_user_gesture,
    autofill::MandatoryReauthBubbleType bubble_type) {
  auto context = ContextFor(web_contents);
  auto* actual =
      web_contents
          ? autofill::MandatoryReauthBubbleControllerImpl::FromWebContents(
                web_contents)
          : nullptr;
  if (!context ||
      !IsAutofillUiPresentationSupported(
          (bubble_type == autofill::MandatoryReauthBubbleType::kConfirmation
               ? Kind::kMandatoryReauthConfirmation
               : Kind::kMandatoryReauthOptIn)) ||
      !actual || actual != controller ||
      actual->GetMandatoryReauthBubbleType() != bubble_type ||
      !NativePaymentConsentSession::Supports(*actual))
    return nullptr;
  auto* session = NativePaymentConsentSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      *actual);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowSaveCardConfirmationBubble(
    content::WebContents* web_contents,
    autofill::SaveCardBubbleController* controller) {
  auto context = ContextFor(web_contents);
  auto* actual = web_contents
                     ? autofill::SaveCardBubbleControllerImpl::FromWebContents(
                           web_contents)
                     : nullptr;
  if (!context || !actual || actual != controller ||
      actual->GetPaymentsBubbleType() !=
          autofill::PaymentsBubbleType::kUploadComplete) {
    return nullptr;
  }
  auto* session = NativeCardSaveSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      *actual);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowSaveIbanConfirmationBubble(
    content::WebContents* web_contents,
    autofill::IbanBubbleController* controller) {
  auto context = ContextFor(web_contents);
  auto* actual =
      web_contents
          ? autofill::IbanBubbleControllerImpl::FromWebContents(web_contents)
          : nullptr;
  if (!context || !IsAutofillUiPresentationSupported(Kind::kIbanConfirmation) ||
      !actual || actual != controller ||
      actual->GetIbanBubbleType() !=
          autofill::IbanBubbleType::kUploadCompleted ||
      !NativeIbanSession::Supports(*actual))
    return nullptr;
  auto* session =
      NativeIbanSession::Create(browser_.get(), *web_contents,
                                context->page_host, context->window, *actual);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowOmniboxAutofillBubble(
    content::WebContents* web_contents,
    autofill::OmniboxAutofillBubbleController* controller) {
  auto context = ContextFor(web_contents);
  auto* tab = context ? tabs::TabInterface::MaybeGetFromContents(web_contents)
                      : nullptr;
  auto* actual =
      tab ? autofill::OmniboxAutofillBubbleController::From(*tab) : nullptr;
  if (!context || !IsAutofillUiPresentationSupported(Kind::kOmniboxAutofill) ||
      !actual || actual != controller ||
      !NativeTabPaymentSession::Supports(
          *web_contents, NativeTabPaymentSession::Kind::kOmnibox))
    return nullptr;
  auto* session = NativeTabPaymentSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      NativeTabPaymentSession::Kind::kOmnibox, true);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowPaymentsChurnedUsersBubble(
    content::WebContents* web_contents,
    autofill::PaymentsChurnedUsersBubbleController* controller,
    bool is_user_gesture) {
  auto context = ContextFor(web_contents);
  auto* tab = context ? tabs::TabInterface::MaybeGetFromContents(web_contents)
                      : nullptr;
  auto* actual =
      tab ? autofill::PaymentsChurnedUsersBubbleController::From(*tab)
          : nullptr;
  if (!context ||
      !IsAutofillUiPresentationSupported(Kind::kPaymentsChurnedUsers) ||
      !actual || actual != controller ||
      !NativeTabPaymentSession::Supports(
          *web_contents, NativeTabPaymentSession::Kind::kChurnedOffer))
    return nullptr;
  auto* session = NativeTabPaymentSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      NativeTabPaymentSession::Kind::kChurnedOffer, is_user_gesture);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowPaymentsChurnedUsersConfirmationBubble(
    content::WebContents* web_contents,
    autofill::PaymentsChurnedUsersBubbleController* controller) {
  auto context = ContextFor(web_contents);
  auto* tab = context ? tabs::TabInterface::MaybeGetFromContents(web_contents)
                      : nullptr;
  auto* actual =
      tab ? autofill::PaymentsChurnedUsersBubbleController::From(*tab)
          : nullptr;
  if (!context ||
      !IsAutofillUiPresentationSupported(
          Kind::kPaymentsChurnedUsersConfirmation) ||
      !actual || actual != controller ||
      !NativeTabPaymentSession::Supports(
          *web_contents, NativeTabPaymentSession::Kind::kChurnedConfirmation))
    return nullptr;
  auto* session = NativeTabPaymentSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      NativeTabPaymentSession::Kind::kChurnedConfirmation, false);
  Track(*web_contents, *session);
  return session;
}
autofill::AutofillBubbleBase*
NativeAutofillBubbleHandler::ShowWalletReminderNoticeBubble(
    content::WebContents* web_contents,
    autofill::WalletReminderNoticeBubbleController* controller,
    bool is_user_gesture) {
  auto context = ContextFor(web_contents);
  auto* tab = context ? tabs::TabInterface::MaybeGetFromContents(web_contents)
                      : nullptr;
  auto* actual =
      tab ? autofill::WalletReminderNoticeBubbleController::From(*tab)
          : nullptr;
  if (!context || !IsAutofillUiPresentationSupported(Kind::kWalletReminder) ||
      !actual || actual != controller ||
      !NativeTabPaymentSession::Supports(
          *web_contents, NativeTabPaymentSession::Kind::kWallet))
    return nullptr;
  auto* session = NativeTabPaymentSession::Create(
      browser_.get(), *web_contents, context->page_host, context->window,
      NativeTabPaymentSession::Kind::kWallet, is_user_gesture);
  Track(*web_contents, *session);
  return session;
}
}  // namespace parc
