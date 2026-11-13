// Copyright 2023 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/mandatory_reauth_bubble_controller_impl.h"

#include "components/autofill/core/browser/metrics/payments/mandatory_reauth_metrics.h"

namespace autofill {

void MandatoryReauthBubbleControllerImpl::RefusePresentation() {
  MarkPresentationUnavailable();
  accept_mandatory_reauth_callback_.Reset();
  cancel_mandatory_reauth_callback_.Reset();
  close_mandatory_reauth_callback_.Reset();
  current_bubble_type_ = MandatoryReauthBubbleType::kInactive;
  UpdatePageActionIcon();
}

void MandatoryReauthBubbleControllerImpl::RecordPresentation() {
  UpdatePageActionIcon();
  if (current_bubble_type_ == MandatoryReauthBubbleType::kOptIn) {
    autofill_metrics::LogMandatoryReauthOptInBubbleOffer(
        autofill_metrics::MandatoryReauthOptInBubbleOffer::kShown, is_reshow_);
  } else if (current_bubble_type_ == MandatoryReauthBubbleType::kConfirmation) {
    autofill_metrics::LogMandatoryReauthOptInConfirmationBubbleMetric(
        autofill_metrics::MandatoryReauthOptInConfirmationBubbleMetric::kShown);
  }
}

}
