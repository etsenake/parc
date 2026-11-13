// Copyright 2022 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/virtual_card_enroll_bubble_controller_impl.h"

#include <utility>

namespace autofill {

void VirtualCardEnrollBubbleControllerImpl::RefusePresentation() {
  MarkPresentationUnavailable();
  auto unavailable = std::move(presentation_unavailable_);
  accept_virtual_card_callback_.Reset();
  decline_virtual_card_callback_.Reset();
#if !BUILDFLAG(IS_ANDROID)
  ResetBubble();
  UpdatePageActionIcon();
#endif
  if (unavailable) {
    std::move(unavailable).Run();
  }
}

}
