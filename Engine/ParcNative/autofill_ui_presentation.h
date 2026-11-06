// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef COMPONENTS_AUTOFILL_CORE_BROWSER_UI_AUTOFILL_UI_PRESENTATION_H_
#define COMPONENTS_AUTOFILL_CORE_BROWSER_UI_AUTOFILL_UI_PRESENTATION_H_
namespace autofill {
// Presentation capabilities, not permissions to fill or access existing data.
// Keep requests distinct: a local new-card sheet cannot present a CVC-only,
// upload, fix, management, or icon-only offer.
enum class AutofillUiPresentation {
  kLocalCardSave,
  kLocalCvcSave,
  kUploadCardSave,
  kUploadCvcSave,
  kCardFixFlow,
  kCardIcon,
  kManageCards,
  kCardConfirmation,
  kLocalAddressSave,
  kAccountAddressSave,
  kAddressUpdate,
  kAddressMigration,
  kAddressMerge,
  kAddressSignInPromo,
  kIbanSave,
  kIbanConfirmation,
  kOfferNotification,
  kAutofillAiImport,
  kAutofillAiNotification,
  kFilledCardInformation,
  kVirtualCardEnrollment,
  kVirtualCardConfirmation,
  kMandatoryReauthOptIn,
  kMandatoryReauthConfirmation,
  kOmniboxAutofill,
  kPaymentsChurnedUsers,
  kPaymentsChurnedUsersConfirmation,
  kWalletReminder,
};
}  // namespace autofill
#endif
