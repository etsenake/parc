#include "chrome/browser/ui/autofill/parc_bubble_presentation.h"

#include "chrome/browser/ui/autofill/autofill_bubble_controller_base.h"
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"

namespace autofill {
bool ParcBubblePresentation::SupportsCardOffer(
    content::WebContents* contents,
    const payments::PaymentsAutofillClient::SaveCreditCardOptions& options,
    bool upload) {
  const bool cvc = options.card_save_type ==
                   payments::PaymentsAutofillClient::CardSaveType::kCvcSaveOnly;
  const auto kind =
      upload ? (cvc ? AutofillUiPresentation::kUploadCvcSave
                    : AutofillUiPresentation::kUploadCardSave)
             : (cvc ? AutofillUiPresentation::kLocalCvcSave
                    : AutofillUiPresentation::kLocalCardSave);
  return AutofillBubbleHandler::IsPresentationSupported(contents, kind) &&
         (options.show_prompt ||
          AutofillBubbleHandler::IsPresentationSupported(
              contents, AutofillUiPresentation::kCardIcon)) &&
         (!(options.should_request_name_from_user ||
            options.should_request_expiration_date_from_user) ||
          AutofillBubbleHandler::IsPresentationSupported(
              contents, AutofillUiPresentation::kCardFixFlow));
}

void ParcBubblePresentation::Adopt(
    AutofillBubbleControllerBase& controller,
    AutofillBubbleBase* view,
    base::OnceClosure shown,
    base::OnceClosure unavailable) {
  if (!view) {
    if (unavailable) {
      std::move(unavailable).Run();
    }
    return;
  }
  controller.SetBubbleView(*view);
  controller.ObservePresentation(std::move(shown), std::move(unavailable));
}
}
