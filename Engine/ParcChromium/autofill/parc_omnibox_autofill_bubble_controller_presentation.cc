// Copyright 2026 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/omnibox_autofill_bubble_controller.h"

#include "chrome/browser/ui/autofill/payments/omnibox_autofill_page_action_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "ui/actions/actions.h"

namespace autofill {

void OmniboxAutofillBubbleController::RecordPresentation() {
  if (auto* action = GetActionItem())
    action->SetIsShowingBubble(true);
}

void OmniboxAutofillBubbleController::RefusePresentation() {
  MarkPresentationUnavailable();
  if (auto* action = GetActionItem())
    action->SetIsShowingBubble(false);
}

bool OmniboxAutofillBubbleController::IsNativeRequestCurrent() const {
  return web_contents() && native_document_.AsRenderFrameHostIfValid() ==
                               web_contents()->GetPrimaryMainFrame();
}

bool OmniboxAutofillBubbleController::CanBeReshown() const {
  if (!IsNativeRequestCurrent())
    return false;
  const auto* chip = OmniboxAutofillPageActionController::From(*tab_interface_);
  return chip && chip->IsNativeEntryVisible() && !suggestions_.empty();
}

}
