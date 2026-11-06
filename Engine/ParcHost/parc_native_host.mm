// Copyright 2026 Parc contributors.
#import <AppKit/AppKit.h>

#include "cef/libcef/browser/chrome/views/parc_native_host.h"

#include <cstdio>
#include <memory>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_writer.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/values.h"
#include "cef/libcef/browser/chrome/chrome_browser_host_impl.h"
#include "cef/libcef/browser/thread_util.h"
#include "chrome/browser/ui/actions/chrome_action_id.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_actions.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/side_panel/side_panel_entry.h"
#include "chrome/browser/ui/side_panel/side_panel_registry.h"
#include "chrome/browser/ui/side_panel/side_panel_ui.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/views/frame/browser_view.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/referrer.h"
#include "ui/actions/actions.h"
#include "ui/base/models/image_model.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/views/controls/native/native_view_host.h"
#include "ui/views/vector_icons.h"
#include "ui/views/widget/widget.h"
#include "url/gurl.h"

namespace parc {
class NativeHostView;
}

// The C++ view strongly owns this NSView. The reverse pointer is cleared before
// detaching/releasing it. All actions are synchronous on Chromium's UI thread.
@interface ParcNativeHostPanel : NSView <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithOwner:(parc::NativeHostView*)owner;
- (void)invalidateOwner;
- (void)displayRows:(NSArray<NSDictionary*>*)rows
          windowID:(int)windowID
         activeID:(int)activeID
              URL:(NSString*)URL;
@end

namespace parc {

class NativeHostView final : public views::NativeViewHost,
                             public TabStripModelObserver {
 public:
  explicit NativeHostView(Browser* browser) : browser_(browser) {
    CEF_REQUIRE_UIT();
    CHECK(browser_);
    CHECK_EQ(browser_->GetType(), BrowserWindowInterface::TYPE_NORMAL);
    model_ = browser_->tab_strip_model();
    model_->AddObserver(this);
    panel_ = [[ParcNativeHostPanel alloc] initWithOwner:this];
    SetPreferredSize(gfx::Size(360, 500));
    Refresh();
  }

  ~NativeHostView() override {
    CEF_REQUIRE_UIT();
    [panel_ invalidateOwner];
    if (model_) {
      model_->RemoveObserver(this);
    }
    model_ = nullptr;
    browser_ = nullptr;
    if (native_view()) {
      Detach();
    }
    panel_ = nil;
  }

  void ViewHierarchyChanged(
      const views::ViewHierarchyChangedDetails& details) override {
    views::NativeViewHost::ViewHierarchyChanged(details);
    // NativeViewHost creates its platform wrapper in the base implementation.
    // Never attach an NSView before it belongs to a valid Chromium Widget.
    if (details.is_add && GetWidget() && !native_view()) {
      Attach(gfx::NativeView(panel_));
      CHECK_EQ(panel_.window,
               GetWidget()->GetNativeWindow().GetNativeNSWindow());
    }
  }

  void OnTabStripModelChanged(TabStripModel* model,
                             const TabStripModelChange& change,
                             const TabStripSelectionChange& selection) override {
    Refresh();
  }

  void OnTabChangedAt(tabs::TabInterface* tab,
                      TabChangeType change_type) override {
    Refresh();
  }

  void OnTabStripModelDestroyed(TabStripModel* model) override {
    CHECK_EQ(model_, model);
    // TabStripModelObserver::ModelDestroyed already removed this observer.
    // Side-panel cached views may be destroyed later by BrowserWindowFeatures.
    model_ = nullptr;
    browser_ = nullptr;
    [panel_ invalidateOwner];
  }

  void Select(int tab_id) {
    CEF_REQUIRE_UIT();
    const int index = IndexForID(tab_id);
    if (index == TabStripModel::kNoTab) {
      return;
    }
    model_->ActivateTabAt(index);
    // Resolve again after activation callbacks rather than retain an index.
    if (auto* contents = ContentsForID(tab_id)) {
      contents->Focus();
    }
  }

  void NewTab() {
    CEF_REQUIRE_UIT();
    if (browser_) {
      chrome::AddTabAt(browser_, GURL("about:blank"), TabStripModel::kNoTab,
                       /*foreground=*/true);
    }
  }

  void Navigate(NSString* input) {
    CEF_REQUIRE_UIT();
    auto* contents = model_ ? model_->GetActiveWebContents() : nullptr;
    if (!contents) {
      return;
    }
    const GURL url(base::SysNSStringToUTF8(input));
    // This engineering harness accepts explicit URLs, not search text or
    // executable javascript/data URLs. The omnibox remains Chrome-owned.
    if (!url.is_valid() ||
        !(url.SchemeIsHTTPOrHTTPS() || url.SchemeIs("chrome") ||
          url == GURL("about:blank"))) {
      NSBeep();
      return;
    }
    contents->GetController().LoadURL(url, content::Referrer(),
                                       ui::PAGE_TRANSITION_TYPED, {});
    contents->Focus();
  }

  void Back() {
    CEF_REQUIRE_UIT();
    if (browser_ && chrome::CanGoBack(browser_)) {
      chrome::GoBack(browser_, WindowOpenDisposition::CURRENT_TAB);
    }
  }

  void Forward() {
    CEF_REQUIRE_UIT();
    if (browser_ && chrome::CanGoForward(browser_)) {
      chrome::GoForward(browser_, WindowOpenDisposition::CURRENT_TAB);
    }
  }

  void Reload() {
    CEF_REQUIRE_UIT();
    if (browser_ && chrome::CanReload(browser_)) {
      chrome::Reload(browser_, WindowOpenDisposition::CURRENT_TAB);
    }
  }

  void CloseActive() {
    CEF_REQUIRE_UIT();
    auto* contents = model_ ? model_->GetActiveWebContents() : nullptr;
    if (contents) {
      // Native close performs beforeunload negotiation. Do not remove any row
      // or synthesize a closed callback before the real model reports it.
      model_->CloseWebContents(contents, TabCloseTypes::CLOSE_USER_GESTURE |
                                           TabCloseTypes::CLOSE_CREATE_HISTORICAL_TAB);
      // Closing the last tab may destroy this view; no further member access.
    }
  }

  void LogIdentity() {
    CEF_REQUIRE_UIT();
    if (!browser_ || !model_) {
      return;
    }
    base::DictValue snapshot;
    snapshot.Set("event", "parc-native-host.identity");
    snapshot.Set("windowId", browser_->GetSessionID().id());
    snapshot.Set("type", browser_->GetType() == BrowserWindowInterface::TYPE_NORMAL
                             ? "normal" : "unexpected");
    snapshot.Set("nativeViewAttachedToBrowserWindow",
                 GetWidget() && panel_.window ==
                     GetWidget()->GetNativeWindow().GetNativeNSWindow());
    base::ListValue tabs;
    for (int index = 0; index < model_->count(); ++index) {
      auto* contents = model_->GetWebContentsAt(index);
      base::DictValue tab;
      tab.Set("id", sessions::SessionTabHelper::IdForTab(contents).id());
      tab.Set("windowId",
              sessions::SessionTabHelper::IdForWindowContainingTab(contents).id());
      tab.Set("index", index);
      tab.Set("active", index == model_->active_index());
      if (auto host = ChromeBrowserHostImpl::GetBrowserForContents(contents)) {
        tab.Set("cefBrowserId", host->GetIdentifier());
      }
      tabs.Append(std::move(tab));
    }
    snapshot.Set("tabs", std::move(tabs));
    const auto json = base::WriteJson(snapshot);
    CHECK(json);
    std::fprintf(stdout, "%s\n", json->c_str());
    std::fflush(stdout);
  }

 private:
  int IndexForID(int tab_id) const {
    if (model_) {
      for (int index = 0; index < model_->count(); ++index) {
        if (sessions::SessionTabHelper::IdForTab(model_->GetWebContentsAt(index))
                .id() == tab_id) {
          return index;
        }
      }
    }
    return TabStripModel::kNoTab;
  }

  content::WebContents* ContentsForID(int tab_id) const {
    const int index = IndexForID(tab_id);
    return index == TabStripModel::kNoTab ? nullptr
                                        : model_->GetWebContentsAt(index);
  }

  void Refresh() {
    CEF_REQUIRE_UIT();
    if (!model_ || !browser_) {
      return;
    }
    NSMutableArray<NSDictionary*>* rows = [NSMutableArray array];
    int active_id = -1;
    NSString* url = @"";
    for (int index = 0; index < model_->count(); ++index) {
      auto* contents = model_->GetWebContentsAt(index);
      const int tab_id = sessions::SessionTabHelper::IdForTab(contents).id();
      NSString* title = base::SysUTF16ToNSString(contents->GetTitle());
      if (title.length == 0) {
        title = base::SysUTF8ToNSString(contents->GetVisibleURL().spec());
      }
      [rows addObject:@{@"id": @(tab_id), @"title": title ?: @""}];
      if (index == model_->active_index()) {
        active_id = tab_id;
        url = base::SysUTF8ToNSString(contents->GetVisibleURL().spec());
      }
    }
    [panel_ displayRows:rows windowID:browser_->GetSessionID().id()
              activeID:active_id URL:url];
  }

  raw_ptr<Browser> browser_;
  raw_ptr<TabStripModel> model_ = nullptr;
  ParcNativeHostPanel* __strong panel_ = nil;
};

void InstallNativeHost(Browser* browser) {
  CEF_REQUIRE_UIT();
  CHECK(browser);
  CHECK_EQ(browser->GetType(), BrowserWindowInterface::TYPE_NORMAL);
  CHECK(BrowserView::GetBrowserViewForBrowser(browser));
  auto* registry = SidePanelRegistry::From(browser);
  auto* browser_actions = BrowserActions::From(browser);
  auto* side_panel = SidePanelUI::From(browser);
  CHECK(registry && browser_actions && side_panel);
  const SidePanelEntryKey key(SidePanelEntryId::kParcNativeHost);
  if (!registry->GetEntryForKey(key)) {
    browser_actions->RegisterAction(
        actions::ActionItem::Builder(base::BindRepeating(
            [](Browser* browser, actions::ActionItem* item,
               actions::ActionInvocationContext context) {
              SidePanelUI::From(browser)->Toggle(
                  SidePanelEntryKey(SidePanelEntryId::kParcNativeHost),
                  SidePanelOpenTrigger::kToolbarButton);
            }, browser))
            .SetActionId(kActionSidePanelShowParcNativeHost)
            .SetText(u"Parc native host")
            .SetTooltipText(u"Show the native AppKit host")
            .SetImage(ui::ImageModel::FromVectorIcon(views::kInfoIcon))
            .Build());
    auto entry = std::make_unique<SidePanelEntry>(
        key, base::BindRepeating([](Browser* browser, SidePanelEntryScope& scope) {
          CHECK_EQ(&scope.GetBrowserWindowInterface(), browser);
          return SidePanelNativeView(std::make_unique<NativeHostView>(browser));
        }, browser), base::NullCallback());
    CHECK(registry->Register(std::move(entry)));
  }
  side_panel->Show(key, std::nullopt, /*suppress_animations=*/true);
}

}  // namespace parc

@implementation ParcNativeHostPanel {
  parc::NativeHostView* _owner;
  NSTableView* _table;
  NSTextField* _identity;
  NSTextField* _address;
  NSArray<NSDictionary*>* _rows;
  BOOL _updatingSelection;
}

- (instancetype)initWithOwner:(parc::NativeHostView*)owner {
  self = [super initWithFrame:NSMakeRect(0, 0, 360, 500)];
  if (!self) return nil;
  _owner = owner;
  _rows = @[];
  self.accessibilityLabel = @"Parc native browser host";
  _identity = [NSTextField labelWithString:@""];
  _identity.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
  _identity.lineBreakMode = NSLineBreakByTruncatingTail;
  _address = [NSTextField textFieldWithString:@""];
  _address.placeholderString = @"https://example.com";
  _address.accessibilityLabel = @"Navigate active Chrome tab";
  _address.target = self;
  _address.action = @selector(navigate:);
  NSStackView* navigation = [NSStackView stackViewWithViews:@[
    [self button:@"Back" action:@selector(back:)],
    [self button:@"Forward" action:@selector(forward:)],
    [self button:@"Reload" action:@selector(reload:)]]];
  NSStackView* actions = [NSStackView stackViewWithViews:@[
    [self button:@"New tab" action:@selector(newTab:)],
    [self button:@"Close tab" action:@selector(closeTab:)],
    [self button:@"Log identities" action:@selector(logIdentity:)]]];
  _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 336, 400)];
  _table.autoresizingMask = NSViewWidthSizable;
  NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"tab"];
  column.title = @"Live Chrome tabs";
  column.resizingMask = NSTableColumnAutoresizingMask;
  [_table addTableColumn:column];
  _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
  _table.headerView = nil;
  _table.rowHeight = 32;
  _table.allowsEmptySelection = NO;
  _table.dataSource = self;
  _table.delegate = self;
  _table.accessibilityLabel = @"Actual Chrome tab model";
  NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scroll.documentView = _table;
  scroll.hasVerticalScroller = YES;
  scroll.drawsBackground = NO;
  NSStackView* stack = [NSStackView stackViewWithViews:@[
    _identity, _address, navigation, actions, scroll]];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 10;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [self addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
    [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
    [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
    [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
    [_identity.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    [_address.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:100]]];
  return self;
}

- (NSButton*)button:(NSString*)title action:(SEL)action {
  NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
  button.bezelStyle = NSBezelStyleRounded;
  button.controlSize = NSControlSizeSmall;
  return button;
}

- (void)invalidateOwner {
  _owner = nullptr;
  _table.delegate = nil;
  _address.enabled = NO;
}

- (void)displayRows:(NSArray<NSDictionary*>*)rows windowID:(int)windowID
          activeID:(int)activeID URL:(NSString*)URL {
  _updatingSelection = YES;
  _rows = [rows copy];
  _identity.stringValue = [NSString stringWithFormat:@"Chrome window %d · %lu tabs",
                           windowID, (unsigned long)rows.count];
  // Keep the field editor's current input intact while model notifications run.
  if (!_address.currentEditor) _address.stringValue = URL;
  [_table reloadData];
  NSUInteger selected = [rows indexOfObjectPassingTest:
      ^BOOL(NSDictionary* row, NSUInteger index, BOOL* stop) {
        return [row[@"id"] intValue] == activeID;
      }];
  if (selected != NSNotFound) {
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:selected]
       byExtendingSelection:NO];
  }
  _updatingSelection = NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return _rows.count;
}

- (NSView*)tableView:(NSTableView*)tableView
   viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  NSDictionary* value = _rows[row];
  NSTextField* label = [NSTextField labelWithString:
      [NSString stringWithFormat:@"#%@  %@", value[@"id"], value[@"title"]]];
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  label.font = [NSFont systemFontOfSize:12];
  return label;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  const NSInteger row = _table.selectedRow;
  if (_owner && !_updatingSelection && row >= 0 && row < (NSInteger)_rows.count) {
    _owner->Select([_rows[row][@"id"] intValue]);
  }
}
- (void)navigate:(id)sender { if (_owner) _owner->Navigate(_address.stringValue); }
- (void)newTab:(id)sender { if (_owner) _owner->NewTab(); }
- (void)back:(id)sender { if (_owner) _owner->Back(); }
- (void)forward:(id)sender { if (_owner) _owner->Forward(); }
- (void)reload:(id)sender { if (_owner) _owner->Reload(); }
- (void)closeTab:(id)sender { if (_owner) _owner->CloseActive(); }
- (void)logIdentity:(id)sender { if (_owner) _owner->LogIdentity(); }
@end
