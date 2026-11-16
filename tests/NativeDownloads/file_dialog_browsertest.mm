// Copyright 2026 Parc contributors.
#include "parc/native/file_dialog.h"

#import <AppKit/AppKit.h>

#include "base/run_loop.h"
#include "base/task/single_thread_task_runner.h"
#include "base/test/run_until.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/test/base/in_process_browser_test.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/browser_test.h"
#include "content/public/test/browser_test_utils.h"
#include "native_auxiliary_page.h"
#import "page_host.h"
#include "ui/base/base_window.h"
#include "ui/shell_dialogs/select_file_policy.h"
#include "ui/shell_dialogs/selected_file_info.h"
#import "window_security_reservation.h"

namespace parc {
class DenyPolicy final : public ui::SelectFilePolicy {
 public:
  bool CanOpenSelectFileDialog() override { return false; }
  void SelectFileDenied() override {}
};
class NativeFileDialogTest : public InProcessBrowserTest,
                             public ui::SelectFileDialog::Listener {
 protected:
  void SetUpOnMainThread() override {
    InProcessBrowserTest::SetUpOnMainThread();
    contents_ =
        TabListInterface::From(browser())->GetActiveTab()->GetContents();
    window_ = browser()->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    [window_ orderFront:nil];
    ASSERT_EQ(contents_->GetNativeView().GetNativeNSView().window, window_);
  }
  void TearDownOnMainThread() override {
    if (dialog_) {
      dialog_->ListenerDestroyed();
    }
    dialog_.reset();
    base::RunLoop().RunUntilIdle();
    InProcessBrowserTest::TearDownOnMainThread();
  }
  void Create() { dialog_ = CreateNativeFileDialog(*contents_, this, nullptr); }
  void Open(NSWindow* window) {
    ui::SelectFileDialog::FileTypeInfo types;
    types.extensions = {{FILE_PATH_LITERAL("txt")},
                        {FILE_PATH_LITERAL("json")}};
    dialog_->SelectFile(ui::SelectFileDialog::SELECT_OPEN_MULTI_FILE,
                        u"Parc ownership test", base::FilePath(), &types, 1,
                        FILE_PATH_LITERAL("txt"), gfx::NativeWindow(window),
                        nullptr);
  }
  void FileSelected(const ui::SelectedFileInfo&, int) override { ++accepted_; }
  void MultiFilesSelected(const std::vector<ui::SelectedFileInfo>&) override {
    ++accepted_;
  }
  void FileSelectionCanceled() override {
    ++cancelled_;
    if (nested_callback_) {
      nested_callback_ = false;
      dialog_.reset();
      base::RunLoop nested(base::RunLoop::Type::kNestableTasksAllowed);
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, nested.QuitClosure());
      nested.Run();
      nested_returned_ = true;
      EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
      CancelNativeFileDialogs(*contents_);
      EXPECT_EQ(cancelled_, 1);
    }
    if (reenter_) {
      reenter_ = false;
      CancelNativeFileDialogs(*contents_);
      dialog_->ListenerDestroyed();
      dialog_.reset();
    }
  }
  raw_ptr<content::WebContents> contents_ = nullptr;
  NSWindow* __weak window_;
  scoped_refptr<ui::SelectFileDialog> dialog_;
  int cancelled_ = 0, accepted_ = 0;
  bool reenter_ = false;
  bool nested_callback_ = false;
  bool nested_returned_ = false;
};

IN_PROC_BROWSER_TEST_F(NativeFileDialogTest, ForeignWindowIsNotAChooserOwner) {
  Create();
  NSWindow* other =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                  styleMask:NSWindowStyleMaskTitled
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  [other orderFront:nil];
  Open(other);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(dialog_->IsRunning(gfx::NativeWindow(other)));
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(other));
  [other close];
}
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       ExistingSecurityReservationCancelsOnce) {
  auto reservation =
      [PCNativeWindowSecurityReservation acquireForWindow:window_];
  ASSERT_TRUE(reservation.active);
  Create();
  Open(window_);
  CancelNativeFileDialogs(*contents_);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_TRUE(reservation.active);
  [reservation invalidate];
}
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       RealNativePanelCancelledOnPageDetach) {
  Create();
  Open(window_);
  ASSERT_TRUE(dialog_->IsRunning(gfx::NativeWindow(window_)));
  ASSERT_TRUE(
      base::test::RunUntil([this] { return window_.attachedSheet != nil; }));
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
  EXPECT_TRUE(dialog_->HasMultipleFileTypeChoices());
  CancelNativeFileDialogs(*contents_);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  ASSERT_TRUE(
      base::test::RunUntil([this] { return window_.attachedSheet == nil; }));
  CancelNativeFileDialogs(*contents_);
  EXPECT_EQ(cancelled_, 1);
}
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       ListenerTeardownDoesNotCallDeadOwner) {
  Create();
  Open(window_);
  ASSERT_TRUE(dialog_->IsRunning(gfx::NativeWindow(window_)));
  dialog_->ListenerDestroyed();
  CancelNativeFileDialogs(*contents_);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(cancelled_, 0);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       CancellationCanReleaseFinalOwnerAndReenter) {
  Create();
  Open(window_);
  reenter_ = true;
  CancelNativeFileDialogs(*contents_);
  EXPECT_FALSE(dialog_);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
}

namespace parc {
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       PolicyRefusalAndDetachDeliverOnlyOnce) {
  dialog_ =
      CreateNativeFileDialog(*contents_, this, std::make_unique<DenyPolicy>());
  Open(window_);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(cancelled_, 1);
  CancelNativeFileDialogs(*contents_);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       DetachBeforeQueuedPolicyRefusalDeliversOnlyOnce) {
  dialog_ =
      CreateNativeFileDialog(*contents_, this, std::make_unique<DenyPolicy>());
  Open(window_);
  CancelNativeFileDialogs(*contents_);
  EXPECT_EQ(cancelled_, 1);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
}
}

namespace parc {
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       AcquisitionReentryRejectsCompetingLease) {
  __block PCNativeWindowSecurityReservation* competing = nil;
  __block bool acquire_again = true;
  NSWindow* parent = window_;
  id token = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:parent
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (acquire_again) {
                  acquire_again = false;
                  competing = [PCNativeWindowSecurityReservation
                      acquireForWindow:parent];
                }
              }];
  Create();
  Open(parent);
  [NSNotificationCenter.defaultCenter removeObserver:token];
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(dialog_->IsRunning(gfx::NativeWindow(parent)));
  EXPECT_EQ(parent.attachedSheet, nil);
  EXPECT_TRUE(competing.isOnlyReservation);
  [competing invalidate];
}
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       PresentedChooserCancelsForSameWindowLeaseOnly) {
  Create();
  Open(window_);
  ASSERT_TRUE(
      base::test::RunUntil([this] { return window_.attachedSheet != nil; }));
  NSWindow* other =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                  styleMask:NSWindowStyleMaskTitled
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  auto unrelated = [PCNativeWindowSecurityReservation acquireForWindow:other];
  EXPECT_TRUE(dialog_->IsRunning(gfx::NativeWindow(window_)));
  EXPECT_EQ(cancelled_, 0);
  auto competing = [PCNativeWindowSecurityReservation acquireForWindow:window_];
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(dialog_->IsRunning(gfx::NativeWindow(window_)));
  EXPECT_TRUE(competing.isOnlyReservation);
  ASSERT_TRUE(
      base::test::RunUntil([this] { return window_.attachedSheet == nil; }));
  EXPECT_TRUE(unrelated.active);
  [competing invalidate];
  [unrelated invalidate];
  [other close];
}
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       NativeCompletionCanRunNestedLoopAndReleaseOwner) {
  Create();
  Open(window_);
  ASSERT_TRUE(
      base::test::RunUntil([this] { return window_.attachedSheet != nil; }));
  ASSERT_TRUE([window_.attachedSheet isKindOfClass:NSSavePanel.class]);
  nested_callback_ = true;
  [(NSSavePanel*)window_.attachedSheet cancel:nil];
  ASSERT_TRUE(base::test::RunUntil([this] { return nested_returned_; }));
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(dialog_);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
}

namespace parc {
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       GenuineAuxiliaryContentsWithoutTabCancelOnce) {
  auto auxiliary = content::WebContents::Create(
      content::WebContents::CreateParams(browser()->GetProfile()));
  ASSERT_FALSE(tabs::TabInterface::MaybeGetFromContents(auxiliary.get()));
  dialog_ = CreateNativeFileDialog(*auxiliary, this, nullptr);
  Open(window_);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(dialog_->IsRunning(gfx::NativeWindow(window_)));
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  EXPECT_EQ(window_.attachedSheet, nil);
  CancelNativeFileDialogs(*auxiliary);
  auxiliary.reset();
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
}
}

namespace parc {
class NativeExtensionFileDialogTest : public NativeFileDialogTest {
 protected:
  void SetUpOnMainThread() override {
    NativeFileDialogTest::SetUpOnMainThread();
    extension_ = content::WebContents::Create(
        content::WebContents::CreateParams(browser()->GetProfile()));
    ASSERT_TRUE(content::NavigateToURL(extension_.get(), GURL("about:blank")));
    page_ = [PCNativePageHost
        hostWithContentView:extension_->GetNativeView().GetNativeNSView()
                   observer:nil];
  }
  void TearDownOnMainThread() override {
    if (dialog_) {
      dialog_->ListenerDestroyed();
    }
    dialog_.reset();
    CancelNativeFileDialogs(*extension_);
    if (lease_) {
      lease_->Revoke();
    }
    lease_.reset();
    base::RunLoop().RunUntilIdle();
    [page_ invalidate];
    page_ = nil;
    if (popup_) {
      [window_ removeChildWindow:popup_];
      [popup_ close];
      popup_ = nil;
    }
    extension_.reset();
    NativeFileDialogTest::TearDownOnMainThread();
  }
  NSWindow* Host(bool popup) {
    NSWindow* page_window = window_;
    if (popup) {
      popup_ = [[NSWindow alloc]
          initWithContentRect:NSMakeRect(200, 200, 320, 240)
                    styleMask:NSWindowStyleMaskTitled
                      backing:NSBackingStoreBuffered
                        defer:NO];
      popup_.releasedWhenClosed = NO;
      popup_.contentView = page_;
      [window_ addChildWindow:popup_ ordered:NSWindowAbove];
      [popup_ orderFront:nil];
      page_window = popup_;
    } else {
      page_.frame = NSMakeRect(0, 0, 320, 240);
      [window_.contentView addSubview:page_];
    }
    extension_->WasShown();
    lease_ = NativeExtensionPage::Bind(
        *extension_, page_, window_,
        base::BindRepeating([](bool* valid) { return *valid; }, &owner_valid_));
    EXPECT_TRUE(lease_);
    EXPECT_EQ(lease_ ? lease_->window() : nil, page_window);
    return page_window;
  }
  void CreateForExtension() {
    dialog_ = CreateNativeFileDialog(*extension_, this, nullptr);
  }
  std::unique_ptr<content::WebContents> extension_;
  std::shared_ptr<NativeExtensionPage> lease_;
  PCNativePageHost* __strong page_ = nil;
  NSWindow* __strong popup_ = nil;
  bool owner_valid_ = true;
};
IN_PROC_BROWSER_TEST_F(NativeExtensionFileDialogTest,
                       PopupChooserIsSheetOnPopupWindow) {
  NSWindow* popup = Host(true);
  CreateForExtension();
  Open(popup);
  ASSERT_TRUE(dialog_->IsRunning(gfx::NativeWindow(popup)));
  ASSERT_TRUE(
      base::test::RunUntil([popup] { return popup.attachedSheet != nil; }));
  EXPECT_EQ(window_.attachedSheet, nil);
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(popup));
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  CancelNativeFileDialogs(*extension_);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(popup));
  ASSERT_TRUE(
      base::test::RunUntil([popup] { return popup.attachedSheet == nil; }));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionFileDialogTest,
                       PopupChooserRefusesBrowserWindowParent) {
  Host(true);
  CreateForExtension();
  Open(window_);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(dialog_->IsRunning(gfx::NativeWindow(window_)));
  EXPECT_EQ(window_.attachedSheet, nil);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionFileDialogTest,
                       SidePanelChooserIsSheetOnBrowserWindow) {
  Host(false);
  CreateForExtension();
  Open(window_);
  ASSERT_TRUE(dialog_->IsRunning(gfx::NativeWindow(window_)));
  ASSERT_TRUE(
      base::test::RunUntil([this] { return window_.attachedSheet != nil; }));
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
  CancelNativeFileDialogs(*extension_);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  ASSERT_TRUE(
      base::test::RunUntil([this] { return window_.attachedSheet == nil; }));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionFileDialogTest,
                       RevokedPopupLeaseCancelsPresentedChooser) {
  NSWindow* popup = Host(true);
  CreateForExtension();
  Open(popup);
  ASSERT_TRUE(
      base::test::RunUntil([popup] { return popup.attachedSheet != nil; }));
  lease_->Revoke();
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_FALSE(dialog_->IsRunning(gfx::NativeWindow(popup)));
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(popup));
  ASSERT_TRUE(
      base::test::RunUntil([popup] { return popup.attachedSheet == nil; }));
}
IN_PROC_BROWSER_TEST_F(NativeExtensionFileDialogTest,
                       StaleSidePanelOwnerRefusesChooser) {
  Host(false);
  owner_valid_ = false;
  CreateForExtension();
  Open(window_);
  EXPECT_EQ(cancelled_, 1);
  EXPECT_EQ(accepted_, 0);
  EXPECT_EQ(window_.attachedSheet, nil);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
}
