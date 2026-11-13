#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "base/test/scoped_feature_list.h"
#include "base/time/time.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/features.h"
#include "components/permissions/permission_decision.h"
#include "components/permissions/permission_prompt_decision.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_request_data.h"
#include "components/permissions/permission_request_manager.h"
#include "components/permissions/request_type.h"
#include "content/public/browser/permission_controller.h"
#include "content/public/browser/permission_descriptor_util.h"
#include "content/public/browser/permission_request_description.h"
#include "content/public/browser/permission_result.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/navigation_simulator.h"
#include "parc/tests/parc_native_test_support/browser_window_test.h"
#include "site_permissions.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
using Manager = permissions::PermissionRequestManager;
using Type = permissions::RequestType;
using Decision = PermissionDecision;
struct Outcome {
  int calls = 0;
  bool finished = false;
  std::optional<Decision> decision;
  std::optional<GeolocationAccuracy> accuracy;
};
NSButton* Button(NSView* view, NSString* title) {
  if ([view isKindOfClass:NSButton.class] &&
      [static_cast<NSButton*>(view).title isEqual:title]) {
    return static_cast<NSButton*>(view);
  }
  for (NSView* child in view.subviews) {
    if (auto b = Button(child, title)) {
      return b;
    }
  }
  return nil;
}
NSPopUpButton* Accuracy(NSView* view) {
  if ([view isKindOfClass:NSPopUpButton.class]) {
    return static_cast<NSPopUpButton*>(view);
  }
  for (NSView* child in view.subviews) {
    if (auto p = Accuracy(child)) {
      return p;
    }
  }
  return nil;
}
template <typename F>
bool Pump(F predicate) {
  auto deadline = base::TimeTicks::Now() + base::Seconds(5);
  do {
    base::RunLoop().RunUntilIdle();
    if (predicate()) {
      return true;
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, .01, true);
  } while (base::TimeTicks::Now() < deadline);
  return predicate();
}
class NativePermissionWindow final : public TestBrowserWindow {
 public:
  explicit NativePermissionWindow(NSWindow* window) : window_(window) {}
  gfx::NativeWindow GetNativeWindow() const override {
    return gfx::NativeWindow(window_);
  }

 private:
  NSWindow* __weak window_;
};
}
class NativeSitePermissionTest : public ParcBrowserWindowTest {
 public:
  NativeSitePermissionTest() {
    features_.InitAndEnableFeature(
        content_settings::features::kApproximateGeolocationPermission);
  }
  void SetUp() override {
    ParcBrowserWindowTest::SetUp();
    ASSERT_FALSE(window()->AsBrowserView());
    AddTab(browser(), GURL("https://permission.example"));
    NSView* view = contents()->GetNativeView().GetNativeNSView();
    ASSERT_TRUE(view);
    view.frame = native_window_.contentView.bounds;
    [native_window_.contentView addSubview:view];
    contents()->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
    Manager::CreateForWebContents(contents());
    manager()->clear_permission_ui_selector_for_testing();
    manager()->set_enabled_app_level_notification_permission_for_testing(true);
    manager()->set_view_factory_for_testing(base::BindRepeating(
        [](NativeSitePermissionTest* self, content::WebContents* contents,
           permissions::PermissionPrompt::Delegate* delegate) {
          return CreateNativeSitePermissionPrompt(*contents, delegate,
                                                  &self->detach_);
        },
        base::Unretained(this)));
    manager()->DOMContentLoaded(nullptr);
    manager()->DocumentOnLoadCompletedInPrimaryMainFrame();
  }
  void TearDown() override {
    browser()->GetTabStripModel()->CloseAllTabs();
    EXPECT_TRUE(Pump([this] { return !Prompt(); }));
    ParcBrowserWindowTest::TearDown();
    [native_window_ close];
    native_window_ = nil;
  }

 protected:
  std::unique_ptr<BrowserWindow> CreateBrowserWindow() override {
    native_window_ = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(-2200, -2200, 640, 480)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    native_window_.releasedWhenClosed = NO;
    [native_window_ orderFront:nil];
    return std::make_unique<NativePermissionWindow>(native_window_);
  }
  content::WebContents* contents() {
    return browser()->GetTabStripModel()->GetActiveWebContents();
  }
  Manager* manager() { return Manager::FromWebContents(contents()); }
  Outcome& Add(
      Type type,
      std::optional<permissions::GeolocationPromptType> geo = std::nullopt) {
    outcomes_.push_back(std::make_unique<Outcome>());
    Outcome* outcome = outcomes_.back().get();
    auto data = std::make_unique<permissions::PermissionRequestData>(
        type, true, GURL("https://permission.example"));
    if (geo) {
      data->WithGeolocationPromptType(*geo);
    }
    auto request = std::make_unique<permissions::PermissionRequest>(
        std::move(data),
        base::BindRepeating(
            [](Outcome* out,
               const permissions::PermissionPromptDecision& decision,
               const permissions::PermissionRequestData&) {
              ++out->calls;
              out->decision = decision.overall_decision;
              if (auto* geo = std::get_if<GeolocationPromptOptions>(
                      &decision.prompt_options)) {
                out->accuracy = geo->selected_accuracy;
              }
            },
            base::Unretained(outcome)),
        base::BindOnce([](Outcome* out) { out->finished = true; },
                       base::Unretained(outcome)));
    manager()->AddRequest(contents()->GetPrimaryMainFrame(),
                          std::move(request));
    return *outcome;
  }
  NSWindow* Prompt() {
    for (NSWindow* child in native_window_.childWindows.reverseObjectEnumerator) {
      if (child.visible) {
        return child;
      }
    }
    return nil;
  }
  bool Sheet() {
    return Pump([this] { return Prompt() != nil; });
  }
  void Click(NSString* title) {
    NSButton* button = Button(Prompt().contentView, title);
    ASSERT_TRUE(button);
    [button performClick:nil];
  }
  base::RepeatingClosure detach_;
  NSWindow* __strong native_window_;
  std::optional<content::PermissionResult> controller_result_;

 private:
  base::test::ScopedFeatureList features_;
  std::vector<std::unique_ptr<Outcome>> outcomes_;
};

TEST_F(NativeSitePermissionTest,
       GenuineNotificationControllerPersistsOnlyUserAllow) {
  const GURL origin("https://permission.example");
  auto* settings = HostContentSettingsMapFactory::GetForProfile(profile());
  ASSERT_EQ(CONTENT_SETTING_ASK,
            settings->GetContentSetting(origin, origin,
                                        ContentSettingsType::NOTIFICATIONS));
  profile()->GetPermissionController()->RequestPermissionFromCurrentDocument(
      contents()->GetPrimaryMainFrame(),
      content::PermissionRequestDescription(
          content::PermissionDescriptorUtil::
              CreatePermissionDescriptorForPermissionType(
                  blink::PermissionType::NOTIFICATIONS),
          true),
      base::BindLambdaForTesting([this](content::PermissionResult result) {
        controller_result_ = std::move(result);
      }));
  ASSERT_TRUE(Sheet());
  EXPECT_FALSE(Button(Prompt().contentView, @"Allow This Time"));
  EXPECT_TRUE(Button(Prompt().contentView, @"Not Now"));
  EXPECT_EQ(CONTENT_SETTING_ASK,
            settings->GetContentSetting(origin, origin,
                                        ContentSettingsType::NOTIFICATIONS));
  Click(@"Allow");
  ASSERT_TRUE(Pump([this] { return controller_result_.has_value(); }));
  EXPECT_EQ(blink::mojom::PermissionStatus::GRANTED,
            controller_result_->status);
  EXPECT_EQ(CONTENT_SETTING_ALLOW,
            settings->GetContentSetting(origin, origin,
                                        ContentSettingsType::NOTIFICATIONS));
}
TEST_F(NativeSitePermissionTest, GroupedCameraAndMicUseBothActualRequests) {
  auto& camera = Add(Type::kCameraStream);
  auto& mic = Add(Type::kMicStream);
  ASSERT_TRUE(Sheet());
  ASSERT_EQ(2u, manager()->Requests().size());
  Click(@"Allow");
  ASSERT_TRUE(Pump([&] { return camera.calls > 0 && mic.calls > 0; }));
  EXPECT_EQ(Decision::kAllow, camera.decision);
  EXPECT_EQ(Decision::kAllow, mic.decision);
}
TEST_F(NativeSitePermissionTest, OldSheetCannotDecideReplacement) {
  auto& old = Add(Type::kCameraStream);
  ASSERT_TRUE(Sheet());
  NSButton* old_allow =
      Button(Prompt().contentView, @"Allow");
  ASSERT_TRUE(old_allow);
  manager()->Dismiss(std::monostate{});
  ASSERT_TRUE(Pump([&] { return !Prompt(); }));
  auto& next = Add(Type::kMicStream);
  ASSERT_TRUE(Sheet());
  [old_allow performClick:nil];
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(0, next.calls);
  EXPECT_EQ(Decision::kNone, old.decision);
  Click(@"Allow");
  ASSERT_TRUE(Pump([&] { return next.calls > 0; }));
  EXPECT_EQ(Decision::kAllow, next.decision);
}
TEST_F(NativeSitePermissionTest, AllowIsRealManagerDecision) {
  auto& result = Add(Type::kCameraStream);
  ASSERT_TRUE(Sheet());
  Click(@"Allow");
  ASSERT_TRUE(Pump([&] { return result.calls > 0; }));
  EXPECT_EQ(Decision::kAllow, result.decision);
  EXPECT_FALSE(result.accuracy);
}
TEST_F(NativeSitePermissionTest, AllowCarriesEngineAccuracySelection) {
  auto& result = Add(Type::kGeolocation,
                     permissions::GeolocationPromptType::kApproximateOrPrecise);
  ASSERT_TRUE(Sheet());
  EXPECT_FALSE(Accuracy(Prompt().contentView));
  const bool precise =
      manager()->GetInitialGeolocationAccuracySelection() ==
      GeolocationAccuracy::kPrecise;
  Click(@"Allow");
  ASSERT_TRUE(Pump([&] { return result.calls > 0; }));
  EXPECT_EQ(Decision::kAllow, result.decision);
  EXPECT_EQ(precise ? GeolocationAccuracy::kPrecise
                    : GeolocationAccuracy::kApproximate,
            result.accuracy);
}
TEST_F(NativeSitePermissionTest, ApproximateOnlyHasNoPreciseControl) {
  auto& result = Add(Type::kGeolocation,
                     permissions::GeolocationPromptType::kApproximateOnly);
  ASSERT_TRUE(Sheet());
  EXPECT_FALSE(Accuracy(Prompt().contentView));
  Click(@"Allow");
  ASSERT_TRUE(Pump([&] { return result.calls > 0; }));
  EXPECT_EQ(GeolocationAccuracy::kApproximate, result.accuracy);
}
TEST_F(NativeSitePermissionTest, UpgradeHasNoApproximateControl) {
  auto& result = Add(Type::kGeolocation,
                     permissions::GeolocationPromptType::kUpgradeToPrecise);
  ASSERT_TRUE(Sheet());
  EXPECT_FALSE(Accuracy(Prompt().contentView));
  Click(@"Allow");
  ASSERT_TRUE(Pump([&] { return result.calls > 0; }));
  EXPECT_EQ(GeolocationAccuracy::kPrecise, result.accuracy);
}
TEST_F(NativeSitePermissionTest, NotNowDismissesWithoutBlocking) {
  auto& camera = Add(Type::kCameraStream);
  ASSERT_TRUE(Sheet());
  EXPECT_FALSE(Button(Prompt().contentView, @"Block"));
  Click(@"Not Now");
  ASSERT_TRUE(Pump([&] { return camera.calls > 0; }));
  EXPECT_EQ(Decision::kNone, camera.decision);
  ASSERT_TRUE(Pump([&] { return !Prompt(); }));
  auto& dismissed = Add(Type::kMicStream);
  ASSERT_TRUE(Sheet());
  Click(@"Not Now");
  ASSERT_TRUE(Pump([&] { return dismissed.calls > 0; }));
  EXPECT_EQ(Decision::kNone, dismissed.decision);
}
TEST_F(NativeSitePermissionTest, NavigationAfterClickCannotGrantOldDocument) {
  auto& result = Add(Type::kCameraStream);
  ASSERT_TRUE(Sheet());
  Click(@"Allow");
  content::NavigationSimulator::NavigateAndCommitFromBrowser(
      contents(), GURL("https://other.example"));
  ASSERT_TRUE(Pump([&] { return result.finished; }));
  EXPECT_TRUE(!result.decision || result.decision == Decision::kNone);
  EXPECT_TRUE(Pump([&] { return !Prompt(); }));
}
TEST_F(NativeSitePermissionTest, HiddenWindowNeverPresentsOrGrants) {
  [native_window_ orderOut:nil];
  auto& result = Add(Type::kCameraStream);
  ASSERT_TRUE(Pump([&] { return result.calls > 0; }));
  EXPECT_EQ(Decision::kNone, result.decision);
  EXPECT_TRUE(Pump([&] { return !Prompt(); }));
}
TEST_F(NativeSitePermissionTest,
       NativeDetachImmediatelyRetiresSheetAndOldCallbackIsInert) {
  auto& old = Add(Type::kCameraStream);
  ASSERT_TRUE(Sheet());
  auto old_detach = detach_;
  ASSERT_TRUE(old_detach);
  old_detach.Run();
  EXPECT_TRUE(Pump([&] { return !Prompt(); }));
  ASSERT_TRUE(Pump([&] { return old.calls > 0; }));
  EXPECT_EQ(Decision::kNone, old.decision);
  auto& next = Add(Type::kMicStream);
  ASSERT_TRUE(Sheet());
  old_detach.Run();
  base::RunLoop().RunUntilIdle();
  EXPECT_TRUE(Prompt());
  EXPECT_EQ(0, next.calls);
  Click(@"Allow");
  ASSERT_TRUE(Pump([&] { return next.calls > 0; }));
  EXPECT_EQ(Decision::kAllow, next.decision);
}
TEST_F(NativeSitePermissionTest, TeardownRetiresActualSheet) {
  auto& result = Add(Type::kCameraStream);
  ASSERT_TRUE(Sheet());
  browser()->GetTabStripModel()->CloseAllTabs();
  ASSERT_TRUE(Pump([&] { return !Prompt(); }));
  EXPECT_TRUE(result.finished);
  EXPECT_TRUE(!result.decision || result.decision == Decision::kNone);
}
TEST_F(NativeSitePermissionTest, CompetingLeaseWhilePresentedCannotGrant) {
  auto& outcome = Add(Type::kCameraStream);
  ASSERT_TRUE(Sheet());
  auto* other =
      [PCNativeWindowSecurityReservation acquireForWindow:native_window_];
  Click(@"Allow");
  ASSERT_TRUE(Pump([&] { return outcome.calls > 0; }));
  EXPECT_EQ(Decision::kNone, outcome.decision);
  EXPECT_TRUE(other.isOnlyReservation);
  [other invalidate];
}
TEST_F(NativeSitePermissionTest,
       GenuineControllerReleaseReentryCannotPersistGrant) {
  const GURL origin("https://permission.example");
  auto* settings = HostContentSettingsMapFactory::GetForProfile(profile());
  ASSERT_EQ(CONTENT_SETTING_ASK,
            settings->GetContentSetting(origin, origin,
                                        ContentSettingsType::NOTIFICATIONS));
  profile()->GetPermissionController()->RequestPermissionFromCurrentDocument(
      contents()->GetPrimaryMainFrame(),
      content::PermissionRequestDescription(
          content::PermissionDescriptorUtil::
              CreatePermissionDescriptorForPermissionType(
                  blink::PermissionType::NOTIFICATIONS),
          true),
      base::BindLambdaForTesting([this](content::PermissionResult result) {
        controller_result_ = std::move(result);
      }));
  ASSERT_TRUE(Sheet());
  __block PCNativeWindowSecurityReservation* replacement = nil;
  id observer = [NSNotificationCenter.defaultCenter
      addObserverForName:PCNativeWindowSecurityStateChanged
                  object:native_window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (!PCNativeWindowHasSecurityReservation(native_window_) &&
                    !replacement) {
                  replacement = [PCNativeWindowSecurityReservation
                      acquireForWindow:native_window_];
                }
              }];
  Click(@"Allow");
  const bool finished = Pump([this] { return controller_result_.has_value(); });
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  EXPECT_TRUE(replacement.isOnlyReservation);
  [replacement invalidate];
  ASSERT_TRUE(finished);
  EXPECT_NE(blink::mojom::PermissionStatus::GRANTED,
            controller_result_->status);
  EXPECT_EQ(CONTENT_SETTING_ASK,
            settings->GetContentSetting(origin, origin,
                                        ContentSettingsType::NOTIFICATIONS));
}
}
