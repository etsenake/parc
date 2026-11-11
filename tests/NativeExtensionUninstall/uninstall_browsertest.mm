// Actual Chromium controller/model/registrar tests. Requires candidate overlay;
// syntax checks alone do not establish execution or native-window integration.
#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/strings/sys_string_conversions.h"
#include "base/test/bind.h"
#include "base/test/run_until.h"
#include "chrome/browser/extensions/extension_apitest.h"
#include "chrome/browser/extensions/extension_context_menu_model.h"
#include "chrome/browser/extensions/extension_uninstall_dialog.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/extensions/security_dialog_tracker.h"
#include "chrome/grit/generated_resources.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/browser_test.h"
#include "content/public/test/browser_test_utils.h"
#include "extension_action_container.h"
#include "extension_security_context.h"
#include "extension_uninstall.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/extension.h"
#include "extensions/test/test_extension_dir.h"
#include "ui/base/base_window.h"
#include "ui/base/interaction/element_identifier.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/models/dialog_model.h"
#include "ui/strings/grit/ui_strings.h"
#include "ui/views/widget/unique_widget_ptr.h"
#include "ui/views/widget/widget.h"
#include "ui/views/window/dialog_delegate.h"
#import "window_security_reservation.h"
namespace parc_hooks {
void SetExtensionUninstallHandler(void (*)(BrowserWindowInterface*,
                                           const extensions::Extension*));
}
namespace parc {
namespace {
DEFINE_LOCAL_ELEMENT_IDENTIFIER_VALUE(kReportCheckbox);
NSButton* FindButton(NSView* root, NSString* title) {
  if ([root isKindOfClass:NSButton.class] &&
      [((NSButton*)root).title isEqualToString:title]) {
    return (NSButton*)root;
  }
  for (NSView* view in root.subviews) {
    if (auto* result = FindButton(view, title)) {
      return result;
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
  // Mirror the production aggregate query: the request must explicitly
  // exclude its own sheet/lease instead of treating them as competing UI.
  bool HasVisibleBrowserSecurityUI() const override {
    return security || window_.attachedSheet ||
           PCNativeWindowHasSecurityReservation(window_);
  }
  bool HasVisibleBrowserSecurityUIExcluding(
      NSWindow* owned_sheet,
      PCNativeWindowSecurityReservation* owned_reservation) const override {
    if (security || !window_ ||
        (window_.attachedSheet && window_.attachedSheet != owned_sheet)) {
      return true;
    }
    return owned_reservation
               ? owned_reservation.window != window_ ||
                     !owned_reservation.isOnlyReservation
               : PCNativeWindowHasSecurityReservation(window_);
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
class NativeExtensionUninstallTest
    : public extensions::ExtensionApiTest,
      public extensions::ExtensionUninstallDialog::Delegate {
 protected:
  void SetUpOnMainThread() override {
    extensions::ExtensionApiTest::SetUpOnMainThread();
    parc_hooks::SetExtensionUninstallHandler(&BeginExtensionUninstall);
    window_ = browser()->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    [window_ orderFront:nil];
    host_ = std::make_unique<Host>(window_);
    service_ =
        std::make_unique<NativeExtensionUninstallService>(*browser(), *host_);
    fixture_.WriteManifest(
        R"({"name":"Parc uninstall lifetime","version":"1.0","manifest_version":3,"action":{}})");
    extension_ = LoadExtension(fixture_.UnpackedPath());
    ASSERT_TRUE(extension_);
  }
  void TearDownOnMainThread() override {
    if (service_) {
      service_->Shutdown();
    }
    binding_.reset();
    dialog_.reset();
    service_.reset();
    host_.reset();
    base::RunLoop().RunUntilIdle();
    extensions::ExtensionApiTest::TearDownOnMainThread();
  }
  void OnExtensionUninstallDialogClosed(bool success,
                                        const std::u16string&) override {
    ++results_;
    success_ = success;
  }
  void Confirm() {
    binding_ = service_->Capture(*extension_);
    auto dialog = std::make_unique<NativeExtensionUninstallDialog>(
        browser()->GetProfile(), browser()->GetWindow()->GetNativeWindow(),
        this, binding_);
    auto* native = dialog.get();
    dialog_ = std::move(dialog);
    native->Confirm(extension_, extensions::UNINSTALL_REASON_USER_INITIATED,
                    extensions::UNINSTALL_SOURCE_TOOLBAR_CONTEXT_MENU);
  }
  bool Presenting() const {
    return window_.attachedSheet && window_.attachedSheet.visible;
  }
  void Click(int label) {
    NSButton* button =
        FindButton(window_.attachedSheet.contentView,
                   base::SysUTF16ToNSString(l10n_util::GetStringUTF16(label)));
    ASSERT_TRUE(button);
    [button performClick:nil];
  }
  bool Registered() const {
    return extensions::ExtensionRegistry::Get(browser()->GetProfile())
               ->GetExtensionById(extension_->id(),
                                  extensions::ExtensionRegistry::EVERYTHING) ==
           extension_.get();
  }
  NSWindow* __weak window_;
  std::unique_ptr<Host> host_;
  std::unique_ptr<NativeExtensionUninstallService> service_;
  std::shared_ptr<ExtensionUninstallNativeBinding> binding_;
  std::unique_ptr<extensions::ExtensionUninstallDialog> dialog_;
  extensions::TestExtensionDir fixture_;
  scoped_refptr<const extensions::Extension> extension_;
  int results_ = 0;
  bool success_ = false;
  int accepted_ = 0, destroyed_ = 0;
  ui::DialogModel* observed_model_ = nullptr;
  bool actual_checkbox_ = false;
};
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       RealControllerCancelPreservesInstalledExtension) {
  ASSERT_TRUE(service_->CanPresent(*extension_));
  Confirm();
  ASSERT_TRUE(base::test::RunUntil([this] { return Presenting(); }));
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
  Click(IDS_APP_CANCEL);
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_FALSE(success_);
  EXPECT_TRUE(Registered());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  binding_->Close();
  EXPECT_EQ(1, results_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       RealUninstallCommandUsesBoundNativeFactoryAndRegistrar) {
  extensions::ExtensionContextMenuModel model(
      extension_.get(), browser(), false, nullptr, true,
      extensions::ExtensionContextMenuModel::ContextMenuSource::kToolbarAction);
  ASSERT_TRUE(model.IsCommandIdEnabled(
      extensions::ExtensionContextMenuModel::UNINSTALL));
  model.ExecuteCommand(extensions::ExtensionContextMenuModel::UNINSTALL, 0);
  ASSERT_TRUE(base::test::RunUntil([this] { return Presenting(); }));
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
  Click(IDS_EXTENSION_PROMPT_UNINSTALL_BUTTON);
  ASSERT_TRUE(base::test::RunUntil([this] { return !Registered(); }));
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       PendingOwnerExpiryCancelsBeforeIconPresentation) {
  Confirm();
  host_->selected = false;
  service_->HostStateChanged();
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_FALSE(success_);
  EXPECT_TRUE(Registered());
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(Presenting());
  EXPECT_EQ(1, results_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       AcquisitionObserverMayDestroyOwningService) {
  id token = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (PCNativeWindowHasSecurityReservation(window_)) {
                  service_.reset();
                }
              }];
  Confirm();
  [NSNotificationCenter.defaultCenter removeObserver:token];
  EXPECT_EQ(1, results_);
  EXPECT_FALSE(success_);
  EXPECT_TRUE(Registered());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       RealModelSurvivesReentrantCloseDuringAccept) {
  binding_ = service_->Capture(*extension_);
  ASSERT_TRUE(
      binding_->Arm(base::BindLambdaForTesting([this] { ++results_; })));
  auto model =
      ui::DialogModel::Builder()
          .SetInternalName("ExtensionUninstallDialog")
          .SetTitle(u"Test")
          .AddOkButton(base::BindLambdaForTesting([this] {
                         ++accepted_;
                         actual_checkbox_ =
                             observed_model_
                                 ->GetCheckboxByUniqueId(kReportCheckbox)
                                 ->is_checked();
                         binding_->Close();
                       }),
                       ui::DialogModel::Button::Params().SetLabel(u"Remove"))
          .AddCancelButton(base::DoNothing())
          .AddCheckbox(kReportCheckbox, ui::DialogModelLabel(u"Real checkbox"))
          .SetDialogDestroyingCallback(base::BindLambdaForTesting([this] {
            observed_model_ = nullptr;
            ++destroyed_;
          }))
          .Build();
  observed_model_ = model.get();
  binding_->Show(std::move(model));
  ASSERT_TRUE(base::test::RunUntil([this] { return Presenting(); }));
  auto* check = FindButton(window_.attachedSheet.contentView, @"Real checkbox");
  ASSERT_TRUE(check);
  [check performClick:nil];
  auto* remove = FindButton(window_.attachedSheet.contentView, @"Remove");
  ASSERT_TRUE(remove);
  [remove performClick:nil];
  ASSERT_TRUE(base::test::RunUntil([this] { return destroyed_ == 1; }));
  EXPECT_EQ(1, accepted_);
  EXPECT_TRUE(actual_checkbox_);
  EXPECT_EQ(0, results_);
  binding_->Close();
  EXPECT_EQ(1, destroyed_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       CapturedPageDetachCancelsWithoutRemoval) {
  Confirm();
  auto* page = TabListInterface::From(browser())->GetActiveTab()->GetContents();
  service_->PageHostWillDetach(page);
  EXPECT_EQ(1, results_);
  EXPECT_FALSE(success_);
  EXPECT_TRUE(Registered());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       ReloadedInstanceDoesNotInheritPendingConsent) {
  const std::string id = extension_->id();
  Confirm();
  ReloadExtension(id);
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_FALSE(success_);
  auto* replacement =
      extensions::ExtensionRegistry::Get(browser()->GetProfile())
          ->GetExtensionById(id, extensions::ExtensionRegistry::EVERYTHING);
  ASSERT_TRUE(replacement);
  EXPECT_NE(extension_.get(), replacement);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       UnsupportedRealModelCancelsExactlyOnce) {
  binding_ = service_->Capture(*extension_);
  ASSERT_TRUE(
      binding_->Arm(base::BindLambdaForTesting([this] { ++results_; })));
  auto model = ui::DialogModel::Builder()
                   .SetInternalName("UnexpectedModel")
                   .AddOkButton(base::DoNothing())
                   .AddCancelButton(base::DoNothing())
                   .SetDialogDestroyingCallback(
                       base::BindLambdaForTesting([this] { ++destroyed_; }))
                   .Build();
  binding_->Show(std::move(model));
  EXPECT_EQ(1, destroyed_);
  EXPECT_EQ(0, results_);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  binding_->Close();
  EXPECT_EQ(1, destroyed_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       OrdinaryNavigationKeepsProfileScopedConsent) {
  Confirm();
  ASSERT_TRUE(base::test::RunUntil([this] { return Presenting(); }));
  auto* page = TabListInterface::From(browser())->GetActiveTab()->GetContents();
  ASSERT_TRUE(
      content::NavigateToURL(page, GURL("data:text/html,<title>Next</title>")));
  EXPECT_TRUE(Presenting());
  EXPECT_EQ(0, results_);
  Click(IDS_APP_CANCEL);
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_FALSE(success_);
  EXPECT_TRUE(Registered());
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       ClosedBindingRejectsLateActualModel) {
  binding_ = service_->Capture(*extension_);
  ASSERT_TRUE(
      binding_->Arm(base::BindLambdaForTesting([this] { ++results_; })));
  binding_->Close();
  EXPECT_EQ(1, results_);
  auto model = ui::DialogModel::Builder()
                   .SetInternalName("ExtensionUninstallDialog")
                   .AddOkButton(base::DoNothing())
                   .AddCancelButton(base::DoNothing())
                   .SetDialogDestroyingCallback(
                       base::BindLambdaForTesting([this] { ++destroyed_; }))
                   .Build();
  binding_->Show(std::move(model));
  EXPECT_EQ(1, destroyed_);
  EXPECT_EQ(1, results_);
  EXPECT_FALSE(Presenting());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
// This is Chromium's supported Add-before-Show sequence. A visibility query
// alone is false at notification time, so the pending dialog must be matched
// through its exact native parent association.
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       SecurityRegistrationBeforeShowCancelsExactWindow) {
  auto* parent = views::Widget::GetWidgetForNativeWindow(
      browser()->GetWindow()->GetNativeWindow());
  ASSERT_TRUE(parent);
  auto delegate = std::make_unique<views::DialogDelegate>();
  views::UniqueWidgetPtr security(
      std::unique_ptr<views::Widget>(views::DialogDelegate::CreateDialogWidget(
          delegate.release(), gfx::NativeWindow(), parent->GetNativeView())));
  ASSERT_FALSE(security->IsVisible());
  ASSERT_TRUE(SecurityWidgetBelongsToWindow(security.get(), window_));
  Confirm();
  auto* tracker = extensions::SecurityDialogTracker::GetInstance();
  EXPECT_FALSE(tracker->BrowserHasVisibleSecurityDialogs(browser()));
  tracker->AddSecurityDialog(security.get());
  EXPECT_EQ(1, results_);
  EXPECT_FALSE(success_);
  EXPECT_TRUE(Registered());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  security->Show();
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(Presenting());
  EXPECT_EQ(1, results_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       SecurityRegistrationInAnotherWindowDoesNotCancel) {
  auto* other = CreateBrowser(browser()->GetProfile());
  auto* parent = views::Widget::GetWidgetForNativeWindow(
      other->GetWindow()->GetNativeWindow());
  ASSERT_TRUE(parent);
  auto delegate = std::make_unique<views::DialogDelegate>();
  views::UniqueWidgetPtr security(
      std::unique_ptr<views::Widget>(views::DialogDelegate::CreateDialogWidget(
          delegate.release(), gfx::NativeWindow(), parent->GetNativeView())));
  ASSERT_FALSE(SecurityWidgetBelongsToWindow(security.get(), window_));
  Confirm();
  extensions::SecurityDialogTracker::GetInstance()->AddSecurityDialog(
      security.get());
  EXPECT_EQ(0, results_);
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
  security->Show();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(0, results_);
  service_->Shutdown();
  EXPECT_EQ(1, results_);
  EXPECT_FALSE(success_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       OwnReservationNotificationDoesNotCancelConfirmation) {
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                service_->HostStateChanged();
              }];
  Confirm();
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  ASSERT_TRUE(base::test::RunUntil([this] { return Presenting(); }));
  EXPECT_EQ(0, results_);
  EXPECT_TRUE(host_->HasVisibleBrowserSecurityUI());
  service_->HostStateChanged();
  EXPECT_TRUE(Presenting());
  EXPECT_EQ(0, results_);
  Click(IDS_APP_CANCEL);
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_TRUE(Registered());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       CompetingReservationCancelsOnlyUninstallOwnership) {
  Confirm();
  ASSERT_TRUE(base::test::RunUntil([this] { return Presenting(); }));
  auto* competing =
      [PCNativeWindowSecurityReservation acquireForWindow:window_];
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_FALSE(success_);
  EXPECT_TRUE(Registered());
  EXPECT_FALSE(Presenting());
  EXPECT_TRUE(competing.isOnlyReservation);
  [competing invalidate];
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  EXPECT_EQ(1, results_);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionUninstallTest,
                       ReservationInAnotherNativeWindowDoesNotCancel) {
  auto* other = CreateBrowser(browser()->GetProfile());
  NSWindow* other_window =
      other->GetWindow()->GetNativeWindow().GetNativeNSWindow();
  Confirm();
  ASSERT_TRUE(base::test::RunUntil([this] { return Presenting(); }));
  auto* unrelated =
      [PCNativeWindowSecurityReservation acquireForWindow:other_window];
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(0, results_);
  EXPECT_TRUE(Presenting());
  EXPECT_TRUE(unrelated.isOnlyReservation);
  Click(IDS_APP_CANCEL);
  ASSERT_TRUE(base::test::RunUntil([this] { return results_ == 1; }));
  EXPECT_TRUE(unrelated.isOnlyReservation);
  [unrelated invalidate];
  EXPECT_TRUE(Registered());
}
}  // namespace parc
