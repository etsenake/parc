// Copyright 2026 Parc contributors.
#import <AppKit/AppKit.h>
#include <memory>
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "base/run_loop.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/test/bind.h"
#include "base/test/run_until.h"
#include "base/threading/thread_restrictions.h"
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "chrome/browser/extensions/extension_action_test_util.h"
#include "chrome/browser/extensions/test_extension_system.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/color/chrome_color_id.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "chrome/test/base/testing_profile.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/navigation_simulator.h"
#include "extension_action_bridge.h"
#include "extension_action_container.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/permissions/active_tab_permission_granter.h"
#include "extensions/browser/unloaded_extension_reason.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_builder.h"
#include "parc/tests/parc_native_test_support/browser_window_test.h"
#include "testing/gtest_mac.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/color/color_provider.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/color_utils.h"

namespace parc {
namespace {
class ActionHost final : public NativeExtensionActionHost {
 public:
  NSWindow* PopupParentWindow() const override { return nil; }
  PCExtensionPopupAnchor* PopupAnchor() const override { return nil; }
  bool IsSelectedBrowser() const override { return selected; }
  bool HasVisibleBrowserSecurityUI() const override { return security; }
  bool HandlePopupMenuKey(content::WebContents*,
                          const input::NativeWebKeyboardEvent&) override {
    return false;
  }
  bool InspectPopup(content::WebContents*) override { return false; }
  bool ShowActionContextMenu(ExtensionActionViewModel& value,
                             id<PCNativeMenuPresenter>) override {
    ++context_calls;
    last_context = value.GetId();
    if (on_context)
      on_context.Run();
    return true;
  }
  void CloseExtensionsMenu() override {}
  bool ToggleExtensionsMenu() override { return false; }
  void ExtensionActionsChanged() override {
    if (bridge)
      bridge->Changed();
  }
  void ExtensionCapabilityUnavailable(const std::string&,
                                      const char*) override {}
  NativeExtensionActionBridge* bridge = nullptr;
  bool selected = true;
  bool security = false;
  int context_calls = 0;
  std::string last_context;
  base::RepeatingClosure on_context;
};
}
class NativeExtensionActionsTest : public ParcBrowserWindowTest,
                                   public ToolbarActionsModel::Observer {
 protected:
  void SetUp() override {
    ParcBrowserWindowTest::SetUp();
    auto* system = static_cast<extensions::TestExtensionSystem*>(
        extensions::ExtensionSystem::Get(profile()));
    system->Init();
    model_ =
        extensions::extension_action_test_util::CreateToolbarModelForProfile(
            profile());
    ASSERT_TRUE(model_);
    ASSERT_EQ(nullptr, ExtensionsContainer::From(*browser()));
    container_ =
        std::make_unique<NativeExtensionActionContainer>(*browser(), host_);
    bridge_ = std::make_unique<NativeExtensionActionBridge>(
        *browser(), *container_,
        base::BindLambdaForTesting(
            [this](content::WebContents&) { return attached_; }),
        base::BindLambdaForTesting([this] { ++notifications_; }));
    host_.bridge = bridge_.get();
    AddTab(browser(), GURL("https://actions.test/first"));
    contents_ = browser()->GetTabStripModel()->GetActiveWebContents();
    extension_ = AddExtension("Action Alpha");
    base::RunLoop().RunUntilIdle();
    model_->AddObserver(this);
  }
  void TearDown() override {
    model_->RemoveObserver(this);
    pin_callback_.Reset();
    host_.on_context.Reset();
    host_.bridge = nullptr;
    if (bridge_) {
      bridge_->Shutdown(base::DoNothing());
      bridge_.reset();
    }
    if (container_) {
      container_->Shutdown();
      container_.reset();
    }
    base::RunLoop().RunUntilIdle();
    ParcBrowserWindowTest::TearDown();
  }
  scoped_refptr<const extensions::Extension> AddExtension(
      const std::string& name) {
    auto value = extensions::ExtensionBuilder(name)
                     .SetManifestVersion(3)
                     .SetAction(extensions::ActionInfo::Type::kAction)
                     .AddAPIPermission("activeTab")
                     .Build();
    extensions::ExtensionRegistrar::Get(profile())->AddExtension(value);
    return value;
  }
  scoped_refptr<const extensions::Extension> AddPreinstalledExtension(
      const std::string& name) {
    auto value =
        extensions::ExtensionBuilder(name)
            .SetManifestVersion(3)
            .SetLocation(extensions::mojom::ManifestLocation::kInternal)
            .AddFlags(extensions::Extension::WAS_INSTALLED_BY_DEFAULT)
            .Build();
    extensions::ExtensionRegistrar::Get(profile())->AddExtension(value);
    return value;
  }
  NSArray<PCNativeExtensionAction*>* Snapshot(
      content::WebContents* contents = nullptr) {
    return bridge_->Snapshot(*(contents ? contents : contents_), @"actual-page",
                             @"test-profile");
  }
  PCNativeExtensionAction* Value(const extensions::Extension& extension) {
    for (PCNativeExtensionAction* value in Snapshot()) {
      if ([value.identifier
              isEqualToString:base::SysUTF8ToNSString(extension.id())])
        return value;
    }
    return nil;
  }
  extensions::ExtensionAction* Action() {
    return extensions::ExtensionActionManager::Get(profile())
        ->GetExtensionAction(*extension_);
  }
  void NotifyAction() {
    extensions::ExtensionActionDispatcher::Get(profile())->NotifyChange(
        Action(), contents_, profile());
  }
  void OnToolbarActionAdded(const std::string&) override {}
  void OnToolbarActionRemoved(const std::string&) override {}
  void OnToolbarActionUpdated(const std::string&) override {}
  void OnToolbarModelInitialized() override {}
  void OnToolbarPinnedActionsChanged() override {
    if (pin_callback_)
      pin_callback_.Run();
  }
  ActionHost host_;
  std::unique_ptr<NativeExtensionActionContainer> container_;
  std::unique_ptr<NativeExtensionActionBridge> bridge_;
  scoped_refptr<const extensions::Extension> extension_;
  content::WebContents* contents_ = nullptr;
  ToolbarActionsModel* model_ = nullptr;
  bool attached_ = true;
  int notifications_ = 0;
  base::RepeatingClosure pin_callback_;
};
TEST_F(NativeExtensionActionsTest, RealMetadataBadgeAndPinOrder) {
  auto other = AddExtension("Action Beta");
  auto* action = Action();
  const int tab_id = sessions::SessionTabHelper::IdForTab(contents_).id();
  action->SetTitle(tab_id, "This actual tab");
  action->SetBadgeText(tab_id, "7");
  action->SetBadgeTextColor(tab_id, SK_ColorWHITE);
  action->SetBadgeBackgroundColor(tab_id, SK_ColorRED);
  NotifyAction();
  model_->SetActionVisibility(other->id(), true);
  model_->SetActionVisibility(extension_->id(), true);
  PCNativeExtensionAction* value = Value(*extension_);
  ASSERT_TRUE(value);
  EXPECT_NSEQ(@"Action Alpha", value.name);
  EXPECT_NSEQ(@"This actual tab", value.title);
  EXPECT_NSEQ(@"7", value.badgeText);
  EXPECT_NSEQ(@"actual-page", value.pageIdentifier);
  EXPECT_NSEQ(@"test-profile", value.profilePath);
  EXPECT_TRUE(value.icon);
  ASSERT_TRUE(value.iconWithoutBadge);
  EXPECT_TRUE(NSEqualSizes(NSMakeSize(32, 32), value.iconWithoutBadge.size));
  EXPECT_NSNE([value.icon TIFFRepresentation],
              [value.iconWithoutBadge TIFFRepresentation]);
  EXPECT_NSEQ([NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1],
              value.badgeTextColor);
  EXPECT_NSEQ([NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1],
              value.badgeBackgroundColor);
  EXPECT_TRUE(value.pinned);
  EXPECT_TRUE(value.canChangePin);
  const auto& pins = model_->pinned_action_ids();
  EXPECT_EQ(extension_->id(), pins.at(value.pinnedIndex));
  EXPECT_EQ(2u, Snapshot().count);
  EXPECT_NE(Value(*other).modelIndex, value.modelIndex);
}
TEST_F(NativeExtensionActionsTest, UnsetBadgeColorsResolveAsPainted) {
  const int tab_id = sessions::SessionTabHelper::IdForTab(contents_).id();
  Action()->SetBadgeText(tab_id, "3");
  NotifyAction();
  model_->SetActionVisibility(extension_->id(), true);
  PCNativeExtensionAction* value = Value(*extension_);
  ASSERT_TRUE(value);
  EXPECT_NSEQ(@"3", value.badgeText);
  ASSERT_TRUE(value.iconWithoutBadge);
  const SkColor background = contents_->GetColorProvider().GetColor(
      kColorExtensionIconBadgeBackgroundDefault);
  const auto native = [](SkColor color) {
    return [NSColor colorWithSRGBRed:SkColorGetR(color) / 255.0
                               green:SkColorGetG(color) / 255.0
                                blue:SkColorGetB(color) / 255.0
                               alpha:SkColorGetA(color) / 255.0];
  };
  EXPECT_EQ(SK_AlphaOPAQUE, SkColorGetA(background));
  EXPECT_NSEQ(native(background), value.badgeBackgroundColor);
  EXPECT_NSEQ(native(color_utils::GetColorWithMaxContrast(background)),
              value.badgeTextColor);
}
TEST_F(NativeExtensionActionsTest, NavigationRejectsOldSnapshot) {
  PCNativeExtensionAction* old = Value(*extension_);
  ASSERT_TRUE(old);
  content::NavigationSimulator::NavigateAndCommitFromBrowser(
      contents_, GURL("https://actions.test/second"));
  EXPECT_FALSE(bridge_->SetPinned(old, *contents_, true));
  PCNativeExtensionAction* fresh = Value(*extension_);
  ASSERT_TRUE(fresh);
  EXPECT_GT(fresh.generation, old.generation);
  EXPECT_TRUE(bridge_->SetPinned(fresh, *contents_, true));
}
TEST_F(NativeExtensionActionsTest, SelectionAndAttachmentRejectOldSnapshots) {
  PCNativeExtensionAction* old = Value(*extension_);
  ASSERT_TRUE(old);
  AddTab(browser(), GURL("https://actions.test/other"));
  EXPECT_FALSE(bridge_->Execute(old, *contents_));
  EXPECT_EQ(0u, Snapshot().count);
  browser()->GetTabStripModel()->ActivateTabAt(
      browser()->GetTabStripModel()->GetIndexOfWebContents(contents_));
  EXPECT_FALSE(bridge_->SetPinned(old, *contents_, true));
  PCNativeExtensionAction* current = Value(*extension_);
  ASSERT_TRUE(current);
  attached_ = false;
  bridge_->Changed();
  attached_ = true;
  EXPECT_FALSE(bridge_->SetPinned(current, *contents_, true));
  EXPECT_TRUE(bridge_->SetPinned(Value(*extension_), *contents_, true));
}
TEST_F(NativeExtensionActionsTest, UnloadReloadSameIDCannotReviveSnapshot) {
  PCNativeExtensionAction* old = Value(*extension_);
  ASSERT_TRUE(old);
  extensions::ExtensionRegistrar::Get(profile())->RemoveExtension(
      extension_->id(), extensions::UnloadedExtensionReason::DISABLE);
  EXPECT_FALSE(bridge_->SetPinned(old, *contents_, true));
  extensions::ExtensionRegistrar::Get(profile())->AddExtension(extension_);
  EXPECT_FALSE(bridge_->SetPinned(old, *contents_, true));
  ASSERT_TRUE(Value(*extension_));
  EXPECT_TRUE(bridge_->SetPinned(Value(*extension_), *contents_, true));
}
TEST_F(NativeExtensionActionsTest, DisabledActionUsesActualContextFallback) {
  auto hidden = extensions::ExtensionBuilder("Hidden action")
                    .SetManifestVersion(3)
                    .SetAction(extensions::ActionInfo::Type::kAction)
                    .Build();
  extensions::ExtensionRegistrar::Get(profile())->AddExtension(hidden);
  auto* action = extensions::ExtensionActionManager::Get(profile())
                     ->GetExtensionAction(*hidden);
  ASSERT_TRUE(action);
  action->SetIsVisible(sessions::SessionTabHelper::IdForTab(contents_).id(),
                       false);
  extensions::ExtensionActionDispatcher::Get(profile())->NotifyChange(
      action, contents_, profile());
  PCNativeExtensionAction* value = Value(*hidden);
  ASSERT_TRUE(value);
  EXPECT_FALSE(value.enabled);
  EXPECT_TRUE(bridge_->Execute(value, *contents_));
  EXPECT_EQ(1, host_.context_calls);
  EXPECT_EQ(hidden->id(), host_.last_context);
}
TEST_F(NativeExtensionActionsTest, UndeclaredActionGetsDisabledStandIn) {
  auto undeclared = extensions::ExtensionBuilder("Undeclared action")
                        .SetManifestVersion(3)
                        .Build();
  extensions::ExtensionRegistrar::Get(profile())->AddExtension(undeclared);
  EXPECT_EQ(2u, Snapshot().count);
  PCNativeExtensionAction* value = Value(*undeclared);
  ASSERT_TRUE(value);
  EXPECT_NSEQ(@"Undeclared action", value.name);
  EXPECT_FALSE(value.enabled);
  EXPECT_TRUE(bridge_->Execute(value, *contents_));
  EXPECT_EQ(1, host_.context_calls);
  EXPECT_EQ(undeclared->id(), host_.last_context);
}
TEST_F(NativeExtensionActionsTest, UserActionGrantsOnlyActualSelectedTab) {
  auto* first = contents_;
  AddTab(browser(), GURL("https://second.test/page"));
  auto* current = browser()->GetTabStripModel()->GetActiveWebContents();
  ASSERT_NE(first, current);
  auto* old_granter =
      extensions::ActiveTabPermissionGranter::FromWebContents(first);
  auto* current_granter =
      extensions::ActiveTabPermissionGranter::FromWebContents(current);
  ASSERT_TRUE(old_granter);
  ASSERT_TRUE(current_granter);
  EXPECT_FALSE(old_granter->IsGranted(extension_.get()));
  EXPECT_FALSE(current_granter->IsGranted(extension_.get()));
  NSArray<PCNativeExtensionAction*>* values = Snapshot(current);
  ASSERT_EQ(1u, values.count);
  EXPECT_TRUE(bridge_->Execute(values[0], *current));
  EXPECT_TRUE(current_granter->IsGranted(extension_.get()));
  EXPECT_FALSE(old_granter->IsGranted(extension_.get()));
}
TEST_F(NativeExtensionActionsTest, SecurityAndForeignSelectionRefuseDispatch) {
  PCNativeExtensionAction* value = Value(*extension_);
  ASSERT_TRUE(value);
  host_.security = true;
  EXPECT_FALSE(bridge_->Execute(value, *contents_));
  EXPECT_FALSE(bridge_->ShowContextMenu(value, *contents_));
  EXPECT_FALSE(bridge_->SetPinned(value, *contents_, true));
  host_.security = false;
  host_.selected = false;
  EXPECT_FALSE(bridge_->Execute(value, *contents_));
  EXPECT_EQ(0u, Snapshot().count);
}
TEST_F(NativeExtensionActionsTest, ShutdownWaitsForRealPinObserverStack) {
  model_->SetActionVisibility(extension_->id(), false);
  PCNativeExtensionAction* value = Value(*extension_);
  ASSERT_TRUE(value);
  bool ready = false;
  bool inside_observer = false;
  pin_callback_ = base::BindLambdaForTesting([&] {
    inside_observer = true;
    bridge_->Shutdown(base::BindLambdaForTesting([&] {
      EXPECT_FALSE(inside_observer);
      ready = true;
    }));
    base::RunLoop nested(base::RunLoop::Type::kNestableTasksAllowed);
    nested.RunUntilIdle();
    EXPECT_FALSE(ready);
    inside_observer = false;
  });
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindLambdaForTesting([&] {
        EXPECT_TRUE(bridge_->SetPinned(value, *contents_, true));
        EXPECT_FALSE(ready);
      }));
  base::RunLoop().RunUntilIdle();
  EXPECT_TRUE(ready);
  EXPECT_EQ(0u, Snapshot().count);
}
TEST_F(NativeExtensionActionsTest, RealChangesCoalesceAndSnapshotIsCopied) {
  PCNativeExtensionAction* old = Value(*extension_);
  ASSERT_TRUE(old);
  const int previous = notifications_;
  Action()->SetTitle(sessions::SessionTabHelper::IdForTab(contents_).id(),
                     "Updated");
  NotifyAction();
  NotifyAction();
  EXPECT_EQ(previous, notifications_);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(previous + 1, notifications_);
  EXPECT_FALSE([old.title isEqualToString:@"Updated"]);
  EXPECT_NSEQ(@"Updated", Value(*extension_).title);
}
TEST_F(NativeExtensionActionsTest, EnabledExtensionWithoutActionInvalidatesGate) {
  auto* registrar = extensions::ExtensionRegistrar::Get(profile());
  registrar->RemoveExtension(extension_->id(),
                             extensions::UnloadedExtensionReason::DISABLE);
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(bridge_->HasEnabledExtensions(*contents_));
  auto component = extensions::ExtensionBuilder("Internal component")
                       .SetManifestVersion(3)
                       .SetLocation(extensions::mojom::ManifestLocation::kComponent)
                       .Build();
  registrar->AddExtension(component);
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(bridge_->HasEnabledExtensions(*contents_));
  const int previous = notifications_;
  auto no_action = AddPreinstalledExtension("No action");
  EXPECT_TRUE(bridge_->HasEnabledExtensions(*contents_));
  EXPECT_EQ(0u, Snapshot().count);
  EXPECT_EQ(previous, notifications_);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(previous + 1, notifications_);
  attached_ = false;
  EXPECT_FALSE(bridge_->HasEnabledExtensions(*contents_));
  attached_ = true;
  registrar->RemoveExtension(no_action->id(),
                             extensions::UnloadedExtensionReason::DISABLE);
  EXPECT_FALSE(bridge_->HasEnabledExtensions(*contents_));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(previous + 2, notifications_);
}
TEST_F(NativeExtensionActionsTest, EnabledMetadataDoesNotInventActionsOrIcons) {
  auto* registrar = extensions::ExtensionRegistrar::Get(profile());
  auto no_action = AddPreinstalledExtension("No action");
  NSArray<PCNativeEnabledExtension*>* values = bridge_->EnabledSnapshot(*contents_);
  PCNativeEnabledExtension* absent_action = nil;
  PCNativeEnabledExtension* action = nil;
  for (PCNativeEnabledExtension* value in values) {
    if ([value.identifier isEqualToString:base::SysUTF8ToNSString(no_action->id())])
      absent_action = value;
    if ([value.identifier isEqualToString:base::SysUTF8ToNSString(extension_->id())])
      action = value;
  }
  ASSERT_TRUE(absent_action);
  ASSERT_TRUE(action);
  EXPECT_NSEQ(@"No action", absent_action.name);
  EXPECT_FALSE(Value(*no_action));
  EXPECT_FALSE(bridge_->ExecuteEnabled(absent_action, *contents_));
  EXPECT_FALSE(bridge_->ShowEnabledContextMenu(absent_action, *contents_));
  host_.security = true;
  EXPECT_FALSE(bridge_->ExecuteEnabled(action, *contents_));
  EXPECT_FALSE(bridge_->ShowEnabledContextMenu(action, *contents_));
  host_.security = false;
  registrar->RemoveExtension(no_action->id(), extensions::UnloadedExtensionReason::DISABLE);
  EXPECT_FALSE(bridge_->ExecuteEnabled(absent_action, *contents_));
  EXPECT_FALSE(bridge_->ShowEnabledContextMenu(action, *contents_));
  base::RunLoop().RunUntilIdle();
  for (PCNativeEnabledExtension* value in bridge_->EnabledSnapshot(*contents_))
    EXPECT_FALSE(value.icon);
}
TEST_F(NativeExtensionActionsTest, EnabledMetadataLoadsSmallManifestIconAndDispatches) {
  base::ScopedAllowBlockingForTesting allow_blocking;
  base::ScopedTempDir directory;
  ASSERT_TRUE(directory.CreateUniqueTempDir());
  SkBitmap bitmap;
  bitmap.allocN32Pixels(16, 16);
  bitmap.eraseColor(SK_ColorRED);
  auto png = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, false);
  ASSERT_TRUE(png);
  ASSERT_TRUE(base::WriteFile(directory.GetPath().AppendASCII("icon.png"), *png));
  auto small = extensions::ExtensionBuilder("Small icon")
                   .SetManifestVersion(3)
                   .SetManifestKey("icons", base::DictValue().Set("16", "icon.png"))
                   .SetPath(directory.GetPath())
                   .Build();
  extensions::ExtensionRegistrar::Get(profile())->AddExtension(small);
  bridge_->EnabledSnapshot(*contents_);
  PCNativeEnabledExtension* small_value = nil;
  ASSERT_TRUE(base::test::RunUntil([&] {
    for (PCNativeEnabledExtension* value in bridge_->EnabledSnapshot(*contents_))
      if ([value.identifier isEqualToString:base::SysUTF8ToNSString(small->id())])
        small_value = value;
    return small_value.icon != nil;
  }));
  EXPECT_TRUE(bridge_->ExecuteEnabled(small_value, *contents_));
  EXPECT_EQ(1, host_.context_calls);
  EXPECT_EQ(small->id(), host_.last_context);
  PCNativeEnabledExtension* action = nil;
  for (PCNativeEnabledExtension* value in bridge_->EnabledSnapshot(*contents_))
    if ([value.identifier isEqualToString:base::SysUTF8ToNSString(extension_->id())])
      action = value;
  ASSERT_TRUE(action);
  EXPECT_TRUE(bridge_->ShowEnabledContextMenu(action, *contents_));
  EXPECT_EQ(extension_->id(), host_.last_context);
  EXPECT_TRUE(bridge_->ExecuteEnabled(action, *contents_));
  content::NavigationSimulator::NavigateAndCommitFromBrowser(
      contents_, GURL("https://actions.test/next"));
  EXPECT_FALSE(bridge_->ExecuteEnabled(action, *contents_));
  EXPECT_FALSE(bridge_->ShowEnabledContextMenu(small_value, *contents_));
}
}
