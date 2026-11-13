// Copyright 2026 Parc contributors.
#import <AppKit/AppKit.h>

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "base/time/time.h"
#include "parc/native/autofill_bubble_handler.h"
#include "chrome/browser/autofill/personal_data_manager_factory.h"
#include "chrome/browser/ui/autofill/address_bubbles_controller.h"
#include "chrome/browser/ui/autofill/bubble_manager_impl.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller_impl.h"
#include "chrome/browser/ui/tabs/public/tab_features.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/autofill/core/browser/data_manager/test_personal_data_manager.h"
#include "components/autofill/core/browser/test_utils/autofill_test_util.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "parc/tests/parc_native_test_support/browser_window_test.h"

namespace parc {
namespace {
using Card = autofill::SaveCardBubbleControllerImpl;
using Client = autofill::payments::PaymentsAutofillClient;
using Decision = Client::SaveCardOfferUserDecision;
using Kind = autofill::AutofillUiPresentation;
class CapabilityWindow final : public TestBrowserWindow {
 public:
  explicit CapabilityWindow(NSWindow* window) : window_(window) {}
  gfx::NativeWindow GetNativeWindow() const override {
    return gfx::NativeWindow(window_);
  }
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override {
    return handler;
  }
  raw_ptr<autofill::AutofillBubbleHandler> handler = nullptr;

 private:
  __weak NSWindow* window_;
};
class OccupiedController final : public autofill::BubbleControllerBase {
 public:
  void ShowBubble() override { showing = true; }
  void HideBubble(bool) override { showing = false; }
  void OnBubbleDiscarded() override {}
  bool CanBeReshown() const override { return true; }
  bool ShouldReshowOnTabVisible() const override { return true; }
  autofill::BubbleType GetBubbleType() const override {
    return autofill::BubbleType::kPassword;
  }
  bool IsShowingBubble() const override { return showing; }
  bool IsMouseHovered() const override { return true; }
  base::WeakPtr<autofill::BubbleControllerBase> GetBubbleControllerBaseWeakPtr()
      override {
    return weak.GetWeakPtr();
  }
  bool showing = false;

 private:
  base::WeakPtrFactory<OccupiedController> weak{this};
};
std::unique_ptr<KeyedService> MemoryData(content::BrowserContext*) {
  auto data = std::make_unique<autofill::TestPersonalDataManager>();
  data->test_payments_data_manager().SetAutofillPaymentMethodsEnabled(true);
  return data;
}
NSButton* Button(NSView* view, NSString* title) {
  if ([view isKindOfClass:NSButton.class] &&
      [((NSButton*)view).title isEqual:title]) {
    return (NSButton*)view;
  }
  for (NSView* child in view.subviews) {
    if (NSButton* result = Button(child, title)) {
      return result;
    }
  }
  return nil;
}
template <class P>
bool Pump(P predicate) {
  auto end = base::TimeTicks::Now() + base::Seconds(5);
  do {
    base::RunLoop().RunUntilIdle();
    if (predicate()) {
      return true;
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
  } while (base::TimeTicks::Now() < end);
  return predicate();
}
}
class NativeAutofillCapabilityTest : public ParcBrowserWindowTest,
                                     public NativeAutofillBubbleHost,
                                     public testing::WithParamInterface<bool> {
 public:
  void SetUp() override {
    ParcBrowserWindowTest::SetUp();
    handler_ = std::make_unique<NativeAutofillBubbleHandler>(*browser(), *this);
    static_cast<CapabilityWindow*>(window())->handler = handler_.get();
    AddTab(browser(), GURL("about:blank"));
    auto* tab = tabs::TabInterface::GetFromContents(contents());
    tab->GetTabFeatures()->SetBubbleManagerForTesting(
        GetParam() ? std::make_unique<autofill::BubbleManagerImpl>(tab)
                   : nullptr);
    NSView* page = contents()->GetNativeView().GetNativeNSView();
    ASSERT_TRUE(page);
    [native_.contentView addSubview:page];
    contents()->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
    Card::CreateForWebContents(contents());
  }
  void TearDown() override {
    if (handler_) {
      handler_->BeginTeardown();
    }
    browser()->GetTabStripModel()->CloseAllTabs();
    EXPECT_TRUE(Pump([this] { return native_.attachedSheet == nil; }));
    base::RunLoop().RunUntilIdle();
    static_cast<CapabilityWindow*>(window())->handler = nullptr;
    handler_.reset();
    ParcBrowserWindowTest::TearDown();
    [native_ close];
    native_ = nil;
  }
  std::optional<NativeAutofillPageContext> GetAutofillPageContext(
      content::WebContents& contents) override {
    if (!host_available_) {
      return std::nullopt;
    }
    const NativeAutofillPageContext context{
        gfx::NativeView(contents.GetNativeView().GetNativeNSView().superview),
        gfx::NativeWindow(native_)};
    if (on_context_) {
      std::move(on_context_).Run();
    }
    return context;
  }

 protected:
  TestingProfile::TestingFactories GetTestingFactories() override {
    auto f = BrowserWithTestWindowTest::GetTestingFactories();
    f.emplace_back(autofill::PersonalDataManagerFactory::GetInstance(),
                   base::BindRepeating(&MemoryData));
    return f;
  }
  std::unique_ptr<BrowserWindow> CreateBrowserWindow() override {
    native_ =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(-2200, -2200, 600, 400)
                                    styleMask:NSWindowStyleMaskTitled
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    native_.releasedWhenClosed = NO;
    [native_ orderFront:nil];
    return std::make_unique<CapabilityWindow>(native_);
  }
  content::WebContents* contents() {
    return browser()->GetTabStripModel()->GetActiveWebContents();
  }
  Card* card() { return Card::FromWebContents(contents()); }
  void Offer(Client::LocalSaveCardPromptCallback callback,
             Client::CardSaveType type = Client::CardSaveType::kCardSaveOnly) {
    auto activation = Card::IgnoreWindowActivationForTesting();
    card()->OfferLocalSave(autofill::test::GetCreditCard(),
                           Client::SaveCreditCardOptions()
                               .with_card_save_type(type)
                               .with_show_prompt(true),
                           std::move(callback));
  }
  void Decline() {
    auto* button = Button(native_.attachedSheet.contentView, @"Not Now");
    ASSERT_TRUE(button);
    [button performClick:nil];
  }
  __strong NSWindow* native_ = nil;
  std::unique_ptr<NativeAutofillBubbleHandler> handler_;
  bool host_available_ = true;
  base::OnceClosure on_context_;
  std::vector<Decision> decisions_;
};
TEST_P(NativeAutofillCapabilityTest, ExactCapabilityAndMissingBrowserDefaults) {
  EXPECT_TRUE(
      handler_->IsAutofillUiPresentationSupported(Kind::kLocalCardSave));
  EXPECT_TRUE(
      handler_->IsAutofillUiPresentationSupported(Kind::kLocalAddressSave));
  for (auto kind :
       {Kind::kLocalCvcSave, Kind::kUploadCardSave, Kind::kCardFixFlow,
        Kind::kCardIcon, Kind::kAddressMerge, Kind::kAddressMigration,
        Kind::kAutofillAiImport, Kind::kWalletReminder}) {
    EXPECT_FALSE(handler_->IsAutofillUiPresentationSupported(kind));
  }
  EXPECT_TRUE(autofill::AutofillBubbleHandler::IsPresentationSupported(
      nullptr, Kind::kLocalCardSave));
}
TEST_P(NativeAutofillCapabilityTest,
       UnsupportedCvcHasNeutralResultAndNextRequestWorks) {
  Offer(base::BindLambdaForTesting(
            [this](Decision d) { decisions_.push_back(d); }),
        Client::CardSaveType::kCvcSaveOnly);
  ASSERT_EQ(decisions_, std::vector<Decision>{Decision::kNotPresented});
  EXPECT_FALSE(card()->GetPaymentBubbleView());
  EXPECT_EQ(native_.attachedSheet, nil);
  Offer(base::BindLambdaForTesting(
      [this](Decision d) { decisions_.push_back(d); }));
  ASSERT_TRUE(Pump([this] { return native_.attachedSheet != nil; }));
  Decline();
  ASSERT_TRUE(Pump([this] { return decisions_.size() == 2; }));
  EXPECT_EQ(decisions_.back(), Decision::kDeclined);
}
TEST_P(NativeAutofillCapabilityTest,
       MissingNativeContextCanDestroyActualPageSynchronously) {
  host_available_ = false;
  auto weak = contents()->GetWeakPtr();
  Offer(base::BindLambdaForTesting([this](Decision d) {
    decisions_.push_back(d);
    browser()->GetTabStripModel()->CloseAllTabs();
  }));
  EXPECT_FALSE(weak);
  EXPECT_EQ(decisions_, std::vector<Decision>{Decision::kNotPresented});
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(native_.attachedSheet, nil);
}
TEST_P(NativeAutofillCapabilityTest,
       DeferredHiddenWindowNeverPresentedAndRestoresProgress) {
  [native_ orderOut:nil];
  Offer(base::BindLambdaForTesting(
      [this](Decision d) { decisions_.push_back(d); }));
  ASSERT_TRUE(card()->GetPaymentBubbleView());
  EXPECT_FALSE((card()->GetPaymentBubbleView() &&
                card()->GetPaymentBubbleView()->IsPresented()));
  EXPECT_TRUE(decisions_.empty());
  ASSERT_TRUE(Pump([this] { return decisions_.size() == 1; }));
  EXPECT_EQ(decisions_.front(), Decision::kNotPresented);
  EXPECT_FALSE(card()->GetPaymentBubbleView());
  EXPECT_EQ(native_.attachedSheet, nil);
  [native_ orderFront:nil];
  Offer(base::BindLambdaForTesting(
      [this](Decision d) { decisions_.push_back(d); }));
  ASSERT_TRUE(Pump([this] {
    return (card()->GetPaymentBubbleView() &&
            card()->GetPaymentBubbleView()->IsPresented());
  }));
  Decline();
  ASSERT_TRUE(Pump([this] { return decisions_.size() == 2; }));
  EXPECT_EQ(decisions_.back(), Decision::kDeclined);
}
TEST_P(NativeAutofillCapabilityTest,
       DetachBlocksReentrantOfferUntilExplicitAttach) {
  handler_->PageHostWillDetach(*contents());
  Offer(base::BindLambdaForTesting(
      [this](Decision d) { decisions_.push_back(d); }));
  EXPECT_EQ(decisions_, std::vector<Decision>{Decision::kNotPresented});
  handler_->PageHostDidAttach(*contents());
  Offer(base::BindLambdaForTesting(
      [this](Decision d) { decisions_.push_back(d); }));
  ASSERT_TRUE(Pump([this] { return native_.attachedSheet != nil; }));
  Decline();
  ASSERT_TRUE(Pump([this] { return decisions_.size() == 2; }));
}
TEST_P(NativeAutofillCapabilityTest, RefusalReentryKeepsReplacementIdentity) {
  [native_ orderOut:nil];
  Offer(base::BindLambdaForTesting([this](Decision d) {
    decisions_.push_back(d);
    [native_ orderFront:nil];
    Offer(base::BindLambdaForTesting(
        [this](Decision replacement) { decisions_.push_back(replacement); }));
  }));
  ASSERT_TRUE(Pump([this] {
    return decisions_.size() == 1 && native_.attachedSheet != nil;
  }));
  EXPECT_EQ(decisions_.front(), Decision::kNotPresented);
  EXPECT_TRUE((card()->GetPaymentBubbleView() &&
               card()->GetPaymentBubbleView()->IsPresented()));
  Decline();
  ASSERT_TRUE(Pump([this] { return decisions_.size() == 2; }));
  EXPECT_EQ(decisions_.back(), Decision::kDeclined);
}
TEST_P(NativeAutofillCapabilityTest,
       OldRefusalCannotRemoveSameControllerQueuedReplacement) {
  if (!GetParam()) {
    GTEST_SKIP() << "Requires the real BubbleManager queue";
  }
  auto* manager = autofill::BubbleManager::GetForWebContents(contents());
  ASSERT_TRUE(manager);
  OccupiedController other;
  [native_ orderOut:nil];
  Offer(base::BindLambdaForTesting([this, manager, &other](Decision d) {
    decisions_.push_back(d);
    [native_ orderFront:nil];
    manager->RequestShowController(other, true);
    Offer(base::BindLambdaForTesting(
        [this](Decision b) { decisions_.push_back(b); }));
  }));
  ASSERT_TRUE(Pump([this] { return decisions_.size() == 1; }));
  EXPECT_EQ(decisions_[0], Decision::kNotPresented);
  ASSERT_TRUE(manager->HasPendingBubbleOfSameType(
      autofill::BubbleType::kSaveUpdateCard));
  EXPECT_EQ(native_.attachedSheet, nil);
  other.HideBubble(false);
  manager->OnBubbleHiddenByController(other, true);
  ASSERT_TRUE(Pump([this] { return native_.attachedSheet != nil; }));
  Decline();
  ASSERT_TRUE(Pump([this] { return decisions_.size() == 2; }));
  EXPECT_EQ(decisions_[1], Decision::kDeclined);
}
TEST_P(NativeAutofillCapabilityTest,
       QueuedNextRefusalCanDestroyPageDuringManagerReset) {
  if (!GetParam()) {
    GTEST_SKIP() << "Requires the real BubbleManager queue";
  }
  auto* manager = autofill::BubbleManager::GetForWebContents(contents());
  OccupiedController other;
  manager->RequestShowController(other, true);
  host_available_ = false;
  auto weak = contents()->GetWeakPtr();
  Offer(base::BindLambdaForTesting([this](Decision d) {
    decisions_.push_back(d);
    browser()->GetTabStripModel()->CloseAllTabs();
  }));
  ASSERT_TRUE(manager->HasPendingBubbleOfSameType(
      autofill::BubbleType::kSaveUpdateCard));
  other.HideBubble(false);
  manager->OnBubbleHiddenByController(other, true);
  EXPECT_FALSE(weak);
  EXPECT_EQ(decisions_, std::vector<Decision>{Decision::kNotPresented});
  base::RunLoop().RunUntilIdle();
}
TEST_P(NativeAutofillCapabilityTest,
       ContextProviderMayDestroyPageWithoutReturningDanglingContent) {
  auto weak = contents()->GetWeakPtr();
  on_context_ = base::BindLambdaForTesting(
      [this] { browser()->GetTabStripModel()->CloseAllTabs(); });
  Offer(base::BindLambdaForTesting(
      [this](Decision d) { decisions_.push_back(d); }));
  EXPECT_FALSE(weak);
  EXPECT_TRUE(decisions_.empty());
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(native_.attachedSheet, nil);
}
TEST_P(NativeAutofillCapabilityTest,
       ClosingPendingNativeSessionDoesNotReenterDyingPage) {
  Offer(base::BindLambdaForTesting(
      [this](Decision d) { decisions_.push_back(d); }));
  ASSERT_TRUE(card()->GetPaymentBubbleView());
  EXPECT_FALSE(card()->GetPaymentBubbleView()->IsPresented());
  auto weak = contents()->GetWeakPtr();
  browser()->GetTabStripModel()->CloseAllTabs();
  EXPECT_FALSE(weak);
  base::RunLoop().RunUntilIdle();
  EXPECT_TRUE(decisions_.empty());
  EXPECT_EQ(native_.attachedSheet, nil);
}
TEST_P(NativeAutofillCapabilityTest,
       ActualDeclineCallbackCanOfferReplacementWithoutOldStateOverwrite) {
  Offer(base::BindLambdaForTesting([this](Decision d) {
    decisions_.push_back(d);
    Offer(base::BindLambdaForTesting(
        [this](Decision next) { decisions_.push_back(next); }));
  }));
  ASSERT_TRUE(Pump([this] { return native_.attachedSheet != nil; }));
  Decline();
  ASSERT_TRUE(Pump([this] {
    return decisions_.size() == 1 && native_.attachedSheet != nil;
  }));
  EXPECT_EQ(decisions_[0], Decision::kDeclined);
  EXPECT_EQ(card()->GetBubbleType(), autofill::BubbleType::kSaveUpdateCard);
  Decline();
  ASSERT_TRUE(Pump([this] { return decisions_.size() == 2; }));
  EXPECT_EQ(decisions_[1], Decision::kDeclined);
}
INSTANTIATE_TEST_SUITE_P(RealManagerModes,
                         NativeAutofillCapabilityTest,
                         testing::Bool());
}
