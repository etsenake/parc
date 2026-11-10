// Actual ExtensionInstallPrompt/InstallPromptData above real Browser/Profile.
// These exercise real consent controllers, not fake installation success.
#import <AppKit/AppKit.h>

#include "base/run_loop.h"
#include "base/strings/sys_string_conversions.h"
#include "base/test/bind.h"
#include "base/test/run_until.h"
#include "base/test/scoped_feature_list.h"
#include "chrome/browser/extensions/extension_apitest.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/browser_test.h"
#include "content/public/test/browser_test_utils.h"
#include "extension_action_container.h"
#include "extension_install.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_features.h"
#include "extensions/common/permissions/permission_set.h"
#include "extensions/common/permissions/permissions_data.h"
#include "extensions/test/test_extension_dir.h"
#include "ui/base/base_window.h"
#import "window_security_reservation.h"
namespace parc {
namespace {
using Result = extensions::ExtensionInstallPromptClient::Result;
using Payload = extensions::ExtensionInstallPromptClient::DoneCallbackPayload;
NSButton* Button(NSView* root, NSString* title) {
  if ([root isKindOfClass:NSButton.class] &&
      [((NSButton*)root).title isEqual:title]) {
    return (NSButton*)root;
  }
  for (NSView* child in root.subviews) {
    if (auto* button = Button(child, title)) {
      return button;
    }
  }
  return nil;
}
class Host final : public NativeExtensionActionHost {
 public:
  explicit Host(NSWindow* window) : window_(window) {}
  NSWindow* PopupParentWindow() const override { return window_; }
  PCExtensionPopupAnchor* PopupAnchor() const override {
    return [PCExtensionPopupAnchor windowAnchor];
  }
  bool IsSelectedBrowser() const override { return selected; }
  bool HasVisibleBrowserSecurityUI() const override {
    return security || window_.attachedSheet ||
           PCNativeWindowHasSecurityReservation(window_);
  }
  bool HasVisibleBrowserSecurityUIExcluding(
      NSWindow* own,
      PCNativeWindowSecurityReservation* lease) const override {
    return security ||
           (window_.attachedSheet && window_.attachedSheet != own) ||
           (lease ? lease.window != window_ || !lease.isOnlyReservation
                  : PCNativeWindowHasSecurityReservation(window_));
  }
  bool HandlePopupMenuKey(content::WebContents*,
                          const input::NativeWebKeyboardEvent&) override {
    return false;
  }
  bool InspectPopup(content::WebContents*) override { return false; }
  bool ShowActionContextMenu(ExtensionActionViewModel&,
                             id<PCNativeMenuPresenter>) override {
    return false;
  }
  void CloseExtensionsMenu() override {}
  bool ToggleExtensionsMenu() override { return false; }
  void ExtensionActionsChanged() override {}
  void ExtensionCapabilityUnavailable(const std::string&,
                                      const char*) override {}
  __weak NSWindow* window_;
  bool selected = true, security = false;
};

}  // namespace
class NativeExtensionInstallTest : public extensions::ExtensionApiTest {
 public:
  NativeExtensionInstallTest() {
    features_.InitAndEnableFeature(
        extensions_features::kAllowWithholdingExtensionPermissionsOnInstall);
  }

 private:
  base::test::ScopedFeatureList features_;

 protected:
  void SetUpOnMainThread() override {
    extensions::ExtensionApiTest::SetUpOnMainThread();
    window_ = browser()->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    [window_ orderFront:nil];
    host_ = std::make_unique<Host>(window_);
    service_ =
        std::make_unique<NativeExtensionInstallService>(*browser(), *host_);
    fixture_.WriteManifest(
        R"({"name":"Parc install consent fixture","version":"1.0","manifest_version":3,"permissions":["history"],"host_permissions":["https://example.test/*"],"action":{}})");
    extension_ = LoadExtension(fixture_.UnpackedPath());
    ASSERT_TRUE(extension_);
    page_ = TabListInterface::From(browser())->GetActiveTab()->GetContents();
  }
  void TearDownOnMainThread() override {
    if (service_) {
      service_->Shutdown();
    }
    prompt_.reset();
    binding_.reset();
    base::RunLoop().RunUntilIdle();
    service_.reset();
    host_.reset();
    extensions::ExtensionApiTest::TearDownOnMainThread();
  }
  void Confirm() {
    auto data = std::make_unique<extensions::InstallPromptData>(
        extensions::InstallPromptData::UNSET_PROMPT_TYPE);
    prompt_ = std::make_unique<ExtensionInstallPrompt>(page_, std::move(data));
    prompt_->ConfirmPermissions(
        base::BindLambdaForTesting([this](Payload payload) {
          ++results_;
          result_ = payload.result;
        }),
        extension_.get(),
        extension_->permissions_data()->active_permissions().Clone());
  }
  bool Showing() const {
    return window_.attachedSheet && window_.attachedSheet.visible;
  }
  NSButton* Accept() const {
    extensions::InstallPromptData data(
        extensions::InstallPromptData::PERMISSIONS_PROMPT);
    data.set_extension(extension_.get());
    return Button(window_.attachedSheet.contentView,
                  base::SysUTF16ToNSString(data.GetAcceptButtonLabel()));
  }
  void Cancel() {
    extensions::InstallPromptData data(
        extensions::InstallPromptData::PERMISSIONS_PROMPT);
    data.set_extension(extension_.get());
    auto* button = Button(window_.attachedSheet.contentView,
                          base::SysUTF16ToNSString(data.GetAbortButtonLabel()));
    ASSERT_TRUE(button);
    [button performClick:nil];
  }
  __weak NSWindow* window_;
  raw_ptr<content::WebContents> page_ = nullptr;
  std::unique_ptr<Host> host_;
  std::unique_ptr<NativeExtensionInstallService> service_;
  std::unique_ptr<ExtensionInstallPrompt> prompt_;
  std::shared_ptr<extensions::ExtensionInstallNativeBinding> binding_;
  extensions::TestExtensionDir fixture_;
  scoped_refptr<const extensions::Extension> extension_;
  int results_ = 0;
  Result result_ = Result::ABORTED;
};
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       RealPromptCancelResolvesOnceWithoutGrant) {
  Confirm();
  ASSERT_TRUE(base::test::RunUntil([this] { return Showing(); }));
  EXPECT_TRUE(host_->HasVisibleBrowserSecurityUI());
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
  Cancel();
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::USER_CANCELED, result_);
  EXPECT_FALSE(Showing());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  prompt_.reset();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(1, results_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       RealPromptAcceptPreservesOncePayload) {
  Confirm();
  ASSERT_TRUE(base::test::RunUntil(
      [this] { return Showing() && Accept() && Accept().enabled; }));
  [Accept() performClick:nil];
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ACCEPTED, result_);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(
    NativeExtensionInstallTest,
    SelectionLossBeforeDeferredPresentationAbortsOriginalOwner) {
  Confirm();
  host_->selected = false;
  service_->HostStateChanged();
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ABORTED, result_);
  EXPECT_FALSE(Showing());
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       ActualNavigationCancelsPresentedConsent) {
  Confirm();
  ASSERT_TRUE(base::test::RunUntil([this] { return Showing(); }));
  ASSERT_TRUE(
      content::NavigateToURL(page_, GURL("data:text/html,new-document")));
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ABORTED, result_);
  EXPECT_FALSE(Showing());
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       HostDetachCancelsBeforeViewRemoval) {
  Confirm();
  ASSERT_TRUE(base::test::RunUntil([this] { return Showing(); }));
  service_->PageHostWillDetach(page_);
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ABORTED, result_);
  EXPECT_FALSE(Showing());
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       CompetingReservationAbortsWithoutClearingOtherOwner) {
  Confirm();
  ASSERT_TRUE(base::test::RunUntil([this] { return Showing(); }));
  auto* other = [PCNativeWindowSecurityReservation acquireForWindow:window_];
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ABORTED, result_);
  EXPECT_TRUE(other.isOnlyReservation);
  [other invalidate];
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       SecondRequestDoesNotReplaceFirstConsent) {
  Confirm();
  ASSERT_TRUE(base::test::RunUntil([this] { return Showing(); }));
  NSWindow* original = window_.attachedSheet;
  auto other = service_->Capture(page_);
  int second_results = 0;
  Result second = Result::ACCEPTED;
  EXPECT_FALSE(
      other->Begin(extension_.get(), base::BindLambdaForTesting([&](Payload p) {
                     ++second_results;
                     second = p.result;
                   })));
  ASSERT_TRUE(base::test::RunUntil([&] { return second_results == 1; }));
  EXPECT_EQ(Result::ABORTED, second);
  EXPECT_EQ(original, window_.attachedSheet);
  EXPECT_EQ(0, results_);
  Cancel();
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       DestructionDuringAcquisitionDoesNotFallBackToViews) {
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (PCNativeWindowHasSecurityReservation(window_)) {
                  service_.reset();
                }
              }];
  Confirm();
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ABORTED, result_);
  EXPECT_FALSE(Showing());
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       ParentApprovalIsNotTreatedAsOrdinaryConsent) {
  binding_ = service_->Capture(page_);
  ASSERT_TRUE(binding_->Begin(extension_.get(),
                              base::BindLambdaForTesting([this](Payload p) {
                                ++results_;
                                result_ = p.result;
                              })));
  auto data = std::make_unique<extensions::InstallPromptData>(
      extensions::InstallPromptData::EXTENSION_PARENT_APPROVAL_PROMPT);
  data->set_extension(extension_.get());
  binding_->Show(std::move(data));
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ABORTED, result_);
  EXPECT_FALSE(Showing());
}
class OpenObserver final
    : public extensions::ExtensionInstallPromptClient::Observer {
 public:
  explicit OpenObserver(base::RepeatingClosure opened)
      : opened_(std::move(opened)) {}
  void OnDialogOpened() override {
    ++opens;
    opened_.Run();
  }
  void OnDialogAccepted() override { ++accepts; }
  void OnDialogCanceled() override { ++cancels; }
  int opens = 0, accepts = 0, cancels = 0;

 private:
  base::RepeatingClosure opened_;
};
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       OpenObserverCanDestroyActualController) {
  OpenObserver observer(
      base::BindLambdaForTesting([this] { prompt_.reset(); }));
  auto data = std::make_unique<extensions::InstallPromptData>(
      extensions::InstallPromptData::PERMISSIONS_PROMPT);
  data->AddObserver(&observer);
  prompt_ = std::make_unique<ExtensionInstallPrompt>(page_, std::move(data));
  prompt_->ShowDialog(base::BindLambdaForTesting([this](Payload p) {
                        ++results_;
                        result_ = p.result;
                      }),
                      extension_.get(), nullptr,
                      ExtensionInstallPrompt::GetDefaultShowDialogCallback());
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ABORTED, result_);
  EXPECT_EQ(1, observer.opens);
  EXPECT_EQ(1, observer.cancels);
  EXPECT_EQ(0, observer.accepts);
  EXPECT_FALSE(Showing());
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       ActualWithheldPolicyKeepsUncheckedHostPermissionResult) {
  auto data = std::make_unique<extensions::InstallPromptData>(
      extensions::InstallPromptData::INSTALL_PROMPT);
  extensions::InstallPromptData labels(
      extensions::InstallPromptData::INSTALL_PROMPT);
  labels.set_extension(extension_.get());
  prompt_ = std::make_unique<ExtensionInstallPrompt>(page_, std::move(data));
  prompt_->ShowDialog(base::BindLambdaForTesting([this](Payload p) {
                        ++results_;
                        result_ = p.result;
                      }),
                      extension_.get(), nullptr,
                      ExtensionInstallPrompt::GetDefaultShowDialogCallback());
  NSString* title = base::SysUTF16ToNSString(labels.GetAcceptButtonLabel());
  ASSERT_TRUE(base::test::RunUntil([&] {
    return Showing() &&
           Button(window_.attachedSheet.contentView, title).enabled;
  }));
  [Button(window_.attachedSheet.contentView, title) performClick:nil];
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS, result_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       OwnerlessNativeProfileDoesNotSelectFrontmostBrowser) {
  auto data = std::make_unique<extensions::InstallPromptData>(
      extensions::InstallPromptData::PERMISSIONS_PROMPT);
  prompt_ = std::make_unique<ExtensionInstallPrompt>(
      browser()->GetProfile(), gfx::NativeWindow(), std::move(data));
  prompt_->ShowDialog(base::BindLambdaForTesting([this](Payload p) {
                        ++results_;
                        result_ = p.result;
                      }),
                      extension_.get(), nullptr,
                      ExtensionInstallPrompt::GetDefaultShowDialogCallback());
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_EQ(Result::ABORTED, result_);
  EXPECT_FALSE(Showing());
}
IN_PROC_BROWSER_TEST_F(NativeExtensionInstallTest,
                       ReleaseObserverCannotGrantBehindNewSecurityOwner) {
  Confirm();
  ASSERT_TRUE(base::test::RunUntil(
      [this] { return Showing() && Accept() && Accept().enabled; }));
  __block PCNativeWindowSecurityReservation* replacement = nil;
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (!PCNativeWindowHasSecurityReservation(window_) &&
                    !replacement) {
                  replacement = [PCNativeWindowSecurityReservation
                      acquireForWindow:window_];
                }
              }];
  [Accept() performClick:nil];
  const bool finished = base::test::RunUntil([this] { return results_ == 1; });
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  EXPECT_TRUE(replacement.isOnlyReservation);
  [replacement invalidate];
  ASSERT_TRUE(finished);
  EXPECT_EQ(Result::ABORTED, result_);
  EXPECT_FALSE(Showing());
}
}  // namespace parc
