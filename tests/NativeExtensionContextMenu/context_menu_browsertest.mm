// Copyright 2026 Parc contributors.
#import <AppKit/AppKit.h>

#include <memory>

#include "base/run_loop.h"
#include "base/strings/sys_string_conversions.h"
#include "base/test/bind.h"
#include "base/test/run_until.h"
#include "chrome/browser/extensions/extension_apitest.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/side_panel/side_panel_entry_key.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "chrome/grit/branded_strings.h"
#include "chrome/grit/generated_resources.h"
#include "chrome/test/base/test_browser_window.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/browser_test.h"
#include "content/public/test/browser_test_utils.h"
#include "extension_action_container.h"
#include "extension_context_menu.h"
#include "extension_side_panel.h"
#include "extensions/common/extension.h"
#include "net/test/embedded_test_server/embedded_test_server.h"
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
  bool ShowActionContextMenu(ExtensionActionViewModel&,
                             id<PCNativeMenuPresenter>) override {
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
}

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
    Dispatch(menu, remove);
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

class NativeSidePanelMenuBrowserTest
    : public NativeExtensionContextMenuBrowserTest,
      public NativeSidePanelHost {
 protected:
  void TearDownOnMainThread() override {
    if (side_presenter_) {
      side_presenter_->Cancel();
      side_presenter_.reset();
    }
    if (actions_) {
      actions_->Shutdown();
      actions_.reset();
    }
    if (panel_) {
      auto drained = std::make_shared<bool>(false);
      panel_->Shutdown(
          base::BindLambdaForTesting([drained] { *drained = true; }));
      EXPECT_TRUE(base::test::RunUntil([&] { return *drained; }));
      panel_.reset();
    }
    if (native_browser_) {
      native_browser_->GetTabStripModel()->CloseAllTabs();
      native_browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
      native_browser_.reset();
    }
    side_host_.reset();
    [window_ close];
    container_ = nil;
    window_ = nil;
    NativeExtensionContextMenuBrowserTest::TearDownOnMainThread();
  }
  void OpenWindow(BrowserWindowInterface::Type type) {
    ASSERT_TRUE(StartEmbeddedTestServer());
    window_ =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 900, 700)
                                    styleMask:NSWindowStyleMaskTitled
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    window_.releasedWhenClosed = NO;
    container_ = [[NSView alloc] initWithFrame:NSMakeRect(540, 0, 360, 700)];
    container_.hidden = YES;
    [window_.contentView addSubview:container_];
    [window_ makeKeyAndOrderFront:nil];
    auto* test_window = new TestBrowserWindow;
    test_window->SetNativeWindow(gfx::NativeWindow(window_));
    BrowserWindowCreateParams params(type, profile(), true);
    params.window = test_window;
    native_browser_ =
        DeprecatedCreateOwnedBrowserWindowForTesting(std::move(params));
    ASSERT_TRUE(native_browser_);
    native_browser_->GetTabStripModel()->AppendWebContents(
        content::WebContents::Create(
            content::WebContents::CreateParams(profile())),
        true);
    ASSERT_TRUE(content::NavigateToURL(
        native_browser_->GetTabStripModel()->GetActiveWebContents(),
        embedded_test_server()->GetURL("/title1.html")));
    panel_ =
        std::make_unique<NativeExtensionSidePanel>(*native_browser_, *this);
    side_host_ = std::make_unique<MenuHost>(window_);
    actions_ = std::make_unique<NativeExtensionActionContainer>(
        *native_browser_, *side_host_);
    side_presenter_ = std::make_unique<NativeExtensionContextMenu>(
        *native_browser_, *side_host_);
    side_fixture_.WriteManifest(
        R"({"name":"Parc side panel menu", "version":"1.0",
      "manifest_version":3,"action":{"default_popup":"popup.html"},
      "permissions":["sidePanel"],
      "side_panel":{"default_path":"panel.html"}})");
    side_fixture_.WriteFile(FILE_PATH_LITERAL("popup.html"),
                            "<!doctype html><title>Popup</title>");
    side_fixture_.WriteFile(FILE_PATH_LITERAL("panel.html"),
                            "<!doctype html><title>Panel</title>");
    side_extension_ = LoadExtension(side_fixture_.UnpackedPath());
    ASSERT_TRUE(side_extension_);
    side_model_ = static_cast<ExtensionActionViewModel*>(
        actions_->GetActionForId(side_extension_->id()));
    ASSERT_TRUE(side_model_);
  }
  SidePanelEntryKey Key() const {
    return SidePanelEntryKey(SidePanelEntryId::kExtension,
                             side_extension_->id());
  }
  bool PanelShowing() {
    return base::test::RunUntil(
        [&] { return panel_->IsSidePanelEntryShowing(Key(), false); });
  }
  NSWindow* SidePanelWindow() const override { return window_; }
  NSView* SidePanelContainer() const override { return container_; }
  bool IsSidePanelBrowserSelected() const override { return true; }
  bool SetSidePanelVisible(bool visible) override {
    container_.hidden = !visible;
    return container_.window == window_ && (!visible || window_.visible);
  }
  bool HandleSidePanelKey(content::WebContents*,
                          const input::NativeWebKeyboardEvent&) override {
    return false;
  }
  extensions::TestExtensionDir side_fixture_;
  scoped_refptr<const extensions::Extension> side_extension_;
  ExtensionActionViewModel* side_model_ = nullptr;
  NSWindow* __strong window_ = nil;
  NSView* __strong container_ = nil;
  std::unique_ptr<BrowserWindowInterface> native_browser_;
  std::unique_ptr<NativeExtensionSidePanel> panel_;
  std::unique_ptr<MenuHost> side_host_;
  std::unique_ptr<NativeExtensionActionContainer> actions_;
  std::unique_ptr<NativeExtensionContextMenu> side_presenter_;
};

IN_PROC_BROWSER_TEST_F(NativeSidePanelMenuBrowserTest,
                       OpenSidePanelCommandShowsNativePanel) {
  ASSERT_NO_FATAL_FAILURE(OpenWindow(BrowserWindowInterface::TYPE_NORMAL));
  WhenTracking(^(NSMenu* menu) {
    [menu update];
    NSMenuItem* open = Item(menu, IDS_EXTENSIONS_SUBMENU_OPEN_SIDE_PANEL_ITEM);
    ASSERT_TRUE(open);
    EXPECT_TRUE(open.enabled);
    EXPECT_EQ(open.toolTip.length, 0u);
    EXPECT_TRUE(
        [open.identifier isEqualToString:@"extension-menu:side-panel"]);
    Dispatch(menu, open);
  });
  EXPECT_TRUE(side_presenter_->Show(*side_model_));
  EXPECT_EQ(began_count_, 1);
  EXPECT_TRUE(PanelShowing());
}

IN_PROC_BROWSER_TEST_F(NativeSidePanelMenuBrowserTest,
                       CloseSidePanelCommandHidesNativePanel) {
  ASSERT_NO_FATAL_FAILURE(OpenWindow(BrowserWindowInterface::TYPE_NORMAL));
  panel_->Toggle(Key(), SidePanelOpenTrigger::kExtension);
  ASSERT_TRUE(PanelShowing());
  WhenTracking(^(NSMenu* menu) {
    [menu update];
    NSMenuItem* close =
        Item(menu, IDS_EXTENSIONS_SUBMENU_CLOSE_SIDE_PANEL_ITEM);
    ASSERT_TRUE(close);
    EXPECT_TRUE(close.enabled);
    Dispatch(menu, close);
  });
  EXPECT_TRUE(side_presenter_->Show(*side_model_));
  EXPECT_TRUE(
      base::test::RunUntil([&] { return !panel_->IsSidePanelShowing(); }));
}

IN_PROC_BROWSER_TEST_F(NativeSidePanelMenuBrowserTest,
                       LoadingSidePanelOffersCloseAndCloses) {
  ASSERT_NO_FATAL_FAILURE(OpenWindow(BrowserWindowInterface::TYPE_NORMAL));
  panel_->Toggle(Key(), SidePanelOpenTrigger::kExtension);
  ASSERT_TRUE(panel_->IsSidePanelEntryPending(Key(), false));
  ASSERT_FALSE(panel_->IsSidePanelEntryShowing(Key()));
  auto* loading = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(loading);
  content::WebContentsDestroyedWatcher destroyed(loading);
  WhenTracking(^(NSMenu* menu) {
    [menu update];
    EXPECT_FALSE(Item(menu, IDS_EXTENSIONS_SUBMENU_OPEN_SIDE_PANEL_ITEM));
    NSMenuItem* close =
        Item(menu, IDS_EXTENSIONS_SUBMENU_CLOSE_SIDE_PANEL_ITEM);
    ASSERT_TRUE(close);
    EXPECT_TRUE(close.enabled);
    EXPECT_TRUE(
        [close.identifier isEqualToString:@"extension-menu:side-panel"]);
    EXPECT_TRUE(panel_->IsSidePanelEntryPending(Key(), false));
    Dispatch(menu, close);
  });
  EXPECT_TRUE(side_presenter_->Show(*side_model_));
  EXPECT_EQ(began_count_, 1);
  EXPECT_FALSE(panel_->IsSidePanelEntryPending(Key(), false));
  EXPECT_FALSE(panel_->IsSidePanelEntryShowing(Key()));
  destroyed.Wait();
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_FALSE(panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
}

IN_PROC_BROWSER_TEST_F(NativeSidePanelMenuBrowserTest,
                       PopupWindowExplainsUnavailableSidePanel) {
  ASSERT_NO_FATAL_FAILURE(OpenWindow(BrowserWindowInterface::TYPE_POPUP));
  WhenTracking(^(NSMenu* menu) {
    [menu update];
    NSMenuItem* open = Item(menu, IDS_EXTENSIONS_SUBMENU_OPEN_SIDE_PANEL_ITEM);
    ASSERT_TRUE(open);
    EXPECT_FALSE(open.enabled);
    EXPECT_TRUE([open.toolTip
        isEqualToString:@"Side panels are not available in pop-up windows."]);
    Dispatch(menu, open);
  });
  EXPECT_TRUE(side_presenter_->Show(*side_model_));
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_FALSE(panel_->IsSidePanelEntryPending(Key(), false));
}
}
