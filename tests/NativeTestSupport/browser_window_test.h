// Copyright 2026 Parc contributors.
#ifndef PARC_TESTS_PARC_NATIVE_TEST_SUPPORT_BROWSER_WINDOW_TEST_H_
#define PARC_TESTS_PARC_NATIVE_TEST_SUPPORT_BROWSER_WINDOW_TEST_H_

#include <memory>
#include <string>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "base/run_loop.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/test/base/browser_with_test_window_test.h"
#include "chrome/test/base/test_browser_window.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/geometry/rect.h"
#include "url/gurl.h"

class ParcBrowserWindowTest : public BrowserWithTestWindowTest {
 protected:
  using BrowserWithTestWindowTest::BrowserWithTestWindowTest;

  void SetUp() override {
    BrowserWithTestWindowTest::SetUp();
    if (!profile()) {
      return;
    }
    std::unique_ptr<BrowserWindow> window = CreateBrowserWindow();
    window_ = window.get();
    browser_ = CreateBrowser(profile(), BrowserWindowInterface::TYPE_NORMAL,
                             false, window.release());
  }

  void TearDown() override {
    base::RunLoop().RunUntilIdle();
    window_ = nullptr;
    if (browser_) {
      browser_->tab_strip_model()->CloseAllTabs();
      browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
      browser_.reset();
    }
    BrowserWithTestWindowTest::TearDown();
  }

  void DeleteProfile(const std::string& profile_name) override {
    if (profile_name == GetDefaultProfileName() && browser_) {
      window_ = nullptr;
      browser_->tab_strip_model()->CloseAllTabs();
      browser_.reset();
    }
    BrowserWithTestWindowTest::DeleteProfile(profile_name);
  }

  BrowserWindow* window() const { return window_.get(); }

  BrowserWindowInterface* browser() const { return browser_.get(); }

  std::unique_ptr<BrowserWindowInterface> release_browser() {
    window_ = nullptr;
    return std::move(browser_);
  }

  void AddTab(BrowserWindowInterface* target, const GURL& url) {
    NavigateParams params(target, url, ui::PAGE_TRANSITION_TYPED);
    params.tabstrip_index = 0;
    params.disposition = WindowOpenDisposition::kNewForegroundTab;
    Navigate(&params);
    CommitPendingLoad(&params.navigated_or_inserted_contents->GetController());
  }

  void NavigateAndCommitActiveTab(const GURL& url) {
    NavigateAndCommit(browser()->GetTabStripModel()->GetActiveWebContents(),
                      url);
  }

  virtual std::unique_ptr<BrowserWindow> CreateBrowserWindow() {
    return std::make_unique<TestBrowserWindow>();
  }

  std::unique_ptr<BrowserWindowInterface> CreateBrowser(
      Profile* target_profile,
      BrowserWindowInterface::Type browser_type,
      bool hosted_app,
      BrowserWindow* browser_window) {
    BrowserWindowCreateParams params(target_profile, true);
    if (hosted_app) {
      params = BrowserWindowCreateParams::CreateForApp(
          "Test", true, gfx::Rect(), target_profile, true);
    } else if (browser_type == BrowserWindowInterface::Type::TYPE_DEVTOOLS) {
      params = BrowserWindowCreateParams::CreateForDevTools(target_profile);
    } else {
      params.type = browser_type;
    }
    params.window = browser_window;
    return DeprecatedCreateOwnedBrowserWindowForTesting(std::move(params));
  }

  std::unique_ptr<BrowserWindowInterface> CreateBrowser(
      Profile* target_profile,
      BrowserWindowInterface::Type browser_type,
      bool hosted_app) {
    std::unique_ptr<BrowserWindow> browser_window = CreateBrowserWindow();
    return CreateBrowser(target_profile, browser_type, hosted_app,
                         browser_window.release());
  }

 private:
  raw_ptr<BrowserWindow> window_;
  std::unique_ptr<BrowserWindowInterface> browser_;
};

#endif
