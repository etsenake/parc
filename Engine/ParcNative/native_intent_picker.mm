// Copyright 2026 Parc contributors.
#include "native_intent_picker.h"
#include <algorithm>
#include <memory>
#include <utility>
#include "base/callback_list.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/services/app_service/public/cpp/intent_util.h"
#include "components/tabs/public/tab_interface.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "ui/gfx/image/image_skia_util_mac.h"
#include "ui/gfx/image/image_skia.h"
#import "window_security_reservation.h"

@interface PCNativeIntentActions : NSObject <NSTableViewDataSource,
                                             NSTableViewDelegate,
                                             NSPopoverDelegate> {
 @public
  base::RepeatingCallback<void(int)> action;
  NSArray<NSDictionary*>* rows;
}
- (void)perform:(NSControl*)sender;
- (void)openSelection:(id)sender;
@end
@implementation PCNativeIntentActions
- (void)perform:(NSControl*)sender { auto run = action; if (run) run.Run((int)sender.tag); }
- (void)openSelection:(id)sender { auto run = action; if (run) run.Run(1); }
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { return rows.count; }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column
                row:(NSInteger)index {
  NSDictionary* row = rows[index];
  NSTableCellView* cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 328, 54)];
  NSImageView* icon = [[NSImageView alloc] initWithFrame:NSMakeRect(6, 7, 40, 40)];
  icon.image = row[@"icon"] == NSNull.null ? nil : row[@"icon"];
  icon.imageScaling = NSImageScaleProportionallyUpOrDown;
  NSTextField* label = [NSTextField labelWithString:row[@"name"]];
  label.frame = NSMakeRect(58, 17, 260, 20);
  label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  label.toolTip = row[@"name"];
  [cell addSubview:icon]; [cell addSubview:label];
  cell.imageView = icon; cell.textField = label;
  return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  auto run = action; if (run) run.Run(0);
}
- (void)popoverDidClose:(NSNotification*)notification {
  auto run = action; if (run) run.Run(3);
}
@end

namespace parc {
namespace {
using Reason = apps::IntentPickerCloseReason;
struct DecisionLease {
  base::WeakPtr<BrowserWindowInterface> browser;
  base::WeakPtr<content::WebContents> page;
  content::WeakDocumentPtr document;
  GURL url;
  NSWindow* __weak window;
  base::RepeatingCallback<bool()> valid;
  bool Current() const {
    return browser && page && !browser->IsDeleteScheduled() && window &&
        browser->GetWindow() &&
        browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window &&
        document.AsRenderFrameHostIfValid() == page->GetPrimaryMainFrame() &&
        page->GetLastCommittedURL() == url && valid && valid.Run();
  }
};
void Deliver(IntentPickerResponse callback, std::string name,
             apps::PickerEntryType type, Reason reason, bool persist,
             std::shared_ptr<DecisionLease> lease = nullptr) {
  if (!callback) return;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
          [](IntentPickerResponse callback, std::string name,
             apps::PickerEntryType type, Reason reason, bool persist,
             std::shared_ptr<DecisionLease> lease) {
            if (lease && !lease->Current()) {
              name.clear(); type = apps::PickerEntryType::kUnknown;
              reason = Reason::DIALOG_DEACTIVATED; persist = false;
            }
            std::move(callback).Run(name, type, reason, persist);
          }, std::move(callback), std::move(name), type, reason, persist,
          std::move(lease)));
}
// Arc142 0x68a7ff8 is a callback-consuming compatibility method, not a recovered
// picker UI. This native page-owned prompt is the explicit Chromium156
//
class IntentSession final : public content::WebContentsObserver,
                            public content::WebContentsUserData<IntentSession> {
 public:
  ~IntentSession() override { Close(); }
  void Show(BrowserWindowInterface& browser, NSWindow* window, NSView* anchor,
            base::RepeatingCallback<bool()> valid,
            std::vector<apps::IntentPickerAppInfo> apps, bool stay, bool remember,
            apps::IntentPickerBubbleType type,
            const std::optional<url::Origin>& origin,
            IntentPickerResponse callback) {
    CHECK(!active_);
    auto* tab = tabs::TabInterface::MaybeGetFromContents(web_contents());
    if (!window || !anchor || anchor.window != window || !window.isKeyWindow ||
        window.attachedSheet || PCNativeWindowHasSecurityReservation(window) ||
        !valid || !valid.Run() || !tab || apps.empty() ||
        std::ranges::any_of(apps, [](const auto& app) {
          return app.launch_name.empty() || app.display_name.empty();
        })) {
      Deliver(std::move(callback), "", apps::PickerEntryType::kUnknown,
              Reason::ERROR_BEFORE_PICKER, false);
      return;
    }
    browser_ = browser.GetWeakPtr();
    document_ = web_contents()->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    url_ = web_contents()->GetLastCommittedURL();
    window_ = window; anchor_ = anchor; valid_ = std::move(valid);
    apps_ = std::move(apps); callback_ = std::move(callback);
    stay_ = stay; remember_ = remember; active_ = true;
    auto weak = weak_factory_.GetWeakPtr();
    deactivate_ = tab->RegisterWillDeactivate(base::BindRepeating(
        [](base::WeakPtr<IntentSession> self, tabs::TabInterface*) {
          if (self) self->Close();
        }, weak));
    detach_ = tab->RegisterWillDetach(base::BindRepeating(
        [](base::WeakPtr<IntentSession> self, tabs::TabInterface*,
           tabs::TabInterface::DetachReason) { if (self) self->Close(); }, weak));
    discard_ = tab->RegisterWillDiscardContents(base::BindRepeating(
        [](base::WeakPtr<IntentSession> self, tabs::TabInterface*,
           content::WebContents*, content::WebContents*) {
          if (self) self->Close();
        }, weak));
    auto reservation = [PCNativeWindowSecurityReservation acquireForWindow:window];
    if (!weak || !ValidOwner() || !reservation.isOnlyReservation) {
      [reservation invalidate];
      if (weak) Close();
      return;
    }
    reservation_ = reservation;
    observations_ = [NSMutableArray array];
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
                                      NSWindowDidMiniaturizeNotification,
                                      PCNativeWindowSecurityStateChanged]) {
      [observations_ addObject:[NSNotificationCenter.defaultCenter
          addObserverForName:name object:window queue:nil
          usingBlock:^(NSNotification*) {
            if (weak && (name != PCNativeWindowSecurityStateChanged ||
                         !weak->Valid())) weak->Close();
          }]];
    }
    [observations_ addObject:[NSNotificationCenter.defaultCenter
        addObserverForName:NSApplicationDidResignActiveNotification object:NSApp
        queue:nil usingBlock:^(NSNotification*) { if (weak) weak->Close(); }]];
    BuildView(type, origin);
    if (!weak || !Valid()) { if (weak) Close(); return; }
    const NSRect bounds = anchor.bounds;
    const NSRect at = NSMakeRect(NSMaxX(bounds) - 28,
        anchor.isFlipped ? NSMinY(bounds) + 8 : NSMaxY(bounds) - 8, 1, 1);
    [popover_ showRelativeToRect:at ofView:anchor preferredEdge:NSRectEdgeMinY];
    if (!weak) return;
    shown_ = popover_.shown;
    if (!shown_) { Close(); return; }
    [popover_.contentViewController.view.window makeFirstResponder:table_];
  }
  void Close() {
    if (!active_) return;
    Finish("", apps::PickerEntryType::kUnknown,
           shown_ ? Reason::DIALOG_DEACTIVATED : Reason::ERROR_BEFORE_PICKER, false);
  }
 private:
  friend class content::WebContentsUserData<IntentSession>;
  explicit IntentSession(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<IntentSession>(*contents) {}
  bool ValidOwner() const {
    auto* frame = document_.AsRenderFrameHostIfValid();
    return active_ && browser_ && !browser_->IsDeleteScheduled() &&
           web_contents() && !web_contents()->IsBeingDestroyed() && frame &&
           frame->IsActive() && web_contents()->GetPrimaryMainFrame() == frame &&
           web_contents()->GetLastCommittedURL() == url_ &&
           window_ && anchor_ && anchor_.window == window_ &&
           !anchor_.hiddenOrHasHiddenAncestor && window_.visible &&
           !window_.miniaturized && valid_ && valid_.Run();
  }
  bool Valid() const {
    return ValidOwner() && !window_.attachedSheet && reservation_ &&
           reservation_.isOnlyReservation;
  }
  void PrimaryPageChanged(content::Page&) override { Close(); }
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && handle->HasCommitted() &&
        web_contents()->GetLastCommittedURL() != url_) Close();
  }
  void WebContentsDestroyed() override { Close(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) Close();
  }
  void Perform(int action) {
    if (!Valid()) { Close(); return; }
    const NSInteger selected = table_.selectedRow;
    const bool has_selection = selected >= 0 &&
        static_cast<size_t>(selected) < apps_.size();
    if (action == 0) {
      open_.enabled = has_selection;
      checkbox_.enabled = !has_selection ||
          apps_[selected].type != apps::PickerEntryType::kDevice;
      if (!checkbox_.enabled) checkbox_.state = NSControlStateValueOff;
      return;
    }
    const bool persist = remember_ && checkbox_.enabled &&
                         checkbox_.state == NSControlStateValueOn;
    if (action == 1 && has_selection) {
      const auto& app = apps_[selected];
      Finish(app.launch_name, app.type, Reason::OPEN_APP, persist);
    } else if (action == 2 && stay_) {
      Finish(apps_util::kUseBrowserForLink, apps::PickerEntryType::kUnknown,
             Reason::STAY_IN_CHROME, persist);
    } else if (action == 3) {
      Close();
    }
  }
  NSButton* Button(NSString* title, int action) {
    NSButton* button = [NSButton buttonWithTitle:title target:actions_
                                         action:@selector(perform:)];
    button.tag = action;
    return button;
  }
  void BuildView(apps::IntentPickerBubbleType type,
                 const std::optional<url::Origin>& origin) {
    actions_ = [PCNativeIntentActions new];
    NSMutableArray* rows = [NSMutableArray arrayWithCapacity:apps_.size()];
    const auto* colors = BrowserWindow::FromBrowser(browser_.get())->GetColorProvider();
    for (const auto& app : apps_) {
      NSImage* icon = app.icon_model.IsEmpty() ? nil :
          gfx::NSImageFromImageSkia(app.icon_model.Rasterize(colors));
      [rows addObject:@{@"name":base::SysUTF8ToNSString(app.display_name),
                        @"icon":icon ?: (id)NSNull.null}];
    }
    actions_->rows = rows;
    const CGFloat list_height = std::min<CGFloat>(270, apps_.size() * 56);
    NSString* origin_text = nil;
    if (origin && !origin->IsSameOriginWith(
                      web_contents()->GetPrimaryMainFrame()->GetLastCommittedOrigin())) {
      origin_text = [@"Requested by " stringByAppendingString:
          base::SysUTF16ToNSString(url_formatter::FormatOriginForSecurityDisplay(*origin))];
    }
    const CGFloat lower = 58 + (remember_ ? 30 : 0) + (origin_text ? 46 : 0);
    const CGFloat height = list_height + lower + 62;
    NSViewController* controller = [NSViewController new];
    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, height)];
    controller.view = view;
    NSTextField* title = [NSTextField labelWithString:
        type == apps::IntentPickerBubbleType::kExternalProtocol
            ? @"Open Link With" : @"Open in Another App"];
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    title.frame = NSMakeRect(18, height - 42, 290, 22);
    [view addSubview:title];
    NSButton* close = Button(@"", 3);
    close.image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"];
    close.bordered = NO; close.keyEquivalent = @"\033";
    [close setAccessibilityLabel:@"Close app chooser"];
    close.frame = NSMakeRect(320, height - 42, 24, 24);
    [view addSubview:close];
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(16, lower, 328, list_height)];
    scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    table_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 328, list_height)];
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"application"];
    column.width = 328; [table_ addTableColumn:column];
    table_.headerView = nil; table_.rowHeight = 54;
    table_.allowsMultipleSelection = NO; table_.allowsEmptySelection = YES;
    table_.dataSource = actions_; table_.delegate = actions_;
    table_.target = actions_; table_.doubleAction = @selector(openSelection:);
    table_.backgroundColor = NSColor.clearColor;
    [table_ setAccessibilityLabel:@"Applications that can open this page"];
    scroll.documentView = table_; [view addSubview:scroll];
    CGFloat y = 58;
    if (remember_) {
      checkbox_ = [NSButton checkboxWithTitle:@"Remember my choice"
                                       target:nil action:nil];
      checkbox_.frame = NSMakeRect(18, y, 324, 22);
      [view addSubview:checkbox_]; y += 30;
    }
    if (origin_text) {
      NSTextField* detail = [NSTextField wrappingLabelWithString:origin_text];
      detail.font = [NSFont systemFontOfSize:11];
      detail.textColor = NSColor.secondaryLabelColor;
      detail.frame = NSMakeRect(18, y, 324, 40); [view addSubview:detail];
    }
    NSButton* cancel = Button(stay_ ? @"Stay in Parc" : @"Cancel", stay_ ? 2 : 3);
    cancel.frame = NSMakeRect(16, 16, 156, 30); [view addSubview:cancel];
    open_ = Button(@"Open", 1); open_.keyEquivalent = @"\r";
    open_.frame = NSMakeRect(238, 16, 106, 30); [view addSubview:open_];
    if (apps_.size() == 1) [table_ selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                               byExtendingSelection:NO];
    open_.enabled = apps_.size() == 1;
    checkbox_.enabled = apps_.size() != 1 ||
        apps_[0].type != apps::PickerEntryType::kDevice;
    actions_->action = base::BindRepeating(&IntentSession::Perform,
                                         weak_factory_.GetWeakPtr());
    popover_ = [NSPopover new]; popover_.behavior = NSPopoverBehaviorTransient;
    popover_.delegate = actions_; popover_.contentViewController = controller;
  }
  void Finish(std::string name, apps::PickerEntryType type, Reason reason,
              bool persist) {
    if (!active_) return;
    std::shared_ptr<DecisionLease> lease;
    if (reason == Reason::OPEN_APP || reason == Reason::STAY_IN_CHROME) {
      lease = std::make_shared<DecisionLease>();
      lease->browser = browser_; lease->page = web_contents()->GetWeakPtr();
      lease->document = document_; lease->url = url_; lease->window = window_;
      lease->valid = valid_;
    }
    active_ = false; shown_ = false;
    weak_factory_.InvalidateWeakPtrs();
    auto callback = std::move(callback_);
    if (actions_) actions_->action.Reset();
    table_.delegate = nil; table_.dataSource = nil; table_.target = nil;
    auto popover = popover_;
    popover.delegate = nil;
    popover_ = nil;
    for (id observer in observations_)
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    observations_ = nil;
    deactivate_ = {}; detach_ = {}; discard_ = {};
    apps_.clear(); valid_.Reset(); browser_.reset();
    window_ = nil; anchor_ = nil; actions_ = nil;
    table_ = nil; open_ = nil; checkbox_ = nil;
    auto reservation = reservation_; reservation_ = nil;
    [popover close];
    [reservation invalidate];
    // All native ownership is retired before the real callback may persist a
    // preference, reparent the original tab, launch an app or destroy its page.
    Deliver(std::move(callback), std::move(name), type, reason, persist,
            std::move(lease));
  }
  bool active_ = false;
  bool shown_ = false;
  bool stay_ = false;
  bool remember_ = false;
  base::WeakPtr<BrowserWindowInterface> browser_;
  content::WeakDocumentPtr document_;
  GURL url_;
  base::RepeatingCallback<bool()> valid_;
  std::vector<apps::IntentPickerAppInfo> apps_;
  IntentPickerResponse callback_;
  NSWindow* __weak window_;
  NSView* __weak anchor_;
  PCNativeWindowSecurityReservation* __strong reservation_;
  PCNativeIntentActions* __strong actions_;
  NSPopover* __strong popover_;
  NSTableView* __strong table_;
  NSButton* __strong open_;
  NSButton* __strong checkbox_;
  NSMutableArray* __strong observations_;
  base::CallbackListSubscription deactivate_, detach_, discard_;
  base::WeakPtrFactory<IntentSession> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(IntentSession);
}  // namespace
void ShowNativeIntentPicker(BrowserWindowInterface& browser,
    content::WebContents& contents, NSWindow* window, NSView* anchor,
    base::RepeatingCallback<bool()> valid,
    std::vector<apps::IntentPickerAppInfo> apps, bool stay, bool remember,
    apps::IntentPickerBubbleType type,
    const std::optional<url::Origin>& origin, IntentPickerResponse callback) {
  CHECK(NSThread.isMainThread);
  auto page = contents.GetWeakPtr();
  auto owner = browser.GetWeakPtr();
  CloseNativeIntentPicker(contents);
  if (!page || !owner) {
    Deliver(std::move(callback), "", apps::PickerEntryType::kUnknown,
            Reason::ERROR_BEFORE_PICKER, false);
    return;
  }
  IntentSession::CreateForWebContents(&contents);
  IntentSession::FromWebContents(&contents)->Show(*owner, window, anchor,
      std::move(valid), std::move(apps), stay, remember, type, origin,
      std::move(callback));
}
void CloseNativeIntentPicker(content::WebContents& contents) {
  CHECK(NSThread.isMainThread);
  if (auto* session = IntentSession::FromWebContents(&contents)) session->Close();
}
}  // namespace parc
