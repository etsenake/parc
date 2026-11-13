// Copyright 2023 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/chrome_payments_autofill_client.h"

#include <utility>
#include "chrome/browser/ui/autofill/payments/virtual_card_enroll_bubble_controller_impl.h"
#include "components/autofill/content/browser/content_autofill_client.h"

namespace autofill::payments {

bool ChromePaymentsAutofillClient::IsAutofillUiPresentationSupported(
    AutofillUiPresentation presentation) const {
  return autofill::IsAutofillUiPresentationSupported(*client_, presentation);
}

void ChromePaymentsAutofillClient::
    ShowVirtualCardEnrollDialogWithPresentationOutcome(
        const VirtualCardEnrollmentFields& fields,
        base::OnceClosure accept,
        base::OnceClosure decline,
        base::OnceClosure unavailable) {
  if (!IsAutofillUiPresentationSupported(
          AutofillUiPresentation::kVirtualCardEnrollment)) {
    if (unavailable) {
      std::move(unavailable).Run();
    }
    return;
  }
  VirtualCardEnrollBubbleControllerImpl::CreateForWebContents(web_contents());
  auto* controller =
      VirtualCardEnrollBubbleControllerImpl::FromWebContents(web_contents());
  controller->SetupAndShowBubble(fields, std::move(accept), std::move(decline),
                                 std::move(unavailable));
}

}
