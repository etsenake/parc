// Copyright 2026 Parc contributors.
// Actual action models, MenuControllerCocoa and NSMenu tracking/dispatch.
// These are linked browser tests, not a parallel menu-model implementation.
#import <AppKit/AppKit.h>

#include <memory>

#include "base/run_loop.h"
#include "base/strings/sys_string_conversions.h"
#include "base/test/bind.h"
#include "chrome/browser/extensions/extension_apitest.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "chrome/grit/branded_strings.h"
#include "chrome/grit/generated_resources.h"
#include "content/public/test/browser_test.h"
#include "extension_action_container.h"
#include "extension_context_menu.h"
#include "extensions/common/extension.h"
#include "extensions/test/test_extension_dir.h"
#include "ui/base/base_window.h"
#include "ui/base/l10n/l10n_util.h"

namespace parc {
namespace {
class MenuHost final : public NativeExtensionActionHost {
 public:
  explicit MenuHost(NSWindow* window) : window_(window) {}
  NSWindow* PopupParentWindow() const override { return window_; }
  PCExtensionPopupAnchor* PopupAnchor() const override { return nil; }
  bool IsSelectedBrowser() const override { return selected; }
  bool HasVisibleBrowserSecurityUI() const override { return security; }
  bool HandlePopupMenuKey(content::WebContents*,
                          const input::NativeWebKeyboardEvent&) override {
    return false;
  }
  bool InspectPopup(content::WebContents*) override { return false; }
  bool ShowActionContextMenu(ExtensionActionViewModel&) override {
    return false;
  }
  void CloseExtensionsMenu() override {}
  bool ToggleExtensionsMenu() override { return false; }
  void ExtensionActionsChanged() override {}
  void ExtensionCapabilityUnavailable(const std::string&,
                                      const char*) override {}
  bool selected = true;
  bool security = false;

 private:
  NSWindow* __weak window_;
};
}  // namespace

class NativeExtensionContextMenuBrowserTest
    : public extensions::ExtensionApiTest,
      public ToolbarActionsModel::Observer {
 protected:
  void SetUpOnMainThread() override {
    extensions::ExtensionApiTest::SetUpOnMainThread();
    browser()->GetWindow()->Show();
    host_ = std::make_unique<MenuHost>(
        browser()->GetWindow()->GetNativeWindow().GetNativeNSWindow());
    presenter_ =
        std::make_unique<NativeExtensionContextMenu>(*browser(), *host_);
    fixture_.WriteManifest(
        R"({"name":"Parc native action menu", "version":"1.0",
      "manifest_version":3,"action":{}})");
    extension_ = LoadExtension(fixture_.UnpackedPath());
    ASSERT_TRUE(extension_);
    auto* container = ExtensionsContainer::From(*browser());
    ASSERT_TRUE(container);
    model_ = static_cast<ExtensionActionViewModel*>(
        container->GetActionForId(extension_->id()));
    ASSERT_TRUE(model_);
    toolbar_ = ToolbarActionsModel::Get(browser()->GetProfile());
    if (toolbar_->IsActionPinned(extension_->id())) {
      toolbar_->SetActionVisibility(extension_->id(), false);
    }
  }
  void TearDownOnMainThread() override {
    if (presenter_) {
      presenter_->Cancel();
    }
    if (observing_pins_) {
      toolbar_->RemoveObserver(this);
      observing_pins_ = false;
    }
    pin_changed_ = nil;
    [timer_ invalidate];
    timer_ = nil;
    if (began_) {
      [NSNotificationCenter.defaultCenter removeObserver:began_];
    }
    began_ = nil;
    command_ = nil;
    presenter_.reset();
    host_.reset();
    base::RunLoop().RunUntilIdle();
    extensions::ExtensionApiTest::TearDownOnMainThread();
  }
  // Keep every callback observation on the fixture. A failed assertion cannot
  // leave an AppKit callback referring to expired test-body locals.
  void WhenTracking(void (^command)(NSMenu*)) {
    command_ = [command copy];
    began_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSMenuDidBeginTrackingNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification* note) {
                  if (timer_) {
                    return;
                  }
                  ++began_count_;
                  NSMenu* menu = note.object;
                  timer_ = [NSTimer
                      timerWithTimeInterval:0.01
                                    repeats:NO
                                      block:^(NSTimer*) {
                                        command_(menu);
                                        [menu cancelTrackingWithoutAnimation];
                                      }];
                  [NSRunLoop.currentRunLoop
                      addTimer:timer_
                       forMode:NSEventTrackingRunLoopMode];
                }];
  }
  NSMenuItem* Item(NSMenu* menu, int label) {
    NSString* title =
        base::SysUTF16ToNSString(l10n_util::GetStringUTF16(label));
    return [menu itemWithTitle:title];
  }
  void Dispatch(NSMenu* menu, NSMenuItem* item) {
    ASSERT_TRUE(item);
    // Go through AppKit's actual target/action, which reaches the production
    // guard and original MenuControllerCocoa -> real model ActivatedAt.
    [menu performActionForItemAtIndex:[menu indexOfItem:item]];
  }
  void WhenPinChanges(void (^command)(void)) {
    pin_changed_ = [command copy];
    toolbar_->AddObserver(this);
    observing_pins_ = true;
  }
  void OnToolbarActionAdded(const std::string&) override {}
  void OnToolbarActionRemoved(const std::string&) override {}
  void OnToolbarActionUpdated(const std::string&) override {}
  void OnToolbarModelInitialized() override {}
  void OnToolbarPinnedActionsChanged() override {
    ++pin_change_count_;
    if (pin_changed_) {
      pin_changed_();
    }
  }
  extensions::TestExtensionDir fixture_;
  scoped_refptr<const extensions::Extension> extension_;
  ExtensionActionViewModel* model_ = nullptr;
  ToolbarActionsModel* toolbar_ = nullptr;
  std::unique_ptr<MenuHost> host_;
  std::unique_ptr<NativeExtensionContextMenu> presenter_;
  id __strong began_;
  NSTimer* __strong timer_;
  void (^__strong command_)(NSMenu*);
  void (^__strong pin_changed_)(void);
  bool observing_pins_ = false;
  int drain_count_ = 0;
  bool show_returned_ = false;
  int pin_change_count_ = 0;
  int began_count_ = 0;
  bool nested_result_ = true;
};

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       ActualPinCommand) {
  WhenTracking(^(NSMenu* menu) {
    [menu update];
    NSMenuItem* pin = Item(menu, IDS_EXTENSIONS_PIN_TO_TOOLBAR);
    ASSERT_TRUE(pin);
    EXPECT_TRUE(pin.enabled);
    Dispatch(menu, pin);
  });
  EXPECT_TRUE(presenter_->Show(*model_));
  EXPECT_EQ(began_count_, 1);
  EXPECT_TRUE(toolbar_->IsActionPinned(extension_->id()));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       CancelDoesNotPin) {
  WhenTracking(^(NSMenu*) {
    presenter_->Cancel();
  });
  EXPECT_TRUE(presenter_->Show(*model_));
  EXPECT_FALSE(toolbar_->IsActionPinned(extension_->id()));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       RejectsReentrantShow) {
  WhenTracking(^(NSMenu* menu) {
    nested_result_ = presenter_->Show(*model_);
    Dispatch(menu, Item(menu, IDS_EXTENSIONS_PIN_TO_TOOLBAR));
  });
  EXPECT_TRUE(presenter_->Show(*model_));
  EXPECT_FALSE(nested_result_);
  EXPECT_TRUE(toolbar_->IsActionPinned(extension_->id()));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       CancelDuringPinRejectsReentrantShow) {
  // SetActionVisibility notifies synchronously, before ExecuteCommand finishes
  // using the original context-menu model for metrics. Reentry must not replace
  // that model even though tracking has been cancelled.
  WhenPinChanges(^{
    presenter_->Cancel();
    nested_result_ = presenter_->Show(*model_);
  });
  WhenTracking(^(NSMenu* menu) {
    Dispatch(menu, Item(menu, IDS_EXTENSIONS_PIN_TO_TOOLBAR));
  });
  EXPECT_TRUE(presenter_->Show(*model_));
  EXPECT_EQ(pin_change_count_, 1);
  EXPECT_FALSE(nested_result_);
  EXPECT_TRUE(toolbar_->IsActionPinned(extension_->id()));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       ReplacementPresenterCannotReplaceExecutingModel) {
  WhenPinChanges(^{
    presenter_.reset();
    presenter_ =
        std::make_unique<NativeExtensionContextMenu>(*browser(), *host_);
    nested_result_ = presenter_->Show(*model_);
  });
  WhenTracking(^(NSMenu* menu) {
    Dispatch(menu, Item(menu, IDS_EXTENSIONS_PIN_TO_TOOLBAR));
  });
  auto* original = presenter_.get();
  EXPECT_TRUE(original->Show(*model_));
  EXPECT_EQ(pin_change_count_, 1);
  EXPECT_FALSE(nested_result_);
  EXPECT_TRUE(toolbar_->IsActionPinned(extension_->id()));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       StaleRebuiltModelCannotDispatch) {
  WhenTracking(^(NSMenu* menu) {
    model_->GetContextMenu(extensions::ExtensionContextMenuModel::
                               ContextMenuSource::kToolbarAction);
    Dispatch(menu, Item(menu, IDS_EXTENSIONS_PIN_TO_TOOLBAR));
  });
  EXPECT_TRUE(presenter_->Show(*model_));
  EXPECT_FALSE(toolbar_->IsActionPinned(extension_->id()));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       PresenterDestructionDuringTracking) {
  WhenTracking(^(NSMenu* menu) {
    presenter_.reset();
    Dispatch(menu, Item(menu, IDS_EXTENSIONS_PIN_TO_TOOLBAR));
  });
  auto* original = presenter_.get();
  EXPECT_TRUE(original->Show(*model_));
  EXPECT_FALSE(toolbar_->IsActionPinned(extension_->id()));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       ActivePageChangeCancels) {
  WhenTracking(^(NSMenu* menu) {
    auto* tabs = TabListInterface::From(browser());
    tabs->OpenTab(GURL("about:blank"), tabs->GetTabCount(), true);
    Dispatch(menu, Item(menu, IDS_EXTENSIONS_PIN_TO_TOOLBAR));
  });
  EXPECT_TRUE(presenter_->Show(*model_));
  EXPECT_FALSE(toolbar_->IsActionPinned(extension_->id()));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       SecurityTransitionCancels) {
  WhenTracking(^(NSMenu* menu) {
    host_->security = true;
    presenter_->HostStateChanged();
    Dispatch(menu, Item(menu, IDS_EXTENSIONS_PIN_TO_TOOLBAR));
  });
  EXPECT_TRUE(presenter_->Show(*model_));
  EXPECT_FALSE(toolbar_->IsActionPinned(extension_->id()));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       UninstallIsTruthfullyUnavailable) {
  WhenTracking(^(NSMenu* menu) {
    [menu update];
    NSMenuItem* remove = Item(menu, IDS_EXTENSIONS_UNINSTALL);
    ASSERT_TRUE(remove);
    EXPECT_FALSE(remove.enabled);
    EXPECT_GT(remove.toolTip.length, 0u);
    Dispatch(menu, remove);  // A programmatic stale action is guarded too.
  });
  EXPECT_TRUE(presenter_->Show(*model_));
  EXPECT_TRUE(model_->GetExtension());
}
IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       DrainAfterActualPinDispatchAndPresenterDestruction) {
  WhenPinChanges(^{
    presenter_->CancelAndWait(base::BindLambdaForTesting([this] {
      EXPECT_TRUE(show_returned_);
      EXPECT_EQ(pin_change_count_, 1);
      EXPECT_TRUE(toolbar_->IsActionPinned(extension_->id()));
      ++drain_count_;
    }));
    EXPECT_EQ(drain_count_, 0);
    presenter_.reset();
  });
  WhenTracking(^(NSMenu* menu) {
    Dispatch(menu, Item(menu, IDS_EXTENSIONS_PIN_TO_TOOLBAR));
  });
  auto* original = presenter_.get();
  EXPECT_TRUE(original->Show(*model_));
  show_returned_ = true;
  EXPECT_EQ(drain_count_, 0);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(drain_count_, 1);
}
IN_PROC_BROWSER_TEST_F(NativeExtensionContextMenuBrowserTest,
                       IdleDrainIsPostedAndPermanentlyRefusesTracking) {
  presenter_->CancelAndWait(
      base::BindLambdaForTesting([this] { ++drain_count_; }));
  presenter_->CancelAndWait(
      base::BindLambdaForTesting([this] { ++drain_count_; }));
  EXPECT_EQ(drain_count_, 0);
  EXPECT_FALSE(presenter_->Show(*model_));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(drain_count_, 2);
}
}  // namespace parc
