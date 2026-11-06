// Copyright 2026 Parc contributors.
// Actual Browser, DevToolsWindow, AppModal queue/controller and native chooser.
// These source tests do not substitute a tab for the auxiliary WebContents.
#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "base/test/run_until.h"
#include "chrome/browser/devtools/devtools_ui_controller.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/devtools/devtools_window_testing.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/test/base/in_process_browser_test.h"
#include "components/javascript_dialogs/app_modal_dialog_controller.h"
#include "components/javascript_dialogs/app_modal_dialog_queue.h"
#include "components/javascript_dialogs/app_modal_dialog_view.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/browser_test.h"
#include "devtools_pane.h"
#include "file_dialog.h"
#include "native_auxiliary_page.h"
#include "native_auxiliary_services.h"
#import "page_host.h"
#include "ui/base/unowned_user_data/user_data_factory.h"
#include "ui/shell_dialogs/select_file_policy.h"
#include "ui/shell_dialogs/selected_file_info.h"
#import "window_security_reservation.h"

namespace parc {
class NativeAuxiliaryBrowserTest : public InProcessBrowserTest,
                                   public ui::SelectFileDialog::Listener {
 public:
  NativeAuxiliaryBrowserTest() {
    override_ = BrowserWindowFeatures::GetUserDataFactoryForTesting()
                    .AddOverrideForTesting(base::BindRepeating(
                        [](NativeAuxiliaryBrowserTest* fixture,
                           BrowserWindowInterface& owner) {
                          return std::make_unique<DevtoolsUIController>(
                              &owner, std::make_unique<Delegate>(*fixture));
                        },
                        base::Unretained(this)));
  }

 protected:
  class Delegate final : public DevtoolsUIController::NativeDelegate {
   public:
    explicit Delegate(NativeAuxiliaryBrowserTest& fixture)
        : fixture_(fixture) {}
    bool Update(content::WebContents* contents, bool replace) override {
      return !fixture_.hold_native_update_ && fixture_.pane_ &&
             fixture_.inspected_ == contents &&
             fixture_.pane_->Refresh(replace);
    }
    void SetScrim(content::WebContents* contents, bool visible) override {
      if (fixture_.pane_ && fixture_.pane_->tools() == contents) {
        fixture_.pane_->SetBlocked(visible);
      }
    }
    void TearDown() override {
      if (fixture_.pane_) {
        fixture_.pane_->Detach();
      }
    }

   private:
    NativeAuxiliaryBrowserTest& fixture_;
  };
  void SetUpOnMainThread() override {
    InProcessBrowserTest::SetUpOnMainThread();
    inspected_ = browser()->GetTabStripModel()->GetActiveWebContents();
    ASSERT_TRUE(inspected_);
    original_ = inspected_->GetNativeView().GetNativeNSView();
    original_parent_ = original_.superview;
    original_frame_ = original_.frame;
    // Unlike containment-only tests, this is the real Browser's native window.
    window_ = browser()->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    ASSERT_TRUE(window_);
    [window_ orderFront:nil];
    page_ = [PCNativePageHost hostWithContentView:original_ observer:nil];
    pane_ = NativeDevToolsPane::Create(*inspected_, page_);
    pane_->view().frame = window_.contentView.bounds;
    [window_.contentView addSubview:pane_->view()];
  }
  void TearDownOnMainThread() override {
    if (reservation_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:reservation_observer_];
      reservation_observer_ = nil;
    }
    [competing_ invalidate];
    competing_ = nil;
    if (chooser_) {
      chooser_->ListenerDestroyed();
    }
    chooser_.reset();
    // Actual cancellation precedes fixture-owned result storage destruction.
    if (lease_) {
      lease_->Revoke();
    }
    if (pane_) {
      pane_->Detach();
    }
    if (inspected_) {
      if (auto* tools =
              DevToolsWindow::GetInstanceForInspectedWebContents(inspected_)) {
        DevToolsWindowTesting::CloseDevToolsWindowSync(tools);
      }
    }
    if (pane_) {
      [pane_->view() removeFromSuperview];
    }
    pane_.reset();
    lease_.reset();
    replacement_.reset();
    [original_ removeFromSuperview];
    [original_parent_ addSubview:original_];
    original_.frame = original_frame_;
    base::RunLoop().RunUntilIdle();
    inspected_ = nullptr;
    tools_ = nullptr;
    InProcessBrowserTest::TearDownOnMainThread();
  }
  void Open() {
    ASSERT_FALSE(javascript_dialogs::AppModalDialogQueue::GetInstance()
                     ->HasActiveDialog());
    auto* window =
        DevToolsWindowTesting::OpenDevToolsWindowSync(inspected_, true);
    ASSERT_TRUE(window);
    tools_ = window->GetDevToolsWebContents().get();
    pane_->Refresh(true);
    ASSERT_EQ(pane_->tools(), tools_);
    lease_ = GetNativeAuxiliaryPage(*tools_);
    ASSERT_TRUE(lease_);
    ASSERT_TRUE(lease_->IsValid());
    ASSERT_EQ(lease_->window(), window_);
    ASSERT_FALSE(tabs::TabInterface::MaybeGetFromContents(tools_));
  }
  std::unique_ptr<javascript_dialogs::AppModalDialogController> Model(
      content::JavaScriptDialogType type =
          content::JAVASCRIPT_DIALOG_TYPE_CONFIRM) {
    extra_data_[tools_];
    return std::make_unique<javascript_dialogs::AppModalDialogController>(
        tools_, &extra_data_, u"Developer Tools", type, u"Actual model message",
        u"default response", true, false, false,
        base::BindOnce(
            [](NativeAuxiliaryBrowserTest* self, bool accepted,
               const std::u16string& text) {
              ++self->dialog_results_;
              self->decisions_.push_back(accepted);
              self->last_accept_ = accepted;
              self->last_text_ = text;
              if (self->reopen_on_result_) {
                self->reopen_on_result_ = false;
                self->hold_native_update_ = false;
                auto* replacement =
                    DevToolsWindowTesting::OpenDevToolsWindowSync(
                        self->inspected_, true);
                EXPECT_TRUE(replacement);
                if (replacement) {
                  self->tools_ = replacement->GetDevToolsWebContents().get();
                  self->pane_->Refresh(true);
                  self->replacement_ = GetNativeAuxiliaryPage(*self->tools_);
                }
              }
              if (self->rebind_on_result_) {
                self->rebind_on_result_ = false;
                self->replacement_ = NativeAuxiliaryPage::BindDevTools(
                    *self->inspected_, *self->tools_,
                    self->pane_->view().toolsView, self->pane_->view());
              }
            },
            base::Unretained(this)));
  }
  void Add(
      std::unique_ptr<javascript_dialogs::AppModalDialogController> model) {
    javascript_dialogs::AppModalDialogQueue::GetInstance()->AddDialog(
        std::move(model));
  }
  void CreateChooser() {
    chooser_ = CreateNativeFileDialog(*tools_, this, nullptr);
    chooser_->SelectFile(ui::SelectFileDialog::SELECT_OPEN_FILE,
                         u"Tools chooser", base::FilePath(), nullptr, 0,
                         FILE_PATH_LITERAL(""), gfx::NativeWindow(window_),
                         nullptr);
  }
  void FileSelected(const ui::SelectedFileInfo&, int) override {
    ++file_accepts_;
  }
  void FileSelectionCanceled() override { ++file_cancels_; }
  raw_ptr<content::WebContents> inspected_ = nullptr;
  raw_ptr<content::WebContents> tools_ = nullptr;
  NSWindow* __weak window_;
  NSView* __strong original_;
  NSView* __strong original_parent_;
  NSRect original_frame_;
  PCNativePageHost* __strong page_;
  std::shared_ptr<NativeDevToolsPane> pane_;
  std::shared_ptr<NativeAuxiliaryPage> lease_, replacement_;
  scoped_refptr<ui::SelectFileDialog> chooser_;
  id __strong reservation_observer_;
  PCNativeWindowSecurityReservation* __strong competing_;
  bool reserve_on_release_ = false;
  bool rebind_on_result_ = false;
  bool reopen_on_result_ = false, hold_native_update_ = false;
  std::vector<bool> decisions_;
  javascript_dialogs::AppModalDialogController::ExtraDataMap extra_data_;
  int dialog_results_ = 0, file_cancels_ = 0, file_accepts_ = 0;
  bool last_accept_ = false;
  std::u16string last_text_;
  ui::UserDataFactory::ScopedOverride override_;
};

IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       ExactEngineIdentityAndWindowRequired) {
  Open();
  ASSERT_TRUE(lease_);
  EXPECT_EQ(lease_->browser(), browser());
  EXPECT_TRUE(lease_->IsActive());
  auto unrelated = content::WebContents::Create(
      content::WebContents::CreateParams(inspected_->GetBrowserContext()));
  EXPECT_FALSE(NativeAuxiliaryPage::BindDevTools(
      *inspected_, *unrelated, unrelated->GetNativeView().GetNativeNSView(),
      pane_->view()));
  NSView* foreign = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
  EXPECT_FALSE(NativeAuxiliaryPage::BindDevTools(
      *inspected_, *tools_, pane_->view().toolsView, foreign));
  EXPECT_TRUE(lease_->IsValid());
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       ReentrantRebindCannotReviveOldLease) {
  Open();
  ASSERT_TRUE(lease_);
  auto subscription = lease_->OnInvalidated(base::BindLambdaForTesting([this] {
    replacement_ = NativeAuxiliaryPage::BindDevTools(
        *inspected_, *tools_, pane_->view().toolsView, pane_->view());
  }));
  auto attempted = NativeAuxiliaryPage::BindDevTools(
      *inspected_, *tools_, pane_->view().toolsView, pane_->view());
  EXPECT_FALSE(attempted);
  ASSERT_TRUE(replacement_);
  EXPECT_FALSE(lease_->IsValid());
  lease_->Revoke();
  EXPECT_EQ(GetNativeAuxiliaryPage(*tools_), replacement_);
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       RealAppModalUsesDefaultPromptAndSuppression) {
  Open();
  ASSERT_TRUE(lease_);
  Add(Model(content::JAVASCRIPT_DIALOG_TYPE_PROMPT));
  auto* active =
      javascript_dialogs::AppModalDialogQueue::GetInstance()->active_dialog();
  ASSERT_TRUE(active);
  ASSERT_TRUE(window_.attachedSheet);
  for (NSView* child in window_.attachedSheet.contentView.subviews) {
    if ([child isKindOfClass:NSButton.class] &&
        [[(NSButton*)child title] hasPrefix:@"Prevent this page"]) {
      [(NSButton*)child setState:NSControlStateValueOn];
    }
  }
  active->view()->AcceptAppModalDialog();
  EXPECT_EQ(dialog_results_, 1);
  EXPECT_TRUE(last_accept_);
  EXPECT_EQ(last_text_, u"default response");
  EXPECT_TRUE(extra_data_[tools_].suppress_javascript_messages_);
  EXPECT_FALSE(javascript_dialogs::AppModalDialogQueue::GetInstance()
                   ->HasActiveDialog());
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       QueuedModelRetainsOriginalLease) {
  Open();
  ASSERT_TRUE(lease_);
  Add(Model());
  Add(Model());  // Actual queued controller captures the old owner.
  ASSERT_NE(javascript_dialogs::AppModalDialogQueue::GetInstance()->begin(),
            javascript_dialogs::AppModalDialogQueue::GetInstance()->end());
  rebind_on_result_ = true;
  lease_
      ->Revoke();  // First result rebinds before the queue shows its next item.
  ASSERT_TRUE(replacement_);
  EXPECT_EQ(dialog_results_, 2);
  EXPECT_FALSE(last_accept_);
  EXPECT_FALSE(window_.attachedSheet);
  Add(Model());
  auto* active =
      javascript_dialogs::AppModalDialogQueue::GetInstance()->active_dialog();
  ASSERT_TRUE(active);
  active->view()->CancelAppModalDialog();
  EXPECT_EQ(dialog_results_, 3);
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       PaneDetachCancelsActualDialogBeforeMove) {
  Open();
  ASSERT_TRUE(lease_);
  Add(Model());
  ASSERT_TRUE(window_.attachedSheet);
  pane_->Detach();
  EXPECT_FALSE(lease_->IsValid());
  EXPECT_EQ(dialog_results_, 1);
  EXPECT_FALSE(last_accept_);
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(javascript_dialogs::AppModalDialogQueue::GetInstance()
                   ->HasActiveDialog());
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       ActualChooserCancelsCapturedLease) {
  Open();
  ASSERT_TRUE(lease_);
  CreateChooser();
  ASSERT_TRUE(
      base::test::RunUntil([&] { return window_.attachedSheet != nil; }));
  lease_->Revoke();
  ASSERT_TRUE(base::test::RunUntil([&] { return file_cancels_ == 1; }));
  EXPECT_EQ(file_accepts_, 0);
  EXPECT_FALSE(window_.attachedSheet);
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       UnboundRoutedToolsNeverChooseCurrentWindow) {
  Open();
  ASSERT_TRUE(lease_);
  pane_->Detach();
  EXPECT_TRUE(HasNativeAuxiliaryRoute(*tools_));
  EXPECT_FALSE(GetNativeAuxiliaryPage(*tools_));
  CreateChooser();
  ASSERT_TRUE(base::test::RunUntil([&] { return file_cancels_ == 1; }));
  EXPECT_FALSE(window_.attachedSheet);
  Add(Model());
  EXPECT_EQ(dialog_results_, 1);
  EXPECT_FALSE(last_accept_);
  EXPECT_FALSE(window_.attachedSheet);
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       ReleaseTimeReservationCannotAcceptOrSuppress) {
  Open();
  ASSERT_TRUE(lease_);
  Add(Model(content::JAVASCRIPT_DIALOG_TYPE_PROMPT));
  auto* active =
      javascript_dialogs::AppModalDialogQueue::GetInstance()->active_dialog();
  ASSERT_TRUE(active);
  ASSERT_TRUE(window_.attachedSheet);
  for (NSView* child in window_.attachedSheet.contentView.subviews) {
    if ([child isKindOfClass:NSButton.class] &&
        [[(NSButton*)child title] hasPrefix:@"Prevent this page"]) {
      [(NSButton*)child setState:NSControlStateValueOn];
    }
  }
  reserve_on_release_ = true;
  reservation_observer_ = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (reserve_on_release_ &&
                    !PCNativeWindowHasSecurityReservation(window_)) {
                  reserve_on_release_ = false;
                  competing_ = [PCNativeWindowSecurityReservation
                      acquireForWindow:window_];
                }
              }];
  active->view()->AcceptAppModalDialog();
  EXPECT_EQ(dialog_results_, 1);
  EXPECT_FALSE(last_accept_);
  EXPECT_FALSE(extra_data_[tools_].suppress_javascript_messages_);
  EXPECT_TRUE(competing_.active);
  EXPECT_FALSE(window_.attachedSheet);
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       RealAppModalActivationSelectsInspectedTab) {
  Open();
  ASSERT_TRUE(lease_);
  AddBlankTabAndShow(browser());
  ASSERT_TRUE(lease_->IsValid());
  ASSERT_FALSE(lease_->IsActive());
  Add(Model());
  auto* active =
      javascript_dialogs::AppModalDialogQueue::GetInstance()->active_dialog();
  ASSERT_TRUE(active);
  EXPECT_EQ(browser()->GetTabStripModel()->GetActiveWebContents(), inspected_);
  EXPECT_TRUE(lease_->IsActive());
  active->view()->CancelAppModalDialog();
  EXPECT_EQ(dialog_results_, 1);
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       QueueAdvancementCannotAuthorizeRevokedLease) {
  Open();
  ASSERT_TRUE(lease_);
  Add(Model(content::JAVASCRIPT_DIALOG_TYPE_PROMPT));
  auto* first =
      javascript_dialogs::AppModalDialogQueue::GetInstance()->active_dialog();
  ASSERT_TRUE(first);
  Add(Model());
  reserve_on_release_ = true;
  reservation_observer_ = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                // The next real queue item's acquisition runs inside
                // first->OnAccept, after the first view's final validation,
                // before its real callback.
                if (reserve_on_release_ &&
                    PCNativeWindowHasSecurityReservation(window_)) {
                  reserve_on_release_ = false;
                  lease_->Revoke();
                }
              }];
  first->view()->AcceptAppModalDialog();
  EXPECT_EQ(dialog_results_, 2);
  EXPECT_EQ(decisions_, (std::vector<bool>{false, false}));
  EXPECT_FALSE(extra_data_[tools_].suppress_javascript_messages_);
  EXPECT_FALSE(window_.attachedSheet);
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       DetachCallbackCanReleaseLastPaneOwner) {
  Open();
  ASSERT_TRUE(lease_);
  std::weak_ptr<NativeDevToolsPane> weak = pane_;
  NSView* retained_view = pane_->view();
  auto subscription = lease_->OnInvalidated(
      base::BindLambdaForTesting([this] { pane_.reset(); }));
  pane_->Detach();
  EXPECT_TRUE(weak.expired());
  EXPECT_FALSE(lease_->IsValid());
  [retained_view removeFromSuperview];
}
IN_PROC_BROWSER_TEST_F(NativeAuxiliaryBrowserTest,
                       OldToolsDestructionCannotClearReentrantFrontend) {
  Open();
  ASSERT_TRUE(lease_);
  auto old_contents = tools_->GetWeakPtr();
  Add(Model());
  // Delay only the presentation notification, leaving genuine engine teardown
  // and its WebContents observer path intact. The result callback opens the
  // real replacement frontend while old ToolsDestroyed is still on stack.
  hold_native_update_ = true;
  reopen_on_result_ = true;
  DevToolsWindowTesting::CloseDevToolsWindowSync(
      DevToolsWindow::GetInstanceForInspectedWebContents(inspected_));
  ASSERT_TRUE(
      base::test::RunUntil([&] { return !old_contents && replacement_; }));
  ASSERT_TRUE(pane_);
  EXPECT_EQ(dialog_results_, 1);
  EXPECT_TRUE(replacement_->IsValid());
  EXPECT_EQ(pane_->tools(), tools_);
  EXPECT_EQ(pane_->view().toolsView.superview, pane_->view());
}
}  // namespace parc
