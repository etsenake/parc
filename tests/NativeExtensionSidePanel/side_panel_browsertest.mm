// Copyright 2026 Parc contributors.
#include "extension_side_panel.h"

#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/run_loop.h"
#include "base/test/bind.h"
#include "base/test/run_until.h"
#include "chrome/browser/extensions/api/side_panel/side_panel_service.h"
#include "chrome/browser/extensions/extension_apitest.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/side_panel/side_panel_entry.h"
#include "chrome/browser/ui/side_panel/side_panel_registry.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/common/extensions/api/side_panel.h"
#include "chrome/test/base/test_browser_window.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/test/browser_test.h"
#include "content/public/test/browser_test_utils.h"
#include "extensions/common/extension.h"
#include "extensions/test/test_extension_dir.h"

namespace parc {
class NativeSidePanelBrowserTest : public extensions::ExtensionApiTest,
                                   public NativeSidePanelHost {
 protected:
  void SetUpOnMainThread() override {
    extensions::ExtensionApiTest::SetUpOnMainThread();
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
    BrowserWindowCreateParams params(profile(), true);
    params.window = test_window;
    native_browser_ =
        DeprecatedCreateOwnedBrowserWindowForTesting(std::move(params));
    ASSERT_TRUE(native_browser_);
    ASSERT_FALSE(SidePanelUI::From(native_browser_.get()));
    AddPage();
    panel_ =
        std::make_unique<NativeExtensionSidePanel>(*native_browser_, *this);
    subscription_ = panel_->RegisterSidePanelShown(
        base::BindLambdaForTesting([this] { ++shown_; }));
  }
  struct SecondaryHost final : NativeSidePanelHost {
    NSWindow* __strong window = nil;
    NSView* __strong container = nil;
    std::unique_ptr<BrowserWindowInterface> browser;
    std::unique_ptr<NativeExtensionSidePanel> panel;
    NSWindow* SidePanelWindow() const override { return window; }
    NSView* SidePanelContainer() const override { return container; }
    bool IsSidePanelBrowserSelected() const override { return true; }
    bool SetSidePanelVisible(bool visible) override {
      container.hidden = !visible;
      return container.window == window && (!visible || window.visible);
    }
    bool HandleSidePanelKey(content::WebContents*,
                            const input::NativeWebKeyboardEvent&) override {
      return false;
    }
  };
  void MakeSecondary() {
    secondary_ = std::make_unique<SecondaryHost>();
    secondary_->window =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 900, 700)
                                    styleMask:NSWindowStyleMaskTitled
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    secondary_->window.releasedWhenClosed = NO;
    secondary_->container =
        [[NSView alloc] initWithFrame:NSMakeRect(540, 0, 360, 700)];
    secondary_->container.hidden = YES;
    [secondary_->window.contentView addSubview:secondary_->container];
    [secondary_->window makeKeyAndOrderFront:nil];
    auto* test_window = new TestBrowserWindow;
    test_window->SetNativeWindow(gfx::NativeWindow(secondary_->window));
    BrowserWindowCreateParams params(profile(), true);
    params.window = test_window;
    secondary_->browser =
        DeprecatedCreateOwnedBrowserWindowForTesting(std::move(params));
    secondary_->browser->GetTabStripModel()->AppendWebContents(
        content::WebContents::Create(
            content::WebContents::CreateParams(profile())),
        true);
    secondary_->panel = std::make_unique<NativeExtensionSidePanel>(
        *secondary_->browser, *secondary_);
  }
  void TearDownOnMainThread() override {
    if (secondary_) {
      auto drained = std::make_shared<bool>(false);
      secondary_->panel->Shutdown(
          base::BindLambdaForTesting([drained] { *drained = true; }));
      EXPECT_TRUE(base::test::RunUntil([&] { return *drained; }));
      secondary_->panel.reset();
      secondary_->browser->GetTabStripModel()->CloseAllTabs();
      secondary_->browser->GetFeatures().TearDownPreBrowserWindowDestruction();
      secondary_->browser.reset();
      [secondary_->window close];
      secondary_.reset();
    }
    Drain();
    subscription_ = {};
    panel_.reset();
    if (native_browser_) {
      native_browser_->GetTabStripModel()->CloseAllTabs();
      native_browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
      native_browser_.reset();
    }
    [window_ close];
    container_ = nil;
    window_ = nil;
    base::RunLoop().RunUntilIdle();
    extensions::ExtensionApiTest::TearDownOnMainThread();
  }
  NSWindow* SidePanelWindow() const override { return window_; }
  NSView* SidePanelContainer() const override { return container_; }
  bool IsSidePanelBrowserSelected() const override { return selected_; }
  bool SetSidePanelVisible(bool visible) override {
    container_.hidden = !visible;
    return container_.window == window_ && (!visible || window_.visible);
  }
  bool HandleSidePanelKey(content::WebContents*,
                          const input::NativeWebKeyboardEvent&) override {
    return false;
  }
  const extensions::Extension* LoadFixture() {
    fixture_.WriteManifest(R"({"manifest_version":3,"name":"Native panel",
      "version":"1.0","permissions":["sidePanel","tabs"],
      "side_panel":{"default_path":"global.html"}})");
    fixture_.WriteFile(FILE_PATH_LITERAL("global.html"),
                       "<!doctype html><title>Global</title><input id=field>");
    fixture_.WriteFile(
        FILE_PATH_LITERAL("tab.html"),
        "<!doctype html><title>Contextual</title><input id=field>");
    return LoadExtension(fixture_.UnpackedPath());
  }
  const extensions::Extension* LoadOther() {
    other_fixture_.WriteManifest(R"({"manifest_version":3,"name":"Other panel",
      "version":"1.0","permissions":["sidePanel"],
      "side_panel":{"default_path":"other.html"}})");
    other_fixture_.WriteFile(FILE_PATH_LITERAL("other.html"),
                             "<!doctype html><title>Other</title>");
    return LoadExtension(other_fixture_.UnpackedPath());
  }
  content::WebContents* AddPage() {
    auto contents = content::WebContents::Create(
        content::WebContents::CreateParams(profile()));
    auto* result = contents.get();
    native_browser_->GetTabStripModel()->AppendWebContents(std::move(contents),
                                                           true);
    return result;
  }
  extensions::SidePanelService* service() {
    return extensions::SidePanelService::Get(profile());
  }
  SidePanelEntryKey Key(const extensions::Extension* extension) {
    return SidePanelEntryKey(SidePanelEntryId::kExtension, extension->id());
  }
  int WindowId() {
    return extensions::ExtensionTabUtil::GetWindowId(native_browser_.get());
  }
  bool OpenGlobal(const extensions::Extension* extension) {
    auto result =
        service()->OpenSidePanelForWindow(*extension, profile(), WindowId(),
                                          false);
    return result.has_value() && result.value();
  }
  bool OpenTab(const extensions::Extension* extension,
               content::WebContents* page) {
    auto result = service()->OpenSidePanelForTab(
        *extension, profile(), extensions::ExtensionTabUtil::GetTabId(page),
        std::nullopt, false);
    return result.has_value() && result.value();
  }
  bool CloseWindowPanel(const extensions::Extension* extension) {
    auto result = service()->CloseSidePanelForWindow(*extension, profile(),
                                                     WindowId(), false);
    return result.has_value() && result.value();
  }
  bool CloseTabPanel(const extensions::Extension* extension,
                     content::WebContents* page) {
    auto result = service()->CloseSidePanelForTab(
        *extension, profile(), extensions::ExtensionTabUtil::GetTabId(page),
        std::nullopt, false);
    return result.has_value() && result.value();
  }
  void Contextual(const extensions::Extension* extension,
                  content::WebContents* page) {
    extensions::api::side_panel::PanelOptions options;
    options.tab_id = extensions::ExtensionTabUtil::GetTabId(page);
    options.path = "tab.html";
    options.enabled = true;
    service()->SetOptions(*extension, std::move(options));
  }
  bool WaitVisible() {
    return base::test::RunUntil([&] { return panel_->IsSidePanelShowing(); });
  }
  void Drain() {
    if (!panel_)
      return;
    auto drained = std::make_shared<bool>(false);
    panel_->Shutdown(
        base::BindLambdaForTesting([drained] { *drained = true; }));
    EXPECT_TRUE(base::test::RunUntil([&] { return *drained; }));
  }
  std::unique_ptr<SecondaryHost> secondary_;
  extensions::TestExtensionDir fixture_;
  extensions::TestExtensionDir other_fixture_;
  NSWindow* __strong window_ = nil;
  NSView* __strong container_ = nil;
  std::unique_ptr<BrowserWindowInterface> native_browser_;
  std::unique_ptr<NativeExtensionSidePanel> panel_;
  base::CallbackListSubscription subscription_;
  bool selected_ = true;
  int shown_ = 0;
};
class PanelDestructionObserver : public content::WebContentsObserver {
 public:
  explicit PanelDestructionObserver(content::WebContents* contents)
      : WebContentsObserver(contents) {}
  void WebContentsDestroyed() override { destroyed = true; }
  bool destroyed = false;
};
class FirstLoadStopObserver : public content::WebContentsObserver {
 public:
  FirstLoadStopObserver(content::WebContents* contents,
                        base::OnceClosure stopped)
      : WebContentsObserver(contents), stopped_(std::move(stopped)) {}
  void DidStopLoading() override {
    if (stopped_)
      std::move(stopped_).Run();
  }

 private:
  base::OnceClosure stopped_;
};

IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       RegisteredGlobalRouteUsesActualExtensionPage) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  ASSERT_EQ(panel_.get(), SidePanelUI::From(native_browser_.get()));
  ASSERT_TRUE(OpenGlobal(extension));
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_EQ(0, shown_);
  ASSERT_TRUE(WaitVisible());
  auto* contents = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(contents);
  EXPECT_EQ(profile(), contents->GetBrowserContext());
  EXPECT_EQ(extension->GetResourceURL("global.html"),
            contents->GetLastCommittedURL());
  EXPECT_EQ(window_, contents->GetNativeView().GetNativeNSView().window);
  EXPECT_TRUE(panel_->IsSidePanelEntryShowing(Key(extension), false));
  EXPECT_EQ(1, shown_);
  EXPECT_EQ(
      extensions::ExtensionTabUtil::GetWindowId(native_browser_.get()),
      content::EvalJs(contents, "chrome.windows.getCurrent().then(w=>w.id)"));
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       HiddenOrUnselectedOwnerCannotAcknowledgePresentation) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  [window_ orderOut:nil];
  ASSERT_TRUE(OpenGlobal(extension));
  EXPECT_FALSE(panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  [window_ orderFront:nil];
  selected_ = false;
  ASSERT_TRUE(OpenGlobal(extension));
  EXPECT_FALSE(panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_EQ(0, shown_);
}
IN_PROC_BROWSER_TEST_F(
    NativeSidePanelBrowserTest,
    BackgroundContextualOpenPreservesSelectionThenShowsCorrectPage) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto* first = native_browser_->GetTabStripModel()->GetActiveWebContents();
  auto* second = AddPage();
  Contextual(extension, first);
  auto result = service()->OpenSidePanelForTab(
      *extension, profile(), extensions::ExtensionTabUtil::GetTabId(first),
      std::nullopt, false);
  ASSERT_TRUE(result.has_value());
  EXPECT_EQ(second,
            native_browser_->GetTabStripModel()->GetActiveWebContents());
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  auto* registry = SidePanelRegistry::GetDeprecated(first);
  ASSERT_TRUE(registry->GetActiveEntry());
  native_browser_->GetTabStripModel()->ActivateTabAt(0);
  ASSERT_TRUE(WaitVisible());
  EXPECT_TRUE(panel_->IsSidePanelEntryShowing(Key(extension), true));
  EXPECT_EQ(extension->GetResourceURL("tab.html"),
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension)
                ->GetLastCommittedURL());
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       GlobalOpenDoesNotReplaceActiveContextualPanel) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto* first = native_browser_->GetTabStripModel()->GetActiveWebContents();
  Contextual(extension, first);
  auto result = service()->OpenSidePanelForTab(
      *extension, profile(), extensions::ExtensionTabUtil::GetTabId(first),
      std::nullopt, false);
  ASSERT_TRUE(result.has_value());
  ASSERT_TRUE(WaitVisible());
  auto* contextual_contents =
      panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(OpenGlobal(extension));
  EXPECT_EQ(contextual_contents,
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_TRUE(panel_->IsSidePanelEntryShowing(Key(extension), true));
  AddPage();
  ASSERT_TRUE(WaitVisible());
  EXPECT_TRUE(panel_->IsSidePanelEntryShowing(Key(extension), false));
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       UnloadCancelsPendingBeforeCoordinatorDisappears) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  const auto id = extension->id();
  ASSERT_TRUE(OpenGlobal(extension));
  auto* contents = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(contents);
  PanelDestructionObserver observer(contents);
  UnloadExtension(id);
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_FALSE(panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_TRUE(base::test::RunUntil([&] { return observer.destroyed; }));
  EXPECT_EQ(0, shown_);
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       PageWindowCloseUsesRealHostCloseHandler) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  ASSERT_TRUE(OpenGlobal(extension));
  ASSERT_TRUE(WaitVisible());
  auto* contents = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  PanelDestructionObserver observer(contents);
  EXPECT_TRUE(content::ExecJs(contents, "window.close()"));
  EXPECT_TRUE(base::test::RunUntil([&] { return observer.destroyed; }));
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_TRUE(container_.hidden);
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       RealServiceRejectsWrongWindowForTab) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto* page = native_browser_->GetTabStripModel()->GetActiveWebContents();
  auto result = service()->OpenSidePanelForTab(
      *extension, profile(), extensions::ExtensionTabUtil::GetTabId(page),
      extensions::ExtensionTabUtil::GetWindowId(browser()), false);
  EXPECT_FALSE(result.has_value());
  EXPECT_FALSE(panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
}
IN_PROC_BROWSER_TEST_F(
    NativeSidePanelBrowserTest,
    ShutdownDrainsActualHostBeforeBrowserAndProfileTeardown) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  ASSERT_TRUE(OpenGlobal(extension));
  auto* contents = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(contents);
  auto observer = std::make_shared<PanelDestructionObserver>(contents);
  auto drained = std::make_shared<bool>(false);
  panel_->Shutdown(base::BindLambdaForTesting([observer, drained] {
    EXPECT_TRUE(observer->destroyed);
    *drained = true;
  }));
  EXPECT_FALSE(*drained);
  EXPECT_FALSE(SidePanelUI::From(native_browser_.get()));
  EXPECT_TRUE(base::test::RunUntil([&] { return *drained; }));
  EXPECT_EQ(0, shown_);
}
IN_PROC_BROWSER_TEST_F(
    NativeSidePanelBrowserTest,
    SwitchingTabsRetainsTheExactContextualPageAndJavaScriptState) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto* first = native_browser_->GetTabStripModel()->GetActiveWebContents();
  Contextual(extension, first);
  auto result = service()->OpenSidePanelForTab(
      *extension, profile(), extensions::ExtensionTabUtil::GetTabId(first),
      std::nullopt, false);
  ASSERT_TRUE(result.has_value());
  ASSERT_TRUE(WaitVisible());
  auto* original = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(content::ExecJs(original, "window.nativePanelIdentity=137"));
  AddPage();
  ASSERT_TRUE(WaitVisible());
  EXPECT_TRUE(panel_->IsSidePanelEntryShowing(Key(extension), false));
  native_browser_->GetTabStripModel()->ActivateTabAt(0);
  ASSERT_TRUE(WaitVisible());
  EXPECT_EQ(original,
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_EQ(137, content::EvalJs(original, "window.nativePanelIdentity"));
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       ExplicitCloseDoesNotReopenGlobalOnTabChange) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  ASSERT_TRUE(OpenGlobal(extension));
  ASSERT_TRUE(WaitVisible());
  panel_->Close();
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(
      SidePanelRegistry::From(native_browser_.get())->GetActiveEntry());
  AddPage();
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_FALSE(panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
}
IN_PROC_BROWSER_TEST_F(
    NativeSidePanelBrowserTest,
    ReentrantShutdownFromShownWaitsForActualHostDestruction) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto drained = std::make_shared<bool>(false);
  std::shared_ptr<PanelDestructionObserver> destroyed;
  auto subscription =
      panel_->RegisterSidePanelShown(base::BindLambdaForTesting([&] {
        auto* contents =
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
        ASSERT_TRUE(contents);
        destroyed = std::make_shared<PanelDestructionObserver>(contents);
        panel_->Shutdown(base::BindLambdaForTesting([destroyed, drained] {
          EXPECT_TRUE(destroyed->destroyed);
          *drained = true;
        }));
        base::RunLoop().RunUntilIdle();
        EXPECT_FALSE(*drained);
        EXPECT_FALSE(destroyed->destroyed);
      }));
  ASSERT_TRUE(OpenGlobal(extension));
  EXPECT_TRUE(base::test::RunUntil([&] { return *drained; }));
  EXPECT_FALSE(SidePanelUI::From(native_browser_.get()));
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       MovingTabPreservesExactPanelAndUsesDestinationWindow) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto* page = native_browser_->GetTabStripModel()->GetActiveWebContents();
  Contextual(extension, page);
  auto result = service()->OpenSidePanelForTab(
      *extension, profile(), extensions::ExtensionTabUtil::GetTabId(page),
      std::nullopt, false);
  ASSERT_TRUE(result.has_value());
  ASSERT_TRUE(WaitVisible());
  auto* original = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(content::ExecJs(original, "window.nativePanelIdentity=281"));
  AddPage();
  native_browser_->GetTabStripModel()->ActivateTabAt(0);
  ASSERT_TRUE(WaitVisible());
  MakeSecondary();
  auto detached =
      native_browser_->GetTabStripModel()->DetachTabAtForInsertion(0);
  secondary_->browser->GetTabStripModel()->InsertDetachedTabAt(
      1, std::move(detached), AddTabTypes::ADD_ACTIVE);
  ASSERT_TRUE(base::test::RunUntil(
      [&] { return secondary_->panel->IsSidePanelShowing(); }));
  EXPECT_EQ(page,
            secondary_->browser->GetTabStripModel()->GetActiveWebContents());
  EXPECT_EQ(original, secondary_->panel->GetWebContentsForTest(
                          SidePanelEntryId::kExtension));
  EXPECT_EQ(281, content::EvalJs(original, "window.nativePanelIdentity"));
  EXPECT_EQ(secondary_->window,
            original->GetNativeView().GetNativeNSView().window);
  EXPECT_EQ(
      extensions::ExtensionTabUtil::GetWindowId(secondary_->browser.get()),
      content::EvalJs(original, "chrome.windows.getCurrent().then(w=>w.id)"));
  EXPECT_NE(original,
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       CloseRestoresActualPriorControlAndPreservesLaterFocus) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  NSTextField* prior =
      [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 200, 24)];
  NSTextField* later =
      [[NSTextField alloc] initWithFrame:NSMakeRect(20, 60, 200, 24)];
  [window_.contentView addSubview:prior];
  [window_.contentView addSubview:later];
  ASSERT_TRUE([window_ makeFirstResponder:prior]);
  ASSERT_TRUE(OpenGlobal(extension));
  ASSERT_TRUE(WaitVisible());
  auto* contents = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(
      content::ExecJs(contents, "document.querySelector('input').focus()"));
  auto focused_on = [&](NSView* view) {
    NSResponder* responder = window_.firstResponder;
    if ([responder isKindOfClass:NSTextView.class] &&
        [(NSTextView*)responder isFieldEditor])
      return (id)[(NSTextView*)responder delegate] == view;
    return responder == view;
  };
  panel_->Close();
  EXPECT_TRUE(focused_on(prior));
  ASSERT_TRUE(OpenGlobal(extension));
  ASSERT_TRUE(WaitVisible());
  ASSERT_TRUE([window_ makeFirstResponder:later]);
  panel_->Close();
  EXPECT_TRUE(focused_on(later));
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       EmptyTabListStillDrainsManagerAsynchronously) {
  native_browser_->GetTabStripModel()->CloseAllTabs();
  ASSERT_EQ(0, native_browser_->GetTabStripModel()->count());
  auto drained = std::make_shared<bool>(false);
  panel_->Shutdown(base::BindLambdaForTesting([drained] { *drained = true; }));
  EXPECT_FALSE(*drained);
  EXPECT_FALSE(SidePanelUI::From(native_browser_.get()));
  EXPECT_TRUE(base::test::RunUntil([&] { return *drained; }));
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       OptionsNavigateSameHostThenDisableClosesIt) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  ASSERT_TRUE(OpenGlobal(extension));
  ASSERT_TRUE(WaitVisible());
  auto* original = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  extensions::api::side_panel::PanelOptions changed;
  changed.path = "tab.html";
  changed.enabled = true;
  service()->SetOptions(*extension, std::move(changed));
  ASSERT_TRUE(content::WaitForLoadStop(original));
  EXPECT_EQ(original,
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_EQ(extension->GetResourceURL("tab.html"),
            original->GetLastCommittedURL());
  PanelDestructionObserver observer(original);
  extensions::api::side_panel::PanelOptions disabled;
  disabled.enabled = false;
  service()->SetOptions(*extension, std::move(disabled));
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_TRUE(base::test::RunUntil([&] { return observer.destroyed; }));
}
IN_PROC_BROWSER_TEST_F(
    NativeSidePanelBrowserTest,
    PendingContextualPageFinishesInBackgroundWithoutRecreation) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto* first = native_browser_->GetTabStripModel()->GetActiveWebContents();
  Contextual(extension, first);
  auto result = service()->OpenSidePanelForTab(
      *extension, profile(), extensions::ExtensionTabUtil::GetTabId(first),
      std::nullopt, false);
  ASSERT_TRUE(result.has_value());
  auto* original = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(original);
  PanelDestructionObserver destroyed(original);
  AddPage();
  ASSERT_TRUE(base::test::RunUntil([&] {
    return destroyed.destroyed || (!original->IsLoading() &&
                                   original->GetLastCommittedURL() ==
                                       extension->GetResourceURL("tab.html"));
  }));
  base::RunLoop().RunUntilIdle();
  ASSERT_FALSE(destroyed.destroyed);
  EXPECT_EQ(nil, original->GetNativeView().GetNativeNSView().window);
  native_browser_->GetTabStripModel()->ActivateTabAt(0);
  ASSERT_TRUE(WaitVisible());
  EXPECT_EQ(original,
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       WindowCloseCancelsLoadingGlobalPanelUntilReopened) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  ASSERT_TRUE(OpenGlobal(extension));
  ASSERT_TRUE(panel_->IsSidePanelEntryPending(Key(extension), false));
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  auto* loading = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(loading);
  PanelDestructionObserver destroyed(loading);
  ASSERT_TRUE(CloseWindowPanel(extension));
  EXPECT_FALSE(panel_->IsSidePanelEntryPending(Key(extension), false));
  EXPECT_FALSE(panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_FALSE(
      SidePanelRegistry::From(native_browser_.get())->GetActiveEntry());
  EXPECT_TRUE(base::test::RunUntil([&] { return destroyed.destroyed; }));
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_TRUE(container_.hidden);
  EXPECT_EQ(0, shown_);
  ASSERT_TRUE(OpenGlobal(extension));
  ASSERT_TRUE(WaitVisible());
  EXPECT_TRUE(panel_->IsSidePanelEntryShowing(Key(extension), false));
  EXPECT_EQ(1, shown_);
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       WindowCloseLeavesLoadingContextualPanel) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto* page = native_browser_->GetTabStripModel()->GetActiveWebContents();
  Contextual(extension, page);
  ASSERT_TRUE(OpenTab(extension, page));
  ASSERT_TRUE(panel_->IsSidePanelEntryPending(Key(extension), true));
  auto* loading = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(loading);
  ASSERT_TRUE(CloseWindowPanel(extension));
  EXPECT_TRUE(panel_->IsSidePanelEntryPending(Key(extension), true));
  ASSERT_TRUE(WaitVisible());
  EXPECT_TRUE(panel_->IsSidePanelEntryShowing(Key(extension), true));
  EXPECT_EQ(loading,
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_EQ(1, shown_);
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       TabCloseCancelsLoadingContextualPanel) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto* page = native_browser_->GetTabStripModel()->GetActiveWebContents();
  Contextual(extension, page);
  ASSERT_TRUE(OpenTab(extension, page));
  ASSERT_TRUE(panel_->IsSidePanelEntryPending(Key(extension), true));
  auto* loading = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(loading);
  PanelDestructionObserver destroyed(loading);
  ASSERT_TRUE(CloseTabPanel(extension, page));
  EXPECT_FALSE(panel_->IsSidePanelEntryPending(Key(extension), true));
  EXPECT_FALSE(SidePanelRegistry::GetDeprecated(page)->GetActiveEntry());
  EXPECT_TRUE(base::test::RunUntil([&] { return destroyed.destroyed; }));
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_FALSE(panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_EQ(0, shown_);
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       TabCloseLeavesLoadingGlobalPanelOfAnotherTab) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  auto* first = native_browser_->GetTabStripModel()->GetActiveWebContents();
  Contextual(extension, first);
  AddPage();
  ASSERT_TRUE(OpenGlobal(extension));
  ASSERT_TRUE(panel_->IsSidePanelEntryPending(Key(extension), false));
  auto* loading = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(loading);
  ASSERT_TRUE(CloseTabPanel(extension, first));
  EXPECT_TRUE(panel_->IsSidePanelEntryPending(Key(extension), false));
  ASSERT_TRUE(WaitVisible());
  EXPECT_TRUE(panel_->IsSidePanelEntryShowing(Key(extension), false));
  EXPECT_EQ(loading,
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_EQ(extension->GetResourceURL("global.html"),
            loading->GetLastCommittedURL());
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       PageChangeWhileLoadingShowsOnlyTheNewestPage) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  ASSERT_TRUE(OpenGlobal(extension));
  auto* loading = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(loading);
  std::vector<GURL> shown_pages;
  auto subscription =
      panel_->RegisterSidePanelShown(base::BindLambdaForTesting([&] {
        shown_pages.push_back(
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension)
                ->GetLastCommittedURL());
      }));
  FirstLoadStopObserver change(
      loading, base::BindLambdaForTesting([&] {
        EXPECT_EQ(extension->GetResourceURL("global.html"),
                  loading->GetLastCommittedURL());
        extensions::api::side_panel::PanelOptions changed;
        changed.path = "tab.html";
        changed.enabled = true;
        service()->SetOptions(*extension, std::move(changed));
      }));
  ASSERT_TRUE(WaitVisible());
  base::RunLoop().RunUntilIdle();
  ASSERT_EQ(1u, shown_pages.size());
  EXPECT_EQ(extension->GetResourceURL("tab.html"), shown_pages.front());
  EXPECT_EQ(loading,
            panel_->GetWebContentsForTest(SidePanelEntryId::kExtension));
  EXPECT_EQ(1, shown_);
}
IN_PROC_BROWSER_TEST_F(NativeSidePanelBrowserTest,
                       WindowCloseCancelsLoadingGlobalPanelOverTabPanel) {
  const auto* tab_extension = LoadFixture();
  ASSERT_TRUE(tab_extension);
  const auto* other = LoadOther();
  ASSERT_TRUE(other);
  auto* page = native_browser_->GetTabStripModel()->GetActiveWebContents();
  Contextual(tab_extension, page);
  ASSERT_TRUE(OpenTab(tab_extension, page));
  ASSERT_TRUE(WaitVisible());
  ASSERT_TRUE(panel_->IsSidePanelEntryShowing(Key(tab_extension), true));
  EXPECT_EQ(1, shown_);
  panel_->Toggle(Key(other), SidePanelOpenTrigger::kExtension);
  ASSERT_TRUE(panel_->IsSidePanelEntryPending(Key(other), false));
  EXPECT_FALSE(SidePanelRegistry::GetDeprecated(page)->GetActiveEntry());
  auto* loading = panel_->GetWebContentsForTest(SidePanelEntryId::kExtension);
  ASSERT_TRUE(loading);
  PanelDestructionObserver destroyed(loading);
  ASSERT_TRUE(CloseWindowPanel(other));
  EXPECT_FALSE(panel_->IsSidePanelEntryPending(Key(other), false));
  EXPECT_TRUE(base::test::RunUntil([&] { return destroyed.destroyed; }));
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(panel_->IsSidePanelShowing());
  EXPECT_EQ(1, shown_);
}
}
