// Copyright 2026 Parc contributors.
// Genuine current-engine DevToolsWindow + native pane tests. The test runner's
// ordinary Browser supplies Profile/tab policy; this does not prove the native
// application factory or Swift auxiliary window integration.
#include "base/functional/bind.h"
#include "chrome/browser/devtools/devtools_ui_controller.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/devtools/devtools_window_testing.h"
#include "chrome/browser/ui/browser_web_contents_delegate/browser_web_contents_delegate.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/web_modal/browser_window_modal_dialog_delegate.h"
#include "chrome/test/base/in_process_browser_test.h"
#include "components/web_modal/single_web_contents_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/browser_test.h"
#include "devtools_pane.h"
#import "page_host.h"
#include "ui/base/unowned_user_data/user_data_factory.h"

namespace parc {
// Uses the actual WebContentsModalDialogManager and Browser delegate. Only the
// platform dialog is a test double; no permissions/dialog state is fabricated.
class TrackingDialog final : public web_modal::SingleWebContentsDialogManager {
 public:
  explicit TrackingDialog(web_modal::WebContentsModalDialogManager& manager)
      : manager_(manager) {}
  void Show() override {}
  void Hide() override {}
  void Close() override { manager_->WillClose(gfx::NativeWindow()); }
  void Focus() override {}
  void Pulse() override {}
  void HostChanged(web_modal::WebContentsModalDialogHost* host) override {
    host_ = host;
  }
  gfx::NativeWindow dialog() override { return gfx::NativeWindow(); }
  bool IsActive() const override { return false; }
  raw_ptr<web_modal::WebContentsModalDialogHost> host_ = nullptr;

 private:
  raw_ref<web_modal::WebContentsModalDialogManager> manager_;
};
class NativeDevToolsBrowserTest : public InProcessBrowserTest {
 public:
  NativeDevToolsBrowserTest() {
    override_ =
        BrowserWindowFeatures::GetUserDataFactoryForTesting()
            .AddOverrideForTesting(base::BindRepeating(
                [](NativeDevToolsBrowserTest* fixture,
                   BrowserWindowInterface& owner) {
                  return std::make_unique<DevtoolsUIController>(
                      &owner, std::make_unique<Delegate>(*fixture, owner));
                },
                base::Unretained(this)));
  }

 protected:
  class Delegate final : public DevtoolsUIController::NativeDelegate {
   public:
    Delegate(NativeDevToolsBrowserTest& fixture, BrowserWindowInterface& owner)
        : fixture_(fixture), owner_(owner) {}
    bool Update(content::WebContents* inspected, bool replace) override {
      return fixture_.pane_ && fixture_.inspected_ == inspected &&
             &owner_ == fixture_.presentation_owner_ &&
             fixture_.pane_->Refresh(replace);
    }
    void SetScrim(content::WebContents* tools, bool visible) override {
      fixture_.scrim_owner_ = &owner_;
      fixture_.scrim_visible_ = visible;
      if (fixture_.pane_ && fixture_.pane_->tools() == tools) {
        fixture_.pane_->SetBlocked(visible);
      }
    }
    void TearDown() override {
      if (fixture_.pane_ && &owner_ == fixture_.presentation_owner_) {
        fixture_.pane_->Detach();
      }
    }

   private:
    NativeDevToolsBrowserTest& fixture_;
    BrowserWindowInterface& owner_;
  };
  void SetUpOnMainThread() override {
    InProcessBrowserTest::SetUpOnMainThread();
    presentation_owner_ = browser();
    inspected_ = browser()->GetTabStripModel()->GetActiveWebContents();
    ASSERT_TRUE(inspected_);
    original_view_ = inspected_->GetNativeView().GetNativeNSView();
    original_parent_ = original_view_.superview;
    original_frame_ = original_view_.frame;
    parent_ = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
                                          styleMask:NSWindowStyleMaskTitled
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    parent_.releasedWhenClosed = NO;
    page_ = [PCNativePageHost hostWithContentView:original_view_ observer:nil];
    pane_ = NativeDevToolsPane::Create(*inspected_, page_);
    pane_->view().frame = parent_.contentView.bounds;
    [parent_.contentView addSubview:pane_->view()];
  }
  void TearDownOnMainThread() override {
    if (inspected_) {
      if (auto* tools =
              DevToolsWindow::GetInstanceForInspectedWebContents(inspected_)) {
        DevToolsWindowTesting::CloseDevToolsWindowSync(tools);
      }
    }
    if (pane_) {
      pane_->Detach();
    }
    pane_.reset();
    [original_view_ removeFromSuperview];
    [original_parent_ addSubview:original_view_];
    original_view_.frame = original_frame_;
    [parent_ close];
    inspected_ = nullptr;
    presentation_owner_ = nullptr;
    scrim_owner_ = nullptr;
    InProcessBrowserTest::TearDownOnMainThread();
  }
  DevToolsWindow* OpenDocked() {
    auto* controller = DevtoolsUIController::From(browser());
    CHECK(controller && controller->CanDockDevtools() &&
          controller->HasNativePresentation());
    auto* tools =
        DevToolsWindowTesting::OpenDevToolsWindowSync(inspected_, true);
    if (tools) {
      pane_->Refresh(true);
    }
    return tools;
  }
  void VerifyModalTransfer(BrowserWindowInterface* destination) {
    auto* window = OpenDocked();
    ASSERT_TRUE(window);
    auto* tools = window->GetDevToolsWebContents().get();
    auto* manager =
        web_modal::WebContentsModalDialogManager::FromWebContents(tools);
    ASSERT_TRUE(manager);
    auto dialog = std::make_unique<TrackingDialog>(*manager);
    auto* dialog_ptr = dialog.get();
    manager->ShowDialogWithManager(gfx::NativeWindow(), std::move(dialog));
    EXPECT_TRUE(manager->IsDialogActive());
    pane_->Detach();
    EXPECT_EQ(manager->delegate(), nullptr);
    EXPECT_EQ(dialog_ptr->host_, nullptr);

    AddBlankTabAndShow(browser());
    auto tab = browser()->GetTabStripModel()->DetachTabAtForInsertion(
        browser()->GetTabStripModel()->GetIndexOfWebContents(inspected_));
    destination->GetTabStripModel()->AppendTab(std::move(tab), true);
    presentation_owner_ = destination;
    pane_ = NativeDevToolsPane::Create(*inspected_, page_);
    pane_->view().frame = parent_.contentView.bounds;
    [parent_.contentView addSubview:pane_->view()];
    pane_->Refresh(true);
    EXPECT_EQ(manager->delegate(),
              BrowserWindowModalDialogDelegate::From(destination));
    EXPECT_NE(dialog_ptr->host_, nullptr);
    EXPECT_EQ(scrim_owner_, destination);
    EXPECT_TRUE(scrim_visible_);
    manager->WillClose(gfx::NativeWindow());
    pane_->Detach();
    auto restored = destination->GetTabStripModel()->DetachTabAtForInsertion(
        destination->GetTabStripModel()->GetIndexOfWebContents(inspected_));
    browser()->GetTabStripModel()->AppendTab(std::move(restored), true);
    presentation_owner_ = browser();
  }
  raw_ptr<BrowserWindowInterface> presentation_owner_ = nullptr;
  raw_ptr<BrowserWindowInterface> scrim_owner_ = nullptr;
  bool scrim_visible_ = false;
  std::shared_ptr<NativeDevToolsPane> pane_;
  raw_ptr<content::WebContents> inspected_ = nullptr;
  NSWindow* __strong parent_;
  NSView* __strong original_parent_;
  NSView* __strong original_view_;
  PCNativePageHost* __strong page_;
  NSRect original_frame_;
  ui::UserDataFactory::ScopedOverride override_;
};
IN_PROC_BROWSER_TEST_F(NativeDevToolsBrowserTest,
                       HostsActualContentsAndRealGeometry) {
  auto* window = OpenDocked();
  ASSERT_TRUE(window);
  auto* tools = window->GetDevToolsWebContents().get();
  ASSERT_EQ(pane_->tools(), tools);
  EXPECT_EQ(pane_->view().toolsView, tools->GetNativeView().GetNativeNSView());
  EXPECT_EQ(pane_->view().inspectedView, page_);
  DevToolsWindowTesting::Get(window)->SetInspectedPageBounds(
      gfx::Rect(0, 0, 620, 700));
  pane_->Refresh(true);
  DevToolsContentsResizingStrategy strategy;
  EXPECT_EQ(DevToolsWindow::GetInTabWebContents(inspected_, &strategy), tools);
  gfx::Rect tools_bounds, page_bounds;
  ApplyDevToolsContentsResizingStrategy(strategy, gfx::Rect(900, 700),
                                        &tools_bounds, &page_bounds);
  EXPECT_TRUE(NSEqualRects(
      page_.frame, NSMakeRect(page_bounds.x(), page_bounds.y(),
                              page_bounds.width(), page_bounds.height())));
  EXPECT_TRUE(NSEqualRects(pane_->find_anchor().frame, page_.frame));
}
IN_PROC_BROWSER_TEST_F(NativeDevToolsBrowserTest,
                       DockTransitionKeepsExactTools) {
  auto* window = OpenDocked();
  ASSERT_TRUE(window);
  auto* actual = window->GetDevToolsWebContents().get();
  auto* delegate = static_cast<DevToolsUIBindings::Delegate*>(window);
  delegate->SetIsDocked(false);
  pane_->Refresh(true);
  EXPECT_EQ(window->GetDevToolsWebContents(), actual);
  EXPECT_NE(pane_->tools(), actual);  // May host the real toolbox instead.
  auto* auxiliary =
      GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(actual);
  ASSERT_TRUE(auxiliary);
  // Undocked main uses its actual Browser delegate, not the direct docked/tools
  // hook. CEF's real delegate runs native menu once then that Browser's
  // registry.
  EXPECT_EQ(actual->GetDelegate(), BrowserWebContentsDelegate::From(auxiliary));
  delegate->SetIsDocked(true);
  pane_->Refresh(true);
  EXPECT_EQ(window->GetDevToolsWebContents(), actual);
  EXPECT_EQ(pane_->tools(), actual);
}
IN_PROC_BROWSER_TEST_F(NativeDevToolsBrowserTest,
                       RealCloseRestoresInspectedPage) {
  auto* window = OpenDocked();
  ASSERT_TRUE(window);
  DevToolsWindowTesting::CloseDevToolsWindowSync(window);
  pane_->Refresh(true);
  EXPECT_FALSE(pane_->tools());
  EXPECT_EQ(pane_->view().inspectedView, page_);
  EXPECT_FALSE(page_.hidden);
  EXPECT_TRUE(NSEqualRects(page_.frame, pane_->view().bounds));
  EXPECT_EQ(browser()->GetTabStripModel()->GetActiveWebContents(), inspected_);
}
IN_PROC_BROWSER_TEST_F(NativeDevToolsBrowserTest,
                       ModalOwnerFollowsActualInspectedTabTransfer) {
  VerifyModalTransfer(CreateBrowser(browser()->GetProfile()));
}
IN_PROC_BROWSER_TEST_F(NativeDevToolsBrowserTest,
                       ExistingDockedModalFollowsTransferIntoPopupBrowser) {
  auto* destination = CreateBrowserForPopup(browser()->GetProfile());
  ASSERT_FALSE(DevtoolsUIController::From(destination)->CanDockDevtools());
  VerifyModalTransfer(destination);
}
IN_PROC_BROWSER_TEST_F(NativeDevToolsBrowserTest,
                       OldModalLeaseCannotClearNewerBindingOrUndockedOwner) {
  auto* window = OpenDocked();
  ASSERT_TRUE(window);
  auto* tools = window->GetDevToolsWebContents().get();
  auto* manager =
      web_modal::WebContentsModalDialogManager::FromWebContents(tools);
  ASSERT_TRUE(manager);
  auto old = DevToolsWindow::BindNativeDockedModalDialogHost(inspected_, tools);
  auto current =
      DevToolsWindow::BindNativeDockedModalDialogHost(inspected_, tools);
  old.RunAndReset();
  EXPECT_EQ(manager->delegate(),
            BrowserWindowModalDialogDelegate::From(browser()));
  static_cast<DevToolsUIBindings::Delegate*>(window)->SetIsDocked(false);
  auto* auxiliary =
      GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(tools);
  ASSERT_TRUE(auxiliary);
  current.RunAndReset();
  EXPECT_EQ(manager->delegate(),
            BrowserWindowModalDialogDelegate::From(auxiliary));
  static_cast<DevToolsUIBindings::Delegate*>(window)->SetIsDocked(true);
  pane_->Refresh(true);
}
}  // namespace parc
