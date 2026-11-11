#import "extension_uninstall_presenter.h"

#import "dialog_style.h"

using namespace parc_dialog;

// A custom sheet, supplied-parent beginSheet and separate Return/Escape
// methods, drawn in Parc's dialog style with the extension's artwork.
@interface PCNativeUninstallPresenter ()
- (void)accept:(id)sender;
- (void)cancel:(id)sender;
- (void)finish:(PCUninstallChoice)choice;
@end
@interface PCNativeUninstallSheet : NSPanel
@property(nonatomic, weak) PCNativeUninstallPresenter* request;
@end
@implementation PCNativeUninstallSheet
@synthesize request = _request;
- (void)cancelOperation:(id)sender {
  [self.request cancel:sender];
}
- (void)insertNewline:(id)sender {
  [self.request accept:sender];
}
- (void)keyDown:(NSEvent*)event {
  // This sheet has no editable text field. Route its standard unmodified
  // Return/Enter commands through the same validity-gated responder action.
  NSEventModifierFlags modifiers =
      event.modifierFlags &
      (NSEventModifierFlagCommand | NSEventModifierFlagControl |
       NSEventModifierFlagOption | NSEventModifierFlagShift);
  NSString* characters = event.charactersIgnoringModifiers;
  if (!modifiers && ([characters isEqualToString:@"\r"] ||
                     [characters isEqualToString:@"\003"])) {
    [self insertNewline:self];
    return;
  }
  [super keyDown:event];
}
@end

@implementation PCNativeUninstallPresenter {
  __weak NSWindow* _parent;
  PCNativeUninstallSheet* _sheet;
  NSButton* _accept;
  NSButton* _cancel;
  NSButton* _checkbox;
  BOOL (^_validate)(void);
  void (^_changed)(BOOL);
  void (^_result)(PCUninstallChoice);
  id _closeObserver;
  id _sheetCloseObserver;
  BOOL _started;
  BOOL _finished;
}
- (instancetype)initWithWindow:(NSWindow*)window
                         title:(NSString*)title
                       message:(NSString*)message
                          icon:(NSImage*)icon
                   acceptLabel:(NSString*)acceptLabel
                   cancelLabel:(NSString*)cancelLabel
                 checkboxLabel:(NSString*)checkboxLabel
                       checked:(BOOL)checked
                      validate:(BOOL (^)(void))validate
                       changed:(void (^)(BOOL))changed
                        result:(void (^)(PCUninstallChoice))result {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  NSParameterAssert(window && title && acceptLabel && cancelLabel && validate &&
                    result);
  if ((self = [super init])) {
    _parent = window;
    _validate = [validate copy];
    _changed = [changed copy];
    _result = [result copy];
    _sheet = [[PCNativeUninstallSheet alloc]
        initWithContentRect:NSMakeRect(0, 0, kWidth, 230)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _sheet.releasedWhenClosed = NO;
    _sheet.title = title;
    _sheet.request = self;
    _sheet.becomesKeyOnlyIfNeeded = NO;
    _sheet.accessibilityLabel = title;
    PrepareSheet(_sheet);
    PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
    CGFloat y = kInset;
    // The adjacent title identifies the extension, so the art is not an element.
    NSImageView* art = ExtensionArt(icon);
    art.frameOrigin = NSMakePoint(kInset, y);
    [root addSubview:art];
    y = AddHeading(root, title, message, y + kArtSize, 200) + 22;
    _accept = [[PCDialogButton alloc] initWithTitle:acceptLabel
                                            primary:YES
                                        destructive:YES];
    _cancel = [[PCDialogButton alloc] initWithTitle:cancelLabel primary:NO];
    _accept.target = self;
    _accept.action = @selector(accept:);
    _cancel.target = self;
    _cancel.action = @selector(cancel:);
    _accept.keyEquivalent = @"\r";
    _cancel.keyEquivalent = @"\033";
    _accept.keyEquivalentModifierMask = 0;
    _cancel.keyEquivalentModifierMask = 0;
    if (checkboxLabel) {
      _checkbox = [[PCDialogCheckbox alloc] initWithTitle:checkboxLabel
                                                   target:self
                                                   action:@selector(checkChanged:)];
      _checkbox.state =
          checked ? NSControlStateValueOn : NSControlStateValueOff;
    }
    y = PlaceFooter(root, y, _checkbox, @[ _accept, _cancel ]);
    root.frame = NSMakeRect(0, 0, kWidth, y);
    _sheet.contentView = root;
    [_sheet setContentSize:NSMakeSize(kWidth, y)];
    // Return is the Remove button's key equivalent; a default button cell
    // would tint over the drawn face.
    [_sheet setAccessibilityDefaultButton:_accept];
    _sheet.initialFirstResponder = _checkbox ?: _accept;
    __weak PCNativeUninstallPresenter* weak = self;
    _closeObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window
                     queue:nil
                usingBlock:^(NSNotification*) {
                  [weak invalidate];
                }];
    _sheetCloseObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:_sheet
                     queue:nil
                usingBlock:^(NSNotification*) {
                  [weak invalidate];
                }];
  }
  return self;
}
- (BOOL)valid {
  __attribute__((objc_precise_lifetime)) PCNativeUninstallPresenter* keep =
      self;
  NSWindow* parent = _parent;
  BOOL result = !_finished && parent && parent.visible &&
                !parent.miniaturized && _validate && _validate();
  (void)keep;
  return result && !_finished && _parent == parent;
}
- (void)start {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if (_started || _finished) {
    return;
  }
  _started = YES;
  [NSRunLoop.mainRunLoop
      performInModes:@[ NSRunLoopCommonModes, NSModalPanelRunLoopMode ]
               block:^{
                 __attribute__((objc_precise_lifetime))
                 PCNativeUninstallPresenter* keep = self;
                 __attribute__((objc_precise_lifetime)) NSWindow* parent =
                     self->_parent;
                 PCNativeUninstallSheet* sheet = self->_sheet;
                 if (![self valid] || parent.attachedSheet) {
                   [self finish:PCUninstallInterrupted];
                   return;
                 }
                 [parent beginSheet:sheet
                     completionHandler:^(NSModalResponse) {
                       [self finish:PCUninstallInterrupted];
                     }];
                 if (!self->_finished &&
                     (![self valid] || self->_sheet != sheet ||
                      sheet.sheetParent != parent ||
                      parent.attachedSheet != sheet || !sheet.visible)) {
                   [self finish:PCUninstallInterrupted];
                 }
                 (void)keep;
               }];
}
- (void)accept:(id)sender {
  (void)sender;
  if (_accept.enabled) {
    [self finish:PCUninstallAccept];
  }
}
- (void)cancel:(id)sender {
  (void)sender;
  if (_cancel.enabled) {
    [self finish:PCUninstallCancel];
  }
}
- (void)checkChanged:(NSButton*)sender {
  __attribute__((objc_precise_lifetime)) PCNativeUninstallPresenter* keep =
      self;
  if ([self valid] && _changed) {
    _changed(sender.state == NSControlStateValueOn);
  }
  (void)keep;
}
- (void)finish:(PCUninstallChoice)choice {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  __attribute__((objc_precise_lifetime)) PCNativeUninstallPresenter* keep =
      self;
  if (_finished) {
    return;
  }
  if (choice == PCUninstallAccept && ![self valid]) {
    choice = PCUninstallInterrupted;
  }
  if (_finished) {
    return;
  }
  _finished = YES;
  auto callback = _result;
  _result = nil;
  _changed = nil;
  _validate = nil;
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
  if (_sheetCloseObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_sheetCloseObserver];
  }
  _closeObserver = nil;
  _sheetCloseObserver = nil;
  PCNativeUninstallSheet* sheet = _sheet;
  _sheet = nil;
  sheet.request = nil;
  for (NSButton* button in @[ _accept, _cancel ]) {
    button.enabled = NO;
    button.target = nil;
  }
  _checkbox.enabled = NO;
  _checkbox.target = nil;
  if (sheet.sheetParent) {
    [sheet.sheetParent endSheet:sheet returnCode:NSModalResponseCancel];
  }
  [sheet orderOut:nil];
  if (callback) {
    callback(choice);
  }
  (void)keep;
}
- (void)invalidate {
  [self finish:PCUninstallInterrupted];
}
- (void)setAcceptEnabled:(BOOL)enabled cancelEnabled:(BOOL)cancelEnabled {
  if (_finished) {
    return;
  }
  _accept.enabled = enabled;
  _cancel.enabled = cancelEnabled;
}
- (NSWindow*)sheet {
  return _sheet;
}
- (BOOL)isPresenting {
  return !_finished && _sheet.sheetParent == _parent && _sheet.visible;
}
- (void)dealloc {
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
  if (_sheetCloseObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_sheetCloseObserver];
  }
  NSCAssert(!_sheet.sheetParent,
            @"Presented requests require explicit invalidation");
}
@end
