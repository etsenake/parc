#import <AppKit/AppKit.h>
#import <SecurityInterface/SFCertificatePanel.h>

#include "base/run_loop.h"
#include "base/test/bind.h"
#import "certificate_viewer.h"
#include "chrome/browser/certificate_viewer.h"
#include "chrome/browser/ssl/ssl_error_controller_client.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/webui/certificate_viewer/certificate_viewer_webui.h"
#include "components/security_interstitials/content/settings_page_helper.h"
#include "components/security_interstitials/core/metrics_helper.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/ssl_status.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/navigation_simulator.h"
#include "net/test/cert_test_util.h"
#include "net/test/test_data_directory.h"
#include "parc/tests/parc_native_test_support/browser_window_test.h"
#import "window_security_reservation.h"

namespace parc_hooks {
void SetCertificateViewer(bool (*)(content::WebContents*,
                                   gfx::NativeWindow,
                                   net::X509Certificate*));
}

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
void Pump() {
  for (int i = 0; i < 20; ++i) {
    @autoreleasepool {
      base::RunLoop().RunUntilIdle();
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, .01, false);
    }
  }
}
}
class NativeCertificateViewerTest : public ParcBrowserWindowTest {
 public:
  void SetUp() override {
    ParcBrowserWindowTest::SetUp();
    certificate_ = net::ImportCertFromFile(net::GetTestCertsDirectory(),
                                           "root_ca_cert.pem");
    ASSERT_TRUE(certificate_);
    AddTab(browser(), GURL("https://certificate.example/"));
    auto* page = contents()->GetNativeView().GetNativeNSView();
    ASSERT_TRUE(page);
    page.frame = window_.contentView.bounds;
    [window_.contentView addSubview:page];
    contents()->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
    contents()->GetController().GetVisibleEntry()->GetSSL().certificate =
        certificate_;
    contents()->GetController().GetVisibleEntry()->GetSSL().initialized = true;
    parc_hooks::SetCertificateViewer(&ShowServerCertificateViewer);
    InstallNativeServerCertificateViewer(*contents());
    SetNativeServerCertificateViewerAttached(*contents(), true);
  }
  void TearDown() override {
    CertificateViewerDialog::MockForTesting({});
    if (contents()) {
      SetNativeServerCertificateViewerAttached(*contents(), false);
    }
    browser()->GetTabStripModel()->CloseAllTabs();
    Pump();
    parc_hooks::SetCertificateViewer(nullptr);
    ParcBrowserWindowTest::TearDown();
    [window_ close];
    window_ = nil;
  }

 protected:
  std::unique_ptr<BrowserWindow> CreateBrowserWindow() override {
    window_ =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(-2500, -2500, 640, 480)
                                    styleMask:NSWindowStyleMaskTitled
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    window_.releasedWhenClosed = NO;
    [window_ orderFront:nil];
    return std::make_unique<Window>(window_);
  }
  content::WebContents* contents() {
    return browser()->GetTabStripModel()->GetActiveWebContents();
  }
  void Show() {
    ::ShowCertificateViewer(contents(), gfx::NativeWindow(window_),
                            certificate_.get(), CertificateViewerEntrypoint::kPageInfo);
  }
  NSWindow* window_;
  scoped_refptr<net::X509Certificate> certificate_;
};
TEST_F(NativeCertificateViewerTest, GenuineGenericEntryOwnsOSSheet) {
  Show();
  EXPECT_FALSE(window_.attachedSheet);
  Pump();
  ASSERT_TRUE([window_.attachedSheet isKindOfClass:SFCertificatePanel.class]);
  EXPECT_TRUE(window_.attachedSheet.visible);
  EXPECT_TRUE(PCNativeWindowHasSecurityReservation(window_));
  auto* sheet = window_.attachedSheet;
  Show();
  Pump();
  EXPECT_EQ(sheet, window_.attachedSheet);
  [NSApp endSheet:sheet];
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
TEST_F(NativeCertificateViewerTest, GenuineSSLErrorControllerShowsDetailsOnly) {
  net::SSLInfo info;
  info.cert = certificate_;
  info.cert_status = net::CERT_STATUS_AUTHORITY_INVALID;
  const int entry_id =
      contents()->GetController().GetVisibleEntry()->GetUniqueID();
  SSLErrorControllerClient controller(
      contents(), info, net::ERR_CERT_AUTHORITY_INVALID,
      GURL("https://certificate.example/"), nullptr, nullptr);
  controller.ShowCertificateViewer();
  Pump();
  ASSERT_TRUE(window_.attachedSheet);
  EXPECT_EQ(entry_id,
            contents()->GetController().GetVisibleEntry()->GetUniqueID());
  EXPECT_EQ(
      certificate_,
      contents()->GetController().GetVisibleEntry()->GetSSL().certificate);
}
TEST_F(NativeCertificateViewerTest, RejectsDifferentSuppliedWindow) {
  NSWindow* other =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(-2000, -2000, 600, 400)
                                  styleMask:NSWindowStyleMaskTitled
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  other.releasedWhenClosed = NO;
  [other orderFront:nil];
  ::ShowCertificateViewer(contents(), gfx::NativeWindow(other),
                          certificate_.get(), CertificateViewerEntrypoint::kPageInfo);
  Pump();
  EXPECT_FALSE(other.attachedSheet);
  EXPECT_FALSE(window_.attachedSheet);
  [other close];
}
TEST_F(NativeCertificateViewerTest,
       RejectsCertificateDifferentFromVisibleEntry) {
  auto other =
      net::ImportCertFromFile(net::GetTestCertsDirectory(), "ok_cert.pem");
  ASSERT_TRUE(other);
  ::ShowCertificateViewer(contents(), gfx::NativeWindow(window_), other.get(), CertificateViewerEntrypoint::kPageInfo);
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
TEST_F(NativeCertificateViewerTest,
       DetachBeforeDeferredPresentationCannotRevive) {
  Show();
  SetNativeServerCertificateViewerAttached(*contents(), false);
  SetNativeServerCertificateViewerAttached(*contents(), true);
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  Show();
  Pump();
  EXPECT_TRUE(window_.attachedSheet);
}
TEST_F(NativeCertificateViewerTest, DetachClosesActualSheet) {
  Show();
  Pump();
  ASSERT_TRUE(window_.attachedSheet);
  SetNativeServerCertificateViewerAttached(*contents(), false);
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
  Show();
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
}
TEST_F(NativeCertificateViewerTest, NavigationClosesOriginalCertificateSheet) {
  Show();
  Pump();
  ASSERT_TRUE(window_.attachedSheet);
  content::NavigationSimulator::NavigateAndCommitFromBrowser(
      contents(), GURL("https://other.example/"));
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
TEST_F(NativeCertificateViewerTest, CompetingReservationPreservesOtherOwner) {
  auto* lease = [PCNativeWindowSecurityReservation acquireForWindow:window_];
  Show();
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_TRUE(lease.isOnlyReservation);
  [lease invalidate];
  Show();
  Pump();
  EXPECT_TRUE(window_.attachedSheet);
}
TEST_F(NativeCertificateViewerTest, DetachDuringAcquireCannotPresent) {
  __block bool once = false;
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (!once && PCNativeWindowHasSecurityReservation(window_)) {
                  once = true;
                  SetNativeServerCertificateViewerAttached(*contents(), false);
                }
              }];
  Show();
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  Pump();
  EXPECT_TRUE(once);
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
TEST_F(NativeCertificateViewerTest, PageDestructionClosesSheet) {
  Show();
  Pump();
  ASSERT_TRUE(window_.attachedSheet);
  browser()->GetTabStripModel()->CloseAllTabs();
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
TEST_F(NativeCertificateViewerTest,
       VisibleCertificateMutationCancelsPendingSheet) {
  Show();
  contents()->GetController().GetVisibleEntry()->GetSSL().certificate = nullptr;
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
TEST_F(NativeCertificateViewerTest, ParentCloseRetiresReservation) {
  Show();
  Pump();
  ASSERT_TRUE(window_.attachedSheet);
  [window_ close];
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
}

namespace parc {
TEST_F(NativeCertificateViewerTest, NativeRefusalDoesNotFallBackToStockViewer) {
  int stock_calls = 0;
  CertificateViewerDialog::MockForTesting(base::BindLambdaForTesting(
      [&](std::vector<bssl::UniquePtr<CRYPTO_BUFFER>> certs,
          content::WebContents* actual) {
        ++stock_calls;
        EXPECT_EQ(actual, contents());
        EXPECT_EQ(certs.size(), 1u);
      }));
  SetNativeServerCertificateViewerAttached(*contents(), false);
  Show();
  Pump();
  EXPECT_EQ(stock_calls, 0);
  EXPECT_FALSE(window_.attachedSheet);
  AddTab(browser(), GURL("https://other.example/"));
  Show();
  EXPECT_EQ(stock_calls, 1);
  EXPECT_FALSE(window_.attachedSheet);
}
}
