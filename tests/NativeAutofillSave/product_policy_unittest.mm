// Copyright 2026 Parc contributors.
// The real page client is constructed before Browser/tab attachment. Force the
// upstream features on so a missing Browser cannot accidentally be the gate.
#include "base/functional/bind.h"
#include "base/test/scoped_feature_list.h"
#include "cef/libcef/features/parc_product_policy.h"
#include "chrome/browser/ui/autofill/autofill_ai/autofill_ai_import_data_controller.h"
#include "chrome/browser/ui/autofill/autofill_ai/autofill_ai_import_data_controller_impl.h"
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "chrome/browser/ui/autofill/chrome_autofill_client.h"
#include "chrome/test/base/chrome_render_view_host_test_harness.h"
#include "components/autofill/core/browser/test_utils/entity_data_test_util.h"
#include "components/autofill/core/common/autofill_features.h"
#include "components/tabs/public/tab_interface.h"
#include "testing/gtest/include/gtest/gtest.h"

static_assert(BUILDFLAG(IS_PARC_BROWSER));
namespace parc {
namespace {
class ProductClient final : public autofill::ChromeAutofillClient {
 public:
  explicit ProductClient(content::WebContents* page)
      : ChromeAutofillClient(page) {}
};
class NativeAutofillProductPolicyTest : public ChromeRenderViewHostTestHarness {
 protected:
  void SetUp() override {
    features_.InitWithFeatures({autofill::features::kAutofillAiWithDataSchema,
                                autofill::features::kAutofillAtMemory,
                                autofill::features::kAutofillActorMode},
                               {});
    ChromeRenderViewHostTestHarness::SetUp();
  }

 private:
  base::test::ScopedFeatureList features_;
};
TEST_F(NativeAutofillProductPolicyTest,
       ConstructorExcludesAiBeforeBrowserAttachment) {
  ASSERT_EQ(tabs::TabInterface::MaybeGetFromContents(web_contents()), nullptr);
  ProductClient client(web_contents());
  EXPECT_EQ(client.GetAutofillAiManager(), nullptr);
  EXPECT_EQ(client.GetAtMemoryManager(), nullptr);
  EXPECT_TRUE(autofill::AutofillBubbleHandler::IsPresentationSupported(
      web_contents(), autofill::AutofillUiPresentation::kLocalAddressSave));
  EXPECT_EQ(autofill::AutofillAiImportDataController::GetOrCreate(
                web_contents(), "en-US"),
            nullptr);
  EXPECT_EQ(autofill::AutofillAiImportDataControllerImpl::FromWebContents(
                web_contents()),
            nullptr);
}
TEST_F(NativeAutofillProductPolicyTest,
       DirectOfferSettlesUnknownAndSuppressionIsNotAccepted) {
  ProductClient client(web_contents());
  int results = 0;
  client.ShowEntityImportBubble(
      autofill::test::GetPassportEntityInstance(), std::nullopt, true, {},
      base::BindOnce(
          [](int* calls,
             autofill::AutofillClient::AutofillAiBubbleResult result,
             std::optional<autofill::EntityInstance> edited,
             const autofill::AutofillClient::EntityImportUIContext& context) {
            ++*calls;
            EXPECT_EQ(
                result,
                autofill::AutofillClient::AutofillAiBubbleResult::kUnknown);
            EXPECT_FALSE(edited);
            EXPECT_FALSE(context.accepted_consent_string_id);
          },
          &results));
  EXPECT_EQ(results, 1);
  int decisions = 0;
  client.ShowAutofillAiSuppressionConfirmationDialog(
      autofill::test::GetPassportEntityInstance(),
      base::BindOnce(
          [](int* calls, bool accepted) {
            ++*calls;
            EXPECT_FALSE(accepted);
          },
          &decisions));
  EXPECT_EQ(decisions, 1);
  client.ShowAutofillAiLocalSaveNotification();
  client.ShowAutofillAiSaveToWalletFailureNotification();
  client.ShowAutofillAiFetchEntityFailureNotification();
  client.ShowAtMemoryFetchFailureNotification(std::nullopt);
  client.ShowAutofillAiPreFetchFailureNotification();
  client.ShowAutofillAiPrivateInferenceNotice();
  EXPECT_EQ(autofill::AutofillAiImportDataControllerImpl::FromWebContents(
                web_contents()),
            nullptr);
}
}  // namespace
}  // namespace parc
