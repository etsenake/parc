// Copyright 2026 Parc contributors.
#import <AppKit/AppKit.h>

#include <memory>
#include <utility>
#include <vector>

#include "autofill_save_session.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "base/time/time.h"
#include "chrome/browser/autofill/personal_data_manager_factory.h"
#include "chrome/browser/ui/autofill/address_bubbles_controller.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller_impl.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/test/test_autofill_bubble_handler.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/autofill/core/browser/data_manager/test_personal_data_manager.h"
#include "components/autofill/core/browser/payments/payments_autofill_client.h"
#include "components/autofill/core/browser/test_utils/autofill_test_util.h"
#include "components/prefs/pref_service.h"
#include "components/signin/public/base/signin_pref_names.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "parc/tests/parc_native_test_support/browser_window_test.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

namespace parc {
namespace {
using CardController = autofill::SaveCardBubbleControllerImpl;
using CardClient = autofill::payments::PaymentsAutofillClient;
using CardDecision = CardClient::SaveCardOfferUserDecision;
using AddressDecision = autofill::AutofillClient::AddressPromptUserDecision;
using AddressType = autofill::AutofillClient::SaveAddressBubbleType;
using PaymentState = autofill::PaymentsBubbleType;

std::unique_ptr<KeyedService> CreateMemoryOnlyPersonalDataManager(
    content::BrowserContext*) {
  auto manager = std::make_unique<autofill::TestPersonalDataManager>();
  manager->test_payments_data_manager().SetAutofillPaymentMethodsEnabled(true);
  return manager;
}

NSButton* FindButton(NSView* view, NSString* title) {
  if ([view isKindOfClass:NSButton.class] &&
      [static_cast<NSButton*>(view).title isEqualToString:title]) {
    return static_cast<NSButton*>(view);
  }
  for (NSView* child in view.subviews) {
    if (NSButton* button = FindButton(child, title)) {
      return button;
    }
  }
  return nil;
}

template <typename Predicate>
bool PumpUntil(Predicate predicate) {
  const auto deadline = base::TimeTicks::Now() + base::Seconds(5);
  do {
    base::RunLoop().RunUntilIdle();
    if (predicate()) {
      return true;
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
  } while (base::TimeTicks::Now() < deadline);
  return predicate();
}

class SessionHandler final : public autofill::TestAutofillBubbleHandler {
 public:
  autofill::AutofillBubbleBase* ShowSaveCreditCardBubble(
      content::WebContents* contents,
      autofill::SaveCardBubbleController* controller,
      bool ) override {
    auto* actual = CardController::FromWebContents(contents);
    CHECK(actual && controller == actual);
    auto* browser = tabs::TabInterface::GetFromContents(contents)
                        ->GetBrowserWindowInterface();
    CHECK(browser);
    auto* session = NativeAutofillSaveSession::CreateLocalCard(
        *browser, *contents, Host(contents),
        browser->GetWindow()->GetNativeWindow(), *actual);
    return Remember(session);
  }

  autofill::AutofillBubbleBase* ShowSaveAddressProfileBubble(
      content::WebContents* contents,
      std::unique_ptr<autofill::SaveAddressBubbleController> controller,
      bool ) override {
    auto* browser = tabs::TabInterface::GetFromContents(contents)
                        ->GetBrowserWindowInterface();
    CHECK(browser);
    auto* session = NativeAutofillSaveSession::CreateLocalAddress(
        *browser, *contents, Host(contents),
        browser->GetWindow()->GetNativeWindow(), std::move(controller));
    return Remember(session);
  }

  void InterruptAll() {
    for (auto session : sessions_) {
      if (session) {
        session->PageHostWillDetach();
      }
    }
  }

  bool AllDestroyed() const {
    for (auto session : sessions_) {
      if (session) {
        return false;
      }
    }
    return true;
  }

  base::WeakPtr<NativeAutofillSaveSession> last;
  int created = 0;

 private:
  gfx::NativeView Host(content::WebContents* contents) {
    NSView* native = contents->GetNativeView().GetNativeNSView();
    CHECK(native && native.superview && native.window);
    return gfx::NativeView(native.superview);
  }
  NativeAutofillSaveSession* Remember(NativeAutofillSaveSession* session) {
    last = session->GetWeakPtr();
    sessions_.push_back(last);
    ++created;
    return session;
  }
  std::vector<base::WeakPtr<NativeAutofillSaveSession>> sessions_;
};

class SessionTestWindow final : public TestBrowserWindow {
 public:
  SessionTestWindow(NSWindow* window, SessionHandler& handler)
      : native_window_(window), handler_(handler) {}
  gfx::NativeWindow GetNativeWindow() const override {
    return gfx::NativeWindow(native_window_);
  }
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override {
    return &handler_.get();
  }

 private:
  __weak NSWindow* native_window_;
  const raw_ref<SessionHandler> handler_;
};
}

class NativeAutofillSaveSessionTest : public ParcBrowserWindowTest {
 public:
  void SetUp() override {
    ParcBrowserWindowTest::SetUp();
    ASSERT_TRUE(native_window_);
    profile()->GetPrefs()->SetBoolean(prefs::kSigninAllowed, false);
    ASSERT_FALSE(window()->AsBrowserView());
    ASSERT_EQ(nullptr, autofill::AutofillBubbleHandler::Get(
                           browser()->GetUnownedUserDataHost()));
    registration_ = std::make_unique<
        ui::ScopedUnownedUserData<autofill::AutofillBubbleHandler>>(
        browser()->GetUnownedUserDataHost(), handler_);

    AddTab(browser(), GURL("about:blank"));
    NSView* native = contents()->GetNativeView().GetNativeNSView();
    ASSERT_TRUE(native);
    native.frame = native_window_.contentView.bounds;
    [native_window_.contentView addSubview:native];
    ASSERT_EQ(native.window, native_window_);
    ASSERT_EQ(tabs::TabInterface::GetFromContents(contents())
                  ->GetBrowserWindowInterface(),
              browser());
    contents()->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
    CardController::CreateForWebContents(contents());
    ASSERT_TRUE(card());
  }

  void TearDown() override {
    handler_.InterruptAll();
    browser()->GetTabStripModel()->CloseAllTabs();
    EXPECT_TRUE(PumpUntil([this] { return handler_.AllDestroyed(); }));
    registration_.reset();
    ParcBrowserWindowTest::TearDown();
    [native_window_ close];
    native_window_ = nil;
  }

 protected:
  TestingProfile::TestingFactories GetTestingFactories() override {
    auto factories = BrowserWithTestWindowTest::GetTestingFactories();
    factories.emplace_back(
        autofill::PersonalDataManagerFactory::GetInstance(),
        base::BindRepeating(&CreateMemoryOnlyPersonalDataManager));
    return factories;
  }

  std::unique_ptr<BrowserWindow> CreateBrowserWindow() override {
    native_window_ = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(-2000, -2000, 600, 400)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    native_window_.releasedWhenClosed = NO;
    [native_window_ orderFront:nil];
    return std::make_unique<SessionTestWindow>(native_window_, handler_);
  }

  content::WebContents* contents() {
    return browser()->GetTabStripModel()->GetActiveWebContents();
  }
  CardController* card() { return CardController::FromWebContents(contents()); }
  autofill::AddressBubblesController* address() {
    return autofill::AddressBubblesController::FromWebContents(contents());
  }
  void OfferCard(CardClient::LocalSaveCardPromptCallback callback) {
    auto ignore_activation = CardController::IgnoreWindowActivationForTesting();
    card()->OfferLocalSave(
        autofill::test::GetCreditCard(),
        CardClient::SaveCreditCardOptions()
            .with_card_save_type(CardClient::CardSaveType::kCardSaveOnly)
            .with_show_prompt(true),
        std::move(callback));
  }
  void OfferAddress(
      autofill::AutofillClient::AddressProfileSavePromptCallback callback) {
    autofill::AddressBubblesController::SetUpAndShowSaveOrUpdateAddressBubble(
        contents(), address_profile_, nullptr, AddressType::kSave,
        true, std::move(callback));
  }
  void AwaitSheet() {
    ASSERT_TRUE(
        PumpUntil([this] { return native_window_.attachedSheet != nil; }));
    EXPECT_EQ(native_window_.attachedSheet.sheetParent, native_window_);
  }
  void Click(NSString* title) {
    NSButton* button =
        FindButton(native_window_.attachedSheet.contentView, title);
    ASSERT_TRUE(button);
    ASSERT_TRUE(button.enabled);
    [button performClick:nil];
  }
  int decisions_ = 0;
  int replacement_decisions_ = 0;
  std::vector<AddressDecision> address_decisions_;
  base::WeakPtr<NativeAutofillSaveSession> replacement_;
  const autofill::AutofillProfile address_profile_ =
      autofill::test::GetFullProfile();
  SessionHandler handler_;
  NSWindow* __strong native_window_ = nil;

 private:
  std::unique_ptr<ui::ScopedUnownedUserData<autofill::AutofillBubbleHandler>>
      registration_;
};

TEST_F(NativeAutofillSaveSessionTest, RegistersActualBubbleBeforePresentation) {
  OfferCard(base::BindLambdaForTesting([this](CardDecision decision) {
    ++decisions_;
    EXPECT_EQ(decision, CardDecision::kDeclined);
  }));
  ASSERT_TRUE(handler_.last);
  auto session = handler_.last;
  EXPECT_EQ(card()->GetPaymentBubbleView(), session.get());
  EXPECT_EQ(native_window_.attachedSheet, nil);
  EXPECT_EQ(decisions_, 0);
  AwaitSheet();
  Click(@"Not Now");
  EXPECT_EQ(decisions_, 0);
  ASSERT_TRUE(PumpUntil([&] { return !session; }));
  EXPECT_EQ(decisions_, 1);
  EXPECT_EQ(card()->GetPaymentBubbleView(), nullptr);
  EXPECT_EQ(card()->GetPaymentsBubbleType(), PaymentState::kInactive);
}

TEST_F(NativeAutofillSaveSessionTest,
       AcceptedSaveReentrantHideFinalizesRealState) {
  OfferCard(base::BindLambdaForTesting([this](CardDecision decision) {
    ++decisions_;
    EXPECT_EQ(decision, CardDecision::kAccepted);
    auto accepting = handler_.last;
    card()->HideBubble(false);
    EXPECT_EQ(card()->GetPaymentsBubbleType(), PaymentState::kManageCards);
    EXPECT_EQ(card()->GetPaymentBubbleView(), nullptr);
    base::RunLoop().RunUntilIdle();
    EXPECT_TRUE(accepting);
  }));
  auto session = handler_.last;
  AwaitSheet();
  Click(@"Save");
  ASSERT_TRUE(PumpUntil([&] { return !session; }));
  EXPECT_EQ(decisions_, 1);
  EXPECT_EQ(card()->GetPaymentsBubbleType(), PaymentState::kManageCards);
  EXPECT_EQ(card()->GetPaymentBubbleView(), nullptr);
}

TEST_F(NativeAutofillSaveSessionTest,
       ReentrantReplacementSurvivesOldCompletion) {
  OfferCard(base::BindLambdaForTesting([this](CardDecision decision) {
    ++decisions_;
    EXPECT_EQ(decision, CardDecision::kAccepted);
    card()->HideBubble(false);
    EXPECT_EQ(card()->GetPaymentsBubbleType(), PaymentState::kManageCards);
    OfferCard(base::BindLambdaForTesting([this](CardDecision next) {
      ++replacement_decisions_;
      EXPECT_EQ(next, CardDecision::kDeclined);
    }));
    replacement_ = handler_.last;
    EXPECT_TRUE(replacement_);
    EXPECT_EQ(card()->GetPaymentBubbleView(), replacement_.get());
    EXPECT_EQ(card()->GetPaymentsBubbleType(), PaymentState::kLocalSave);
  }));
  auto old_session = handler_.last;
  AwaitSheet();
  Click(@"Save");
  ASSERT_TRUE(PumpUntil([&] { return !old_session && replacement_; }));
  ASSERT_TRUE(replacement_);
  EXPECT_EQ(handler_.created, 2);
  EXPECT_EQ(card()->GetPaymentBubbleView(), replacement_.get());
  EXPECT_EQ(card()->GetPaymentsBubbleType(), PaymentState::kLocalSave);
  EXPECT_EQ(decisions_, 1);
  EXPECT_EQ(replacement_decisions_, 0);
  AwaitSheet();
  Click(@"Not Now");
  ASSERT_TRUE(PumpUntil([&] { return !replacement_; }));
  EXPECT_EQ(replacement_decisions_, 1);
  EXPECT_EQ(card()->GetPaymentsBubbleType(), PaymentState::kInactive);
}

TEST_F(NativeAutofillSaveSessionTest, PageLossCancelsQueuedCardAcceptance) {
  OfferCard(base::BindLambdaForTesting([this](CardDecision) { ++decisions_; }));
  auto session = handler_.last;
  auto controller = card()->GetBubbleControllerBaseWeakPtr();
  AwaitSheet();
  Click(@"Save");
  EXPECT_EQ(decisions_, 0);
  browser()->GetTabStripModel()->CloseAllTabs();
  ASSERT_TRUE(PumpUntil([&] { return !session && !controller; }));
  EXPECT_EQ(decisions_, 0);
  EXPECT_EQ(native_window_.attachedSheet, nil);
}

TEST_F(NativeAutofillSaveSessionTest, ActualAddressSaveUsesOwnedController) {
  OfferAddress(base::BindLambdaForTesting(
      [this](AddressDecision decision,
             base::optional_ref<const autofill::AutofillProfile> value) {
        ++decisions_;
        EXPECT_EQ(decision, AddressDecision::kAccepted);
        ASSERT_TRUE(value);
        EXPECT_EQ(value->guid(), address_profile_.guid());
      }));
  ASSERT_TRUE(address());
  auto session = handler_.last;
  ASSERT_TRUE(session);
  EXPECT_EQ(address()->GetBubbleView(), session.get());
  EXPECT_EQ(native_window_.attachedSheet, nil);
  AwaitSheet();
  Click(@"Save");
  ASSERT_TRUE(PumpUntil([&] { return !session; }));
  EXPECT_EQ(decisions_, 1);
  EXPECT_EQ(address()->GetBubbleView(), nullptr);
  EXPECT_FALSE(address()->IsBubbleActive());
}

TEST_F(NativeAutofillSaveSessionTest, AddressDeclineAndPageLossAreDistinct) {
  auto callback = [&] {
    return base::BindLambdaForTesting(
        [this](AddressDecision decision,
               base::optional_ref<const autofill::AutofillProfile> value) {
          address_decisions_.push_back(decision);
          EXPECT_FALSE(value);
        });
  };
  OfferAddress(callback());
  auto first = handler_.last;
  ASSERT_TRUE(first);
  AwaitSheet();
  Click(@"No Thanks");
  ASSERT_TRUE(PumpUntil([&] { return !first; }));
  ASSERT_EQ(address_decisions_.size(), 1u);
  EXPECT_EQ(address_decisions_[0], AddressDecision::kDeclined);

  OfferAddress(callback());
  auto second = handler_.last;
  ASSERT_TRUE(second);
  browser()->GetTabStripModel()->CloseAllTabs();
  ASSERT_TRUE(PumpUntil([&] { return !second; }));
  ASSERT_EQ(address_decisions_.size(), 2u);
  EXPECT_EQ(address_decisions_[1], AddressDecision::kIgnored);
  EXPECT_EQ(native_window_.attachedSheet, nil);
}

TEST_F(NativeAutofillSaveSessionTest,
       LocalProfileDoesNotAdmitMergeOrMigration) {
  autofill::AddressBubblesController::CreateForWebContents(contents());
  const auto local = autofill::test::GetFullProfile();
  ASSERT_FALSE(local.IsAccountProfile());
  for (auto type : {AddressType::kSave, AddressType::kMigrateToAccount,
                    AddressType::kHomeWorkNameEmailMerge}) {
    autofill::SaveAddressBubbleController controller(address()->GetWeakPtr(),
                                                     contents(), local, type);
    EXPECT_EQ(NativeAutofillSaveSession::SupportsLocalAddress(controller),
              type == AddressType::kSave);
  }
}
}
