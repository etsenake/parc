// Copyright 2023 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/iban_bubble_controller_impl.h"

#include <utility>
#include "components/autofill/core/browser/ui/payments/save_payment_method_and_virtual_card_enroll_confirmation_ui_params.h"

namespace autofill {

void IbanBubbleControllerImpl::RefusePresentation() {
  MarkPresentationUnavailable();
  auto callback = std::move(save_iban_prompt_callback_);
  current_bubble_type_ = IbanBubbleType::kInactive;
  confirmation_ui_params_.reset();
  auto_close_confirmation_timer_.Stop();
  UpdatePageActionIcon();
  if (callback) {
    std::move(callback).Run(payments::PaymentsAutofillClient::
                                SaveIbanOfferUserDecision::kNotPresented,
                            {});
  }
}

}
