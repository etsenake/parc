// Copyright 2026 Parc contributors.
#include "device_chooser.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <optional>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "ui/base/base_window.h"
#include "chrome/grit/generated_resources.h"
#include "components/permissions/chooser_controller.h"
#include "components/strings/grit/components_strings.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#import "dialog_style.h"
#include "native_auxiliary_page.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/display/types/display_constants.h"
#import "window_security_reservation.h"

using namespace parc_dialog;

typedef NS_ENUM(NSInteger, PCDeviceChooserLink) {
  PCDeviceChooserLinkHelp,
  PCDeviceChooserLinkAdapterOff,
  PCDeviceChooserLinkPermission,
  PCDeviceChooserLinkRescan,
};

@interface PCDeviceChooserRow : NSObject
@property(nonatomic, copy) NSString* title;
@property(nonatomic) NSInteger level;
@property(nonatomic) BOOL connected;
@property(nonatomic) BOOL paired;
@end
@implementation PCDeviceChooserRow
@synthesize title = _title;
@synthesize level = _level;
@synthesize connected = _connected;
@synthesize paired = _paired;
@end

@interface PCDeviceChooserContent : NSObject
@property(nonatomic, copy) NSString* title;
@property(nonatomic, copy) NSString* okLabel;
@property(nonatomic, copy) NSString* cancelLabel;
@property(nonatomic, copy) NSString* listLabel;
@property(nonatomic, copy) NSString* noOptionsText;
@property(nonatomic, copy) NSString* throbberText;
@property(nonatomic, copy) NSString* throbberTooltip;
@property(nonatomic, copy, nullable) NSString* rescanLabel;
@property(nonatomic, copy, nullable) NSString* rescanTooltip;
@property(nonatomic, copy, nullable) NSString* helpLabel;
@property(nonatomic, copy, nullable) NSString* adapterOffText;
@property(nonatomic, copy, nullable) NSString* adapterOffLink;
@property(nonatomic, copy, nullable) NSString* unauthorizedText;
@property(nonatomic, copy, nullable) NSString* unauthorizedLink;
@property(nonatomic) BOOL showsIcons;
@property(nonatomic) BOOL multiple;
@property(nonatomic) BOOL bothButtonsEnabled;
@property(nonatomic) BOOL tableAlwaysDisabled;
@end
@implementation PCDeviceChooserContent
@synthesize title = _title;
@synthesize okLabel = _okLabel;
@synthesize cancelLabel = _cancelLabel;
@synthesize listLabel = _listLabel;
@synthesize noOptionsText = _noOptionsText;
@synthesize throbberText = _throbberText;
@synthesize throbberTooltip = _throbberTooltip;
@synthesize rescanLabel = _rescanLabel;
@synthesize rescanTooltip = _rescanTooltip;
@synthesize helpLabel = _helpLabel;
@synthesize adapterOffText = _adapterOffText;
@synthesize adapterOffLink = _adapterOffLink;
@synthesize unauthorizedText = _unauthorizedText;
@synthesize unauthorizedLink = _unauthorizedLink;
@synthesize showsIcons = _showsIcons;
@synthesize multiple = _multiple;
@synthesize bothButtonsEnabled = _bothButtonsEnabled;
@synthesize tableAlwaysDisabled = _tableAlwaysDisabled;
@end

@interface PCDeviceChooserTable : NSTableView
@end
@implementation PCDeviceChooserTable
- (NSAccessibilityRole)accessibilityRole {
  return NSAccessibilityTableRole;
}
@end

@interface PCDeviceChooserPresenter
    : NSObject <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                     content:(PCDeviceChooserContent*)content
                       count:(NSInteger (^)(void))count
                         row:(PCDeviceChooserRow* (^)(NSInteger))row
                    validate:(BOOL (^)(void))validate
                        link:(void (^)(PCDeviceChooserLink))link
                      result:(void (^)(BOOL accepted,
                                       std::vector<size_t> indices))result;
@property(nonatomic, readonly) NSWindow* sheet;
- (void)show;
- (void)invalidate;
- (void)optionsInitialized;
- (void)optionAdded:(NSInteger)index;
- (void)optionRemoved:(NSInteger)index;
- (void)optionUpdated:(NSInteger)index;
- (void)adapterEnabledChanged:(BOOL)enabled;
- (void)adapterAuthorizationChanged:(BOOL)authorized;
- (void)refreshStateChanged:(BOOL)refreshing;
@end

namespace {
constexpr CGFloat kListHeight = 208;
constexpr CGFloat kRowHeight = 36;
constexpr CGFloat kStatusHeight = 24;
NSButton* LinkButton(NSString* title, id target, SEL action) {
  NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
  button.bordered = NO;
  button.attributedTitle = [[NSAttributedString alloc]
      initWithString:title
          attributes:@{
            NSFontAttributeName : [NSFont systemFontOfSize:13
                                                    weight:NSFontWeightMedium],
            NSForegroundColorAttributeName : SelectionColor()
          }];
  [button sizeToFit];
  return button;
}
NSString* RowAccessibilityLabel(PCDeviceChooserRow* row) {
  NSMutableArray<NSString*>* parts = [NSMutableArray arrayWithObject:row.title];
  if (row.connected) {
    [parts addObject:@"Connected"];
  } else if (row.level >= 0) {
    [parts addObject:[NSString stringWithFormat:@"Signal strength %ld of 4",
                                                (long)row.level]];
  }
  return [parts componentsJoinedByString:@", "];
}
}

@implementation PCDeviceChooserPresenter {
  __weak NSView* _page;
  __weak NSWindow* _window;
  PCDeviceChooserContent* _content;
  PCDialogPanel* _sheet;
  PCDeviceChooserTable* _table;
  NSScrollView* _scroll;
  PCDialogCard* _card;
  NSTextField* _message;
  NSButton* _messageLink;
  NSProgressIndicator* _spinner;
  NSTextField* _throbberLabel;
  NSButton* _rescan;
  NSButton* _help;
  PCDialogButton* _connect;
  PCDialogButton* _cancel;
  NSInteger (^_count)(void);
  PCDeviceChooserRow* (^_row)(NSInteger);
  BOOL (^_validate)(void);
  void (^_link)(PCDeviceChooserLink);
  void (^_result)(BOOL, std::vector<size_t>);
  BOOL _initialized, _adapterEnabled, _adapterAuthorized;
  BOOL _started, _terminal;
}
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                     content:(PCDeviceChooserContent*)content
                       count:(NSInteger (^)(void))count
                         row:(PCDeviceChooserRow* (^)(NSInteger))row
                    validate:(BOOL (^)(void))validate
                        link:(void (^)(PCDeviceChooserLink))link
                      result:(void (^)(BOOL, std::vector<size_t>))result {
  CHECK(NSThread.isMainThread);
  if ((self = [super init])) {
    _page = page;
    _window = window;
    _content = content;
    _count = [count copy];
    _row = [row copy];
    _validate = [validate copy];
    _link = [link copy];
    _result = [result copy];
    _adapterEnabled = YES;
    _adapterAuthorized = YES;
    [self build];
    [self showThrobber];
    [self update];
  }
  return self;
}
- (void)build {
  _sheet = [[PCDialogPanel alloc] initWithContentRect:NSMakeRect(0, 0, kWidth, 200)
                                            styleMask:NSWindowStyleMaskTitled
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  _sheet.releasedWhenClosed = NO;
  _sheet.becomesKeyOnlyIfNeeded = NO;
  _sheet.title = _content.title;
  _sheet.accessibilityLabel = _content.title;
  PrepareSheet(_sheet);
  PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
  CGFloat y = kInset;
  NSRect markRect;
  NSImage* mark = ParcMark(&markRect);
  PCDialogPictureIcon* art = [[PCDialogPictureIcon alloc] initWithImage:mark
                                                              imageRect:markRect];
  [art setAccessibilityElement:NO];
  art.frameOrigin = NSMakePoint(kInset, y);
  [root addSubview:art];
  y = AddHeading(root, _content.title, nil, y + kArtSize, 0) + 8;
  const CGFloat width = kWidth - 2 * kInset;
  _card = [[PCDialogCard alloc] initWithFrame:NSMakeRect(kInset, y, width, kListHeight)];
  [root addSubview:_card];
  _table = [[PCDeviceChooserTable alloc] initWithFrame:NSZeroRect];
  NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"device"];
  column.resizingMask = NSTableColumnAutoresizingMask;
  [_table addTableColumn:column];
  _table.headerView = nil;
  _table.rowHeight = kRowHeight;
  _table.intercellSpacing = NSMakeSize(0, 2);
  _table.backgroundColor = NSColor.clearColor;
  _table.style = NSTableViewStyleSourceList;
  _table.allowsMultipleSelection = _content.multiple;
  _table.allowsEmptySelection = YES;
  _table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
  _table.dataSource = self;
  _table.delegate = self;
  _table.target = self;
  _table.doubleAction = @selector(doubleClicked:);
  _table.accessibilityLabel = _content.listLabel;
  _table.identifier = @"device-chooser-list";
  _scroll = [[NSScrollView alloc] initWithFrame:NSInsetRect(_card.bounds, 4, 4)];
  _scroll.drawsBackground = NO;
  _scroll.contentView.drawsBackground = NO;
  _scroll.hasVerticalScroller = YES;
  _scroll.autohidesScrollers = YES;
  _scroll.documentView = _table;
  [column setWidth:NSWidth(_scroll.bounds)];
  [_card addSubview:_scroll];
  _message = Label(@"", BodyFont(), PopoverMessage(), 1);
  _message.alignment = NSTextAlignmentCenter;
  [_card addSubview:_message];
  _messageLink = LinkButton(@" ", self, @selector(messageLinkClicked:));
  [_card addSubview:_messageLink];
  y += kListHeight + 10;
  _spinner = [[NSProgressIndicator alloc]
      initWithFrame:NSMakeRect(kInset, y + (kStatusHeight - 16) / 2, 16, 16)];
  _spinner.style = NSProgressIndicatorStyleSpinning;
  _spinner.controlSize = NSControlSizeSmall;
  _spinner.displayedWhenStopped = NO;
  [root addSubview:_spinner];
  _throbberLabel = Label(_content.throbberText ?: @"",
                         [NSFont systemFontOfSize:13], PopoverMessage(), 0);
  _throbberLabel.toolTip = _content.throbberTooltip;
  PlaceLabel(_throbberLabel, kInset + 24, y + 3, width - 60);
  [root addSubview:_throbberLabel];
  if (_content.rescanLabel.length) {
    _rescan = LinkButton(_content.rescanLabel, self, @selector(rescanClicked:));
    _rescan.toolTip = _content.rescanTooltip;
    _rescan.identifier = @"device-chooser-rescan";
    _rescan.frameOrigin =
        NSMakePoint(kInset - 2, y + (kStatusHeight - NSHeight(_rescan.frame)) / 2);
    [root addSubview:_rescan];
  }
  if (_content.helpLabel.length) {
    _help = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"questionmark.circle"
                                               accessibilityDescription:_content.helpLabel]
                               target:self
                               action:@selector(helpClicked:)];
    _help.bordered = NO;
    _help.contentTintColor = PopoverMessage();
    _help.toolTip = _content.helpLabel;
    _help.accessibilityLabel = _content.helpLabel;
    _help.identifier = @"device-chooser-help";
    _help.frame = NSMakeRect(kWidth - kInset - 22, y + 1, 22, 22);
    [root addSubview:_help];
  }
  y += kStatusHeight + 18;
  _connect = [[PCDialogButton alloc] initWithTitle:_content.okLabel primary:YES];
  _connect.identifier = @"device-chooser-connect";
  _connect.keyEquivalent = @"\r";
  _connect.target = self;
  _connect.action = @selector(connect:);
  _cancel = [[PCDialogButton alloc] initWithTitle:_content.cancelLabel primary:NO];
  _cancel.identifier = @"device-chooser-cancel";
  _cancel.keyEquivalent = @"\033";
  _cancel.target = self;
  _cancel.action = @selector(cancel:);
  y = PlaceFooter(root, y, nil, @[ _connect, _cancel ]);
  root.frame = NSMakeRect(0, 0, kWidth, y);
  _sheet.contentView = root;
  [_sheet setContentSize:NSMakeSize(kWidth, y)];
  _sheet.enterButton = _connect;
  _sheet.escapeButton = _cancel;
  [_sheet setAccessibilityDefaultButton:_connect];
  [_sheet setAccessibilityCancelButton:_cancel];
  _sheet.initialFirstResponder = _table;
}
- (NSWindow*)sheet {
  return _sheet;
}
- (BOOL)valid {
  __attribute__((objc_precise_lifetime)) PCDeviceChooserPresenter* keep = self;
  (void)keep;
  NSView* page = _page;
  NSWindow* window = _window;
  if (_terminal || !page || !window || page.window != window || !window.visible ||
      window.miniaturized || page.hiddenOrHasHiddenAncestor) {
    return NO;
  }
  return _validate && _validate() && !_terminal;
}
- (void)show {
  if (_started || _terminal) {
    return;
  }
  _started = YES;
  [NSRunLoop.mainRunLoop
      performInModes:@[ NSRunLoopCommonModes, NSModalPanelRunLoopMode ]
               block:^{
                 __attribute__((objc_precise_lifetime)) NSWindow* parent =
                     self->_window;
                 if (self->_terminal) {
                   return;
                 }
                 if (![self valid] || !parent || parent.attachedSheet) {
                   [self finish:NO];
                   return;
                 }
                 [parent beginSheet:self->_sheet
                     completionHandler:^(NSModalResponse) {
                       [self finish:NO];
                     }];
                 if (self->_terminal || ![self valid] ||
                     parent.attachedSheet != self->_sheet ||
                     self->_sheet.sheetParent != parent) {
                   [self finish:NO];
                   return;
                 }
                 [self->_sheet makeFirstResponder:self->_table];
               }];
}
- (NSInteger)rowCount {
  return _terminal || !_count ? 0 : std::max<NSInteger>(0, _count());
}
- (BOOL)hasOptions {
  return _adapterEnabled && _adapterAuthorized && [self rowCount] > 0;
}
- (void)update {
  if (_terminal) {
    return;
  }
  const NSInteger count = [self rowCount];
  const BOOL hasOptions = [self hasOptions];
  _scroll.hidden = !hasOptions;
  _table.enabled = hasOptions && !_content.tableAlwaysDisabled;
  NSString* text = nil;
  NSString* link = nil;
  if (!_adapterAuthorized && _content.unauthorizedText) {
    text = _content.unauthorizedText;
    link = _content.unauthorizedLink;
  } else if (_adapterAuthorized && !_adapterEnabled && _content.adapterOffText) {
    text = _content.adapterOffText;
    link = _content.adapterOffLink;
  } else if (count == 0 && _initialized && _adapterEnabled && _adapterAuthorized) {
    text = _content.noOptionsText;
  }
  [self layOutMessage:text link:link];
  if (!_adapterEnabled || !_adapterAuthorized) {
    [self hideThrobber];
  }
  [self updateConnect];
}
- (void)layOutMessage:(NSString*)text link:(NSString*)link {
  _message.hidden = !text.length;
  _messageLink.hidden = !text.length || !link.length;
  if (!text.length) {
    _card.accessibilityLabel = nil;
    return;
  }
  const CGFloat width = NSWidth(_card.bounds) - 40;
  _message.attributedStringValue = [[NSAttributedString alloc]
      initWithString:text
          attributes:@{
            NSFontAttributeName : BodyFont(),
            NSForegroundColorAttributeName : PopoverMessage()
          }];
  _message.alignment = NSTextAlignmentCenter;
  CGFloat height = PlaceLabel(_message, 20, 0, width);
  CGFloat linkHeight = 0;
  if (link.length) {
    NSButton* updated = LinkButton(link, self, @selector(messageLinkClicked:));
    _messageLink.attributedTitle = updated.attributedTitle;
    [_messageLink sizeToFit];
    linkHeight = NSHeight(_messageLink.frame) + 6;
  }
  const CGFloat top = std::max<CGFloat>(12, (NSHeight(_card.bounds) - height - linkHeight) / 2);
  PlaceLabel(_message, 20, top, width);
  if (link.length) {
    _messageLink.frameOrigin = NSMakePoint(
        (NSWidth(_card.bounds) - NSWidth(_messageLink.frame)) / 2, top + height + 6);
  }
}
- (void)updateConnect {
  _connect.enabled = !_terminal && (_content.bothButtonsEnabled ||
                                    (_table.enabled && _table.selectedRowIndexes.count > 0));
}
- (void)showThrobber {
  _rescan.hidden = YES;
  _spinner.hidden = NO;
  _throbberLabel.hidden = NO;
  [_spinner startAnimation:nil];
}
- (void)hideThrobber {
  [_spinner stopAnimation:nil];
  _spinner.hidden = YES;
  _throbberLabel.hidden = YES;
}
- (void)showRescan:(BOOL)enabled {
  if (!_rescan) {
    return;
  }
  _rescan.hidden = NO;
  _rescan.enabled = enabled;
  [self hideThrobber];
}
- (void)optionsInitialized {
  _initialized = YES;
  [_table reloadData];
  [self update];
  [self hideThrobber];
}
- (void)optionAdded:(NSInteger)index {
  _initialized = YES;
  const NSInteger count = [self rowCount];
  if (index >= 0 && index < count && _table.numberOfRows == count - 1) {
    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:index]
                  withAnimation:NSTableViewAnimationEffectNone];
  } else {
    [_table reloadData];
  }
  [self update];
}
- (void)optionRemoved:(NSInteger)index {
  const NSInteger count = [self rowCount];
  if (index >= 0 && index <= count && _table.numberOfRows == count + 1) {
    [_table removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:index]
                  withAnimation:NSTableViewAnimationEffectNone];
  } else {
    [_table reloadData];
  }
  [self update];
}
- (void)optionUpdated:(NSInteger)index {
  if (index >= 0 && index < _table.numberOfRows && _table.numberOfRows == [self rowCount]) {
    [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index]
                      columnIndexes:[NSIndexSet indexSetWithIndex:0]];
  } else {
    [_table reloadData];
  }
  [self update];
}
- (void)adapterEnabledChanged:(BOOL)enabled {
  [_table deselectAll:nil];
  _adapterEnabled = enabled;
  [self update];
  [self showRescan:enabled];
}
- (void)adapterAuthorizationChanged:(BOOL)authorized {
  [_table deselectAll:nil];
  _adapterAuthorized = authorized;
  [self update];
  [self showRescan:authorized];
}
- (void)refreshStateChanged:(BOOL)refreshing {
  if (refreshing) {
    [_table deselectAll:nil];
    [self update];
    [self showThrobber];
  } else {
    [self showRescan:YES];
  }
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return [self rowCount];
}
- (NSView*)tableView:(NSTableView*)tableView
    viewForTableColumn:(NSTableColumn*)tableColumn
                   row:(NSInteger)index {
  NSTableCellView* cell = [tableView makeViewWithIdentifier:@"device-row" owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, kRowHeight)];
    cell.identifier = @"device-row";
    NSTextField* text = [NSTextField labelWithString:@""];
    text.font = BodyFont();
    text.textColor = PopoverTitle();
    text.lineBreakMode = NSLineBreakByTruncatingTail;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:text];
    cell.textField = text;
    NSImageView* image = [[NSImageView alloc] initWithFrame:NSZeroRect];
    image.translatesAutoresizingMaskIntoConstraints = NO;
    image.contentTintColor = PopoverMessage();
    [image setAccessibilityElement:NO];
    [cell addSubview:image];
    cell.imageView = image;
    const BOOL icons = _content.showsIcons;
    [NSLayoutConstraint activateConstraints:@[
      [image.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
      [image.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
      [image.widthAnchor constraintEqualToConstant:icons ? 18 : 0],
      [image.heightAnchor constraintEqualToConstant:18],
      [text.leadingAnchor constraintEqualToAnchor:image.trailingAnchor
                                         constant:icons ? 10 : 2],
      [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
      [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
  }
  PCDeviceChooserRow* row =
      index >= 0 && index < [self rowCount] && _row ? _row(index) : nil;
  cell.textField.stringValue = row.title ?: @"";
  NSImage* icon = nil;
  if (_content.showsIcons && row.connected) {
    icon = [NSImage imageWithSystemSymbolName:@"link" accessibilityDescription:nil];
  } else if (_content.showsIcons && row.level >= 0) {
    icon = [NSImage imageWithSystemSymbolName:@"cellularbars"
                                variableValue:std::min<NSInteger>(row.level, 4) / 4.0
                     accessibilityDescription:nil];
  }
  cell.imageView.image = icon;
  cell.imageView.hidden = !icon;
  NSString* label = row ? RowAccessibilityLabel(row) : @"";
  cell.accessibilityLabel = label;
  cell.textField.accessibilityLabel = label;
  return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  [self updateConnect];
}
- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row {
  return !_terminal && tableView.enabled;
}
- (void)doubleClicked:(id)sender {
  const NSInteger row = _table.clickedRow;
  if (_terminal || row < 0 || !_table.enabled || ![_table isRowSelected:row]) {
    return;
  }
  [self connect:_connect];
}
- (void)connect:(id)sender {
  __attribute__((objc_precise_lifetime)) PCDeviceChooserPresenter* keep = self;
  (void)keep;
  [self updateConnect];
  if (_terminal || !_connect.enabled || !_sheet.visible || ![self valid]) {
    return;
  }
  std::vector<size_t> indices;
  const NSInteger count = [self rowCount];
  if (_table.enabled) {
    NSIndexSet* selected = _table.selectedRowIndexes;
    for (NSUInteger index = selected.firstIndex; index != NSNotFound;
         index = [selected indexGreaterThanIndex:index]) {
      if ((NSInteger)index < count) {
        indices.push_back(index);
      }
    }
  }
  [self finish:YES indices:std::move(indices)];
}
- (void)cancel:(id)sender {
  [self finish:NO];
}
- (void)activate:(PCDeviceChooserLink)link {
  __attribute__((objc_precise_lifetime)) PCDeviceChooserPresenter* keep = self;
  (void)keep;
  if (!_terminal && _sheet.visible && [self valid] && _link) {
    _link(link);
  }
}
- (void)helpClicked:(id)sender {
  [self activate:PCDeviceChooserLinkHelp];
}
- (void)rescanClicked:(id)sender {
  [_sheet makeFirstResponder:_rescan];
  [self activate:PCDeviceChooserLinkRescan];
}
- (void)messageLinkClicked:(id)sender {
  [self activate:_adapterAuthorized ? PCDeviceChooserLinkAdapterOff
                                    : PCDeviceChooserLinkPermission];
}
- (void)finish:(BOOL)accepted {
  [self finish:accepted indices:{}];
}
- (void)finish:(BOOL)accepted indices:(std::vector<size_t>)indices {
  __attribute__((objc_precise_lifetime)) PCDeviceChooserPresenter* keep = self;
  (void)keep;
  if (_terminal) {
    return;
  }
  _terminal = YES;
  [_spinner stopAnimation:nil];
  _table.dataSource = nil;
  _table.delegate = nil;
  if (_sheet.sheetParent) {
    [_sheet.sheetParent endSheet:_sheet];
  }
  [_sheet orderOut:nil];
  auto result = _result;
  _result = nil;
  _count = nil;
  _row = nil;
  _link = nil;
  if (result) {
    result(accepted, std::move(indices));
  }
}
- (void)invalidate {
  _result = nil;
  [self finish:NO];
}
@end

namespace parc {
namespace {
NSString* NSStringFromId(int id) {
  return base::SysUTF16ToNSString(l10n_util::GetStringUTF16(id));
}

class DeviceChooser final : public content::WebContentsObserver,
                            public permissions::ChooserController::View {
 public:
  enum class Ending { kSelect, kCancel, kClose };

  DeviceChooser(content::WebContents& contents,
                content::RenderFrameHost& frame,
                std::unique_ptr<permissions::ChooserController> controller)
      : content::WebContentsObserver(&contents),
        controller_(std::move(controller)),
        document_(frame.GetWeakDocumentPtr()),
        frame_tree_node_id_(frame.GetFrameTreeNodeId()) {}

  ~DeviceChooser() override {
    if (controller_) {
      controller_->set_view(nullptr);
    }
    RemoveObservers();
    [presenter_ invalidate];
    [reservation_ invalidate];
  }

  bool Start() {
    auto* contents = web_contents();
    if (!contents || contents->IsBeingDestroyed() || !Frame()) {
      return false;
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    auxiliary_ = tab ? nullptr : GetNativeAuxiliaryPage(*contents);
    extension_page_ =
        tab || auxiliary_ ? nullptr : GetNativeExtensionPage(*contents);
    if (!tab && !auxiliary_ && !extension_page_) {
      return false;
    }
    if (tab && !tab->IsActivated()) {
      return false;
    }
    fullscreen_blocker_ =
        contents->ForSecurityDropFullscreen(display::kInvalidDisplayId);
    if (!fullscreen_blocker_ || !Frame() || contents->IsBeingDestroyed()) {
      return false;
    }
    if (extension_page_) {
      if (!extension_page_->IsValid()) {
        return false;
      }
      window_ = extension_page_->window();
    } else {
      auto* browser = tab ? tab->GetBrowserWindowInterface()
                          : auxiliary_->browser();
      if (!browser || browser->IsDeleteScheduled() || !browser->GetWindow()) {
        return false;
      }
      browser_ = browser->GetWeakPtr();
      window_ = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    }
    page_ = contents->GetNativeView().GetNativeNSView();
    if (!Valid() || window_.attachedSheet ||
        PCNativeWindowHasSecurityReservation(window_)) {
      return false;
    }
    auto weak = weak_factory_.GetWeakPtr();
    const auto stale = base::BindRepeating(&DeviceChooser::CancelSoon, weak);
    if (auxiliary_) {
      owner_cancel_ = auxiliary_->OnInvalidated(stale);
    } else if (extension_page_) {
      owner_cancel_ = extension_page_->OnInvalidated(stale);
    }
    window_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (weak) {
                    weak->CancelSoon();
                  }
                }];
    security_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (weak && !weak->acquiring_ &&
                      !weak->reservation_.isOnlyReservation) {
                    weak->CancelSoon();
                  }
                }];
    acquiring_ = true;
    PCNativeWindowSecurityReservation* reservation =
        [PCNativeWindowSecurityReservation acquireForWindow:window_];
    acquiring_ = false;
    reservation_ = reservation;
    if (done_ || !reservation.isOnlyReservation || !Valid()) {
      return false;
    }
    presenter_ = [[PCDeviceChooserPresenter alloc] initWithPage:page_
        window:window_
        content:Content()
        count:^NSInteger {
          return weak && weak->controller_
                     ? static_cast<NSInteger>(weak->controller_->NumOptions())
                     : 0;
        }
        row:^PCDeviceChooserRow*(NSInteger index) {
          return weak ? weak->Row(index) : nil;
        }
        validate:^BOOL {
          return weak && weak->Valid();
        }
        link:^(PCDeviceChooserLink link) {
          if (weak) {
            weak->OpenLink(link);
          }
        }
        result:^(BOOL accepted, std::vector<size_t> indices) {
          if (weak) {
            weak->Finish(accepted ? Ending::kSelect : Ending::kCancel,
                         std::move(indices), false);
          }
        }];
    controller_->set_view(this);
    [presenter_ show];
    return !done_;
  }

  void CloseFromCaller() {
    Finish(Ending::kClose, {}, true);
  }

  void OnOptionsInitialized() override { [presenter_ optionsInitialized]; }
  void OnOptionAdded(size_t index) override {
    [presenter_ optionAdded:static_cast<NSInteger>(index)];
  }
  void OnOptionRemoved(size_t index) override {
    [presenter_ optionRemoved:static_cast<NSInteger>(index)];
  }
  void OnOptionUpdated(size_t index) override {
    [presenter_ optionUpdated:static_cast<NSInteger>(index)];
  }
  void OnAdapterEnabledChanged(bool enabled) override {
    [presenter_ adapterEnabledChanged:enabled];
  }
  void OnAdapterAuthorizationChanged(bool authorized) override {
    [presenter_ adapterAuthorizationChanged:authorized];
  }
  void OnRefreshStateChanged(bool refreshing) override {
    [presenter_ refreshStateChanged:refreshing];
  }

  void Finish(Ending ending, std::vector<size_t> indices, bool deferred) {
    if (done_) {
      return;
    }
    done_ = true;
    weak_factory_.InvalidateWeakPtrs();
    Observe(nullptr);
    owner_cancel_ = {};
    RemoveObservers();
    auto* presenter = presenter_;
    presenter_ = nil;
    [presenter invalidate];
    auto* reservation = reservation_;
    reservation_ = nil;
    [reservation invalidate];
    fullscreen_blocker_.reset();
    auto controller = std::move(controller_);
    auto runner = base::SequencedTaskRunner::GetCurrentDefault();
    runner->DeleteSoon(FROM_HERE, this);
    if (!controller) {
      return;
    }
    controller->set_view(nullptr);
    auto end = base::BindOnce(
        [](Ending ending, std::vector<size_t> indices,
           std::unique_ptr<permissions::ChooserController> controller) {
          switch (ending) {
            case Ending::kSelect:
              controller->Select(indices);
              break;
            case Ending::kCancel:
              controller->Cancel();
              break;
            case Ending::kClose:
              controller->Close();
              break;
          }
          base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(
              FROM_HERE, std::move(controller));
        },
        ending, std::move(indices), std::move(controller));
    if (deferred) {
      runner->PostTask(FROM_HERE, std::move(end));
    } else {
      std::move(end).Run();
    }
  }

  base::WeakPtr<DeviceChooser> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

 private:
  content::RenderFrameHost* Frame() const {
    auto* frame = document_.AsRenderFrameHostIfValid();
    return frame && frame->IsActive() && frame->IsRenderFrameLive() &&
                   web_contents() &&
                   content::WebContents::FromRenderFrameHost(frame)
                           ->GetOutermostWebContents() == web_contents()
               ? frame
               : nullptr;
  }

  bool Valid() const {
    auto* contents = web_contents();
    NSWindow* sheet = presenter_.sheet;
    if (done_ || !contents || contents->IsBeingDestroyed() || !Frame() ||
        !controller_ || !window_ || !page_ || page_.window != window_ ||
        !window_.visible || window_.miniaturized ||
        page_.hiddenOrHasHiddenAncestor ||
        contents->GetVisibility() == content::Visibility::HIDDEN ||
        (window_.attachedSheet && window_.attachedSheet != sheet) ||
        (reservation_ ? !reservation_.isOnlyReservation
                      : PCNativeWindowHasSecurityReservation(window_))) {
      return false;
    }
    if (extension_page_) {
      return extension_page_->IsValid() && extension_page_->window() == window_;
    }
    if (!browser_ || browser_->IsDeleteScheduled() || !browser_->GetWindow() ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_) {
      return false;
    }
    if (auxiliary_) {
      return auxiliary_->IsValid() && auxiliary_->IsActive() &&
             auxiliary_->browser() == browser_.get();
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    return tab && tab->IsActivated() && tab->GetContents() == contents &&
           tab->GetBrowserWindowInterface() == browser_.get();
  }

  PCDeviceChooserContent* Content() const {
    auto& controller = *controller_;
    PCDeviceChooserContent* content = [[PCDeviceChooserContent alloc] init];
    content.title = base::SysUTF16ToNSString(controller.GetTitle());
    content.okLabel = base::SysUTF16ToNSString(controller.GetOkButtonLabel());
    content.cancelLabel =
        base::SysUTF16ToNSString(controller.GetCancelButtonLabel());
    content.listLabel =
        NSStringFromId(IDS_DEVICE_CHOOSER_ACCNAME_COMPATIBLE_DEVICES_LIST);
    content.noOptionsText =
        base::SysUTF16ToNSString(controller.GetNoOptionsText());
    auto throbber = controller.GetThrobberLabelAndTooltip();
    content.throbberText = base::SysUTF16ToNSString(throbber.first);
    content.throbberTooltip = base::SysUTF16ToNSString(throbber.second);
    if (controller.ShouldShowReScanButton()) {
      content.rescanLabel = NSStringFromId(IDS_BLUETOOTH_DEVICE_CHOOSER_RE_SCAN);
      content.rescanTooltip =
          NSStringFromId(IDS_BLUETOOTH_DEVICE_CHOOSER_RE_SCAN_TOOLTIP);
    }
    if (controller.ShouldShowHelpButton()) {
      content.helpLabel = NSStringFromId(IDS_LEARN_MORE);
    }
    if (controller.ShouldShowAdapterOffView()) {
      std::u16string link = l10n_util::GetStringUTF16(
          controller.GetTurnAdapterOnLinkTextMessageId());
      size_t offset = 0;
      content.adapterOffText = base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
          controller.GetAdapterOffMessageId(), link, &offset));
      content.adapterOffLink = base::SysUTF16ToNSString(link);
    }
    if (controller.ShouldShowAdapterUnauthorizedView()) {
      std::u16string link = l10n_util::GetStringUTF16(
          controller.GetAuthorizeBluetoothLinkTextMessageId());
      content.unauthorizedText =
          base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
              controller.GetBluetoothUnauthorizedMessageId(), link));
      content.unauthorizedLink = base::SysUTF16ToNSString(link);
    }
    content.showsIcons = controller.ShouldShowIconBeforeText();
    content.multiple = controller.AllowMultipleSelection();
    content.bothButtonsEnabled = controller.BothButtonsAlwaysEnabled();
    content.tableAlwaysDisabled = controller.TableViewAlwaysDisabled();
    return content;
  }

  PCDeviceChooserRow* Row(NSInteger index) const {
    if (!controller_ || index < 0 ||
        static_cast<size_t>(index) >= controller_->NumOptions()) {
      return nil;
    }
    const size_t row = static_cast<size_t>(index);
    std::u16string text = controller_->GetOption(row);
    const bool paired = controller_->IsPaired(row);
    if (paired) {
      text = l10n_util::GetStringFUTF16(
          IDS_DEVICE_CHOOSER_DEVICE_NAME_AND_PAIRED_STATUS_TEXT, text);
    }
    PCDeviceChooserRow* result = [[PCDeviceChooserRow alloc] init];
    result.title = base::SysUTF16ToNSString(text);
    result.paired = paired;
    if (controller_->ShouldShowIconBeforeText()) {
      result.connected = controller_->IsConnected(row);
      result.level = controller_->GetSignalStrengthLevel(row);
    } else {
      result.level = -1;
    }
    return result;
  }

  void OpenLink(PCDeviceChooserLink link) {
    if (done_ || !controller_ || !Valid()) {
      return;
    }
    switch (link) {
      case PCDeviceChooserLinkHelp:
        controller_->OpenHelpCenterUrl();
        break;
      case PCDeviceChooserLinkAdapterOff:
        controller_->OpenAdapterOffHelpUrl();
        break;
      case PCDeviceChooserLinkPermission:
        controller_->OpenPermissionPreferences();
        break;
      case PCDeviceChooserLinkRescan:
        controller_->RefreshOptions();
        break;
    }
  }

  void CancelSoon() { Finish(Ending::kCancel, {}, true); }

  void RemoveObservers() {
    if (window_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:window_observer_];
      window_observer_ = nil;
    }
    if (security_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_observer_];
      security_observer_ = nil;
    }
  }

  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (!navigation->HasCommitted() || navigation->IsSameDocument()) {
      return;
    }
    if (navigation->IsInPrimaryMainFrame() ||
        navigation->GetFrameTreeNodeId() == frame_tree_node_id_) {
      CancelSoon();
    }
  }
  void RenderFrameDeleted(content::RenderFrameHost* frame) override {
    if (frame == document_.AsRenderFrameHostIfValid() || !Frame()) {
      CancelSoon();
    }
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) {
      CancelSoon();
    }
  }
  void WebContentsDestroyed() override { CancelSoon(); }

  std::unique_ptr<permissions::ChooserController> controller_;
  content::WeakDocumentPtr document_;
  const content::FrameTreeNodeId frame_tree_node_id_;
  std::shared_ptr<NativeAuxiliaryPage> auxiliary_;
  std::shared_ptr<NativeExtensionPage> extension_page_;
  base::CallbackListSubscription owner_cancel_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  std::optional<base::ScopedClosureRunner> fullscreen_blocker_;
  NSWindow* __weak window_;
  NSView* __weak page_;
  PCDeviceChooserPresenter* __strong presenter_;
  PCNativeWindowSecurityReservation* __strong reservation_;
  id __strong window_observer_;
  id __strong security_observer_;
  bool acquiring_ = false;
  bool done_ = false;
  base::WeakPtrFactory<DeviceChooser> weak_factory_{this};
};
}

base::OnceClosure ShowNativeDeviceChooser(
    content::RenderFrameHost* frame,
    std::unique_ptr<permissions::ChooserController> controller) {
  CHECK(NSThread.isMainThread);
  if (!controller) {
    return base::DoNothing();
  }
  auto* contents =
      frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
  contents = contents ? contents->GetOutermostWebContents() : nullptr;
  if (!frame || !contents || contents->IsBeingDestroyed() ||
      !frame->IsActive()) {
    controller->Cancel();
    return base::DoNothing();
  }
  auto* chooser = new DeviceChooser(*contents, *frame, std::move(controller));
  auto weak = chooser->GetWeakPtr();
  if (!chooser->Start()) {
    if (weak) {
      weak->Finish(DeviceChooser::Ending::kCancel, {}, false);
    }
    return base::DoNothing();
  }
  return base::BindOnce(&DeviceChooser::CloseFromCaller, std::move(weak));
}
}
