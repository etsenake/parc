// Copyright 2026 Parc contributors.

#include "chrome/browser/ui/autofill/payments/wallet_reminder_notice_bubble_controller.h"

#include <memory>
#include <utility>

#include "base/functional/bind.h"
#include "base/test/bind.h"
#include "chrome/browser/ui/actions/chrome_action_id.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "chrome/browser/ui/autofill/payments/wallet_reminder_notice_page_action_controller.h"
#include "chrome/browser/ui/autofill/test/test_autofill_bubble_handler.h"
#include "chrome/browser/ui/browser_actions.h"
#include "chrome/browser/ui/browser_window/test/mock_browser_window_interface.h"
#include "chrome/browser/ui/page_action/test_support/mock_page_action_controller.h"
#include "chrome/test/base/chrome_render_view_host_test_harness.h"
#include "components/tabs/public/mock_tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "ui/actions/actions.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"
#include "ui/base/unowned_user_data/unowned_user_data_host.h"
#include "url/gurl.h"

namespace autofill {

namespace {

class ParcWalletBrowserWindow : public MockBrowserWindowInterface {
 public:
  bool IsNormalBrowser() const override { return true; }
};

class ParcWalletAutofillBubbleHandler : public TestAutofillBubbleHandler {
 public:
  MOCK_METHOD(AutofillBubbleBase*,
              ShowWalletReminderNoticeBubble,
              (content::WebContents*,
               WalletReminderNoticeBubbleController*,
               bool),
              (override));
};

class ParcWalletReminderNoticeBubbleControllerTest
    : public ChromeRenderViewHostTestHarness {
 protected:
  void SetUp() override {
    ChromeRenderViewHostTestHarness::SetUp();
    NavigateAndCommit(GURL("about:blank"));

    ON_CALL(mock_tab_interface_, GetUnownedUserDataHost())
        .WillByDefault(testing::ReturnRef(tab_unowned_user_data_host_));
    ON_CALL(mock_tab_interface_, GetBrowserWindowInterface())
        .WillByDefault(testing::Return(&mock_browser_window_interface_));
    ON_CALL(mock_browser_window_interface_, GetUnownedUserDataHost())
        .WillByDefault(testing::ReturnRef(browser_unowned_user_data_host_));

    test_autofill_bubble_handler_registration_ =
        std::make_unique<ui::ScopedUnownedUserData<AutofillBubbleHandler>>(
            mock_browser_window_interface_.GetUnownedUserDataHost(),
            mock_autofill_bubble_handler_);

    wallet_reminder_notice_page_action_controller_ =
        std::make_unique<WalletReminderNoticePageActionController>(
            mock_tab_interface_, mock_page_action_controller_);

    controller_ = std::make_unique<WalletReminderNoticeBubbleController>(
        mock_tab_interface_, web_contents());
  }

  void TearDown() override {
    wallet_reminder_notice_page_action_controller_.reset();
    test_autofill_bubble_handler_registration_.reset();
    controller_.reset();
    ChromeRenderViewHostTestHarness::TearDown();
  }

  tabs::MockTabInterface mock_tab_interface_;
  ParcWalletBrowserWindow mock_browser_window_interface_;
  ui::UnownedUserDataHost browser_unowned_user_data_host_;
  ParcWalletAutofillBubbleHandler mock_autofill_bubble_handler_;
  std::unique_ptr<ui::ScopedUnownedUserData<AutofillBubbleHandler>>
      test_autofill_bubble_handler_registration_;
  TestAutofillBubble test_bubble_;
  ui::UnownedUserDataHost tab_unowned_user_data_host_;
  page_actions::MockPageActionController mock_page_action_controller_;
  std::unique_ptr<WalletReminderNoticePageActionController>
      wallet_reminder_notice_page_action_controller_;
  std::unique_ptr<WalletReminderNoticeBubbleController> controller_;
};

TEST_F(ParcWalletReminderNoticeBubbleControllerTest,
       HandlerCanDestroyControllerBeforeReturningView) {
  EXPECT_CALL(
      mock_autofill_bubble_handler_,
      ShowWalletReminderNoticeBubble(web_contents(), controller_.get(), false))
      .WillOnce([&](auto*, auto*, bool) {
        controller_.reset();
        return &test_bubble_;
      });
  int results = 0;
  controller_->Show({}, base::BindLambdaForTesting([&](bool presented) {
                      ++results;
                      EXPECT_FALSE(presented);
                    }));
  EXPECT_FALSE(controller_);
  EXPECT_EQ(results, 1);
}

TEST_F(ParcWalletReminderNoticeBubbleControllerTest,
       ActionObserverCanDestroyControllerBeforePresentationObserver) {
  ON_CALL(mock_browser_window_interface_, GetProfile())
      .WillByDefault(testing::Return(profile()));
  BrowserActions browser_actions(&mock_browser_window_interface_);
  auto root = actions::ActionItem::Builder().Build();
  auto* action = root->AddChild(actions::ActionItem::Builder()
                                    .SetActionId(kActionWalletReminderNotice)
                                    .Build());
  browser_actions.set_root_action_item_for_testing(
      actions::ActionManager::Get().AddAction(std::move(root)));
  auto subscription =
      action->AddActionChangedCallback(base::BindLambdaForTesting([&] {
        if (action->GetIsShowingBubble()) {
          controller_.reset();
        }
      }));
  EXPECT_CALL(mock_page_action_controller_, Show(kActionWalletReminderNotice))
      .Times(0);
  EXPECT_CALL(
      mock_autofill_bubble_handler_,
      ShowWalletReminderNoticeBubble(web_contents(), controller_.get(), false))
      .WillOnce(testing::Return(&test_bubble_));
  int results = 0;
  controller_->Show({}, base::BindLambdaForTesting([&](bool presented) {
                      ++results;
                      EXPECT_FALSE(presented);
                    }));
  EXPECT_FALSE(controller_);
  EXPECT_EQ(results, 1);
}

TEST_F(ParcWalletReminderNoticeBubbleControllerTest,
       ActionObserverCanCloseBeforePresentationObserver) {
  ON_CALL(mock_browser_window_interface_, GetProfile())
      .WillByDefault(testing::Return(profile()));
  BrowserActions browser_actions(&mock_browser_window_interface_);
  auto root = actions::ActionItem::Builder().Build();
  auto* action = root->AddChild(actions::ActionItem::Builder()
                                    .SetActionId(kActionWalletReminderNotice)
                                    .Build());
  browser_actions.set_root_action_item_for_testing(
      actions::ActionManager::Get().AddAction(std::move(root)));
  auto subscription =
      action->AddActionChangedCallback(base::BindLambdaForTesting([&] {
        if (action->GetIsShowingBubble()) {
          controller_->OnBubbleClosed();
        }
      }));
  EXPECT_CALL(mock_page_action_controller_, Show(kActionWalletReminderNotice))
      .Times(0);
  EXPECT_CALL(
      mock_autofill_bubble_handler_,
      ShowWalletReminderNoticeBubble(web_contents(), controller_.get(), false))
      .WillOnce(testing::Return(&test_bubble_));
  int results = 0;
  controller_->Show({}, base::BindLambdaForTesting([&](bool presented) {
                      ++results;
                      EXPECT_FALSE(presented);
                    }));
  ASSERT_TRUE(controller_);
  EXPECT_EQ(controller_->GetBubbleView(), nullptr);
  EXPECT_EQ(results, 1);
}

}  // namespace

}  // namespace autofill
