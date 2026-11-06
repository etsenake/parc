// Copyright 2026 Parc contributors.
#import <AppKit/AppKit.h>

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/test/run_until.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/dialogs/browser_dialogs.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/test/base/in_process_browser_test.h"
#include "chrome/test/base/ui_test_utils.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/browser_test.h"
#include "folder_upload.h"
#include "ui/base/models/dialog_model.h"
#include "ui/views/bubble/bubble_dialog_model_host.h"
#include "ui/views/widget/widget.h"
#import "window_security_reservation.h"

namespace parc {
class CloseDuringBlock final
    : public web_modal::WebContentsModalDialogManagerDelegate {
 public:
  explicit CloseDuringBlock(web_modal::WebContentsModalDialogManager& manager)
      : manager_(manager), original_(manager.delegate()) {
    manager_.SetDelegate(this);
  }
  ~CloseDuringBlock() override { manager_.SetDelegate(original_); }
  void SetWebContentsBlocked(content::WebContents* contents,
                             bool blocked) override {
    original_->SetWebContentsBlocked(contents, blocked);
    if (blocked)
      manager_.CloseAllDialogs();
  }
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost(
      content::WebContents* contents) override {
    return original_->GetWebContentsModalDialogHost(contents);
  }
  bool IsWebContentsVisible(content::WebContents* contents) override {
    return original_->IsWebContentsVisible(contents);
  }

 private:
  web_modal::WebContentsModalDialogManager& manager_;
  raw_ptr<web_modal::WebContentsModalDialogManagerDelegate> original_;
};
class DetachBeforeInsertion final
    : public web_modal::WebContentsModalDialogManager::Observer {
 public:
  explicit DetachBeforeInsertion(content::WebContents& contents)
      : contents_(contents) {
    web_modal::WebContentsModalDialogManager::FromWebContents(&contents_)
        ->AddObserver(this);
  }
  ~DetachBeforeInsertion() override {
    web_modal::WebContentsModalDialogManager::FromWebContents(&contents_)
        ->RemoveObserver(this);
  }
  void OnWillShow() override {
    SetNativeFolderUploadAttached(contents_, false);
  }

 private:
  content::WebContents& contents_;
};
class NativeFolderUploadTest : public InProcessBrowserTest {
 protected:
  void SetUpOnMainThread() override {
    InProcessBrowserTest::SetUpOnMainThread();
    ASSERT_TRUE(ui_test_utils::NavigateToURL(browser(), GURL("about:blank")));
    contents_ = browser()->tab_strip_model()->GetActiveWebContents();
    window_ = contents_->GetTopLevelNativeWindow().GetNativeNSWindow();
    [window_ orderFront:nil];
    InstallNativeFolderUpload(*contents_);
    SetNativeFolderUploadAttached(*contents_, true);
  }
  void TearDownOnMainThread() override {
    SetNativeFolderUploadAttached(*contents_, false);
    base::RunLoop().RunUntilIdle();
    InProcessBrowserTest::TearDownOnMainThread();
  }
  void Open() {
    // This genuine DialogModel drives the production folder adapter. The
    // existing FileSelectHelperTest.ConfirmationDialog separately verifies
    // the actual enumerated-files/title/default/input-protection schema.
    chrome::ShowFolderUploadConfirmation(
        ui::DialogModel::Builder()
            .SetTitle(u"Upload test folder?")
            .AddParagraph(ui::DialogModelLabel(u"Two files"))
            .AddOkButton(base::BindOnce([](int* n) { ++*n; }, &accepted_))
            .AddCancelButton(base::BindOnce([](int* n) { ++*n; }, &cancelled_))
            .SetCloseActionCallback(
                base::BindOnce([](int* n) { ++*n; }, &closed_))
            .OverrideDefaultButton(ui::mojom::DialogButton::kCancel)
            .SetEnableInputProtection(true)
            .Build(),
        contents_, contents_->GetPrimaryMainFrame());
  }
  views::Widget* Dialog() {
    for (NSWindow* child in window_.childWindows) {
      if (auto* widget = views::Widget::GetWidgetForNativeWindow(
              gfx::NativeWindow(child))) {
        if (widget->widget_delegate()->AsDialogDelegate())
          return widget;
      }
    }
    return nullptr;
  }
  bool ModalActive() {
    return web_modal::WebContentsModalDialogManager::FromWebContents(contents_)
        ->IsDialogActive();
  }
  raw_ptr<content::WebContents> contents_ = nullptr;
  NSWindow* __weak window_;
  int accepted_ = 0, cancelled_ = 0, closed_ = 0;
};
IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest, RealModelAndWindowCancel) {
  Open();
  ASSERT_TRUE(base::test::RunUntil(
      [this] { return Dialog() && Dialog()->IsVisible(); }));
  auto* dialog = Dialog()->widget_delegate()->AsDialogDelegate();
  EXPECT_EQ(dialog->GetDefaultDialogButton(),
            static_cast<int>(ui::mojom::DialogButton::kCancel));
  EXPECT_FALSE(dialog->ShouldAllowKeyEventsDuringInputProtection());
  EXPECT_TRUE(ModalActive());
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
  dialog->CancelDialog();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(ModalActive());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest, ActualModelAcceptanceRunsOnce) {
  Open();
  ASSERT_TRUE(Dialog());
  Dialog()->widget_delegate()->AsDialogDelegate()->AcceptDialog();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(accepted_, 1);
  EXPECT_EQ(cancelled_, 0);
  EXPECT_FALSE(ModalActive());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest,
                       DetachReattachCannotReviveOldOK) {
  Open();
  ASSERT_TRUE(Dialog());
  auto widget = Dialog()->GetWeakPtr();
  SetNativeFolderUploadAttached(*contents_, false);
  SetNativeFolderUploadAttached(*contents_, true);
  // Acceptance before the deferred cancellation task must still use Cancel.
  ASSERT_TRUE(widget);
  widget->widget_delegate()->AsDialogDelegate()->AcceptDialog();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(accepted_, 0);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_FALSE(ModalActive());
}
IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest,
                       ExistingLeaseRefusesUnshownModel) {
  auto lease = [PCNativeWindowSecurityReservation acquireForWindow:window_];
  Open();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(accepted_, 0);
  EXPECT_EQ(closed_, 1);
  EXPECT_FALSE(ModalActive());
  EXPECT_TRUE(lease.active);
  [lease invalidate];
}
IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest,
                       ReleaseTimeCompetitionCancelsOK) {
  Open();
  ASSERT_TRUE(Dialog());
  __block PCNativeWindowSecurityReservation* competing = nil;
  NSWindow* parent = window_;
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:parent
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (!PCNativeWindowHasSecurityReservation(parent)) {
                  competing = [PCNativeWindowSecurityReservation
                      acquireForWindow:parent];
                }
              }];
  Dialog()->widget_delegate()->AsDialogDelegate()->AcceptDialog();
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(accepted_, 0);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_TRUE(competing.active);
  EXPECT_FALSE(ModalActive());
  [competing invalidate];
}
IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest,
                       ReleaseCallbackClosesOriginalModel) {
  Open();
  ASSERT_TRUE(Dialog());
  auto widget = Dialog()->GetWeakPtr();
  NSWindow* parent = window_;
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:parent
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (!PCNativeWindowHasSecurityReservation(parent) && widget &&
                    !widget->IsClosed()) {
                  widget->Close();
                }
              }];
  widget->widget_delegate()->AsDialogDelegate()->AcceptDialog();
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(accepted_, 0);
  EXPECT_EQ(cancelled_, 0);
  EXPECT_EQ(closed_, 1);
  EXPECT_FALSE(ModalActive());
}

IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest, PageNavigationRetiresDialog) {
  Open();
  ASSERT_TRUE(Dialog());
  ASSERT_TRUE(ui_test_utils::NavigateToURL(
      browser(), GURL("data:text/html,new document")));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(accepted_, 0);
  EXPECT_EQ(closed_, 1);
  EXPECT_FALSE(ModalActive());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest,
                       ManagerCloseAllDrainsSynchronously) {
  Open();
  ASSERT_TRUE(Dialog());
  auto* manager =
      web_modal::WebContentsModalDialogManager::FromWebContents(contents_);
  manager->CloseAllDialogs();
  EXPECT_FALSE(manager->IsDialogActive());
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(accepted_, 0);
  EXPECT_EQ(closed_, 1);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest,
                       ReentrantCloseDuringManagerRegistration) {
  CloseDuringBlock delegate(
      *web_modal::WebContentsModalDialogManager::FromWebContents(contents_));
  Open();
  EXPECT_FALSE(ModalActive());
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(accepted_, 0);
  EXPECT_EQ(closed_, 1);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeFolderUploadTest,
                       PreInsertionCancellationDoesNotLeaveEntry) {
  DetachBeforeInsertion observer(*contents_);
  Open();
  EXPECT_FALSE(ModalActive());
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(accepted_, 0);
  EXPECT_EQ(closed_, 1);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
}  // namespace parc
