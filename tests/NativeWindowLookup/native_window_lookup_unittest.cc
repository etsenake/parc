// Copyright 2026 Parc contributors.
#include <memory>
#include <utility>

#include "chrome/browser/ui/autofill/address_bubbles_controller.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/web_contents_tester.h"
#include "parc/tests/parc_native_test_support/browser_window_test.h"
#include "url/gurl.h"

namespace parc {

class NativeWindowLookupTest : public ParcBrowserWindowTest {};

TEST_F(NativeWindowLookupTest, ResolvesActiveAndBackgroundTabsWithoutViews) {
  ASSERT_FALSE(window()->AsBrowserView());
  AddTab(browser(), GURL("https://first.example/"));
  auto* first = browser()->GetTabStripModel()->GetActiveWebContents();
  ASSERT_TRUE(first);
  EXPECT_EQ(window(), BrowserWindow::FindBrowserWindowWithWebContents(first));

  AddTab(browser(), GURL("https://second.example/"));
  auto* second = browser()->GetTabStripModel()->GetActiveWebContents();
  ASSERT_NE(first, second);
  EXPECT_EQ(window(), BrowserWindow::FindBrowserWindowWithWebContents(first));
  EXPECT_EQ(window(), BrowserWindow::FindBrowserWindowWithWebContents(second));
}

TEST_F(NativeWindowLookupTest, UnattachedContentsDoesNotBorrowCurrentWindow) {
  AddTab(browser(), GURL("https://active.example/"));
  auto contents =
      content::WebContentsTester::CreateTestWebContents(profile(), nullptr);
  EXPECT_EQ(nullptr,
            BrowserWindow::FindBrowserWindowWithWebContents(contents.get()));
}

TEST_F(NativeWindowLookupTest, AddressAcceptanceDoesNotRequireChromePromoView) {
  AddTab(browser(), GURL("https://address.example/"));
  auto* contents = browser()->GetTabStripModel()->GetActiveWebContents();
  ASSERT_EQ(window(),
            BrowserWindow::FindBrowserWindowWithWebContents(contents));
  ASSERT_FALSE(window()->AsBrowserView());
  autofill::AddressBubblesController::CreateForWebContents(contents);
  auto* controller =
      autofill::AddressBubblesController::FromWebContents(contents);
  ASSERT_TRUE(controller);
  autofill::AutofillProfile address(autofill::AddressCountryCode("US"));
  autofill::SaveAddressBubbleController save_controller(
      controller->GetWeakPtr(), contents, address,
      autofill::AutofillClient::SaveAddressBubbleType::kSave);
  save_controller.OnUserDecision(
      autofill::AutofillClient::AddressPromptUserDecision::kAccepted, address);
}

TEST_F(NativeWindowLookupTest, DetachedTabResolvesOnlyAfterActualReinsertion) {
  AddTab(browser(), GURL("https://keep-source.example/"));
  AddTab(browser(), GURL("https://transfer.example/"));
  auto* source_tabs = browser()->GetTabStripModel();
  auto* contents = source_tabs->GetActiveWebContents();
  auto tab = source_tabs->DetachTabAtForInsertion(source_tabs->active_index());
  ASSERT_TRUE(tab);
  EXPECT_EQ(nullptr, BrowserWindow::FindBrowserWindowWithWebContents(contents));

  auto destination =
      CreateBrowser(profile(), BrowserWindowInterface::TYPE_NORMAL, false);
  ASSERT_TRUE(destination);
  auto* destination_window = BrowserWindow::FromBrowser(destination.get());
  ASSERT_TRUE(destination_window);
  ASSERT_NE(window(), destination_window);
  destination->GetTabStripModel()->InsertDetachedTabAt(0, std::move(tab),
                                                       AddTabTypes::ADD_ACTIVE);
  EXPECT_EQ(destination_window,
            BrowserWindow::FindBrowserWindowWithWebContents(contents));

  destination->GetTabStripModel()->CloseAllTabs();
  destination->GetFeatures().TearDownPreBrowserWindowDestruction();
  destination.reset();
}

}
