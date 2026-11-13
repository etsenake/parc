// Copyright 2026 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/payments_churned_users_bubble_controller.h"

#include "base/notreached.h"
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "components/autofill/core/browser/payments/payments_churned_users_metrics.h"
#include "components/strings/grit/components_strings.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/l10n/l10n_util.h"

namespace autofill {

std::u16string PaymentsChurnedUsersBubbleController::GetWindowTitle() const {
  switch (GetAutofillEnableResurrectingPaymentsUsersTreatmentArm()) {
    case AutofillEnableResurrectingPaymentsUsersTreatmentArm::kSecurity: {
      return l10n_util::GetStringUTF16(
          IDS_AUTOFILL_CHURNED_USERS_BUBBLE_SECURITY_TITLE);
    }
    case AutofillEnableResurrectingPaymentsUsersTreatmentArm::kConvenience: {
      return l10n_util::GetStringUTF16(
          IDS_AUTOFILL_CHURNED_USERS_BUBBLE_CONVENIENCE_TITLE);
    }
    case AutofillEnableResurrectingPaymentsUsersTreatmentArm::kMessage:
      NOTREACHED();
  }
}

bool PaymentsChurnedUsersBubbleController::IsNativeRequestCurrent() const {
  return web_contents() && native_document_.AsRenderFrameHostIfValid() ==
                               web_contents()->GetPrimaryMainFrame();
}

void PaymentsChurnedUsersBubbleController::RefusePresentation() {
  MarkPresentationUnavailable();
  closed_callback_.Reset();
  should_show_icon_ = false;
  UpdatePageActionIcon();
}

void PaymentsChurnedUsersBubbleController::RecordPresentation() {
  UpdatePageActionIcon();
  autofill_metrics::LogPaymentsChurnedUsersUiShowResult(
      autofill_metrics::PaymentsChurnedUsersUiShowResult::kShown);
}

}
