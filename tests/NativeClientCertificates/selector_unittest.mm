// Genuine SSLClientCertificateSelector, identities, SSL auth observer and modal
// manager. Only certificate/private-key inputs are synthetic test fixtures.
#import <AppKit/AppKit.h>

#include <memory>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/raw_ref.h"
#include "base/run_loop.h"
#include "base/time/time.h"
#include "browser_window.h"
#include "chrome/browser/ssl/ssl_client_auth_observer.h"
#include "chrome/browser/ssl/ssl_client_certificate_selector.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/ssl_client_certificate_selector.h"
#include "chrome/test/base/browser_with_test_window_test.h"
#include "client_certificates.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/client_certificate_delegate.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/navigation_simulator.h"
#include "net/ssl/client_cert_identity_test_util.h"
#include "net/ssl/ssl_cert_request_info.h"
#include "net/ssl/ssl_private_key.h"
#include "net/test/test_data_directory.h"
#include "ui/views/widget/widget.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
struct Outcome {
  int replies = 0;
  int destroyed = 0;
  scoped_refptr<net::X509Certificate> certificate;
  scoped_refptr<net::SSLPrivateKey> key;
  base::OnceClosure on_reply;
};
class Delegate final : public content::ClientCertificateDelegate {
 public:
  explicit Delegate(Outcome& result) : result_(result) {}
  ~Delegate() override { ++result_->destroyed; }
  void ContinueWithCertificate(scoped_refptr<net::X509Certificate> cert,
                               scoped_refptr<net::SSLPrivateKey> key) override {
    ++result_->replies;
    result_->certificate = std::move(cert);
    result_->key = std::move(key);
    if (result_->on_reply) {
      std::move(result_->on_reply).Run();
    }
  }

 private:
  const raw_ref<Outcome> result_;
};
class PeerObserver final : public SSLClientAuthObserver {
 public:
  PeerObserver(content::BrowserContext* context,
               net::SSLCertRequestInfo* info,
               std::unique_ptr<content::ClientCertificateDelegate> delegate)
      : SSLClientAuthObserver(context, info, std::move(delegate)) {
    StartObserving();
  }
  ~PeerObserver() override { CancelCertificateSelection(); }
  void OnCertSelectedByNotification() override { ++notifications; }
  int notifications = 0;
};
struct Acquisition {
  int calls = 0;
  bool deferred = false;
  scoped_refptr<net::SSLPrivateKey> key;
  base::OnceCallback<void(scoped_refptr<net::SSLPrivateKey>)> pending;
};
class Identity final : public net::ClientCertIdentity {
 public:
  Identity(scoped_refptr<net::X509Certificate> cert,
           std::shared_ptr<Acquisition> state)
      : ClientCertIdentity(std::move(cert)), state_(std::move(state)) {}
  void AcquirePrivateKey(
      base::OnceCallback<void(scoped_refptr<net::SSLPrivateKey>)> callback)
      override {
    ++state_->calls;
    if (state_->deferred) {
      state_->pending = std::move(callback);
    } else {
      std::move(callback).Run(state_->key);
    }
  }

 private:
  const std::shared_ptr<Acquisition> state_;
};
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
  for (int i = 0; i < 10; ++i) {
    base::RunLoop().RunUntilIdle();
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, .01, true);
  }
}
}  // namespace
class NativeClientCertificatesTest : public BrowserWithTestWindowTest {
 public:
  void SetUp() override {
    BrowserWithTestWindowTest::SetUp();
    AddTab(browser(), GURL("https://certificate.example/request"));
    auto* page = contents()->GetNativeView().GetNativeNSView();
    ASSERT_TRUE(page);
    page.frame = window_.contentView.bounds;
    [window_.contentView addSubview:page];
    modal_.page = page;
    contents()->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
    web_modal::WebContentsModalDialogManager::CreateForWebContents(contents());
    manager()->SetDelegate(&modal_);
    InstallNativeClientCertificates(*contents());
    SetNativeClientCertificatesAttached(*contents(), true);
    identity_ = net::FakeClientCertIdentity::CreateFromCertAndKeyFiles(
        net::GetTestCertsDirectory(), "client_1.pem", "client_1.pk8");
    ASSERT_TRUE(identity_);
    acquisition_ = std::make_shared<Acquisition>();
    acquisition_->key = identity_->ssl_private_key();
    info_ = base::MakeRefCounted<net::SSLCertRequestInfo>();
    info_->host_and_port = net::HostPortPair("certificate.example", 443);
  }
  void TearDown() override {
    if (contents()) {
      SetNativeClientCertificatesAttached(*contents(), false);
    }
    if (acquisition_->pending) {
      std::move(acquisition_->pending).Run(acquisition_->key);
    }
    Pump();
    browser()->GetTabStripModel()->CloseAllTabs();
    Pump();
    modal_.host.Invalidate();
    BrowserWithTestWindowTest::TearDown();
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
  Outcome& Start(bool empty = false) {
    auto outcome = std::make_unique<Outcome>();
    auto& result = *outcome;
    outcomes_.push_back(std::move(outcome));
    net::ClientCertIdentityList identities;
    if (!empty) {
      identities.push_back(
          std::make_unique<Identity>(identity_->certificate(), acquisition_));
    }
    callbacks_.push_back(ShowSSLClientCertificateSelector(
        contents(), info_.get(), std::move(identities),
        std::make_unique<Delegate>(result)));
    return result;
  }
  SSLClientCertificateSelector* selector() {
    if (window_.childWindows.count != 1) {
      return nullptr;
    }
    auto* widget = views::Widget::GetWidgetForNativeWindow(
        gfx::NativeWindow(window_.childWindows.firstObject));
    return widget ? static_cast<SSLClientCertificateSelector*>(
                        widget->widget_delegate()->AsDialogDelegate())
                  : nullptr;
  }
  NSWindow* window_;
  ModalDelegate modal_;
  std::unique_ptr<net::FakeClientCertIdentity> identity_;
  std::shared_ptr<Acquisition> acquisition_;
  scoped_refptr<net::SSLCertRequestInfo> info_;
  std::vector<std::unique_ptr<Outcome>> outcomes_;
  std::vector<base::OnceClosure> callbacks_;
};

TEST_F(NativeClientCertificatesTest,
       ActualSelectorUsesSuppliedNativeWindowAndIdentity) {
  auto& result = Start();
  ASSERT_TRUE(selector());
  EXPECT_TRUE(manager()->IsDialogActive());
  EXPECT_TRUE(modal_.blocked);
  EXPECT_EQ(selector()->GetSelectedCert()->certificate(),
            identity_->certificate());
  EXPECT_EQ(window_.childWindows.firstObject.parentWindow, window_);
  EXPECT_TRUE(window_.childWindows.firstObject.visible);
  EXPECT_EQ(views::Widget::GetWidgetForNativeWindow(gfx::NativeWindow(window_)),
            nullptr);
  selector()->AcceptDialog();
  EXPECT_EQ(result.replies, 0);
  Pump();
  EXPECT_EQ(acquisition_->calls, 1);
  EXPECT_EQ(result.replies, 1);
  EXPECT_EQ(result.certificate.get(), identity_->certificate());
  EXPECT_EQ(result.key.get(), identity_->ssl_private_key());
  EXPECT_FALSE(manager()->IsDialogActive());
  EXPECT_FALSE(modal_.blocked);
}
TEST_F(NativeClientCertificatesTest,
       ExplicitCancelContinuesWithoutCertificate) {
  auto& result = Start();
  ASSERT_TRUE(selector());
  selector()->CancelDialog();
  Pump();
  EXPECT_EQ(result.replies, 1);
  EXPECT_FALSE(result.certificate);
  EXPECT_FALSE(result.key);
  EXPECT_EQ(acquisition_->calls, 0);
}
TEST_F(NativeClientCertificatesTest, EmptyPolicyListDoesNotCreateWindow) {
  auto& result = Start(true);
  EXPECT_EQ(result.replies, 1);
  EXPECT_FALSE(result.certificate);
  EXPECT_FALSE(selector());
  EXPECT_FALSE(manager()->IsDialogActive());
}
TEST_F(NativeClientCertificatesTest,
       DetachedBeforeShowAbortsWithoutNullConsent) {
  SetNativeClientCertificatesAttached(*contents(), false);
  auto& result = Start();
  Pump();
  EXPECT_EQ(result.replies, 0);
  EXPECT_EQ(result.destroyed, 1);
  EXPECT_EQ(acquisition_->calls, 0);
  EXPECT_FALSE(selector());
}
TEST_F(NativeClientCertificatesTest, HiddenParentDoesNotPresent) {
  [window_ orderOut:nil];
  auto& result = Start();
  Pump();
  EXPECT_EQ(result.replies, 0);
  EXPECT_EQ(result.destroyed, 1);
  EXPECT_FALSE(manager()->IsDialogActive());
}
TEST_F(NativeClientCertificatesTest, ExactPageDetachCancelsAndUnblocks) {
  auto& result = Start();
  ASSERT_TRUE(selector());
  SetNativeClientCertificatesAttached(*contents(), false);
  EXPECT_FALSE(manager()->IsDialogActive());
  Pump();
  EXPECT_EQ(result.replies, 0);
  EXPECT_EQ(result.destroyed, 1);
  EXPECT_EQ(acquisition_->calls, 0);
}
TEST_F(NativeClientCertificatesTest,
       DelayedPrivateKeyCannotAuthorizeDetachedPage) {
  acquisition_->deferred = true;
  auto& result = Start();
  ASSERT_TRUE(selector());
  selector()->AcceptDialog();
  ASSERT_TRUE(acquisition_->pending);
  SetNativeClientCertificatesAttached(*contents(), false);
  std::move(acquisition_->pending).Run(acquisition_->key);
  Pump();
  EXPECT_EQ(result.replies, 0);
  EXPECT_EQ(result.destroyed, 1);
}
TEST_F(NativeClientCertificatesTest,
       InvalidLateKeyDoesNotBroadcastToSameChallenge) {
  acquisition_->deferred = true;
  Outcome other;
  PeerObserver peer(contents()->GetBrowserContext(), info_.get(),
                    std::make_unique<Delegate>(other));
  auto& result = Start();
  ASSERT_TRUE(selector());
  selector()->AcceptDialog();
  ASSERT_TRUE(acquisition_->pending);
  SetNativeClientCertificatesAttached(*contents(), false);
  std::move(acquisition_->pending).Run(acquisition_->key);
  Pump();
  EXPECT_EQ(result.replies, 0);
  EXPECT_EQ(other.replies, 0);
  EXPECT_EQ(peer.notifications, 0);
}
TEST_F(NativeClientCertificatesTest, CompetingReservationPreventsAcquisition) {
  auto& result = Start();
  ASSERT_TRUE(selector());
  auto* lease = [PCNativeWindowSecurityReservation acquireForWindow:window_];
  selector()->AcceptDialog();
  Pump();
  EXPECT_EQ(acquisition_->calls, 0);
  EXPECT_EQ(result.replies, 0);
  EXPECT_EQ(result.destroyed, 1);
  [lease invalidate];
}
TEST_F(NativeClientCertificatesTest,
       ReleaseTimeCompetingReservationAbortsReply) {
  auto& result = Start();
  ASSERT_TRUE(selector());
  __block PCNativeWindowSecurityReservation* replacement = nil;
  __block bool replacing = false;
  NSWindow* window = window_;
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (!replacing &&
                    !PCNativeWindowHasSecurityReservation(window)) {
                  replacing = true;
                  replacement = [PCNativeWindowSecurityReservation
                      acquireForWindow:window];
                }
              }];
  selector()->AcceptDialog();
  Pump();
  EXPECT_TRUE(replacing);
  EXPECT_EQ(result.replies, 0);
  EXPECT_EQ(result.destroyed, 1);
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  [replacement invalidate];
}
TEST_F(NativeClientCertificatesTest, NavigationAbortsOriginalRequest) {
  auto& result = Start();
  ASSERT_TRUE(selector());
  content::NavigationSimulator::NavigateAndCommitFromBrowser(
      contents(), GURL("https://other.example/new"));
  Pump();
  EXPECT_EQ(result.replies, 0);
  EXPECT_EQ(result.destroyed, 1);
  EXPECT_FALSE(manager()->IsDialogActive());
}
TEST_F(NativeClientCertificatesTest, ParentCloseAbortsOriginalRequest) {
  auto& result = Start();
  ASSERT_TRUE(selector());
  [window_ close];
  Pump();
  EXPECT_EQ(result.replies, 0);
  EXPECT_EQ(result.destroyed, 1);
}
TEST_F(NativeClientCertificatesTest, SecondRequestDoesNotReplaceLiveDialog) {
  auto& first = Start();
  auto* original = selector();
  ASSERT_TRUE(original);
  auto& second = Start();
  Pump();
  EXPECT_EQ(selector(), original);
  EXPECT_EQ(first.destroyed, 0);
  EXPECT_EQ(second.replies, 0);
  EXPECT_EQ(second.destroyed, 1);
  original->CancelDialog();
  Pump();
  EXPECT_EQ(first.replies, 1);
}
TEST_F(NativeClientCertificatesTest, GenuineDelegateCanDestroyPageOnReply) {
  auto& result = Start();
  ASSERT_TRUE(selector());
  result.on_reply = base::BindOnce(
      [](BrowserWindowInterface* browser) {
        browser->GetTabStripModel()->CloseAllTabs();
      },
      browser());
  selector()->AcceptDialog();
  Pump();
  EXPECT_EQ(result.replies, 1);
  EXPECT_EQ(result.destroyed, 1);
  EXPECT_EQ(browser()->GetTabStripModel()->count(), 0);
}
}  // namespace parc
