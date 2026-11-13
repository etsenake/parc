// Copyright 2015 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller_impl.h"

#include <utility>
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "components/autofill/core/browser/ui/payments/save_payment_method_and_virtual_card_enroll_confirmation_ui_params.h"

namespace autofill {

AutofillUiPresentation SaveCardBubbleControllerImpl::CurrentPresentation()
    const {
  switch (current_bubble_type_) {
    case PaymentsBubbleType::kLocalSave:
      return AutofillUiPresentation::kLocalCardSave;
    case PaymentsBubbleType::kLocalCvcSave:
      return AutofillUiPresentation::kLocalCvcSave;
    case PaymentsBubbleType::kUploadSave:
    case PaymentsBubbleType::kUploadCardholderNameUpdate:
      return AutofillUiPresentation::kUploadCardSave;
    case PaymentsBubbleType::kUploadCvcSave:
      return AutofillUiPresentation::kUploadCvcSave;
    case PaymentsBubbleType::kManageCards:
      return AutofillUiPresentation::kManageCards;
    case PaymentsBubbleType::kUploadComplete:
      return AutofillUiPresentation::kCardConfirmation;
    case PaymentsBubbleType::kUploadInProgress:
      return AutofillUiPresentation::kUploadCardSave;
    case PaymentsBubbleType::kInactive:
      return AutofillUiPresentation::kCardIcon;
  }
}

bool SaveCardBubbleControllerImpl::SupportsCurrentPresentation() const {
  return AutofillBubbleHandler::IsPresentationSupported(
             web_contents(), CurrentPresentation()) &&
         (!(ShouldRequestNameFromUser() ||
            ShouldRequestExpirationDateFromUser()) ||
          AutofillBubbleHandler::IsPresentationSupported(
              web_contents(), AutofillUiPresentation::kCardFixFlow));
}

void SaveCardBubbleControllerImpl::RefusePresentation() {
  MarkPresentationUnavailable();
  const auto previous = current_bubble_type_;
  auto local = std::move(local_save_card_prompt_callback_);
  auto upload = std::move(upload_save_card_prompt_callback_);
  auto confirmation =
      std::exchange(on_confirmation_closed_callback_, std::nullopt);
  current_bubble_type_ = PaymentsBubbleType::kInactive;
  confirmation_ui_params_.reset();
  auto_close_confirmation_timer_.Stop();
  UpdatePageActionIcon();
  using Decision = payments::PaymentsAutofillClient::SaveCardOfferUserDecision;
  if (local && (previous == PaymentsBubbleType::kLocalSave ||
                previous == PaymentsBubbleType::kLocalCvcSave)) {
    std::move(local).Run(Decision::kNotPresented);
  } else if (upload && (previous == PaymentsBubbleType::kUploadSave ||
                        previous == PaymentsBubbleType::kUploadCvcSave ||
                        previous == PaymentsBubbleType::kUploadCardholderNameUpdate)) {
    std::move(upload).Run(Decision::kNotPresented, {});
  }
  if (confirmation) {
    std::move(*confirmation).Run();
  }
}

}
