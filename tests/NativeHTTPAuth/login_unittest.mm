// Real LoginHandler / WebContentsModalDialogManager / Browser / Profile. The
// fixture supplies only a native test window and a modal visibility delegate.
#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <vector>

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "base/time/time.h"
#include "chrome/browser/ui/login/login_handler.h"
#include "chrome/browser/ui/login/http_auth_coordinator.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/test/base/browser_with_test_window_test.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/navigation_simulator.h"
#include "http_auth.h"
#include "net/base/auth.h"
#include "url/gurl.h"
#include "url/scheme_host_port.h"
#import "window_security_reservation.h"

namespace parc_hooks {
void SetLoginHandlerAuthValidator(bool (*validator)(LoginHandler*));
}

namespace parc {
namespace {
NSView* Find(NSView* v, NSString* name) {
  if ([v.identifier isEqual:name] ||
      ([v isKindOfClass:NSButton.class] &&
       [static_cast<NSButton*>(v).title isEqual:name])) {
    return v;
  }
  for (NSView* child in v.subviews) {
    if (auto f = Find(child, name)) {
      return f;
    }
  }
  return nil;
}
bool TextContains(NSView* v, NSString* text) {
  if ([v isKindOfClass:NSTextField.class] &&
      [static_cast<NSTextField*>(v).stringValue containsString:text]) {
    return true;
  }
  for (NSView* c in v.subviews) {
    if (TextContains(c, text)) {
      return true;
    }
  }
  return false;
}
template <typename F>
bool Pump(F predicate) {
  auto end = base::TimeTicks::Now() + base::Seconds(4);
  do {
    base::RunLoop().RunUntilIdle();
    if (predicate()) {
      return true;
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, .01, true);
  } while (base::TimeTicks::Now() < end);
  return predicate();
}
class Window final : public TestBrowserWindow {
 public:
  explicit Window(NSWindow* w) : window_(w) {}
  gfx::NativeWindow GetNativeWindow() const override {
    return gfx::NativeWindow(window_);
  }

 private:
  NSWindow* __weak window_;
};
class ModalDelegate final
    : public web_modal::WebContentsModalDialogManagerDelegate {
 public:
  void SetWebContentsBlocked(content::WebContents*, bool b) override {
    blocked = b;
  }
  bool IsWebContentsVisible(content::WebContents*) override { return true; }
  bool blocked = false;
};
struct Outcome {
  int calls = 0;
  std::optional<net::AuthCredentials> credentials;
};
}  // namespace
class NativeHTTPAuthTest : public BrowserWithTestWindowTest {
 public:
  void SetUp() override {
    BrowserWithTestWindowTest::SetUp();
    AddTab(browser(), GURL("https://auth.example:8443/page"));
    auto* page = contents()->GetNativeView().GetNativeNSView();
    ASSERT_TRUE(page);
    page.frame = native_window_.contentView.bounds;
    [native_window_.contentView addSubview:page];
    contents()->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
    web_modal::WebContentsModalDialogManager::CreateForWebContents(contents());
    manager()->SetDelegate(&modal_);
    InstallNativeHTTPAuth(*contents());
    SetNativeHTTPAuthAttached(*contents(), true);
  }
  void TearDown() override {
    handlers_.clear();
    base::RunLoop().RunUntilIdle();
    browser()->GetTabStripModel()->CloseAllTabs();
    BrowserWithTestWindowTest::TearDown();
    [native_window_ close];
    native_window_ = nil;
  }

 protected:
  std::unique_ptr<BrowserWindow> CreateBrowserWindow() override {
    native_window_ = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(-2300, -2300, 640, 480)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    native_window_.releasedWhenClosed = NO;
    [native_window_ orderFront:nil];
    return std::make_unique<Window>(native_window_);
  }
  content::WebContents* contents() {
    return browser()->GetTabStripModel()->GetActiveWebContents();
  }
  web_modal::WebContentsModalDialogManager* manager() {
    return web_modal::WebContentsModalDialogManager::FromWebContents(
        contents());
  }
  Outcome& Start(bool proxy = false, base::OnceClosure on_reply = {}) {
    auto outcome = std::make_unique<Outcome>();
    auto* out = outcome.get();
    outcomes_.push_back(std::move(outcome));
    net::AuthChallengeInfo info;
    info.is_proxy = proxy;
    info.scheme = "basic";
    info.realm = "private";
    info.challenger = url::SchemeHostPort(GURL(
        proxy ? "http://proxy.example:8080" : "https://auth.example:8443"));
    parc_hooks::SetLoginHandlerAuthValidator(&ValidateNativeLoginHandlerAuth);
    auto coordinator = CreateNativeHttpAuthCoordinator();
    auto handler = coordinator->CreateLoginDelegateFromLoginHandler(
        contents(), info, content::GlobalRequestID(),
        GURL("https://auth.example:8443/page"), nullptr,
        base::BindOnce(
            [](Outcome* out, base::OnceClosure reenter,
               const std::optional<net::AuthCredentials>& credentials) {
              ++out->calls;
              out->credentials = credentials;
              if (reenter) {
                std::move(reenter).Run();
              }
            },
            out, std::move(on_reply)));
    handlers_.push_back(std::unique_ptr<LoginHandler>(
        static_cast<LoginHandler*>(handler.release())));
    return *out;
  }
  void FillAndAccept() {
    ASSERT_TRUE(native_window_.attachedSheet);
    auto* view = native_window_.attachedSheet.contentView;
    static_cast<NSTextField*>(Find(view, @"http-auth-username")).stringValue =
        @"actual-user";
    static_cast<NSTextField*>(Find(view, @"http-auth-password")).stringValue =
        @"actual-secret";
    [static_cast<NSButton*>(Find(view, @"http-auth-sign-in")) performClick:nil];
  }
  NSWindow* native_window_;
  ModalDelegate modal_;
  std::vector<std::unique_ptr<LoginHandler>> handlers_;
  std::vector<std::unique_ptr<Outcome>> outcomes_;
};
TEST_F(NativeHTTPAuthTest, ActualHandlerAcceptsOnlyAfterNativeSubmission) {
  auto& out = Start();
  EXPECT_EQ(out.calls, 0);
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  EXPECT_TRUE(manager()->IsDialogActive());
  EXPECT_TRUE(modal_.blocked);
  FillAndAccept();
  EXPECT_EQ(out.calls, 0);
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  ASSERT_TRUE(out.credentials);
  EXPECT_EQ(out.credentials->username(), u"actual-user");
  EXPECT_EQ(out.credentials->password(), u"actual-secret");
  EXPECT_FALSE(manager()->IsDialogActive());
  EXPECT_FALSE(modal_.blocked);
}
TEST_F(NativeHTTPAuthTest, ProxyKeepsActualChallengerAndTransportWarning) {
  auto& out = Start(true);
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  EXPECT_TRUE(TextContains(native_window_.attachedSheet.contentView,
                           @"Sign in to The proxy"));
  EXPECT_TRUE(TextContains(native_window_.attachedSheet.contentView,
                           @"proxy.example:8080"));
  EXPECT_TRUE(
      TextContains(native_window_.attachedSheet.contentView, @"not private"));
  [native_window_.attachedSheet cancelOperation:nil];
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  EXPECT_FALSE(out.credentials);
}
TEST_F(NativeHTTPAuthTest, OwnerDestructionDropsContinuationAndClosesModal) {
  auto& out = Start();
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  handlers_.clear();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(out.calls, 0);
  EXPECT_FALSE(manager()->IsDialogActive());
  EXPECT_FALSE(native_window_.attachedSheet);
}
TEST_F(NativeHTTPAuthTest, PageDetachWithoutNavigationCancelsExactRequest) {
  auto& out = Start();
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  SetNativeHTTPAuthAttached(*contents(), false);
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  EXPECT_FALSE(out.credentials);
  EXPECT_FALSE(manager()->IsDialogActive());
  SetNativeHTTPAuthAttached(*contents(), true);
  auto& next = Start();
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  FillAndAccept();
  ASSERT_TRUE(Pump([&] { return next.calls == 1; }));
  EXPECT_TRUE(next.credentials);
  EXPECT_EQ(out.calls, 1);
}
TEST_F(NativeHTTPAuthTest, NavigationCannotAuthorizeNewDocument) {
  auto& out = Start();
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  content::NavigationSimulator::NavigateAndCommitFromBrowser(
      contents(), GURL("https://auth.example:8443/other"));
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  EXPECT_FALSE(out.credentials);
  EXPECT_FALSE(native_window_.attachedSheet);
}
TEST_F(NativeHTTPAuthTest, CompetingLeaseAtReleaseCannotAccept) {
  auto& out = Start();
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  __block PCNativeWindowSecurityReservation* competing = nil;
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:native_window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (!competing &&
                    !PCNativeWindowHasSecurityReservation(native_window_)) {
                  competing = [PCNativeWindowSecurityReservation
                      acquireForWindow:native_window_];
                }
              }];
  FillAndAccept();
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  EXPECT_FALSE(out.credentials);
  EXPECT_TRUE(competing.isOnlyReservation);
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  [competing invalidate];
}
TEST_F(NativeHTTPAuthTest,
       ActiveLeaseConflictRejectsWithoutClearingOtherLease) {
  auto* lease =
      [PCNativeWindowSecurityReservation acquireForWindow:native_window_];
  auto& out = Start();
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  EXPECT_FALSE(out.credentials);
  EXPECT_FALSE(native_window_.attachedSheet);
  EXPECT_TRUE(lease.isOnlyReservation);
  [lease invalidate];
}
TEST_F(NativeHTTPAuthTest, DuplicateRequestDoesNotReplaceExecutingNativeSheet) {
  auto& first = Start();
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  NSWindow* first_sheet = native_window_.attachedSheet;
  auto& second = Start();
  ASSERT_TRUE(Pump([&] { return second.calls == 1; }));
  EXPECT_FALSE(second.credentials);
  EXPECT_EQ(first.calls, 0);
  EXPECT_EQ(first_sheet, native_window_.attachedSheet);
  FillAndAccept();
  ASSERT_TRUE(Pump([&] { return first.calls == 1; }));
  EXPECT_TRUE(first.credentials);
}
TEST_F(NativeHTTPAuthTest, PropagatedCredentialsAlsoRespectDetachedOwner) {
  auto& out = Start();
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  SetNativeHTTPAuthAttached(*contents(), false);
  // Same entry the actual LoginHandler uses for another matching challenge.
  handlers_.front()->SetAuth(u"other-handler", u"must-not-apply");
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  EXPECT_FALSE(out.credentials);
}
TEST_F(NativeHTTPAuthTest, ActualModalManagerCloseCancelsAndRemovesItsEntry) {
  auto& out = Start();
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  manager()->CloseAllDialogs();
  EXPECT_FALSE(manager()->IsDialogActive());
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  EXPECT_FALSE(out.credentials);
  EXPECT_FALSE(modal_.blocked);
}
TEST_F(NativeHTTPAuthTest, ReplyMayDeleteHandlerAndCreateReplacement) {
  auto& out = Start(false, base::BindLambdaForTesting([&] {
                      handlers_.clear();
                      Start(true);
                    }));
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  FillAndAccept();
  ASSERT_TRUE(Pump(
      [&] { return out.calls == 1 && native_window_.attachedSheet != nil; }));
  EXPECT_TRUE(out.credentials);
  EXPECT_TRUE(TextContains(native_window_.attachedSheet.contentView,
                           @"Sign in to The proxy"));
}
TEST_F(NativeHTTPAuthTest, HiddenNativeOwnerDoesNotFallBackToViews) {
  [native_window_ orderOut:nil];
  auto& out = Start();
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  EXPECT_FALSE(out.credentials);
  EXPECT_FALSE(native_window_.attachedSheet);
  EXPECT_FALSE(manager()->IsDialogActive());
}
TEST_F(NativeHTTPAuthTest, InvalidHostCannotReviveBeforeDeferredCancellation) {
  auto& out = Start();
  ASSERT_TRUE(Pump([&] { return native_window_.attachedSheet != nil; }));
  NSView* page = contents()->GetNativeView().GetNativeNSView();
  NSView* parent = page.superview;
  [page removeFromSuperview];
  // The real modal manager sends HostChanged while its collection is active.
  // No task pump occurs between invalidation and restoring the exact owner.
  manager()->SetDelegate(nullptr);
  [parent addSubview:page];
  manager()->SetDelegate(&modal_);
  EXPECT_TRUE(manager()->IsDialogActive());
  handlers_.front()->SetAuth(u"late-user", u"must-not-apply");
  ASSERT_TRUE(Pump([&] { return out.calls == 1; }));
  EXPECT_FALSE(out.credentials);
  EXPECT_FALSE(manager()->IsDialogActive());
  EXPECT_FALSE(native_window_.attachedSheet);
}
}  // namespace parc
