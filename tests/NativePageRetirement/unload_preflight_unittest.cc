// Copyright 2026 Parc contributors.
// Real UnloadController, TabStripModel and WebContents. The controlled custom
// confirmation is the public TabUnloadHandler input, not a copy of transaction
// state or a fake unload controller. Renderer/AppKit integration is a separate
// browser runtime gate.
#include <map>
#include <memory>
#include <set>
#include <vector>

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/test/base/browser_with_test_window_test.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/mock_render_process_host.h"
#include "content/public/test/web_contents_tester.h"
#include "tab_retirement.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace parc {
namespace {
class Confirmations final : public UnloadController::TabUnloadHandler {
 public:
  bool ShouldSkipBeforeUnload(content::WebContents*) override { return false; }
  bool ShouldShowCustomConfirmation(content::WebContents* contents) override {
    return selected.contains(contents);
  }
  bool ShowCustomConfirmation(
      content::WebContents* contents,
      base::OnceCallback<void(bool)> callback) override {
    ++shows;
    if (synchronous_accept) {
      std::move(callback).Run(true);
    } else {
      callbacks[contents] = std::move(callback);
    }
    return true;
  }
  void Reply(content::WebContents* contents, bool allow) {
    auto found = callbacks.find(contents);
    ASSERT_NE(found, callbacks.end());
    auto callback = std::move(found->second);
    callbacks.erase(found);
    std::move(callback).Run(allow);
    base::RunLoop().RunUntilIdle();
  }
  std::set<content::WebContents*> selected;
  std::map<content::WebContents*, base::OnceCallback<void(bool)>> callbacks;
  int shows = 0;
  bool synchronous_accept = false;
};

class NativePageRetirementTest : public BrowserWithTestWindowTest {
 protected:
  void SetUp() override {
    BrowserWithTestWindowTest::SetUp();
    a_ = Append();
    b_ = Append();
    untouched_ = Append();
    auto handler = std::make_unique<Confirmations>();
    handler_ = handler.get();
    handler_->selected = {a_, b_};
    controller()->AddTabUnloadHandler(std::move(handler));
  }
  void TearDown() override {
    if (token_) {
      controller()->ReleaseTabClosePreflight(*token_);
    }
    handler_->selected.clear();
    handler_->callbacks.clear();
    base::RunLoop().RunUntilIdle();
    BrowserWithTestWindowTest::TearDown();
    base::RunLoop().RunUntilIdle();
  }
  content::WebContents* Append() {
    auto contents =
        content::WebContentsTester::CreateTestWebContents(profile(), nullptr);
    auto* result = contents.get();
    browser()->GetTabStripModel()->AppendWebContents(std::move(contents), true);
    return result;
  }
  UnloadController* controller() { return UnloadController::From(browser()); }
  void Begin() {
    token_ = controller()->ReserveTabClosePreflight(
        {a_, b_}, base::BindLambdaForTesting(
                      [this](bool allow) { results_.push_back(allow); }));
    ASSERT_TRUE(token_);
    ASSERT_TRUE(controller()->RunTabClosePreflight(*token_));
    EXPECT_TRUE(results_.empty());
    base::RunLoop().RunUntilIdle();
  }
  int Count() { return browser()->GetTabStripModel()->count(); }
  raw_ptr<content::WebContents> a_ = nullptr;
  raw_ptr<content::WebContents> b_ = nullptr;
  raw_ptr<content::WebContents> untouched_ = nullptr;
  raw_ptr<Confirmations> handler_ = nullptr;
  std::optional<UnloadController::TabCloseToken> token_;
  std::vector<bool> results_;
};

TEST_F(NativePageRetirementTest, LaterStayPreservesEarlierApprovedLivePage) {
  Begin();
  handler_->Reply(a_, true);
  EXPECT_EQ(Count(), 3);
  EXPECT_TRUE(results_.empty());
  EXPECT_FALSE(controller()->CanCloseContents(a_));
  handler_->Reply(b_, false);
  EXPECT_EQ(results_, std::vector<bool>({false}));
  EXPECT_EQ(Count(), 3);
  EXPECT_EQ(browser()->GetTabStripModel()->GetWebContentsAt(0), a_);
  EXPECT_EQ(browser()->GetTabStripModel()->GetWebContentsAt(1), b_);
  EXPECT_FALSE(controller()->HasTabClosePreflight());
}

TEST_F(NativePageRetirementTest, EveryApprovalPrecedesPostedActualUnload) {
  auto first = a_->GetWeakPtr();
  auto second = b_->GetWeakPtr();
  Begin();
  handler_->Reply(a_, true);
  handler_->Reply(b_, true);
  ASSERT_EQ(results_, std::vector<bool>({true}));
  EXPECT_EQ(Count(), 3);
  ASSERT_TRUE(controller()->IsTabClosePreflightReady(*token_));
  ASSERT_TRUE(controller()->CommitTabClosePreflight(*token_));
  EXPECT_EQ(Count(), 3);  // Commit must not run a renderer or native callback.
  // Blank TestWebContents have no renderer/unload handler; actual ClosePage
  // reaches Browser's genuine CloseContents/TabStripModel removal synchronously
  // when the posted commit runs.
  a_ = nullptr;
  b_ = nullptr;
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(first);
  EXPECT_FALSE(second);
  EXPECT_EQ(Count(), 1);
  EXPECT_EQ(browser()->GetTabStripModel()->GetWebContentsAt(0), untouched_);
  a_ = nullptr;
  b_ = nullptr;
}

TEST_F(NativePageRetirementTest, LateCustomLeaveAfterCancellationCannotClose) {
  Begin();
  controller()->ReleaseTabClosePreflight(*token_);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(results_, std::vector<bool>({false}));
  EXPECT_FALSE(controller()->ReserveTabClosePreflight(
      {a_, b_}, base::BindRepeating([](bool) {})));
  handler_->Reply(a_,
                  true);  // Old generation is consumed, never ordinary close.
  EXPECT_EQ(Count(), 3);
  EXPECT_EQ(results_.size(), 1u);
  token_ = controller()->ReserveTabClosePreflight(
      {a_, b_},
      base::BindLambdaForTesting([this](bool v) { results_.push_back(v); }));
  ASSERT_TRUE(token_);
}

TEST_F(NativePageRetirementTest, PreparedDocumentReplacementInvalidatesCommit) {
  Begin();
  handler_->Reply(a_, true);
  handler_->Reply(b_, true);
  NavigateAndCommit(a_, GURL("https://example.test/new-document"));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(results_, std::vector<bool>({true, false}));
  EXPECT_FALSE(controller()->CommitTabClosePreflight(*token_));
  EXPECT_EQ(Count(), 3);
}

TEST_F(NativePageRetirementTest, DetachedTargetCannotBeClosedByStaleApproval) {
  Begin();
  auto detached =
      browser()->GetTabStripModel()->DetachWebContentsAtForInsertion(0);
  ASSERT_EQ(detached.get(), a_);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(results_, std::vector<bool>({false}));
  handler_->Reply(a_, true);
  EXPECT_FALSE(detached->IsBeingDestroyed());
  EXPECT_EQ(Count(), 2);
  a_ = nullptr;
}

TEST_F(NativePageRetirementTest,
       LateRendererReplyFollowsPageAcrossBrowserMove) {
  Begin();
  auto other = CreateBrowser(profile(),
                             BrowserWindowInterface::Type::TYPE_NORMAL, false);
  auto moved =
      browser()->GetTabStripModel()->DetachWebContentsAtForInsertion(0);
  auto* identity = moved.get();
  other->GetTabStripModel()->AppendWebContents(std::move(moved), true);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(results_, std::vector<bool>({false}));
  EXPECT_TRUE(
      UnloadController::From(other.get())->RunUnloadEventsHelper(identity));
  EXPECT_FALSE(UnloadController::From(other.get())->CanCloseContents(identity));
  EXPECT_TRUE(UnloadController::From(other.get())->HasTabClosePreflight());
  EXPECT_FALSE(UnloadController::From(other.get())->HandleBeforeClose());
  EXPECT_FALSE(
      UnloadController::From(other.get())->BeforeUnloadFired(identity, true));
  handler_->Reply(identity,
                  true);  // Stale custom callback cannot consume a new request.
  EXPECT_EQ(other->GetTabStripModel()->count(), 1);
  EXPECT_EQ(other->GetTabStripModel()->GetWebContentsAt(0), identity);
  a_ = nullptr;
  other->GetTabStripModel()->CloseAllTabs();
  other.reset();
  base::RunLoop().RunUntilIdle();
}

TEST_F(NativePageRetirementTest, NewDocumentRetiresCancelledReplyReservation) {
  Begin();
  controller()->ReleaseTabClosePreflight(*token_);
  NavigateAndCommit(a_, GURL("https://example.test/after-cancel"));
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(controller()->HasTabClosePreflight());
  auto fresh = controller()->ReserveTabClosePreflight(
      {a_}, base::BindRepeating([](bool) {}));
  ASSERT_TRUE(fresh);
  handler_->Reply(a_, true);  // Old custom callback cannot approve fresh token.
  EXPECT_FALSE(controller()->IsTabClosePreflightReady(*fresh));
  controller()->ReleaseTabClosePreflight(*fresh);
}

TEST_F(NativePageRetirementTest,
       RendererCrashRetiresReplyAndAllowsExactPageRetry) {
  NavigateAndCommit(a_, GURL("https://example.test/before-crash"));
  Begin();
  auto stale = std::move(handler_->callbacks[a_]);
  handler_->callbacks.erase(a_);
  static_cast<content::MockRenderProcessHost*>(
      a_->GetPrimaryMainFrame()->GetProcess())
      ->SimulateCrash();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(results_, std::vector<bool>({false}));
  EXPECT_TRUE(a_->IsCrashed());
  EXPECT_FALSE(controller()->HasTabClosePreflight());
  NavigateAndCommit(a_, GURL("https://example.test/recovered"));
  token_ = controller()->ReserveTabClosePreflight(
      {a_}, base::BindLambdaForTesting(
                [this](bool allow) { results_.push_back(allow); }));
  ASSERT_TRUE(token_);
  ASSERT_TRUE(controller()->RunTabClosePreflight(*token_));
  base::RunLoop().RunUntilIdle();
  std::move(stale).Run(true);
  EXPECT_FALSE(controller()->IsTabClosePreflightReady(*token_));
  handler_->Reply(a_, true);
  EXPECT_EQ(results_, std::vector<bool>({false, true}));
  EXPECT_TRUE(controller()->IsTabClosePreflightReady(*token_));
  EXPECT_EQ(Count(), 3);
}

TEST_F(NativePageRetirementTest, WindowCloseCannotReplaceSubsetCallback) {
  Begin();
  bool global_result = true;
  EXPECT_TRUE(controller()->RunBeforeUnloadForShutdown(
      false,
      base::BindLambdaForTesting([&](bool allow) { global_result = allow; })));
  EXPECT_FALSE(controller()->HandleBeforeClose());
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(global_result);
  EXPECT_TRUE(results_.empty());
  handler_->Reply(a_, true);
  handler_->Reply(b_, false);
  EXPECT_EQ(results_, std::vector<bool>({false}));
  EXPECT_EQ(Count(), 3);
}

TEST_F(NativePageRetirementTest, DuplicateOrNonmemberTargetsAreRejected) {
  EXPECT_FALSE(controller()->ReserveTabClosePreflight(
      {a_, a_}, base::BindRepeating([](bool) {})));
  auto outside =
      content::WebContentsTester::CreateTestWebContents(profile(), nullptr);
  EXPECT_FALSE(controller()->ReserveTabClosePreflight(
      {a_, outside.get()}, base::BindRepeating([](bool) {})));
  EXPECT_FALSE(controller()->ReserveTabClosePreflight(
      {nullptr}, base::BindRepeating([](bool) {})));
  EXPECT_EQ(Count(), 3);
}

TEST_F(NativePageRetirementTest,
       SynchronousCustomConsentStillCannotUnloadEarly) {
  handler_->synchronous_accept = true;
  Begin();
  EXPECT_EQ(handler_->shows, 2);
  EXPECT_EQ(results_, std::vector<bool>({true}));
  EXPECT_EQ(Count(), 3);
  controller()->ReleaseTabClosePreflight(*token_);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(results_, std::vector<bool>({true, false}));
}

TEST_F(NativePageRetirementTest, OtherPageIsNotRequestedOrDestroyed) {
  token_ = controller()->ReserveTabClosePreflight(
      {a_}, base::BindLambdaForTesting(
                [this](bool allow) { results_.push_back(allow); }));
  ASSERT_TRUE(token_);
  ASSERT_TRUE(controller()->RunTabClosePreflight(*token_));
  base::RunLoop().RunUntilIdle();
  handler_->Reply(a_, true);
  EXPECT_EQ(handler_->shows, 1);
  EXPECT_TRUE(controller()->CanCloseContents(b_));
  EXPECT_TRUE(controller()->CanCloseContents(untouched_));
  EXPECT_EQ(Count(), 3);
}

TEST_F(NativePageRetirementTest, EmptySetStillRequiresModelValidation) {
  int validations = 0;
  std::vector<bool> completed;
  RequestTabRetirement({}, base::BindRepeating([] { return true; }),
                       base::BindLambdaForTesting([&] {
                         ++validations;
                         return false;
                       }),
                       base::BindLambdaForTesting(
                           [&](bool result) { completed.push_back(result); }));
  EXPECT_EQ(validations, 1);
  EXPECT_TRUE(completed.empty());
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(completed, std::vector<bool>({false}));
  EXPECT_FALSE(HasTabRetirementWork());
}

TEST_F(NativePageRetirementTest, CommittedReplacementIsNeverClosed) {
  Begin();
  handler_->Reply(a_, true);
  handler_->Reply(b_, true);
  ASSERT_TRUE(controller()->CommitTabClosePreflight(*token_));
  NavigateAndCommit(a_, GURL("https://example.test/after-commit"));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(results_, std::vector<bool>({true, false}));
  EXPECT_EQ(Count(), 3);
}

TEST_F(NativePageRetirementTest,
       CommittedTransferTerminatesWithoutClosingPeer) {
  Begin();
  handler_->Reply(a_, true);
  handler_->Reply(b_, true);
  ASSERT_TRUE(controller()->CommitTabClosePreflight(*token_));
  auto moved =
      browser()->GetTabStripModel()->DetachWebContentsAtForInsertion(0);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(results_, std::vector<bool>({true, false}));
  EXPECT_EQ(Count(), 2);
  EXPECT_EQ(moved.get(), a_);
  EXPECT_EQ(browser()->GetTabStripModel()->GetWebContentsAt(0), b_);
  a_ = nullptr;
}

TEST_F(NativePageRetirementTest,
       ProductionCoordinatorValidatorCancelsBeforeUnload) {
  int validations = 0;
  std::vector<bool> completed;
  RequestTabRetirement({a_, b_}, base::BindRepeating([] { return true; }),
                       base::BindLambdaForTesting([&] {
                         ++validations;
                         EXPECT_EQ(Count(), 3);
                         return false;
                       }),
                       base::BindLambdaForTesting(
                           [&](bool result) { completed.push_back(result); }));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(validations, 0);
  handler_->Reply(a_, true);
  EXPECT_EQ(validations, 0);
  handler_->Reply(b_, true);
  EXPECT_EQ(validations, 1);
  EXPECT_EQ(completed, std::vector<bool>({false}));
  EXPECT_EQ(Count(), 3);
  EXPECT_FALSE(HasTabRetirementWork());
}

TEST_F(NativePageRetirementTest,
       ProductionCoordinatorRevalidatesAfterValidator) {
  std::vector<bool> completed;
  RequestTabRetirement(
      {a_, b_}, base::BindRepeating([] { return true; }),
      base::BindLambdaForTesting([&] {
        NavigateAndCommit(a_,
                          GURL("https://example.test/replaced-in-validator"));
        return true;
      }),
      base::BindLambdaForTesting(
          [&](bool result) { completed.push_back(result); }));
  base::RunLoop().RunUntilIdle();
  handler_->Reply(a_, true);
  handler_->Reply(b_, true);
  EXPECT_EQ(completed, std::vector<bool>({false}));
  EXPECT_EQ(Count(), 3);
  EXPECT_FALSE(HasTabRetirementWork());
}

TEST_F(NativePageRetirementTest, ProductionCoordinatorWaitsActualDestruction) {
  auto first = a_->GetWeakPtr();
  auto second = b_->GetWeakPtr();
  std::vector<bool> completed;
  RequestTabRetirement({a_, b_}, base::BindRepeating([] { return true; }),
                       base::BindLambdaForTesting([&] {
                         EXPECT_TRUE(first && second);
                         EXPECT_EQ(Count(), 3);
                         a_ = nullptr;
                         b_ = nullptr;
                         return true;
                       }),
                       base::BindLambdaForTesting([&](bool result) {
                         EXPECT_FALSE(first);
                         EXPECT_FALSE(second);
                         completed.push_back(result);
                       }));
  base::RunLoop().RunUntilIdle();
  handler_->Reply(first.get(), true);
  handler_->Reply(second.get(), true);
  EXPECT_EQ(completed, std::vector<bool>({true}));
  EXPECT_EQ(Count(), 1);
  EXPECT_FALSE(HasTabRetirementWork());
}

TEST_F(NativePageRetirementTest,
       CrossBrowserPromptsAreSequentialAndStayIsAtomic) {
  auto other = CreateBrowser(profile(),
                             BrowserWindowInterface::Type::TYPE_NORMAL, false);
  auto contents =
      content::WebContentsTester::CreateTestWebContents(profile(), nullptr);
  auto* other_page = contents.get();
  other->GetTabStripModel()->AppendWebContents(std::move(contents), true);
  other->GetTabStripModel()->AppendWebContents(
      content::WebContentsTester::CreateTestWebContents(profile(), nullptr),
      true);
  auto handler = std::make_unique<Confirmations>();
  auto* other_handler = handler.get();
  other_handler->selected.insert(other_page);
  UnloadController::From(other.get())->AddTabUnloadHandler(std::move(handler));
  int validations = 0;
  std::vector<bool> completed;
  RequestTabRetirement({a_, other_page},
                       base::BindRepeating([] { return true; }),
                       base::BindLambdaForTesting([&] {
                         ++validations;
                         return true;
                       }),
                       base::BindLambdaForTesting(
                           [&](bool result) { completed.push_back(result); }));
  base::RunLoop().RunUntilIdle();
  ASSERT_EQ(handler_->shows + other_handler->shows, 1);
  if (handler_->shows) {
    handler_->Reply(a_, true);
    EXPECT_EQ(other_handler->shows, 1);
    other_handler->Reply(other_page, false);
  } else {
    other_handler->Reply(other_page, true);
    EXPECT_EQ(handler_->shows, 1);
    handler_->Reply(a_, false);
  }
  EXPECT_EQ(validations, 0);
  EXPECT_EQ(completed, std::vector<bool>({false}));
  EXPECT_EQ(Count(), 3);
  EXPECT_EQ(other->GetTabStripModel()->count(), 2);
  other_handler->selected.clear();
  other->GetTabStripModel()->CloseAllTabs();
  other.reset();
  base::RunLoop().RunUntilIdle();
}
}  // namespace
}  // namespace parc
