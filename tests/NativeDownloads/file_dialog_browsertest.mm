// Copyright 2026 Parc contributors.
// Genuine Browser/TabInterface/native chooser tests. Source checks do not run
// these cases; final acceptance also needs the supplied Parc NSWindow route.
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
      // Spin a genuine nested loop while the platform FileWasSelected callback
      // is on stack and the external owner has released its wrapper reference.
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
}  // namespace parc

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
}  // namespace parc

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
}  // namespace parc

namespace parc {
IN_PROC_BROWSER_TEST_F(NativeFileDialogTest,
                       GenuineAuxiliaryContentsWithoutTabCancelOnce) {
  auto auxiliary = content::WebContents::Create(
      content::WebContents::CreateParams(browser()->GetProfile()));
  ASSERT_FALSE(tabs::TabInterface::MaybeGetFromContents(auxiliary.get()));
  // A retained CEF host can request a chooser after its actual tools contents
  // redock and cease to be a tab. No Browser/window owner may be fabricated.
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
}  // namespace parc
