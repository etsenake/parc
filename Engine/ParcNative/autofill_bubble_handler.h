// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_AUTOFILL_BUBBLE_HANDLER_H_
#define PARC_NATIVE_AUTOFILL_BUBBLE_HANDLER_H_
#include <optional>
#include <vector>

#include "base/memory/raw_ref.h"
#include "base/memory/weak_ptr.h"
#include "cef/libcef/browser/parc_native/autofill_save_session.h"
#include "cef/libcef/browser/parc_native/native_card_save_session.h"
#include "cef/libcef/browser/parc_native/native_iban_session.h"
#include "cef/libcef/browser/parc_native/native_payment_consent_session.h"
#include "cef/libcef/browser/parc_native/native_payment_information_session.h"
#include "cef/libcef/browser/parc_native/native_tab_payment_session.h"
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"
#include "ui/gfx/native_ui_types.h"
class BrowserWindowInterface;
namespace parc {
struct NativeAutofillPageContext {
  gfx::NativeView page_host;
  gfx::NativeWindow window;
};
// Same Browser/Profile owner as this handler. Never choose a frontmost window
// or active split pane instead of the actual request page. The provider and
// Browser outlive the handler; provider calls must not destroy the handler or
// either owner. Page teardown/reparenting is revalidated after the callback.
class NativeAutofillBubbleHost {
 public:
  virtual ~NativeAutofillBubbleHost() = default;
  virtual bool CanShowPaymentEntry() const { return false; }
  virtual void PaymentEntryChanged(content::WebContents&) {}
  virtual std::optional<NativeAutofillPageContext> GetAutofillPageContext(
      content::WebContents& contents) = 0;
};
// UI-thread-only real handler. Install before creating page AutofillClients.
// Its BrowserWindow getter and unowned-data registration must refer to this
// same instance. Destroy before Browser/Profile services, and notify BEFORE
// native page reparenting. Requires the coherent native-autofill-capabilities
// source patch; returning unavailable is never a fabricated BubbleBase.
class NativeAutofillBubbleHandler final
    : public autofill::AutofillBubbleHandler {
 public:
  NativeAutofillBubbleHandler(BrowserWindowInterface&,
                              NativeAutofillBubbleHost&);
  ~NativeAutofillBubbleHandler() override;
  bool IsAutofillUiPresentationSupported(
      autofill::AutofillUiPresentation) const override;
  void OnPaymentStateChanged(content::WebContents*) override;
  void PageHostWillDetach(content::WebContents&);
  void PageHostDidAttach(content::WebContents&);
  void BeginTeardown();
  autofill::AutofillBubbleBase* ShowSaveCreditCardBubble(
      content::WebContents* web_contents,
      autofill::SaveCardBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowIbanBubble(
      content::WebContents* web_contents,
      autofill::IbanBubbleController* controller,
      bool is_user_gesture,
      autofill::IbanBubbleType bubble_type) override;
  autofill::AutofillBubbleBase* ShowOfferNotificationBubble(
      content::WebContents* web_contents,
      autofill::OfferNotificationBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowSaveAutofillAiDataBubble(
      content::WebContents* web_contents,
      autofill::AutofillAiImportDataController* controller) override;
  autofill::AutofillBubbleBase* ShowAutofillAiLocalSaveNotification(
      content::WebContents* web_contents,
      autofill::AutofillAiImportDataController* controller) override;
  autofill::AutofillBubbleBase* ShowSaveAddressProfileBubble(
      content::WebContents* web_contents,
      std::unique_ptr<autofill::SaveAddressBubbleController> controller,
      bool is_user_gesture) override;
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  autofill::AutofillBubbleBase* ShowAddressSignInPromo(
      content::WebContents* web_contents,
      const autofill::AutofillProfile& autofill_profile) override;
#endif
  autofill::AutofillBubbleBase* ShowUpdateAddressProfileBubble(
      content::WebContents* web_contents,
      std::unique_ptr<autofill::UpdateAddressBubbleController> controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowFilledCardInformationBubble(
      content::WebContents* web_contents,
      autofill::FilledCardInformationBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollBubble(
      content::WebContents* web_contents,
      autofill::VirtualCardEnrollBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollConfirmationBubble(
      content::WebContents* web_contents,
      autofill::VirtualCardEnrollBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowMandatoryReauthBubble(
      content::WebContents* web_contents,
      autofill::MandatoryReauthBubbleController* controller,
      bool is_user_gesture,
      autofill::MandatoryReauthBubbleType bubble_type) override;
  autofill::AutofillBubbleBase* ShowSaveCardConfirmationBubble(
      content::WebContents* web_contents,
      autofill::SaveCardBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowSaveIbanConfirmationBubble(
      content::WebContents* web_contents,
      autofill::IbanBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowOmniboxAutofillBubble(
      content::WebContents* web_contents,
      autofill::OmniboxAutofillBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersBubble(
      content::WebContents* web_contents,
      autofill::PaymentsChurnedUsersBubbleController* controller,
      bool is_user_gesture) override;
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersConfirmationBubble(
      content::WebContents* web_contents,
      autofill::PaymentsChurnedUsersBubbleController* controller) override;
  autofill::AutofillBubbleBase* ShowWalletReminderNoticeBubble(
      content::WebContents* web_contents,
      autofill::WalletReminderNoticeBubbleController* controller,
      bool is_user_gesture) override;

 private:
  std::optional<NativeAutofillPageContext> ContextFor(content::WebContents*);
  void Track(content::WebContents&, NativeAutofillSaveSession&);
  void Track(content::WebContents&, NativeCardSaveSession&);
  void Track(content::WebContents&, NativeIbanSession&);
  void Track(content::WebContents&, NativePaymentConsentSession&);
  void Track(content::WebContents&, NativePaymentInformationSession&);
  void Track(content::WebContents&, NativeTabPaymentSession&);
  struct TabPaymentRequest {
    base::WeakPtr<content::WebContents> contents;
    base::WeakPtr<NativeTabPaymentSession> session;
  };
  struct InformationRequest {
    base::WeakPtr<content::WebContents> contents;
    base::WeakPtr<NativePaymentInformationSession> session;
  };
  struct ConsentRequest {
    base::WeakPtr<content::WebContents> contents;
    base::WeakPtr<NativePaymentConsentSession> session;
  };
  struct IbanRequest {
    base::WeakPtr<content::WebContents> contents;
    base::WeakPtr<NativeIbanSession> session;
  };
  struct CardRequest {
    base::WeakPtr<content::WebContents> contents;
    base::WeakPtr<NativeCardSaveSession> session;
  };
  struct Request {
    base::WeakPtr<content::WebContents> contents;
    base::WeakPtr<NativeAutofillSaveSession> session;
  };
  const raw_ref<BrowserWindowInterface> browser_;
  const raw_ref<NativeAutofillBubbleHost> host_;
  bool tearing_down_ = false;
  std::vector<Request> requests_;
  std::vector<CardRequest> card_requests_;
  std::vector<IbanRequest> iban_requests_;
  std::vector<ConsentRequest> consent_requests_;
  std::vector<InformationRequest> information_requests_;
  std::vector<TabPaymentRequest> tab_payment_requests_;
  std::vector<base::WeakPtr<content::WebContents>> detached_pages_;
  ui::ScopedUnownedUserData<autofill::AutofillBubbleHandler> registration_;
};
}  // namespace parc
#endif
