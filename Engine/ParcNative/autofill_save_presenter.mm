#import "autofill_save_presenter.h"

#import "dialog_style.h"

using namespace parc_dialog;

@interface PCAutofillSavePresenter () {
  __weak NSView* _page;
  __weak NSWindow* _window;
  NSString* _title;
  NSString* _message;
  NSString* _saveLabel;
  NSString* _declineLabel;
  BOOL (^_validateContext)(void);
  void (^_completion)(PCAutofillSaveOutcome);
  NSWindow* _sheet;
  NSButton* _save;
  NSButton* _decline;
  NSButton* _never;
  id _closeObserver;
  BOOL _started;
  BOOL _finished;
  BOOL _invalidated;
}
- (void)finish:(PCAutofillSaveOutcome)outcome;
- (void)save:(id)sender;
- (void)decline:(id)sender;
- (void)never:(id)sender;
@end

@interface PCAutofillSaveSheet : NSWindow
@property(nonatomic, weak) PCAutofillSavePresenter* request;
@end
@implementation PCAutofillSaveSheet
@synthesize request = _request;
- (void)cancelOperation:(id)sender {
  [self.request decline:sender];
}
- (void)insertNewline:(id)sender {
  [self.request save:sender];
}
// Keypad Enter types U+0003, so Save's Return equivalent misses it.
- (void)keyDown:(NSEvent*)event {
  const NSEventModifierFlags modifiers =
      event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl |
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

static void Later(void (^block)(void)) {
  [NSRunLoop.mainRunLoop
      performInModes:@[ NSRunLoopCommonModes, NSModalPanelRunLoopMode ]
               block:block];
}

@implementation PCAutofillSavePresenter
@synthesize onPresented = _onPresented;
@synthesize neverLabel = _neverLabel;
- (instancetype)initWithPageView:(NSView*)page
                          window:(NSWindow*)window
                           title:(NSString*)title
                         message:(NSString*)message
                       saveLabel:(NSString*)saveLabel
                    declineLabel:(NSString*)declineLabel
                 validateContext:(BOOL (^)(void))validateContext
                      completion:(void (^)(PCAutofillSaveOutcome))completion {
  NSParameterAssert(page && window && validateContext && completion);
  NSCAssert(NSThread.isMainThread, @"Autofill requires the UI thread");
  if ((self = [super init])) {
    _page = page;
    _window = window;
    _title = [title copy];
    _message = [message copy];
    _saveLabel = [saveLabel copy];
    _declineLabel = [declineLabel copy];
    _validateContext = [validateContext copy];
    _completion = [completion copy];
    __weak PCAutofillSavePresenter* weakSelf = self;
    _closeObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window
                     queue:nil
                usingBlock:^(NSNotification*) {
                  [weakSelf invalidate];
                }];
  }
  return self;
}
- (BOOL)contextIsValid {
  // The caller validation can enter arbitrary native code. Retain this request
  // and recheck terminal state/physical association after that call returns.
  __attribute__((objc_precise_lifetime)) PCAutofillSavePresenter* keepAlive =
      self;
  (void)keepAlive;
  NSWindow* window = _window;
  NSView* page = _page;
  if (_invalidated || !window || !page || page.window != window) {
    return NO;
  }
  BOOL valid = _validateContext && _validateContext();
  return valid && !_invalidated && _window == window && _page == page &&
         page.window == window;
}
- (void)start {
  NSCAssert(NSThread.isMainThread, @"Autofill requires the UI thread");
  if (_started || _finished) {
    return;
  }
  _started = YES;
  Later(^{
    if (self->_finished) {
      return;
    }
    // Validation may release the shell's last owner. Keep this exact native
    // association alive through attachment rather than reloading weak storage
    // after arbitrary caller code has run.
    __attribute__((objc_precise_lifetime)) NSWindow* window = self->_window;
    __attribute__((objc_precise_lifetime)) NSView* page = self->_page;
    if (!window || !page || !window.visible || window.miniaturized ||
        ![self contextIsValid] || window.attachedSheet) {
      [self finish:PCAutofillSaveInterrupted];
      return;
    }
    PCAutofillSaveSheet* sheet = [[PCAutofillSaveSheet alloc]
        initWithContentRect:NSMakeRect(0, 0, kWidth, 180)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    sheet.releasedWhenClosed = NO;
    sheet.title = self->_title;
    sheet.accessibilityLabel = self->_title;
    sheet.request = self;
    PrepareSheet(sheet);
    PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
    CGFloat y = kInset;
    NSRect markRect;
    NSImage* mark = ParcMark(&markRect);
    PCDialogPictureIcon* art = [[PCDialogPictureIcon alloc] initWithImage:mark
                                                               imageRect:markRect];
    [art setAccessibilityElement:NO];
    art.frameOrigin = NSMakePoint(kInset, y);
    [root addSubview:art];
    y = AddHeading(root, self->_title, self->_message, y + kArtSize, 200) + 22;
    PCDialogButton* save = [[PCDialogButton alloc] initWithTitle:self->_saveLabel primary:YES];
    save.target = self;
    save.action = @selector(save:);
    save.keyEquivalent = @"\r";
    self->_save = save;
    PCDialogButton* decline = [[PCDialogButton alloc] initWithTitle:self->_declineLabel
                                                            primary:NO];
    decline.target = self;
    decline.action = @selector(decline:);
    decline.keyEquivalent = @"\033";
    self->_decline = decline;
    NSMutableArray<NSButton*>* buttons = [NSMutableArray arrayWithObjects:save, decline, nil];
    if (self.neverLabel.length) {
      PCDialogButton* never = [[PCDialogButton alloc] initWithTitle:self.neverLabel primary:NO];
      never.showsHint = NO;
      never.target = self;
      never.action = @selector(never:);
      self->_never = never;
      [buttons addObject:never];
    }
    y = PlaceFooter(root, y, nil, buttons);
    root.frame = NSMakeRect(0, 0, kWidth, y);
    sheet.contentView = root;
    [sheet setContentSize:NSMakeSize(kWidth, y)];
    [sheet setAccessibilityDefaultButton:save];
    if (self->_finished || self->_invalidated || self->_window != window ||
        self->_page != page || page.window != window || window.attachedSheet) {
      [self finish:PCAutofillSaveInterrupted];
      return;
    }
    self->_sheet = sheet;
    [window beginSheet:sheet
        completionHandler:^(NSModalResponse) {
          [self finish:PCAutofillSaveInterrupted];
        }];
    if (self->_finished || self->_invalidated || self->_sheet != sheet ||
        sheet.sheetParent != window || window.attachedSheet != sheet ||
        !sheet.visible || !window.visible || window.miniaturized ||
        self->_window != window || self->_page != page ||
        page.window != window || ![self contextIsValid]) {
      [self finish:PCAutofillSaveInterrupted];
      return;
    }
    // Validation may reenter. Recheck exact association immediately before the
    // once-only event, and make no request access after caller delivery.
    if (self->_finished || self->_invalidated || self->_sheet != sheet ||
        sheet.sheetParent != window || window.attachedSheet != sheet ||
        !sheet.visible || !window.visible || window.miniaturized ||
        page.window != window) {
      [self finish:PCAutofillSaveInterrupted];
      return;
    }
    void (^presented)(void) = self.onPresented;
    self.onPresented = nil;
    if (presented) {
      presented();
    }
  });
}
- (void)save:(id)sender {
  (void)sender;
  [self finish:PCAutofillSaveAccepted];
}
- (void)decline:(id)sender {
  (void)sender;
  [self finish:PCAutofillSaveDeclined];
}
- (void)never:(id)sender {
  (void)sender;
  if (_never && _never.enabled) {
    [self finish:PCAutofillSaveNever];
  }
}
- (void)finish:(PCAutofillSaveOutcome)outcome {
  NSCAssert(NSThread.isMainThread, @"Autofill requires the UI thread");
  if (_finished) {
    return;
  }
  _finished = YES;
  self.onPresented = nil;
  _save.enabled = NO;
  _decline.enabled = NO;
  _never.enabled = NO;
  _save.target = nil;
  _decline.target = nil;
  _never.target = nil;
  NSWindow* sheet = _sheet;
  _sheet = nil;
  if (sheet.sheetParent) {
    [sheet.sheetParent endSheet:sheet];
  }
  [sheet orderOut:nil];
  Later(^{
    if (!self->_completion) {
      return;
    }
    BOOL valid = [self contextIsValid];
    void (^completion)(PCAutofillSaveOutcome) = self->_completion;
    self->_completion = nil;
    self->_validateContext = nil;
    if (self->_closeObserver) {
      [NSNotificationCenter.defaultCenter removeObserver:self->_closeObserver];
      self->_closeObserver = nil;
    }
    completion(valid ? outcome : PCAutofillSaveInterrupted);
  });
}
- (void)invalidate {
  NSCAssert(NSThread.isMainThread, @"Autofill requires the UI thread");
  _invalidated = YES;
  [self finish:PCAutofillSaveInterrupted];
}
- (NSWindow*)sheet {
  return _sheet;
}
- (BOOL)isPresenting {
  return _sheet != nil;
}
- (BOOL)isMouseHovered {
  if (!_sheet || !_sheet.visible) {
    return NO;
  }
  NSPoint point =
      [_sheet.contentView convertPoint:_sheet.mouseLocationOutsideOfEventStream
                              fromView:nil];
  return NSPointInRect(point, _sheet.contentView.bounds);
}
- (void)dealloc {
  NSCAssert(NSThread.isMainThread, @"Autofill requires the UI thread");
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
  // start/finish blocks retain their request through delivery. Owners must call
  // invalidate before releasing a presented request; no callback from dealloc.
  NSCAssert(!_sheet, @"A presented autofill request must be invalidated");
}
@end
