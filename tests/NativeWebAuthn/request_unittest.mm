#import <AppKit/AppKit.h>

#include <memory>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/run_loop.h"
#include "browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/webauthn/authenticator_request_dialog_view.h"
#include "chrome/browser/webauthn/authenticator_request_dialog_model.h"
#include "chrome/browser/webauthn/authenticator_request_scheduler.h"
#include "chrome/browser/webauthn/chrome_authenticator_request_delegate.h"
#include "chrome/browser/webauthn/native_authenticator_request_context.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/navigation_simulator.h"
#include "parc/tests/parc_native_test_support/browser_window_test.h"
#include "ui/views/widget/widget.h"
#include "webauthn.h"
#import "window_security_reservation.h"
namespace parc {
namespace {
class Window final : public TestBrowserWindow {
 public:
  explicit Window(NSWindow* window) : window_(window) {}
  gfx::NativeWindow GetNativeWindow() const override {
    return gfx::NativeWindow(window_);
  }

 private:
  __weak NSWindow* window_;
};
class ModalDelegate final
    : public web_modal::WebContentsModalDialogManagerDelegate,
      public NativeModalDialogHostDelegate {
 public:
  ModalDelegate() : host(*this) {}
  gfx::NativeView GetActivePageHostView() const override {
    return gfx::NativeView(page);
  }
  gfx::Size GetBrowserWindowSize() const override {
    return gfx::Size(640, 480);
  }
  gfx::Size GetContentsSize() const override { return gfx::Size(640, 480); }
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost(
      content::WebContents*) override {
    return &host;
  }
  void SetWebContentsBlocked(content::WebContents*, bool value) override {
    blocked = value;
  }
  bool IsWebContentsVisible(content::WebContents*) override { return true; }
  __weak NSView* page;
  bool blocked = false;
  NativeModalDialogHost host;
};
void Pump() {
  for (int i = 0; i < 6; ++i) {
    base::RunLoop().RunUntilIdle();
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, .01, true);
  }
}
}
class NativeWebAuthnTest : public ParcBrowserWindowTest {
 public:
  void SetUp() override {
    ParcBrowserWindowTest::SetUp();
    AddTab(browser(), GURL("https://webauthn.example/auth"));
    auto* page = contents()->GetNativeView().GetNativeNSView();
    ASSERT_TRUE(page);
    page.frame = window_.contentView.bounds;
    [window_.contentView addSubview:page];
    modal_.page = page;
    contents()->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
    web_modal::WebContentsModalDialogManager::CreateForWebContents(contents());
    manager()->SetDelegate(&modal_);
    InstallNativeWebAuthn(*contents());
    SetNativeWebAuthnAttached(*contents(), true);
  }
  void TearDown() override {
    if (contents()) {
      SetNativeWebAuthnAttached(*contents(), false);
    }
    request_.reset();
    Pump();
    browser()->GetTabStripModel()->CloseAllTabs();
    Pump();
    modal_.host.Invalidate();
    ParcBrowserWindowTest::TearDown();
    [window_ close];
    window_ = nil;
  }

 protected:
  std::unique_ptr<BrowserWindow> CreateBrowserWindow() override {
    window_ = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(-2300, -2300, 640, 480)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window_.releasedWhenClosed = NO;
    [window_ orderFront:nil];
    return std::make_unique<Window>(window_);
  }
  content::WebContents* contents() {
    return browser()->GetTabStripModel()->GetActiveWebContents();
  }
  web_modal::WebContentsModalDialogManager* manager() {
    return web_modal::WebContentsModalDialogManager::FromWebContents(
        contents());
  }
  void Create(bool ready = true) {
    request_ = CreateWebAuthenticationRequestDelegate(
        contents()->GetPrimaryMainFrame());
    ASSERT_TRUE(request_);
    request_->SetRelyingPartyId("webauthn.example");
    if (ready) {
      Ready();
    }
  }
  void Ready() {
    request_->RegisterActionCallbacks(base::BindOnce(
                                          [](NativeWebAuthnTest* self) {
                                            ++self->cancelled_;
                                            self->request_.reset();
                                          },
                                          this),
                                      base::DoNothing(), base::DoNothing(),
                                      base::DoNothing(), base::DoNothing(),
                                      base::DoNothing(), base::DoNothing(),
                                      base::DoNothing(), base::DoNothing());
  }
  void Show() {
    request_->dialog_model()->SetStep(
        AuthenticatorRequestDialogModel::Step::kErrorNoAvailableTransports);
  }
  AuthenticatorRequestDialogView* view() {
    if (window_.childWindows.count != 1) {
      return nullptr;
    }
    auto* widget = views::Widget::GetWidgetForNativeWindow(
        gfx::NativeWindow(window_.childWindows.firstObject));
    return widget ? static_cast<AuthenticatorRequestDialogView*>(
                        widget->widget_delegate()->AsDialogDelegate())
                  : nullptr;
  }
  NSWindow* window_;
  ModalDelegate modal_;
  std::unique_ptr<ChromeAuthenticatorRequestDelegate> request_;
  int cancelled_ = 0;
};
TEST_F(NativeWebAuthnTest, RealDialogIsOwnedByExactNativePage) {
  Create();
  Show();
  Pump();
  ASSERT_TRUE(view());
  EXPECT_TRUE(window_.childWindows.firstObject.visible);
  EXPECT_TRUE(manager()->IsDialogActive());
  EXPECT_TRUE(modal_.blocked);
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
  EXPECT_EQ(0, cancelled_);
}
TEST_F(NativeWebAuthnTest, CancelUsesRealRequestCallbackOnce) {
  Create();
  Show();
  Pump();
  ASSERT_TRUE(view());
  view()->CancelDialog();
  Pump();
  EXPECT_EQ(1, cancelled_);
  EXPECT_FALSE(request_);
  EXPECT_FALSE(manager()->IsDialogActive());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
TEST_F(NativeWebAuthnTest, NativeDetachIsTerminalEvenAfterReattach) {
  Create();
  Show();
  SetNativeWebAuthnAttached(*contents(), false);
  SetNativeWebAuthnAttached(*contents(), true);
  Pump();
  EXPECT_EQ(1, cancelled_);
  EXPECT_FALSE(request_);
  EXPECT_FALSE(manager()->IsDialogActive());
  Create();
  Show();
  Pump();
  EXPECT_TRUE(view());
}
TEST_F(NativeWebAuthnTest, DetachBeforeCallbacksCancelsAfterRegistration) {
  Create(false);
  SetNativeWebAuthnAttached(*contents(), false);
  SetNativeWebAuthnAttached(*contents(), true);
  Ready();
  EXPECT_TRUE(request_);
  Pump();
  EXPECT_EQ(1, cancelled_);
  EXPECT_FALSE(request_);
}
TEST_F(NativeWebAuthnTest, RealSchedulerRejectsSecondRequest) {
  Create();
  EXPECT_FALSE(AuthenticatorRequestScheduler::CreateRequestDelegate(
      contents()->GetPrimaryMainFrame()));
  EXPECT_EQ(0, cancelled_);
}
TEST_F(NativeWebAuthnTest, GenuineOSWindowBindingUsesSuppliedWindow) {
  Create();
  auto* context = NativeAuthenticatorRequestContext::Get(contents());
  EXPECT_EQ(
      window_,
      context->AuthenticatorWindow(request_->AsWeakPtr()).GetNativeNSWindow());
  SetNativeWebAuthnAttached(*contents(), false);
  EXPECT_FALSE(request_);
  EXPECT_EQ(1, cancelled_);
}
TEST_F(NativeWebAuthnTest, CompetingReservationCannotPresentOrConfigureOS) {
  Create();
  auto* lease = [PCNativeWindowSecurityReservation acquireForWindow:window_];
  EXPECT_FALSE(NativeAuthenticatorRequestContext::Get(contents())
                   ->AuthenticatorWindow(request_->AsWeakPtr()));
  Pump();
  EXPECT_EQ(1, cancelled_);
  EXPECT_FALSE(request_);
  EXPECT_TRUE(lease.isOnlyReservation);
  [lease invalidate];
}
TEST_F(NativeWebAuthnTest, NavigationCancelsOriginalDocument) {
  Create();
  Show();
  content::NavigationSimulator::NavigateAndCommitFromBrowser(
      contents(), GURL("https://other.example/"));
  Pump();
  EXPECT_EQ(1, cancelled_);
  EXPECT_FALSE(request_);
  EXPECT_FALSE(manager()->IsDialogActive());
}
TEST_F(NativeWebAuthnTest, ClosingParentCancelsActualRequest) {
  Create();
  Show();
  [window_ close];
  Pump();
  EXPECT_EQ(1, cancelled_);
  EXPECT_FALSE(request_);
}
TEST_F(NativeWebAuthnTest, DetachDuringReservationDoesNotDestroyFactoryStack) {
  Create();
  __block bool saw = false;
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (!saw && PCNativeWindowHasSecurityReservation(window_)) {
                  saw = true;
                  SetNativeWebAuthnAttached(*contents(), false);
                }
              }];
  Show();
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  EXPECT_TRUE(saw);
  Pump();
  EXPECT_EQ(1, cancelled_);
  EXPECT_FALSE(request_);
  EXPECT_FALSE(manager()->IsDialogActive());
}
TEST_F(NativeWebAuthnTest, RealModalHostChangeDefersRemovalUntilIterationEnds) {
  Create();
  Show();
  ASSERT_TRUE(manager()->IsDialogActive());
  manager()->SetDelegate(nullptr);
  EXPECT_TRUE(manager()->IsDialogActive());
  EXPECT_TRUE(request_);
  manager()->SetDelegate(&modal_);
  Pump();
  EXPECT_EQ(1, cancelled_);
  EXPECT_FALSE(request_);
  EXPECT_FALSE(manager()->IsDialogActive());
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  Create();
  Show();
  Pump();
  EXPECT_TRUE(view());
}
}
