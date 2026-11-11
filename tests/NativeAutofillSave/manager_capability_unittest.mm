// Copyright 2026 Parc contributors.
// Real manager effects; the test client captures UI callbacks and the network
// interface records requests. No payments service, Keychain or real user data.
#include "base/functional/bind.h"
#include "base/strings/utf_string_conversions.h"
#include "base/test/task_environment.h"
#include "components/autofill/core/browser/form_import/addresses/address_profile_save_manager.h"
#include "components/autofill/core/browser/form_import/addresses/autofill_profile_import_process.h"
#include "components/autofill/core/browser/form_import/form_data_importer_util.h"
#include "components/autofill/core/browser/foundations/test_autofill_client.h"
#include "components/autofill/core/browser/payments/credit_card_save_manager.h"
#include "components/autofill/core/browser/payments/iban_save_manager.h"
#include "components/autofill/core/browser/payments/iban_save_manager_test_api.h"
#include "components/autofill/core/browser/payments/multiple_request_payments_network_interface.h"
#include "components/autofill/core/browser/payments/payments_network_interface.h"
#include "components/autofill/core/browser/payments/test_legal_message_line.h"
#include "components/autofill/core/browser/payments/test_payments_autofill_client.h"
#include "components/autofill/core/browser/payments/virtual_card_enrollment_manager.h"
#include "components/autofill/core/browser/payments/wallet_reminder_notice_manager.h"
#include "components/autofill/core/browser/strike_databases/payments/credit_card_save_strike_database.h"
#include "components/autofill/core/browser/strike_databases/payments/iban_save_strike_database.h"
#include "components/autofill/core/browser/test_utils/autofill_test_util.h"
#include "components/autofill/core/browser/ui/payments/wallet_reminder_notice_ui_delegate.h"
#include "components/autofill/core/common/autofill_prefs.h"
#include "parc/chromium_hooks.h"
#include "services/metrics/public/cpp/ukm_source_id.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace parc {
namespace {
using namespace autofill;
using Client = payments::PaymentsAutofillClient;
using Kind = AutofillUiPresentation;
class CapabilityClient : public TestAutofillClient {
 public:
  bool Supports(Kind kind) const {
    return kind != blocked;
  }
  void ConfirmSaveAddressProfile(
      const AutofillProfile&,
      const AutofillProfile*,
      SaveAddressBubbleType,
      AddressProfileSavePromptCallback callback) override {
    ++address_offers;
    pending_address = std::move(callback);
  }
  int address_offers = 0;
  AddressProfileSavePromptCallback pending_address;
  Kind blocked = Kind::kAutofillAiImport;
};
bool SupportsPresentation(const AutofillClient& client, Kind kind) {
  return static_cast<const CapabilityClient&>(client).Supports(kind);
}
class CapturePayments final : public payments::TestPaymentsAutofillClient {
 public:
  explicit CapturePayments(AutofillClient* client)
      : TestPaymentsAutofillClient(client), client_(*client) {}
  bool IsAutofillUiPresentationSupported(Kind kind) const override {
    return autofill::IsAutofillUiPresentationSupported(*client_, kind);
  }
  bool LocalCardSaveIsSupported() override { return true; }
  void ShowSaveCreditCardLocally(
      const CreditCard&,
      SaveCreditCardOptions,
      LocalSaveCardPromptCallback callback) override {
    ++card_offers;
    pending_card = std::move(callback);
  }
  void ShowVirtualCardEnrollDialogWithPresentationOutcome(
      const VirtualCardEnrollmentFields&,
      base::OnceClosure,
      base::OnceClosure,
      base::OnceClosure unavailable) override {
    pending_virtual = std::move(unavailable);
  }
  int card_offers = 0;
  LocalSaveCardPromptCallback pending_card;
  base::OnceClosure pending_virtual;

 private:
  raw_ref<AutofillClient> client_;
};
class CaptureWallet final : public payments::WalletReminderNoticeUiDelegate {
 public:
  void ShowWalletReminderNotice(LegalMessageLines) override {
    ADD_FAILURE() << "Desktop manager must use actual presentation result";
  }
  void ShowWalletReminderNoticeWithPresentationResult(
      LegalMessageLines,
      base::OnceCallback<void(bool)> callback) override {
    pending = std::move(callback);
  }
  base::OnceCallback<void(bool)> pending;
};
class CaptureNetwork final : public payments::PaymentsNetworkInterface {
 public:
  CaptureNetwork() : PaymentsNetworkInterface(nullptr, nullptr, nullptr) {}
  void RecordLegalReminderAcknowledgment(
      const payments::RecordLegalReminderAcknowledgmentRequestDetails& request,
      base::OnceCallback<void(Client::PaymentsRpcResult)> callback) override {
    ++acknowledgments;
    token = request.legal_message_token;
    std::move(callback).Run(Client::PaymentsRpcResult::kSuccess);
  }
  int acknowledgments = 0;
  std::string token;
};
class EpochEnrollment final : public VirtualCardEnrollmentManager {
 public:
  explicit EpochEnrollment(AutofillClient& client)
      : VirtualCardEnrollmentManager(
            &client.GetPersonalDataManager().payments_data_manager(),
            client.GetPaymentsAutofillClient()
                ->GetMultipleRequestPaymentsNetworkInterface(),
            &client) {}
  void Prepare(int64_t id) {
    state_.virtual_card_enrollment_fields.credit_card =
        test::GetMaskedServerCard();
    state_.virtual_card_enrollment_fields.credit_card.set_instrument_id(id);
    state_.virtual_card_enrollment_fields.virtual_card_enrollment_source =
        VirtualCardEnrollmentSource::kUpstream;
  }
  void Show() {
    ShowVirtualCardEnrollBubble(&state_.virtual_card_enrollment_fields);
  }
  int64_t instrument() const {
    return state_.virtual_card_enrollment_fields.credit_card.instrument_id();
  }
  using VirtualCardEnrollmentManager::Reset;
};
// Only preserves the production import result for assertions. Import
// classification, offer, decision, strikes and persistence are all real code.
class InspectAddressManager final : public AddressProfileSaveManager {
 public:
  explicit InspectAddressManager(AutofillClient* client)
      : AddressProfileSaveManager(client) {}
  std::unique_ptr<ProfileImportProcess> last;

 protected:
  void ClearPendingImport(
      std::unique_ptr<ProfileImportProcess> process) override {
    last = std::move(process);
  }
};
class NativeAutofillManagerCapabilityTest : public testing::Test {
 protected:
  void SetUp() override {
    parc_hooks::SetAutofillUiPresentationSupport(&SupportsPresentation);
    auto payments = std::make_unique<CapturePayments>(&client);
    capture = payments.get();
    client.set_payments_autofill_client(std::move(payments));
    client.GetPersonalDataManager()
        .test_payments_data_manager()
        .SetAutofillPaymentMethodsEnabled(true);
  }
  void TearDown() override {
    parc_hooks::SetAutofillUiPresentationSupport(nullptr);
  }
  base::test::TaskEnvironment tasks;
  test::AutofillUnitTestEnvironment autofill_environment;
  CapabilityClient client;
  raw_ptr<CapturePayments> capture = nullptr;
};
TEST_F(NativeAutofillManagerCapabilityTest,
       LocalCardNotPresentedDoesNotStrikeOrSaveAndNextOfferWorks) {
  CreditCardSaveManager manager(&client);
  auto card = test::GetCreditCard();
  CreditCardSaveStrikeDatabase strikes(client.GetStrikeDatabase());
  const std::string key = base::UTF16ToUTF8(card.LastFourDigits());
  const auto initial_cards = client.GetPersonalDataManager()
                                 .payments_data_manager()
                                 .GetCreditCards()
                                 .size();
  EXPECT_TRUE(manager.AttemptToOfferCardLocalSave(card));
  ASSERT_TRUE(capture->pending_card);
  std::move(capture->pending_card)
      .Run(Client::SaveCardOfferUserDecision::kNotPresented);
  EXPECT_EQ(strikes.GetStrikes(key), 0);
  EXPECT_EQ(client.GetPersonalDataManager()
                .payments_data_manager()
                .GetCreditCards()
                .size(),
            initial_cards);
  EXPECT_TRUE(manager.AttemptToOfferCardLocalSave(card));
  ASSERT_TRUE(capture->pending_card);
  EXPECT_EQ(capture->card_offers, 2);
  std::move(capture->pending_card)
      .Run(Client::SaveCardOfferUserDecision::kDeclined);
  EXPECT_EQ(strikes.GetStrikes(key),
            1);  // Actual user refusal remains distinct.
}
TEST_F(NativeAutofillManagerCapabilityTest,
       AddressRefusalHasNoPromptStrikeOrDataAndNextOfferProgresses) {
  InspectAddressManager manager(&client);
  auto& data = client.GetPersonalDataManager().test_address_data_manager();
  const GURL source("https://autofill-fixture.invalid/form");
  const auto profile = test::GetFullProfile();
  const auto offer = [&] {
    manager.ImportProfileFromForm(profile, "en-US", source,
                                  ukm::kInvalidSourceId, false,
                                  ProfileImportMetadata{});
  };
  offer();
  ASSERT_TRUE(client.pending_address);
  std::move(client.pending_address)
      .Run(AutofillClient::AddressPromptUserDecision::kAutoDeclined,
           std::nullopt);
  ASSERT_TRUE(manager.last);
  EXPECT_FALSE(manager.last->prompt_shown());
  EXPECT_FALSE(manager.last->UserDeclined());
  EXPECT_TRUE(data.GetProfiles().empty());
  EXPECT_EQ(data.GetProfileSaveStrikeDatabase()->GetStrikes(source.GetHost()),
            0);
  offer();
  ASSERT_TRUE(client.pending_address);
  EXPECT_EQ(client.address_offers, 2);
  std::move(client.pending_address)
      .Run(AutofillClient::AddressPromptUserDecision::kDeclined, std::nullopt);
  EXPECT_TRUE(manager.last->prompt_shown());
  EXPECT_TRUE(manager.last->UserDeclined());
  EXPECT_EQ(data.GetProfileSaveStrikeDatabase()->GetStrikes(source.GetHost()),
            1);
  EXPECT_TRUE(data.GetProfiles().empty());
}
TEST_F(NativeAutofillManagerCapabilityTest,
       UnsupportedAddressOfferNeverSetsPromptState) {
  InspectAddressManager manager(&client);
  client.blocked = Kind::kLocalAddressSave;
  manager.ImportProfileFromForm(test::GetFullProfile(), "en-US",
                                GURL("https://autofill-fixture.invalid/form"),
                                ukm::kInvalidSourceId, false,
                                ProfileImportMetadata{});
  EXPECT_EQ(client.address_offers, 0);
  ASSERT_TRUE(manager.last);
  EXPECT_FALSE(manager.last->prompt_shown());
  EXPECT_FALSE(manager.last->UserDeclined());
  EXPECT_TRUE(client.GetPersonalDataManager()
                  .address_data_manager()
                  .GetProfiles()
                  .empty());
}
TEST_F(NativeAutofillManagerCapabilityTest,
       IbanNeutralResultDoesNotStrikeOrPersist) {
  IbanSaveManager manager(&client);
  auto iban = test::GetLocalIban();
  auto api = test_api(manager);
  auto* strikes = api.GetIbanSaveStrikeDatabase();
  const auto key = IbanSaveManager::GetPartialIbanHashString(
      base::UTF16ToUTF8(iban.value()));
  const auto count = client.GetPersonalDataManager()
                         .payments_data_manager()
                         .GetLocalIbans()
                         .size();
  api.OnUserDidDecideOnLocalSave(
      iban, Client::SaveIbanOfferUserDecision::kNotPresented);
  EXPECT_EQ(strikes->GetStrikes(key), 0);
  EXPECT_FALSE(api.OnUserDidDecideOnUploadSave(
      iban, Client::SaveIbanOfferUserDecision::kNotPresented));
  EXPECT_EQ(strikes->GetStrikes(key), 0);
  EXPECT_EQ(client.GetPersonalDataManager()
                .payments_data_manager()
                .GetLocalIbans()
                .size(),
            count);
  client.blocked = Kind::kIbanSave;
  EXPECT_FALSE(api.AttemptToOfferLocalSave(iban));
  EXPECT_FALSE(api.AttemptToOfferUploadSave(iban));
}
TEST_F(NativeAutofillManagerCapabilityTest,
       OldVirtualUnavailableCannotResetReplacementEpoch) {
  EpochEnrollment manager(client);
  manager.Prepare(101);
  manager.Show();
  ASSERT_TRUE(capture->pending_virtual);
  auto old = std::move(capture->pending_virtual);
  manager.Reset();
  manager.Prepare(202);
  manager.Show();
  ASSERT_TRUE(capture->pending_virtual);
  std::move(old).Run();
  EXPECT_EQ(manager.instrument(), 202);
  std::move(capture->pending_virtual).Run();
  EXPECT_NE(manager.instrument(), 202);
}
TEST_F(NativeAutofillManagerCapabilityTest,
       WalletQueueOrRefusalDoesNotAcknowledgeButActualPresentationDoes) {
  auto network = std::make_unique<CaptureNetwork>();
  auto* n = network.get();
  capture->set_payments_network_interface(std::move(network));
  auto ui = std::make_unique<CaptureWallet>();
  auto* view = ui.get();
  capture->set_wallet_reminder_notice_ui_delegate(std::move(ui));
  payments::WalletReminderNoticeManager manager(&client);
  payments::GetWalletReminderNoticeResponseDetails response;
  response.legal_message_lines = {
      TestLegalMessageLine("Synthetic legal disclosure")};
  response.acknowledgement_token = "local-fixture-token";
  response.has_user_been_shown_reminder = false;
  auto flow = payments::RecordLegalReminderAcknowledgmentRequestDetails::
      FlowType::kChromeDownstream;
  manager.OnGetWalletReminderNoticeResponse(
      flow, Client::PaymentsRpcResult::kSuccess, response);
  ASSERT_TRUE(view->pending);
  EXPECT_EQ(n->acknowledgments, 0);
  EXPECT_FALSE(
      autofill::prefs::HasShownWalletReminderNotice(client.GetPrefs()));
  std::move(view->pending).Run(false);
  EXPECT_EQ(n->acknowledgments, 0);
  EXPECT_FALSE(
      autofill::prefs::HasShownWalletReminderNotice(client.GetPrefs()));
  manager.OnGetWalletReminderNoticeResponse(
      flow, Client::PaymentsRpcResult::kSuccess, response);
  ASSERT_TRUE(view->pending);
  std::move(view->pending).Run(true);
  EXPECT_EQ(n->acknowledgments, 1);
  EXPECT_EQ(n->token, "local-fixture-token");
  EXPECT_TRUE(autofill::prefs::HasShownWalletReminderNotice(client.GetPrefs()));
}
}  // namespace
}  // namespace parc
