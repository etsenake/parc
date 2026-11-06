// Real Browser/Profile/Tab, external-protocol continuation, native modal
// manager and sheet. Only OS launch is intercepted by Chromium's test delegate.
#import <AppKit/AppKit.h>

#include <memory>

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "base/test/scoped_command_line.h"
#include "browser_window.h"
#include "chrome/browser/external_protocol/external_protocol_handler.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_occlusion_tracker.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/common/pref_names.h"
#include "chrome/test/base/browser_with_test_window_test.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/navigation_simulator.h"
#include "external_protocol.h"
#include "ui/events/event.h"
#include "ui/views/input_event_activation_protector.h"
#include "ui/views/test/views_test_base.h"
#include "ui/views/view.h"
#include "ui/views/views_switches.h"
#include "ui/views/widget/widget.h"
#import "window_security_reservation.h"
namespace parc {
namespace {
class OSDelegate final : public ExternalProtocolHandler::Delegate {
 public:
  scoped_refptr<shell_integration::DefaultSchemeClientWorker> CreateShellWorker(
      const GURL&) override {
    return nullptr;
  }
  ExternalProtocolHandler::BlockState GetBlockState(const std::string&,
                                                    Profile*) override {
    return ExternalProtocolHandler::UNKNOWN;
  }
  void BlockRequest() override {}
  void RunExternalProtocolDialog(const GURL&,
                                 content::WebContents*,
                                 ui::PageTransition,
                                 bool,
                                 const std::optional<url::Origin>&,
                                 const std::u16string&) override {}
  void LaunchUrlWithoutSecurityCheck(const GURL& url,
                                     content::WebContents* page) override {
    ++launches;
    launched = url;
    launched_page = page;
    if (on_launch) {
      std::move(on_launch).Run();
    }
  }
  void FinishedProcessingCheck() override {}
  int launches = 0;
  GURL launched;
  raw_ptr<content::WebContents> launched_page = nullptr;
  base::OnceClosure on_launch;
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
NSButton* Find(NSView* root, NSString* id) {
  if ([root.identifier isEqual:id]) {
    return static_cast<NSButton*>(root);
  }
  for (NSView* child in root.subviews) {
    if (auto* found = Find(child, id)) {
      return found;
    }
  }
  return nil;
}
}  // namespace
class NativeExternalProtocolTest : public BrowserWithTestWindowTest {
 public:
  void SetUp() override {
    BrowserWithTestWindowTest::SetUp();
    AddTab(browser(), GURL("https://protocol.example/start"));
    auto* page = contents()->GetNativeView().GetNativeNSView();
    ASSERT_TRUE(page);
    page.frame = window_.contentView.bounds;
    [window_.contentView addSubview:page];
    modal_.page = page;
    contents()->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
    web_modal::WebContentsModalDialogManager::CreateForWebContents(contents());
    manager()->SetDelegate(&modal_);
    InstallNativeExternalProtocol(*contents());
    SetNativeExternalProtocolAttached(*contents(), true);
    ExternalProtocolHandler::SetDelegateForTesting(&os_);
    // Lifetime/decision cases use Chromium's explicit test switch. The real
    // protector remains exercised separately; production has no such override.
    command_.GetProcessCommandLine()->AppendSwitch(
        views::switches::kDisableInputEventActivationProtectionForTesting);
  }
  void TearDown() override {
    if (contents()) {
      SetNativeExternalProtocolAttached(*contents(), false);
    }
    Pump();
    os_.launched_page = nullptr;
    browser()->tab_strip_model()->CloseAllTabs();
    Pump();
    modal_.host.Invalidate();
    ExternalProtocolHandler::SetDelegateForTesting(nullptr);
    os_.launched_page = nullptr;
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
    return browser()->tab_strip_model()->GetActiveWebContents();
  }
  web_modal::WebContentsModalDialogManager* manager() {
    return web_modal::WebContentsModalDialogManager::FromWebContents(
        contents());
  }
  void Start(std::optional<url::Origin> origin =
                 url::Origin::Create(GURL("https://protocol.example")),
             bool stale = false) {
    auto doc = contents()->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    if (stale) {
      content::NavigationSimulator::NavigateAndCommitFromBrowser(
          contents(), GURL("https://replacement.example"));
    }
    ExternalProtocolHandler::RunExternalProtocolDialog(
        GURL("parc-test:payload"), contents(), ui::PAGE_TRANSITION_LINK, true,
        false, origin, doc, u"Example App");
  }
  NSButton* button(NSString* name) {
    return Find(window_.attachedSheet.contentView, name);
  }
  //
  // may not remember, only Open exists.
  void Accept(bool remember = false) {
    NSButton* always = button(@"external-protocol-remember");
    [(remember && always ? always : button(@"external-protocol-open"))
        performClick:nil];
  }
  NSWindow* window_;
  ModalDelegate modal_;
  OSDelegate os_;
  base::test::ScopedCommandLine command_;
};
TEST_F(NativeExternalProtocolTest, ActualPageModalAndOnceOnlyOSContinuation) {
  Start();
  EXPECT_FALSE(window_.attachedSheet);
  Pump();
  ASSERT_TRUE(window_.attachedSheet);
  EXPECT_TRUE(modal_.blocked);
  EXPECT_EQ(views::Widget::GetWidgetForNativeWindow(gfx::NativeWindow(window_)),
            nullptr);
  Accept();
  EXPECT_EQ(os_.launches, 0);
  Pump();
  EXPECT_EQ(os_.launches, 1);
  EXPECT_EQ(os_.launched, GURL("parc-test:payload"));
  EXPECT_EQ(os_.launched_page, contents());
  EXPECT_FALSE(manager()->IsDialogActive());
  EXPECT_FALSE(modal_.blocked);
}
TEST_F(NativeExternalProtocolTest, CancelDoesNotLaunchOrRemember) {
  Start();
  Pump();
  [button(@"external-protocol-cancel") performClick:nil];
  Pump();
  EXPECT_EQ(os_.launches, 0);
  EXPECT_TRUE(profile()
                  ->GetPrefs()
                  ->GetDict(prefs::kProtocolHandlerPerOriginAllowedProtocols)
                  .empty());
}
TEST_F(NativeExternalProtocolTest, ExplicitRememberUsesRealProfilePreference) {
  Start();
  Pump();
  ASSERT_TRUE(button(@"external-protocol-remember"));
  Accept(true);
  Pump();
  EXPECT_EQ(os_.launches, 1);
  auto* dict = profile()
                   ->GetPrefs()
                   ->GetDict(prefs::kProtocolHandlerPerOriginAllowedProtocols)
                   .FindDict("https://protocol.example");
  ASSERT_TRUE(dict);
  EXPECT_EQ(dict->FindBool("parc-test"), true);
}
TEST_F(NativeExternalProtocolTest, ManagedCheckboxPolicyPreventsRemember) {
  profile()->GetPrefs()->SetBoolean(
      prefs::kExternalProtocolDialogShowAlwaysOpenCheckbox, false);
  Start();
  Pump();
  EXPECT_FALSE(button(@"external-protocol-remember"));
  Accept(true);
  Pump();
  EXPECT_EQ(os_.launches, 1);
  EXPECT_TRUE(profile()
                  ->GetPrefs()
                  ->GetDict(prefs::kProtocolHandlerPerOriginAllowedProtocols)
                  .empty());
}
TEST_F(NativeExternalProtocolTest, UntrustworthyOriginCannotBeRemembered) {
  Start(url::Origin::Create(GURL("http://untrusted.example")));
  Pump();
  EXPECT_FALSE(button(@"external-protocol-remember"));
  Accept(true);
  Pump();
  EXPECT_EQ(os_.launches, 1);
  EXPECT_TRUE(profile()
                  ->GetPrefs()
                  ->GetDict(prefs::kProtocolHandlerPerOriginAllowedProtocols)
                  .empty());
}
TEST_F(NativeExternalProtocolTest, StaleInitiatorCannotCreateConsent) {
  Start(url::Origin::Create(GURL("https://protocol.example")), true);
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_EQ(os_.launches, 0);
}
TEST_F(NativeExternalProtocolTest, NavigationCancelsPendingRequest) {
  Start();
  Pump();
  content::NavigationSimulator::NavigateAndCommitFromBrowser(
      contents(), GURL("https://other.example"));
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_EQ(os_.launches, 0);
}
TEST_F(NativeExternalProtocolTest, DetachCancelsBeforeViewRemoval) {
  Start();
  Pump();
  SetNativeExternalProtocolAttached(*contents(), false);
  Pump();
  EXPECT_FALSE(window_.attachedSheet);
  EXPECT_EQ(os_.launches, 0);
  EXPECT_FALSE(PCNativeWindowHasSecurityReservation(window_));
}
TEST_F(NativeExternalProtocolTest, DetachCannotReviveQueuedAcceptedDecision) {
  Start();
  Pump();
  ASSERT_TRUE(button(@"external-protocol-remember"));
  Accept(true);
  EXPECT_EQ(os_.launches, 0);
  SetNativeExternalProtocolAttached(*contents(), false);
  SetNativeExternalProtocolAttached(*contents(), true);
  Pump();
  EXPECT_EQ(os_.launches, 0);
  EXPECT_TRUE(profile()
                  ->GetPrefs()
                  ->GetDict(prefs::kProtocolHandlerPerOriginAllowedProtocols)
                  .empty());
  Start();
  Pump();
  ASSERT_TRUE(window_.attachedSheet);
  Accept();
  Pump();
  EXPECT_EQ(os_.launches, 1);
}
TEST_F(NativeExternalProtocolTest, NewRequestReplacesWithoutOldDecision) {
  Start();
  Pump();
  NSWindow* old = window_.attachedSheet;
  Start();
  Pump();
  ASSERT_TRUE(window_.attachedSheet);
  EXPECT_NE(window_.attachedSheet, old);
  Accept();
  Pump();
  EXPECT_EQ(os_.launches, 1);
}
TEST_F(NativeExternalProtocolTest, CompetingLeaseAtReleasePreventsLaunch) {
  Start();
  Pump();
  __block PCNativeWindowSecurityReservation* competing;
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (!PCNativeWindowHasSecurityReservation(window_) &&
                    !competing) {
                  competing = [PCNativeWindowSecurityReservation
                      acquireForWindow:window_];
                }
              }];
  Accept();
  Pump();
  EXPECT_EQ(os_.launches, 0);
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  [competing invalidate];
}
TEST_F(NativeExternalProtocolTest,
       PreferenceObserverNavigationPreventsOSLaunch) {
  PrefChangeRegistrar registrar;
  registrar.Init(profile()->GetPrefs());
  registrar.Add(prefs::kProtocolHandlerPerOriginAllowedProtocols,
                base::BindLambdaForTesting([&] {
                  content::NavigationSimulator::NavigateAndCommitFromBrowser(
                      contents(), GURL("https://replacement.example"));
                }));
  Start();
  Pump();
  Accept(true);
  Pump();
  EXPECT_EQ(os_.launches, 0);
}
TEST_F(NativeExternalProtocolTest, AcceptedContinuationMayDestroyOriginalPage) {
  os_.on_launch = base::BindLambdaForTesting([&] {
    os_.launched_page = nullptr;
    browser()->tab_strip_model()->CloseAllTabs();
  });
  Start();
  Pump();
  Accept();
  Pump();
  EXPECT_EQ(os_.launches, 1);
  EXPECT_EQ(browser()->tab_strip_model()->count(), 0);
}
TEST_F(NativeExternalProtocolTest, ExistingSchemePolicyRemainsAuthoritative) {
  ExternalProtocolHandler::PermitLaunchUrl();
  auto origin = url::Origin::Create(GURL("https://protocol.example"));
  EXPECT_EQ(ExternalProtocolHandler::GetBlockState("file", &origin, profile()),
            ExternalProtocolHandler::BLOCK);
  EXPECT_EQ(os_.launches, 0);
}
}  // namespace parc
namespace parc {
class NativeExternalProtocolProtectionTest : public views::ViewsTestBase {};
TEST_F(NativeExternalProtocolProtectionTest,
       NativeBoundsTrackActualFloatingWidgets) {
  PictureInPictureOcclusionTracker tracker;
  auto floating =
      CreateTestWidget(views::Widget::InitParams::CLIENT_OWNS_WIDGET);
  floating->SetBounds({0, 0, 200, 200});
  floating->Show();
  int changes = 0;
  auto subscription = tracker.ObserveNativeOccluderChanges(
      base::BindLambdaForTesting([&] { ++changes; }));
  EXPECT_FALSE(tracker.IsNativeRectangleOccluded({50, 50, 40, 40}));
  tracker.OnPictureInPictureWidgetOpened(floating.get());
  EXPECT_TRUE(tracker.IsNativeRectangleOccluded({50, 50, 40, 40}));
  EXPECT_FALSE(tracker.IsNativeRectangleOccluded({300, 300, 40, 40}));
  floating->Hide();
  EXPECT_FALSE(tracker.IsNativeRectangleOccluded({50, 50, 40, 40}));
  floating->Show();
  EXPECT_TRUE(tracker.IsNativeRectangleOccluded({50, 50, 40, 40}));
  floating->CloseNow();
  EXPECT_FALSE(tracker.IsNativeRectangleOccluded({50, 50, 40, 40}));
  EXPECT_GE(changes, 4);
}
TEST_F(NativeExternalProtocolProtectionTest,
       NativeObserverCanReleaseOwnSubscription) {
  PictureInPictureOcclusionTracker tracker;
  auto floating =
      CreateTestWidget(views::Widget::InitParams::CLIENT_OWNS_WIDGET);
  int changes = 0;
  base::CallbackListSubscription subscription;
  subscription =
      tracker.ObserveNativeOccluderChanges(base::BindLambdaForTesting([&] {
        ++changes;
        subscription = {};
      }));
  tracker.OnPictureInPictureWidgetOpened(floating.get());
  floating->Show();
  floating->CloseNow();
  EXPECT_EQ(changes, 1);
}
TEST_F(NativeExternalProtocolProtectionTest,
       RealProtectorBlocksImmediateAndRepeatedKeys) {
  views::InputEventActivationProtector protector;
  protector.VisibilityChanged(true);
  ui::KeyEvent immediate(ui::EventType::kKeyPressed, ui::VKEY_RETURN, 0,
                         base::TimeTicks::Now());
  EXPECT_TRUE(protector.IsPossiblyUnintendedInteraction(immediate, false));
  ui::KeyEvent later(ui::EventType::kKeyPressed, ui::VKEY_RETURN, 0,
                     base::TimeTicks::Now() + protector.cooldown_interval() +
                         base::Milliseconds(1));
  EXPECT_FALSE(protector.IsPossiblyUnintendedInteraction(later, false));
  EXPECT_TRUE(protector.IsPossiblyUnintendedInteraction(later, false));
  protector.MaybeUpdateViewProtectedTimeStamp(true);
  ui::KeyEvent reveal(ui::EventType::kKeyPressed, ui::VKEY_RETURN, 0,
                      base::TimeTicks::Now());
  EXPECT_TRUE(protector.IsPossiblyUnintendedInteraction(reveal, false));
}
}  // namespace parc
