// Copyright 2026 Parc contributors.
// The production transaction operates on actual Browser, TabStripModel,
// TabInterface, WebContents and UnloadController instances. AppKit presentation
// is a narrow callback input; no tab model or close state machine is copied.
#include "tab_transfer.h"

#include <memory>
#include <vector>

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "chrome/browser/ui/tabs/tab_group_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/test/base/browser_with_test_window_test.h"
#include "chrome/test/base/test_browser_window.h"
#include "chrome/test/base/testing_profile.h"
#include "components/tab_groups/tab_group_color.h"
#include "components/tab_groups/tab_group_visual_data.h"
#include "components/tabs/public/tab_group.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/web_contents_tester.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "unload_transactions.h"

namespace parc_hooks {
void SetUnloadControllerLifetime(void (*)(UnloadController&,
                                          BrowserWindowInterface&,
                                          base::RepeatingCallback<bool()>,
                                          parc::UnloadEventsRunner),
                                 void (*)(UnloadController&));
void SetUnloadControllerTabEvents(
    void (*)(UnloadController&, content::WebContents*),
    void (*)(UnloadController&, content::WebContents*),
    void (*)(UnloadController&, content::WebContents*),
    bool (*)(UnloadController&));
void SetUnloadControllerCloseGates(bool (*)(const UnloadController&),
                                   bool (*)(const UnloadController&),
                                   bool (*)(const UnloadController&));
void SetUnloadControllerPageGates(
    bool (*)(const UnloadController&, content::WebContents*),
    std::optional<bool> (*)(const UnloadController&, content::WebContents*),
    bool (*)(content::WebContents*),
    bool (*)(UnloadController&, content::WebContents*, bool));
}  // namespace parc_hooks

namespace parc {
namespace {
// The hooks ParcMainDelegate installs, set before any test Browser exists.
void InstallUnloadTransactions(bool install) {
  parc_hooks::SetUnloadControllerLifetime(
      install ? &OnUnloadControllerCreated : nullptr,
      install ? &OnUnloadControllerDestroyed : nullptr);
  parc_hooks::SetUnloadControllerTabEvents(
      install ? &OnUnloadControllerTabAttached : nullptr,
      install ? &OnUnloadControllerTabDetached : nullptr,
      install ? &OnUnloadControllerRenderProcessGone : nullptr,
      install ? &AbsorbsTabStripEmpty : nullptr);
  parc_hooks::SetUnloadControllerCloseGates(
      install ? &BlocksWindowClose : nullptr,
      install ? &HoldsClosingStatus : nullptr,
      install ? &BlocksShutdownBeforeUnload : nullptr);
  parc_hooks::SetUnloadControllerPageGates(
      install ? &HoldsContents : nullptr,
      install ? &UnloadEventsResult : nullptr,
      install ? &HasTabCloseReply : nullptr,
      install ? &ConsumesBeforeUnloadReply : nullptr);
}

class NativeTabTransferTest : public BrowserWithTestWindowTest {
 protected:
  void SetUp() override {
    InstallUnloadTransactions(true);
    BrowserWithTestWindowTest::SetUp();
    destination_ =
        CreateBrowser(profile(), BrowserWindowInterface::TYPE_NORMAL, false);
    page_ = Append(browser());
    tab_ = tabs::TabInterface::MaybeGetFromContents(page_);
  }
  void TearDown() override {
    page_ = nullptr;
    tab_ = nullptr;
    destination_->GetTabStripModel()->CloseAllTabs();
    destination_.reset();
    base::RunLoop().RunUntilIdle();
    BrowserWithTestWindowTest::TearDown();
    base::RunLoop().RunUntilIdle();
    InstallUnloadTransactions(false);
  }
  content::WebContents* Append(BrowserWindowInterface* browser) {
    auto page = content::WebContentsTester::CreateTestWebContents(
        browser->GetProfile(), nullptr);
    auto* raw = page.get();
    browser->GetTabStripModel()->AppendWebContents(std::move(page), true);
    return raw;
  }
  TabTransferResult Move(bool attach = true) {
    return TransferLiveTab(
        *page_, *destination_,
        base::BindLambdaForTesting([&, attach](BrowserWindowInterface& owner,
                                               content::WebContents& actual) {
          EXPECT_EQ(&actual, page_);
          EXPECT_EQ(tabs::TabInterface::MaybeGetFromContents(&actual), tab_);
          EXPECT_EQ(tab_->GetBrowserWindowInterface(), &owner);
          presented_.push_back(&owner);
          return &owner == browser() || attach;
        }));
  }
  std::unique_ptr<BrowserWindowInterface> destination_;
  raw_ptr<content::WebContents> page_ = nullptr;
  raw_ptr<tabs::TabInterface> tab_ = nullptr;
  std::vector<BrowserWindowInterface*> presented_;
};

TEST_F(NativeTabTransferTest,
       PreservesActualTabAndContentsIntoEmptyDestination) {
  auto* identity = page_.get();
  auto* tab_identity = tab_.get();
  EXPECT_EQ(Move(), TabTransferResult::kTransferred);
  EXPECT_EQ(destination_->GetTabStripModel()->GetActiveWebContents(), identity);
  EXPECT_EQ(destination_->GetTabStripModel()->GetTabAtIndex(0), tab_identity);
  EXPECT_TRUE(browser()->GetTabStripModel()->empty());
  EXPECT_EQ(presented_,
            std::vector<BrowserWindowInterface*>({destination_.get()}));
  EXPECT_FALSE(HasLiveTabTransfer());
}

TEST_F(NativeTabTransferTest,
       ReleasingUntouchedEmptyDestinationDoesNotCloseIt) {
  auto* window = static_cast<TestBrowserWindow*>(destination_->GetWindow());
  ASSERT_FALSE(window->IsClosed());
  auto* controller = UnloadController::From(destination_.get());
  auto token = ReserveTabTransfer(*controller);
  ASSERT_TRUE(token);
  ReleaseTabTransfer(*controller, *token);
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(window->IsClosed());
  EXPECT_TRUE(destination_->GetTabStripModel()->empty());
}

TEST_F(NativeTabTransferTest,
       EmptySourceCloseWaitsForExplicitResultCompletion) {
  base::OnceClosure retire_source;
  EXPECT_EQ(TransferLiveTab(
                *page_, *destination_,
                base::BindRepeating([](BrowserWindowInterface&,
                                       content::WebContents&) { return true; }),
                &retire_source),
            TabTransferResult::kTransferred);
  ASSERT_TRUE(retire_source);
  // TestBrowserWindow records Browser's immediate TabStripEmpty notification;
  // it does not implement native Close's UnloadController refusal. Install the
  // observer afterward to isolate the transaction's actual deferred close.
  int closes = 0;
  static_cast<TestBrowserWindow*>(browser()->GetWindow())
      ->SetCloseCallback(base::BindLambdaForTesting([&] { ++closes; }));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(closes, 0);
  EXPECT_EQ(tab_->GetBrowserWindowInterface(), destination_.get());
  // The caller has delivered its result and committed shell ownership here.
  std::move(retire_source).Run();
  EXPECT_EQ(closes, 1);
}

TEST_F(NativeTabTransferTest, DeferredSourceCloseRechecksActualEmptiness) {
  base::OnceClosure retire_source;
  ASSERT_EQ(TransferLiveTab(
                *page_, *destination_,
                base::BindRepeating([](BrowserWindowInterface&,
                                       content::WebContents&) { return true; }),
                &retire_source),
            TabTransferResult::kTransferred);
  ASSERT_TRUE(retire_source);
  auto* new_page = Append(browser());
  int closes = 0;
  static_cast<TestBrowserWindow*>(browser()->GetWindow())
      ->SetCloseCallback(base::BindLambdaForTesting([&] { ++closes; }));
  std::move(retire_source).Run();
  EXPECT_EQ(closes, 0);
  EXPECT_EQ(browser()->GetTabStripModel()->GetActiveWebContents(), new_page);
}

TEST_F(NativeTabTransferTest, RollbackPreservesPreexistingEmptyDestination) {
  base::OnceClosure retire_source;
  EXPECT_EQ(TransferLiveTab(
                *page_, *destination_,
                base::BindLambdaForTesting(
                    [&](BrowserWindowInterface& owner, content::WebContents&) {
                      return &owner == browser();
                    }),
                &retire_source),
            TabTransferResult::kRestoredToSource);
  EXPECT_FALSE(retire_source);
  EXPECT_TRUE(destination_->GetTabStripModel()->empty());
  int closes = 0;
  static_cast<TestBrowserWindow*>(destination_->GetWindow())
      ->SetCloseCallback(base::BindLambdaForTesting([&] { ++closes; }));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(closes, 0);
  auto token = ReserveTabTransfer(*UnloadController::From(destination_.get()));
  ASSERT_TRUE(token);
  EXPECT_FALSE(
      ReleaseTabTransfer(*UnloadController::From(destination_.get()), *token));
}

TEST_F(NativeTabTransferTest, FailedSourceReattachmentReportsInterruption) {
  int calls = 0;
  EXPECT_EQ(
      TransferLiveTab(*page_, *destination_,
                      base::BindLambdaForTesting(
                          [&](BrowserWindowInterface&, content::WebContents&) {
                            ++calls;
                            return false;
                          })),
      TabTransferResult::kExternallyInterrupted);
  EXPECT_EQ(calls, 2);
  EXPECT_EQ(browser()->GetTabStripModel()->GetTabAtIndex(0), tab_);
  EXPECT_EQ(browser()->GetTabStripModel()->GetWebContentsAt(0), page_);
}

TEST_F(NativeTabTransferTest, SourcePresentationDestructionIsInterrupted) {
  const auto weak = page_->GetWeakPtr();
  EXPECT_EQ(
      TransferLiveTab(
          *page_, *destination_,
          base::BindLambdaForTesting(
              [&](BrowserWindowInterface& owner, content::WebContents& actual) {
                if (&owner == browser()) {
                  page_ = nullptr;
                  tab_ = nullptr;
                  owner.GetTabStripModel()->DetachAndDeleteWebContentsAt(
                      owner.GetTabStripModel()->GetIndexOfWebContents(&actual));
                  return true;
                }
                return false;
              })),
      TabTransferResult::kExternallyInterrupted);
  EXPECT_FALSE(weak);
  EXPECT_TRUE(browser()->GetTabStripModel()->empty());
  EXPECT_TRUE(destination_->GetTabStripModel()->empty());
}

TEST_F(NativeTabTransferTest, SourcePresentationOwnershipChangeIsInterrupted) {
  auto third =
      CreateBrowser(profile(), BrowserWindowInterface::TYPE_NORMAL, false);
  EXPECT_EQ(
      TransferLiveTab(
          *page_, *destination_,
          base::BindLambdaForTesting([&](BrowserWindowInterface& owner,
                                         content::WebContents& actual) {
            if (&owner == browser()) {
              auto returning =
                  owner.GetTabStripModel()->DetachTabAtForInsertion(
                      owner.GetTabStripModel()->GetIndexOfWebContents(&actual));
              third->GetTabStripModel()->AppendTab(std::move(returning), true);
              return true;
            }
            return false;
          })),
      TabTransferResult::kExternallyInterrupted);
  EXPECT_EQ(third->GetTabStripModel()->GetTabAtIndex(0), tab_);
  EXPECT_EQ(third->GetTabStripModel()->GetActiveWebContents(), page_);
  page_ = nullptr;
  tab_ = nullptr;
  third->GetTabStripModel()->CloseAllTabs();
  third.reset();
}

TEST_F(NativeTabTransferTest, NonemptyDestinationKeepsItsSelection) {
  auto* selected = Append(destination_.get());
  EXPECT_EQ(Move(), TabTransferResult::kTransferred);
  EXPECT_EQ(destination_->GetTabStripModel()->GetActiveWebContents(), selected);
  EXPECT_EQ(destination_->GetTabStripModel()->GetWebContentsAt(1), page_);
}

TEST_F(NativeTabTransferTest, SuccessfulMoveDoesNotCopyChromiumPinOrGroup) {
  browser()->GetTabStripModel()->SetTabPinned(0, true);
  EXPECT_EQ(Move(), TabTransferResult::kTransferred);
  EXPECT_FALSE(destination_->GetTabStripModel()->IsTabPinned(0));
  EXPECT_FALSE(destination_->GetTabStripModel()->GetTabGroupForTab(0));
}

TEST_F(NativeTabTransferTest,
       FailedAttachmentRestoresLastSourceWithoutCloseState) {
  EXPECT_EQ(Move(false), TabTransferResult::kRestoredToSource);
  EXPECT_EQ(browser()->GetTabStripModel()->GetActiveWebContents(), page_);
  EXPECT_EQ(browser()->GetTabStripModel()->GetTabAtIndex(0), tab_);
  EXPECT_TRUE(destination_->GetTabStripModel()->empty());
  EXPECT_EQ(presented_, std::vector<BrowserWindowInterface*>(
                            {destination_.get(), browser()}));
  // A premature TabStripEmpty close would leave the real controller past Idle.
  auto token = ReserveTabTransfer(*UnloadController::From(browser()));
  ASSERT_TRUE(token);
  ReleaseTabTransfer(*UnloadController::From(browser()), *token);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(browser()->GetTabStripModel()->GetActiveWebContents(), page_);
}

TEST_F(NativeTabTransferTest, RollbackRestoresOriginalPositionAndPinnedState) {
  auto* other = Append(browser());
  browser()->GetTabStripModel()->SetTabPinned(0, true);
  EXPECT_EQ(Move(false), TabTransferResult::kRestoredToSource);
  EXPECT_EQ(browser()->GetTabStripModel()->GetWebContentsAt(0), page_);
  EXPECT_EQ(browser()->GetTabStripModel()->GetActiveWebContents(), other);
  EXPECT_TRUE(browser()->GetTabStripModel()->IsTabPinned(0));
}

TEST_F(NativeTabTransferTest, RollbackRestoresLastMemberGroupAndVisualData) {
  auto* model = browser()->GetTabStripModel();
  const auto group = model->AddToNewGroup({0});
  const tab_groups::TabGroupVisualData visuals(
      u"Source", tab_groups::TabGroupColorId::kBlue);
  model->ChangeTabGroupVisuals(group, visuals);
  EXPECT_EQ(Move(false), TabTransferResult::kRestoredToSource);
  EXPECT_EQ(model->GetTabGroupForTab(0), group);
  ASSERT_TRUE(model->group_model()->ContainsTabGroup(group));
  EXPECT_EQ(model->group_model()->GetTabGroup(group)->visual_data()->title(),
            u"Source");
  EXPECT_EQ(model->group_model()->GetTabGroup(group)->visual_data()->color(),
            tab_groups::TabGroupColorId::kBlue);
}

TEST_F(NativeTabTransferTest, SameOwnerRefusesBeforeAnyPresentation) {
  EXPECT_EQ(
      TransferLiveTab(*page_, *browser(),
                      base::BindLambdaForTesting(
                          [&](BrowserWindowInterface&, content::WebContents&) {
                            ADD_FAILURE();
                            return true;
                          })),
      TabTransferResult::kRefused);
  EXPECT_EQ(browser()->GetTabStripModel()->GetTabAtIndex(0), tab_);
}

TEST_F(NativeTabTransferTest, CrossProfileRefusesBeforeMutation) {
  auto other_profile = std::make_unique<TestingProfile>();
  auto other = CreateBrowser(other_profile.get(),
                             BrowserWindowInterface::TYPE_NORMAL, false);
  EXPECT_EQ(
      TransferLiveTab(*page_, *other,
                      base::BindLambdaForTesting(
                          [&](BrowserWindowInterface&, content::WebContents&) {
                            ADD_FAILURE();
                            return true;
                          })),
      TabTransferResult::kRefused);
  EXPECT_EQ(browser()->GetTabStripModel()->GetTabAtIndex(0), tab_);
  EXPECT_TRUE(other->GetTabStripModel()->empty());
  other.reset();
}

TEST_F(NativeTabTransferTest, OrdinaryPopupUsesSameActualTabContract) {
  auto popup =
      CreateBrowser(profile(), BrowserWindowInterface::TYPE_POPUP, false);
  EXPECT_EQ(TransferLiveTab(*page_, *popup,
                            base::BindRepeating(
                                [](BrowserWindowInterface&,
                                   content::WebContents&) { return true; })),
            TabTransferResult::kTransferred);
  EXPECT_EQ(popup->GetTabStripModel()->GetTabAtIndex(0), tab_);
  EXPECT_EQ(TransferLiveTab(*page_, *browser(),
                            base::BindRepeating(
                                [](BrowserWindowInterface&,
                                   content::WebContents&) { return true; })),
            TabTransferResult::kTransferred);
  EXPECT_EQ(browser()->GetTabStripModel()->GetTabAtIndex(0), tab_);
  popup.reset();
}

TEST_F(NativeTabTransferTest, SeparateDeveloperToolsOwnershipIsRefused) {
  auto tools =
      CreateBrowser(profile(), BrowserWindowInterface::TYPE_DEVTOOLS, false);
  EXPECT_EQ(
      TransferLiveTab(*page_, *tools,
                      base::BindLambdaForTesting(
                          [](BrowserWindowInterface&, content::WebContents&) {
                            ADD_FAILURE();
                            return true;
                          })),
      TabTransferResult::kRefused);
  EXPECT_EQ(browser()->GetTabStripModel()->GetTabAtIndex(0), tab_);
  EXPECT_TRUE(tools->GetTabStripModel()->empty());
  tools.reset();
}

TEST_F(NativeTabTransferTest, ClearsTabStripOpenerWithoutReplacingPage) {
  auto* opener = Append(browser());
  auto* opener_tab = tabs::TabInterface::MaybeGetFromContents(opener);
  browser()->GetTabStripModel()->SetOpenerOfTabAt(0, opener_tab);
  ASSERT_EQ(browser()->GetTabStripModel()->GetOpenerOfTabAt(0), opener_tab);
  EXPECT_EQ(Move(), TabTransferResult::kTransferred);
  EXPECT_EQ(destination_->GetTabStripModel()->GetTabAtIndex(0), tab_);
  EXPECT_EQ(destination_->GetTabStripModel()->GetOpenerOfTabAt(0), nullptr);
}

TEST_F(NativeTabTransferTest, FailedAttachmentRestoresSourceOpenerGraph) {
  auto* opener = Append(browser());
  auto* child = Append(browser());
  auto* opener_tab = tabs::TabInterface::MaybeGetFromContents(opener);
  browser()->GetTabStripModel()->SetOpenerOfTabAt(0, opener_tab);
  browser()->GetTabStripModel()->SetOpenerOfTabAt(2, tab_);
  EXPECT_EQ(Move(false), TabTransferResult::kRestoredToSource);
  EXPECT_EQ(browser()->GetTabStripModel()->GetOpenerOfTabAt(0), opener_tab);
  EXPECT_EQ(browser()->GetTabStripModel()->GetOpenerOfTabAt(
                browser()->GetTabStripModel()->GetIndexOfWebContents(child)),
            tab_);
}

TEST_F(NativeTabTransferTest, PendingBeforeUnloadReservationRefusesTransfer) {
  auto* controller = UnloadController::From(browser());
  auto token = ReserveTabClosePreflight(*controller,
      {page_}, base::BindRepeating([](bool) {}));
  ASSERT_TRUE(token);
  EXPECT_EQ(Move(), TabTransferResult::kRefused);
  EXPECT_TRUE(presented_.empty());
  EXPECT_EQ(browser()->GetTabStripModel()->GetTabAtIndex(0), tab_);
  ReleaseTabClosePreflight(*controller, *token);
}

TEST_F(NativeTabTransferTest, HoldRejectsCompetingCloseAndNestedTransfer) {
  EXPECT_EQ(TransferLiveTab(
                *page_, *destination_,
                base::BindLambdaForTesting([&](BrowserWindowInterface& owner,
                                               content::WebContents& actual) {
                  EXPECT_TRUE(HasLiveTabTransfer());
                  EXPECT_TRUE(IsLiveTabTransferTarget(&actual));
                  EXPECT_FALSE(
                      UnloadController::From(browser())->HandleBeforeClose());
                  EXPECT_FALSE(UnloadController::From(&owner)->CanCloseContents(
                      &actual));
                  EXPECT_FALSE(
                      ReserveTabClosePreflight(*UnloadController::From(&owner),
                          {&actual}, base::BindRepeating([](bool) {})));
                  EXPECT_EQ(TransferLiveTab(
                                actual, *browser(),
                                base::BindRepeating([](BrowserWindowInterface&,
                                                       content::WebContents&) {
                                  return true;
                                })),
                            TabTransferResult::kRefused);
                  return true;
                })),
            TabTransferResult::kTransferred);
}

TEST_F(NativeTabTransferTest,
       ExternalPageDestructionIsInterruptedNotRecreated) {
  const auto weak = page_->GetWeakPtr();
  EXPECT_EQ(TransferLiveTab(
                *page_, *destination_,
                base::BindLambdaForTesting([&](BrowserWindowInterface& owner,
                                               content::WebContents& actual) {
                  owner.GetTabStripModel()->DetachAndDeleteWebContentsAt(
                      owner.GetTabStripModel()->GetIndexOfWebContents(&actual));
                  return false;
                })),
            TabTransferResult::kExternallyInterrupted);
  EXPECT_FALSE(weak);
  page_ = nullptr;
  tab_ = nullptr;
  EXPECT_TRUE(browser()->GetTabStripModel()->empty());
  EXPECT_TRUE(destination_->GetTabStripModel()->empty());
}
TEST_F(NativeTabTransferTest, CollectionCommitsOnlyAfterAllOriginalPagesAttach) {
  auto* second = Append(browser());
  auto* second_tab = tabs::TabInterface::MaybeGetFromContents(second);
  auto* original = page_.get();
  std::vector<base::OnceClosure> cleanup;
  int attached = 0;
  bool committed = false;
  EXPECT_EQ(TransferLiveTabs(
      {original, second}, *destination_,
      base::BindLambdaForTesting([&](BrowserWindowInterface& owner, content::WebContents&) {
        EXPECT_EQ(&owner, destination_.get());
        EXPECT_TRUE(HasLiveTabTransfer());
        EXPECT_TRUE(IsLiveTabTransferTarget(original));
        EXPECT_TRUE(IsLiveTabTransferTarget(second));
        EXPECT_FALSE(ReserveTabTransfer(*UnloadController::From(browser())));
        EXPECT_FALSE(ReserveTabTransfer(*UnloadController::From(destination_.get())));
        ++attached;
        return true;
      }), base::BindLambdaForTesting([&] {
        EXPECT_EQ(attached, 2);
        EXPECT_EQ(tab_->GetBrowserWindowInterface(), destination_.get());
        EXPECT_EQ(second_tab->GetBrowserWindowInterface(), destination_.get());
        committed = true;
        return true;
      }), &cleanup), TabTransferResult::kTransferred);
  EXPECT_TRUE(committed);
  EXPECT_EQ(destination_->GetTabStripModel()->GetTabAtIndex(0), tab_);
  EXPECT_EQ(destination_->GetTabStripModel()->GetTabAtIndex(1), second_tab);
  EXPECT_FALSE(HasLiveTabTransfer());
  EXPECT_FALSE(IsLiveTabTransferTarget(second));
  EXPECT_FALSE(static_cast<TestBrowserWindow*>(browser()->GetWindow())->IsClosed());
  // The physical caller may still own local Notes/Easels; it decides cleanup.
  EXPECT_EQ(cleanup.size(), 1u);
}

TEST_F(NativeTabTransferTest, CollectionAttachmentFailureRestoresOrderSelectionAndOpeners) {
  auto* second = Append(browser());
  auto* third = Append(browser());
  auto* second_tab = tabs::TabInterface::MaybeGetFromContents(second);
  auto* third_tab = tabs::TabInterface::MaybeGetFromContents(third);
  auto* model = browser()->GetTabStripModel();
  model->SetOpenerOfTabAt(1, tab_);
  model->SetTabPinned(0, true);
  model->ActivateTabAt(1);
  int committed = 0;
  std::vector<base::OnceClosure> cleanup;
  EXPECT_EQ(TransferLiveTabs(
      {page_, second}, *destination_,
      base::BindLambdaForTesting([&](BrowserWindowInterface& owner, content::WebContents& actual) {
        return &owner == browser() || &actual != second;
      }), base::BindLambdaForTesting([&] { ++committed; return true; }), &cleanup),
      TabTransferResult::kRestoredToSource);
  EXPECT_EQ(committed, 0);
  EXPECT_EQ(model->GetTabAtIndex(0), tab_);
  EXPECT_EQ(model->GetTabAtIndex(1), second_tab);
  EXPECT_EQ(model->GetTabAtIndex(2), third_tab);
  EXPECT_EQ(model->GetActiveWebContents(), second);
  EXPECT_EQ(model->GetOpenerOfTabAt(1), tab_);
  EXPECT_TRUE(model->IsTabPinned(0));
  EXPECT_TRUE(destination_->GetTabStripModel()->empty());
}

TEST_F(NativeTabTransferTest, CollectionDurableCommitRefusalRollsBackEveryOriginal) {
  auto* second = Append(browser());
  std::vector<base::OnceClosure> cleanup;
  int commit_calls = 0;
  EXPECT_EQ(TransferLiveTabs(
      {page_, second}, *destination_,
      base::BindLambdaForTesting([](BrowserWindowInterface&, content::WebContents&) { return true; }),
      base::BindLambdaForTesting([&] { ++commit_calls; return false; }), &cleanup),
      TabTransferResult::kRestoredToSource);
  EXPECT_EQ(commit_calls, 1);
  EXPECT_EQ(browser()->GetTabStripModel()->GetWebContentsAt(0), page_);
  EXPECT_EQ(browser()->GetTabStripModel()->GetWebContentsAt(1), second);
  EXPECT_TRUE(destination_->GetTabStripModel()->empty());
}

TEST_F(NativeTabTransferTest, CollectionRefusesDuplicateAndForeignOriginalBeforeMutation) {
  auto* foreign = Append(destination_.get());
  std::vector<base::OnceClosure> cleanup;
  int called = 0;
  auto present = base::BindLambdaForTesting([&](BrowserWindowInterface&, content::WebContents&) { ++called; return true; });
  EXPECT_EQ(TransferLiveTabs({page_, page_}, *destination_, present,
      base::BindLambdaForTesting([&] { ++called; return true; }), &cleanup), TabTransferResult::kRefused);
  EXPECT_EQ(TransferLiveTabs({page_, foreign}, *destination_, present,
      base::BindLambdaForTesting([&] { ++called; return true; }), &cleanup), TabTransferResult::kRefused);
  EXPECT_EQ(called, 0);
  EXPECT_EQ(tab_->GetBrowserWindowInterface(), browser());
}

TEST_F(NativeTabTransferTest, CollectionRejectsReentrantSingleTransfer) {
  auto* second = Append(browser());
  std::vector<base::OnceClosure> cleanup;
  EXPECT_EQ(TransferLiveTabs({page_, second}, *destination_,
      base::BindLambdaForTesting([&](BrowserWindowInterface&, content::WebContents&) {
        EXPECT_EQ(TransferLiveTab(*second, *destination_,
            base::BindLambdaForTesting([](BrowserWindowInterface&, content::WebContents&) { return true; })),
            TabTransferResult::kRefused);
        return true;
      }), base::BindLambdaForTesting([] { return true; }), &cleanup), TabTransferResult::kTransferred);
}

}  // namespace
}  // namespace parc
