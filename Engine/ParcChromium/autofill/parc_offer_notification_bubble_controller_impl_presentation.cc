// Copyright 2021 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/offer_notification_bubble_controller_impl.h"

#include "components/autofill/core/browser/data_model/payments/autofill_offer_data.h"
#include "content/public/browser/web_contents.h"
#include "url/origin.h"

namespace autofill {

void OfferNotificationBubbleControllerImpl::RefusePresentation() {
  MarkPresentationUnavailable();
  bubble_state_ = BubbleState::kHidden;
  bubble_shown_timestamp_.reset();
  UpdatePageActionIcon();
}

bool OfferNotificationBubbleControllerImpl::CanBeReshown() const {
  return IsIconVisible() &&
         offer_.GetOfferType() != AutofillOfferData::OfferType::UNKNOWN &&
         offer_.IsActiveAndEligibleForOrigin(
             url::Origin::Create(web_contents()->GetLastCommittedURL())
                 .GetURL());
}

}
