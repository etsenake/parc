// Copyright 2026 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/wallet_reminder_notice_bubble_controller.h"

#include <utility>
#include "chrome/browser/ui/autofill/payments/wallet_reminder_notice_page_action_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"

namespace autofill {

bool WalletReminderNoticeBubbleController::IsNativeRequestCurrent() const {
  return web_contents() && native_document_.AsRenderFrameHostIfValid() ==
                               web_contents()->GetPrimaryMainFrame();
}

bool WalletReminderNoticeBubbleController::CanBeReshown() const {
  if (!IsNativeRequestCurrent())
    return false;
  auto* chip = WalletReminderNoticePageActionController::From(*tab_interface_);
  return native_request_id_ &&
         (presentation_callback_ || (chip && chip->IsNativeEntryVisible()));
}

void WalletReminderNoticeBubbleController::ReportPresentation(bool presented) {
  auto callback = std::move(presentation_callback_);
  if (presented) {
    if (auto* page_action =
            WalletReminderNoticePageActionController::From(*tab_interface_)) {
      page_action->Show();
    }
  }
  if (callback) {
    std::move(callback).Run(presented);
  }
}

}
