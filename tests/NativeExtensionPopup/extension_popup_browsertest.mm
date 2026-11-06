// Copyright 2026 Parc contributors.
// Genuine ExtensionViewHost/WebContents tests. Not standalone presenter mocks.
#include "extension_popup.h"

#include <memory>

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "chrome/browser/extensions/extension_apitest.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/test/browser_test.h"
#include "content/public/test/browser_test_utils.h"
#include "extensions/common/extension.h"
#include "extensions/test/test_extension_dir.h"

namespace parc {
class NativeExtensionPopupBrowserTest : public extensions::ExtensionApiTest {
 protected:
  const extensions::Extension* LoadFixture() {
    fixture_.WriteManifest(R"({"name":"Parc popup lifetime", "version":"1.0",
      "manifest_version":3,"action":{"default_popup":"popup.html"}})");
    fixture_.WriteFile(FILE_PATH_LITERAL("popup.html"),
                       "<!doctype html><title>Native "
                       "popup</title><button>Actual extension</button>");
    return LoadExtension(fixture_.UnpackedPath());
  }
  void SetUpOnMainThread() override {
    extensions::ExtensionApiTest::SetUpOnMainThread();
    parent_ = [[NSWindow alloc] initWithContentRect:NSMakeRect(10, 10, 900, 700)
                                          styleMask:NSWindowStyleMaskTitled
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    parent_.releasedWhenClosed = NO;
  }
  void TearDownOnMainThread() override {
    if (popup_) {
      popup_->Close();
    }
    popup_.reset();
    base::RunLoop().RunUntilIdle();
    [parent_ close];
    parent_ = nil;
    extensions::ExtensionApiTest::TearDownOnMainThread();
  }
  std::unique_ptr<extensions::ExtensionViewHost> MakeHost(
      const extensions::Extension& extension) {
    return extensions::ExtensionViewHostFactory::CreatePopupHost(
        extension, extension.GetResourceURL("popup.html"), browser());
  }
  void Create(std::unique_ptr<extensions::ExtensionViewHost> host,
              ShowPopupCallback callback) {
    NativeExtensionPopup::Callbacks hooks;
    hooks.anchor = base::BindRepeating(
        [] { return [PCExtensionPopupAnchor windowAnchor]; });
    hooks.security_ui_visible =
        base::BindLambdaForTesting([this] { return security_visible_; });
    hooks.menu_key = base::BindRepeating(
        [](content::WebContents*, const input::NativeWebKeyboardEvent&) {
          return false;
        });
    hooks.inspect =
        base::BindRepeating([](content::WebContents*) { return false; });
    // These session tests isolate the owning host; production uses real action
    // HidePopup through NativeExtensionActionContainer.
    hooks.request_hide = base::BindLambdaForTesting([this] {
      if (popup_) {
        popup_->Close();
      }
    });
    hooks.closed = base::BindLambdaForTesting([this] { ++closed_; });
    popup_ = std::make_shared<NativeExtensionPopup>(
        std::move(host), parent_, PopupShowAction::kShow, std::move(callback),
        std::move(hooks));
  }
  ShowPopupCallback ObserveResult() {
    return base::BindLambdaForTesting(
        [this](extensions::ExtensionHost* result) {
          ++results_;
          last_result_ = result;
          if (waiter_) {
            waiter_->Quit();
          }
        });
  }
  int close_completions_ = 0;
  bool contents_destroyed_ = false;
  int results_ = 0;
  extensions::ExtensionHost* last_result_ = nullptr;
  std::unique_ptr<base::RunLoop> waiter_;
  extensions::TestExtensionDir fixture_;
  NSWindow* __strong parent_ = nil;
  std::shared_ptr<NativeExtensionPopup> popup_;
  bool security_visible_ = false;
  int closed_ = 0;
};
class VisibilityCloser : public content::WebContentsObserver {
 public:
  VisibilityCloser(content::WebContents* contents,
                   std::weak_ptr<NativeExtensionPopup> popup,
                   content::Visibility desired)
      : WebContentsObserver(contents),
        popup_(std::move(popup)),
        desired_(desired) {}
  void OnVisibilityWillChange(content::Visibility visibility) override {
    if (visibility != desired_ || invoked) {
      return;
    }
    invoked = true;
    auto popup = popup_.lock();
    ASSERT_TRUE(popup);
    auto* original = web_contents();
    popup->Close();
    // Real Chromium continues to use this WebContents after this notification.
    EXPECT_EQ(original, web_contents());
    EXPECT_FALSE(destroyed);
  }
  void WebContentsDestroyed() override { destroyed = true; }
  bool invoked = false;
  bool destroyed = false;

 private:
  std::weak_ptr<NativeExtensionPopup> popup_;
  content::Visibility desired_;
};

IN_PROC_BROWSER_TEST_F(NativeExtensionPopupBrowserTest,
                       SuppliedHostIdentityAndCloseOnce) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto host = MakeHost(*extension);
  auto* expected_host = host.get();
  auto* expected_contents = host->host_contents();
  waiter_ = std::make_unique<base::RunLoop>();
  Create(std::move(host), ObserveResult());
  ASSERT_TRUE(popup_->Start());
  waiter_->Run();
  EXPECT_EQ(expected_host, last_result_);
  EXPECT_EQ(expected_contents,
            last_result_ ? last_result_->host_contents() : nullptr);
  EXPECT_EQ(1, results_);
  EXPECT_EQ(profile(), expected_contents->GetBrowserContext());
  expected_host->Close();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(1, closed_);
  EXPECT_EQ(1, results_);
  popup_->Close();
  EXPECT_EQ(1, closed_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionPopupBrowserTest,
                       StartKeepsLoadingPopupVisible) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto host = MakeHost(*extension);
  auto* contents = host->host_contents();
  Create(std::move(host), ObserveResult());
  ASSERT_TRUE(popup_->Start());
  // As in Chrome, the page loads visible so its renderer keeps foreground
  // priority; a hidden load starved it under system load.
  EXPECT_EQ(content::Visibility::VISIBLE, contents->GetVisibility());
  popup_->Close();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(nullptr, last_result_);
  EXPECT_EQ(1, results_);
  EXPECT_EQ(1, closed_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionPopupBrowserTest,
                       CloseDuringShowNeverReportsSuccess) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto host = MakeHost(*extension);
  auto* contents = host->host_contents();
  waiter_ = std::make_unique<base::RunLoop>();
  Create(std::move(host), ObserveResult());
  ASSERT_TRUE(popup_->Start());
  // Start already made the page visible in the unshown window; hide it so the
  // only VISIBLE notice left is the one the show sends.
  contents->WasHidden();
  VisibilityCloser closer(contents, popup_, content::Visibility::VISIBLE);
  waiter_->Run();
  EXPECT_EQ(nullptr, last_result_);
  EXPECT_TRUE(closer.invoked);
  EXPECT_TRUE(closer.destroyed);
  EXPECT_EQ(nullptr, last_result_);
  EXPECT_EQ(1, results_);
  EXPECT_EQ(1, closed_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionPopupBrowserTest,
                       SecurityWhileOpeningCancelsShow) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  waiter_ = std::make_unique<base::RunLoop>();
  Create(MakeHost(*extension), ObserveResult());
  ASSERT_TRUE(popup_->Start());
  security_visible_ = true;
  popup_->SecurityUIChanged();
  waiter_->Run();
  EXPECT_EQ(nullptr, last_result_);
  EXPECT_EQ(1, results_);
  EXPECT_EQ(1, closed_);
  EXPECT_EQ(nullptr, popup_->host());
}
class CompletionCloser : public content::WebContentsObserver {
 public:
  CompletionCloser(content::WebContents* contents,
                   std::weak_ptr<NativeExtensionPopup> popup,
                   base::OnceClosure completed,
                   bool& destroyed)
      : WebContentsObserver(contents),
        popup_(std::move(popup)),
        completed_(std::move(completed)),
        destroyed_(destroyed) {}
  void OnVisibilityWillChange(content::Visibility visibility) override {
    if (visibility != content::Visibility::VISIBLE || invoked_) {
      return;
    }
    invoked_ = true;
    auto popup = popup_.lock();
    ASSERT_TRUE(popup);
    auto* original = web_contents();
    popup->Close(std::move(completed_));
    // The true engine-owned object must survive its visibility callback.
    EXPECT_EQ(original, web_contents());
    EXPECT_FALSE(destroyed_);
  }
  void WebContentsDestroyed() override { destroyed_ = true; }

 private:
  std::weak_ptr<NativeExtensionPopup> popup_;
  base::OnceClosure completed_;
  bool& destroyed_;
  bool invoked_ = false;
};
IN_PROC_BROWSER_TEST_F(NativeExtensionPopupBrowserTest,
                       CloseCompletionFollowsActualHostDestruction) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto host = MakeHost(*extension);
  auto* contents = host->host_contents();
  Create(std::move(host), ObserveResult());
  ASSERT_TRUE(popup_->Start());
  // Start already made the page visible in the unshown window; hide it so the
  // close happens inside the show's VISIBLE notice.
  contents->WasHidden();
  base::RunLoop completed;
  CompletionCloser closer(contents, popup_,
                          base::BindLambdaForTesting([this, &completed] {
                            EXPECT_TRUE(contents_destroyed_);
                            EXPECT_EQ(1, closed_);
                            EXPECT_EQ(1, results_);
                            EXPECT_EQ(nullptr, popup_->host());
                            ++close_completions_;
                            completed.Quit();
                          }),
                          contents_destroyed_);
  EXPECT_EQ(0, close_completions_);
  completed.Run();
  EXPECT_EQ(1, close_completions_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionPopupBrowserTest,
                       RepeatedCloseObserversAreAlwaysPostedOnce) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  Create(MakeHost(*extension), ObserveResult());
  popup_->Close(base::BindLambdaForTesting([this] { ++close_completions_; }));
  EXPECT_EQ(0, close_completions_);
  popup_->Close(base::BindLambdaForTesting([this] { ++close_completions_; }));
  EXPECT_EQ(0, close_completions_);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(2, close_completions_);
  EXPECT_EQ(1, closed_);
  EXPECT_EQ(1, results_);
  popup_->Close();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(2, close_completions_);
}
}  // namespace parc
