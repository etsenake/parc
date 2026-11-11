// Copyright 2026 Parc contributors.
#import "external_protocol_presenter.h"

#import "dialog_style.h"

using namespace parc_dialog;

@interface PCExternalProtocolPresenter () {
  __weak NSView* _page;
  __weak NSWindow* _window;
  NSWindow* _sheet;
  NSButton* _open;
  BOOL (^_validate)(void);
  BOOL (^_inputAllowed)(NSEvent*);
  void (^_stateChanged)(void);
  void (^_result)(BOOL, BOOL);
  NSMutableArray* _observers;
  BOOL _started, _terminal, _invalidated;
}
- (void)accept:(id)sender;
- (void)acceptRemembering:(id)sender;
- (void)cancel:(id)sender;
- (void)acceptFromKeyboard;
- (void)finish:(BOOL)accepted remember:(BOOL)remember;
@end
@interface PCExternalProtocolSheet : NSPanel
@property(nonatomic, weak) PCExternalProtocolPresenter* request;
@end
@implementation PCExternalProtocolSheet
@synthesize request = _request;
- (void)cancelOperation:(id)sender {
  [self.request cancel:sender];
}
// Keypad Enter types U+0003, which misses Open's Return equivalent; it takes
// the same input-protected Open path.
- (BOOL)performKeyEquivalent:(NSEvent*)event {
  const BOOL plain = !(event.modifierFlags &
                       (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                        NSEventModifierFlagOption | NSEventModifierFlagShift));
  if (event.type == NSEventTypeKeyDown && plain &&
      (event.keyCode == 76 || [event.charactersIgnoringModifiers isEqualToString:@"\003"])) {
    [self.request acceptFromKeyboard];
    return YES;
  }
  return [super performKeyEquivalent:event];
}
@end
@implementation PCExternalProtocolPresenter
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                       title:(NSString*)title
                     message:(NSString*)message
                        icon:(NSImage*)icon
                 acceptLabel:(NSString*)acceptLabel
                 cancelLabel:(NSString*)cancelLabel
               rememberLabel:(NSString*)rememberLabel
                    validate:(BOOL (^)(void))validate
                inputAllowed:(BOOL (^)(NSEvent*))inputAllowed
                stateChanged:(void (^)(void))stateChanged
                      result:(void (^)(BOOL, BOOL))result {
  NSParameterAssert(page && window && validate && inputAllowed &&
                    stateChanged && result);
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if ((self = [super init])) {
    _page = page;
    _window = window;
    _validate = [validate copy];
    _inputAllowed = [inputAllowed copy];
    _stateChanged = [stateChanged copy];
    _result = [result copy];
    PCExternalProtocolSheet* sheet = [[PCExternalProtocolSheet alloc]
        initWithContentRect:NSMakeRect(0, 0, kWidth, 200)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    sheet.releasedWhenClosed = NO;
    sheet.becomesKeyOnlyIfNeeded = NO;
    sheet.title = title;
    sheet.accessibilityLabel = title;
    sheet.request = self;
    PrepareSheet(sheet);
    PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
    CGFloat y = kInset;
    // The destination application's icon, else Parc's mark.
    NSView* art;
    if (icon) {
      NSImageView* image = [NSImageView imageViewWithImage:icon];
      image.imageScaling = NSImageScaleProportionallyUpOrDown;
      image.frame = NSMakeRect(0, 0, kArtSize, kArtSize);
      art = image;
    } else {
      NSRect markRect;
      NSImage* mark = ParcMark(&markRect);
      art = [[PCDialogPictureIcon alloc] initWithImage:mark imageRect:markRect];
    }
    [art setAccessibilityElement:NO];
    art.frameOrigin = NSMakePoint(kInset, y);
    [root addSubview:art];
    y = AddHeading(root, title, message, y + kArtSize, 200) + 22;
    // Open is the default (Return) and Cancel answers Escape. Every button
    // reports here, so only an explicit, protected decision ends the request.
    PCDialogButton* open = [[PCDialogButton alloc] initWithTitle:acceptLabel primary:YES];
    open.identifier = @"external-protocol-open";
    open.target = self;
    open.action = @selector(accept:);
    open.keyEquivalent = @"\r";
    _open = open;
    PCDialogButton* cancel = [[PCDialogButton alloc] initWithTitle:cancelLabel primary:NO];
    cancel.identifier = @"external-protocol-cancel";
    cancel.keyEquivalent = @"\033";
    cancel.target = self;
    cancel.action = @selector(cancel:);
    NSMutableArray<NSButton*>* buttons = [NSMutableArray arrayWithObjects:open, cancel, nil];
    if (rememberLabel.length) {
      PCDialogButton* remember = [[PCDialogButton alloc] initWithTitle:rememberLabel primary:NO];
      remember.showsHint = NO;
      remember.identifier = @"external-protocol-remember";
      remember.target = self;
      remember.action = @selector(acceptRemembering:);
      [buttons addObject:remember];
    }
    y = PlaceFooter(root, y, nil, buttons);
    root.frame = NSMakeRect(0, 0, kWidth, y);
    sheet.contentView = root;
    [sheet setContentSize:NSMakeSize(kWidth, y)];
    [sheet setAccessibilityDefaultButton:open];
    _sheet = sheet;
    _observers = [NSMutableArray new];
    __weak PCExternalProtocolPresenter* weak = self;
    [_observers addObject:[NSNotificationCenter.defaultCenter
                              addObserverForName:NSWindowWillCloseNotification
                                          object:window
                                           queue:nil
                                      usingBlock:^(NSNotification*) {
                                        [weak invalidate];
                                      }]];
    for (NSWindow* target in @[ window, _sheet ]) {
      for (NSNotificationName name in @[
             NSWindowDidBecomeKeyNotification, NSWindowDidMoveNotification,
             NSWindowDidResizeNotification
           ]) {
        [_observers addObject:[NSNotificationCenter.defaultCenter
                                  addObserverForName:name
                                              object:target
                                               queue:nil
                                          usingBlock:^(NSNotification*) {
                                            PCExternalProtocolPresenter* owner =
                                                weak;
                                            if (owner && !owner->_terminal &&
                                                owner->_stateChanged) {
                                              owner->_stateChanged();
                                            }
                                          }]];
      }
    }
  }
  return self;
}
- (NSWindow*)sheet {
  return _sheet;
}
- (BOOL)valid {
  __attribute__((objc_precise_lifetime)) PCExternalProtocolPresenter* keep =
      self;
  (void)keep;
  NSView* page = _page;
  NSWindow* window = _window;
  if (_invalidated || !page || !window || page.window != window ||
      !window.visible || window.miniaturized ||
      page.hiddenOrHasHiddenAncestor) {
    return NO;
  }
  BOOL valid = _validate && _validate();
  return valid && !_invalidated && _page == page && _window == window &&
         page.window == window && window.visible && !window.miniaturized &&
         !page.hiddenOrHasHiddenAncestor;
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
                 __attribute__((objc_precise_lifetime)) NSView* page =
                     self->_page;
                 (void)page;
                 if (self->_terminal) {
                   return;
                 }
                 if (![self valid] || !parent || parent.attachedSheet) {
                   [self finish:NO remember:NO];
                   return;
                 }
                 self->_stateChanged();
                 if (self->_terminal || ![self valid]) {
                   [self finish:NO remember:NO];
                   return;
                 }
                 // A sheet on the page's window.
                 [parent beginSheet:self->_sheet
                     completionHandler:^(NSModalResponse) {
                       [self finish:NO remember:NO];
                     }];
                 if (self->_terminal || ![self valid] ||
                     parent.attachedSheet != self->_sheet ||
                     self->_sheet.sheetParent != parent ||
                     !self->_sheet.visible) {
                   [self finish:NO remember:NO];
                   return;
                 }
                 self->_stateChanged();
               }];
}
- (void)focus {
  if (!_terminal && _sheet.visible && _sheet.sheetParent == _window &&
      [self valid]) {
    [_sheet makeKeyWindow];
  }
}
- (void)decide:(NSButton*)sender remember:(BOOL)remember {
  __attribute__((objc_precise_lifetime)) PCExternalProtocolPresenter* keep =
      self;
  (void)keep;
  if (_terminal || sender.window != _sheet || !sender.enabled ||
      !_sheet.visible || _sheet.sheetParent != _window || ![self valid]) {
    return;
  }
  // Chromium's input protection still gates the accepting buttons, including
  // Return and keypad Enter on the default Open button.
  BOOL allowed = _inputAllowed && _inputAllowed(NSApp.currentEvent);
  if (allowed && !_terminal && [self valid]) {
    [self finish:YES remember:remember];
  }
}
- (void)accept:(NSButton*)sender {
  [self decide:sender remember:NO];
}
- (void)acceptRemembering:(NSButton*)sender {
  [self decide:sender remember:YES];
}
- (void)acceptFromKeyboard {
  [self decide:_open remember:NO];
}
- (void)cancel:(id)sender {
  [self finish:NO remember:NO];
}
- (void)finish:(BOOL)accepted remember:(BOOL)remember {
  __attribute__((objc_precise_lifetime)) PCExternalProtocolPresenter* keep =
      self;
  (void)keep;
  if (_terminal) {
    return;
  }
  _terminal = YES;
  if (_sheet.sheetParent) {
    [_sheet.sheetParent endSheet:_sheet];
  }
  [_sheet orderOut:nil];
  auto result = _result;
  _result = nil;
  if (result) {
    result(accepted, accepted && remember);
  }
}
- (void)invalidate {
  _invalidated = YES;
  [self finish:NO remember:NO];
}
- (void)dealloc {
  for (id observer in _observers) {
    [NSNotificationCenter.defaultCenter removeObserver:observer];
  }
}
@end
