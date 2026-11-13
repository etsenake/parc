// Copyright 2021 The Chromium Authors

#include "chrome/browser/ui/autofill/payments/filled_card_information_bubble_controller_impl.h"


namespace autofill {

void FilledCardInformationBubbleControllerImpl::RefusePresentation() {
  MarkPresentationUnavailable();
  should_icon_be_visible_ = false;
  UpdatePageActionIcon();
}

bool FilledCardInformationBubbleControllerImpl::CanBeReshown() const {
  return should_icon_be_visible_ && options_.IsValid();
}

}
