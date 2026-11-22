#import "javascript_dialog_presenter.h"

#import "dialog_style.h"

using namespace parc_dialog;

@class PCJavaScriptDialogRequest;

@interface PCJavaScriptDialogPresenter () {
  __weak NSView* _pageView;
  __weak NSWindow* _closingWindow;
  PCJavaScriptDialogRequest* _request;
  BOOL _invalidated;
  BOOL _detaching;
}
- (void)requestFinished:(PCJavaScriptDialogRequest*)request;
- (void)parentWindowWillClose:(NSWindow*)window;
@end

// A request is also the AppKit completion's lifetime anchor. Clearing its
// completion before endSheet prevents a synchronous AppKit callback from
// resolving it a second time. It does not retain its presenter or host.
@interface PCJavaScriptDialogRequest : NSObject <NSTextFieldDelegate>
@property(nonatomic, weak) PCJavaScriptDialogPresenter* owner;
@property(nonatomic, weak) NSView* page;
@property(nonatomic, weak) NSWindow* parent;
@property(nonatomic, strong) NSPanel* sheet;
@property(nonatomic, strong) NSTextField* input;
@property(nonatomic, strong) NSButton* suppression;
@property(nonatomic, strong) NSButton* accept;
@property(nonatomic, strong) NSButton* cancelButton;
@property(nonatomic, strong) NSTimer* inputTimer;
@property(nonatomic) NSTimeInterval allowAfter;
@property(nonatomic, strong) id closeObserver;
@property(nonatomic, copy) PCJavaScriptDialogCompletion completion;
@property(nonatomic, strong) id<PCNativePresentation> presentation;
// fromUser is NO for programmatic handling, cancellation, teardown and another
// owner ending the sheet; only a button or key reports the suppression checkbox.
- (void)finishAccepted:(BOOL)accepted
              override:(NSString*)input
              fromUser:(BOOL)fromUser;
- (void)acceptFromUser:(NSEvent*)key;
- (void)cancelFromUser;
- (BOOL)composing;
@end

static NSEvent* CurrentKeyEvent(void) {
  NSEvent* event = NSApp.currentEvent;
  return event.type == NSEventTypeKeyDown ? event : nil;
}
static BOOL IsPlainKey(NSEvent* event) {
  return !(event.modifierFlags &
           (NSEventModifierFlagCommand | NSEventModifierFlagControl |
            NSEventModifierFlagOption | NSEventModifierFlagShift));
}
// Return, or keypad Enter (U+0003, which misses the button's Return equivalent).
static BOOL IsEnter(NSEvent* event) {
  NSString* characters = event.charactersIgnoringModifiers;
  return IsPlainKey(event) && (event.keyCode == 76 || [characters isEqualToString:@"\003"]);
}

@interface PCJavaScriptDialogSheet : NSPanel
@property(nonatomic, weak) PCJavaScriptDialogRequest* request;
@end
@implementation PCJavaScriptDialogSheet
@synthesize request = _request;
- (void)cancelOperation:(id)sender {
  [self.request cancelFromUser];
}
- (BOOL)performKeyEquivalent:(NSEvent*)event {
  // An input method composing in the prompt keeps its Return and Escape.
  if (event.type == NSEventTypeKeyDown && self.request.composing) {
    return NO;
  }
  if (event.type == NSEventTypeKeyDown && IsEnter(event)) {
    [self.request acceptFromUser:event];
    return YES;
  }
  return [super performKeyEquivalent:event];
}
- (void)keyDown:(NSEvent*)event {
  if (!self.request.composing &&
      (IsEnter(event) ||
       (IsPlainKey(event) && [event.charactersIgnoringModifiers isEqualToString:@"\r"]))) {
    [self.request acceptFromUser:event];
    return;
  }
  [super keyDown:event];
}
@end

@implementation PCJavaScriptDialogRequest
@synthesize owner = _owner;
@synthesize page = _page;
@synthesize parent = _parent;
@synthesize sheet = _sheet;
@synthesize input = _input;
@synthesize suppression = _suppression;
@synthesize accept = _accept;
@synthesize cancelButton = _cancelButton;
@synthesize inputTimer = _inputTimer;
@synthesize allowAfter = _allowAfter;
@synthesize closeObserver = _closeObserver;
@synthesize completion = _completion;
@synthesize presentation = _presentation;
- (BOOL)composing {
  NSText* editor = self.input.currentEditor;
  return [editor isKindOfClass:NSTextView.class] && ((NSTextView*)editor).hasMarkedText;
}
- (void)acceptClicked:(PCDialogButton*)sender {
  [self acceptFromUser:sender.keyEvent ?: CurrentKeyEvent()];
}
- (void)cancelClicked:(id)sender {
  [self cancelFromUser];
}
// A page can open a dialog at any moment, so OK is inert for half a second
// after the sheet appears, and a held or earlier Return never accepts it;
// NSEvent timestamps share systemUptime's clock.
- (void)acceptFromUser:(NSEvent*)key {
  if (!self.completion || !self.accept.enabled || self.composing) {
    return;
  }
  if (key && (key.isARepeat || key.timestamp < self.allowAfter)) {
    return;
  }
  [self finishAccepted:YES override:nil fromUser:YES];
}
// A plain alert has no Cancel, so Escape leaves it open.
- (void)cancelFromUser {
  if (!self.completion || !self.cancelButton) {
    return;
  }
  [self finishAccepted:NO override:nil fromUser:YES];
}
- (BOOL)control:(NSControl*)control
               textView:(NSTextView*)textView
    doCommandBySelector:(SEL)command {
  if (control != self.input || textView.hasMarkedText) {
    return NO;
  }
  if (command == @selector(insertNewline:)) {
    [self acceptFromUser:CurrentKeyEvent()];
    return YES;
  }
  if (command == @selector(cancelOperation:)) {
    [self cancelFromUser];
    return YES;
  }
  return NO;
}
- (void)finishAccepted:(BOOL)accepted
              override:(NSString*)input
              fromUser:(BOOL)fromUser {
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  PCJavaScriptDialogCompletion completion = self.completion;
  if (!completion) {
    return;
  }
  self.completion = nil;
  NSWindow* parent = self.parent;
  // A late click must not accept a request after its page changed windows.
  const BOOL attached = parent && self.page && self.page.window == parent;
  accepted = accepted && attached;
  NSString* result =
      accepted && self.input ? [input ?: self.input.stringValue copy] : @"";
  // The checkbox is reported with either button; a moved page reports none.
  const BOOL suppress = fromUser && attached && self.suppression &&
                        self.suppression.state == NSControlStateValueOn;
  NSPanel* sheet = self.sheet;
  self.sheet = nil;
  ((PCJavaScriptDialogSheet*)sheet).request = nil;
  [self.inputTimer invalidate];
  self.inputTimer = nil;
  for (NSButton* button in @[ self.accept ?: NSNull.null, self.cancelButton ?: NSNull.null ]) {
    if ([button isKindOfClass:NSButton.class]) button.target = nil;
  }
  self.input.delegate = nil;
  self.accept = nil;
  self.cancelButton = nil;
  self.input = nil;
  self.suppression = nil;
  if (self.closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:self.closeObserver];
    self.closeObserver = nil;
  }
  [self.owner requestFinished:self];
  self.owner = nil;
  id<PCNativePresentation> presentation = self.presentation;
  if ([presentation sheetParentOfWindow:sheet]) {
    [presentation window:[presentation sheetParentOfWindow:sheet]
                endSheet:sheet
              returnCode:accepted ? NSModalResponseOK : NSModalResponseCancel];
  }
  [presentation orderOutWindow:sheet];
  completion(accepted, result, suppress);
}
@end

@implementation PCJavaScriptDialogPresenter
@synthesize presentation = _presentation;
@synthesize scheduler = _scheduler;
- (instancetype)initWithPageView:(NSView*)pageView {
  NSParameterAssert(pageView);
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  if ((self = [super init])) {
    _pageView = pageView;
    _presentation = PCNativeSystemPresentation.sharedPresentation;
    _scheduler = PCNativeSystemScheduling.sharedScheduling;
  }
  return self;
}

- (BOOL)isPresenting {
  return _request != nil;
}
- (NSWindow*)presentedSheet {
  return _request.sheet;
}

- (void)presentKind:(PCJavaScriptDialogKind)kind
                title:(NSString*)title
              message:(NSString*)message
          defaultText:(NSString*)defaultText
    offersSuppression:(BOOL)offersSuppression
           completion:(PCJavaScriptDialogCompletion)completion {
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  NSParameterAssert(completion);
  NSView* page = _pageView;
  NSWindow* window = page.window;
  if (_invalidated || _detaching || _request || !window ||
      window == _closingWindow || [_presentation attachedSheetOfWindow:window]) {
    completion(NO, @"", NO);
    return;
  }
  PCJavaScriptDialogRequest* request = [PCJavaScriptDialogRequest new];
  request.owner = self;
  request.page = page;
  request.parent = window;
  request.completion = completion;
  request.presentation = _presentation;
  // The title is the engine's ("<origin> says", "Leave site?"); the page text
  // is the message. Parc's mark stands where NSAlert showed the app icon.
  NSString* heading = title.length ? title : @"This page says";
  PCJavaScriptDialogSheet* sheet = [[PCJavaScriptDialogSheet alloc]
      initWithContentRect:NSMakeRect(0, 0, kWidth, 200)
                styleMask:NSWindowStyleMaskTitled
                  backing:NSBackingStoreBuffered
                    defer:YES];
  sheet.releasedWhenClosed = NO;
  sheet.title = heading;
  sheet.request = request;
  sheet.becomesKeyOnlyIfNeeded = NO;
  sheet.accessibilityLabel = heading;
  PrepareSheet(sheet);
  request.sheet = sheet;
  PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
  CGFloat y = kInset;
  NSRect markRect;
  NSImage* mark = ParcMark(&markRect);
  PCDialogPictureIcon* art = [[PCDialogPictureIcon alloc] initWithImage:mark imageRect:markRect];
  [art setAccessibilityElement:NO];
  art.frameOrigin = NSMakePoint(kInset, y);
  [root addSubview:art];
  y = AddHeading(root, heading, message, y + kArtSize, 240);
  if (kind == PCJavaScriptDialogPrompt) {
    y += message.length ? 16 : 8;
    PCDialogInputField* input = [[PCDialogInputField alloc] initWithText:defaultText];
    input.frame = NSMakeRect(kInset, y, kWidth - 2 * kInset, 36);
    input.field.accessibilityLabel = @"Response";
    input.field.delegate = request;
    request.input = input.field;
    [root addSubview:input];
    y += 36;
  }
  y += 22;
  PCDialogButton* accept = [[PCDialogButton alloc] initWithTitle:@"OK" primary:YES];
  accept.target = request;
  accept.action = @selector(acceptClicked:);
  accept.keyEquivalent = @"\r";
  accept.keyEquivalentModifierMask = 0;
  accept.enabled = NO;
  request.accept = accept;
  NSMutableArray<NSButton*>* buttons = [NSMutableArray arrayWithObject:accept];
  if (kind != PCJavaScriptDialogAlert) {
    PCDialogButton* cancel = [[PCDialogButton alloc] initWithTitle:@"Cancel" primary:NO];
    cancel.target = request;
    cancel.action = @selector(cancelClicked:);
    cancel.keyEquivalent = @"\033";
    cancel.keyEquivalentModifierMask = 0;
    request.cancelButton = cancel;
    [buttons addObject:cancel];
  }
  if (offersSuppression && kind != PCJavaScriptDialogBeforeUnload) {
    request.suppression = [[PCDialogCheckbox alloc] initWithTitle:@"Don't show this again"
                                                           target:nil
                                                           action:nil];
  }
  y = PlaceFooter(root, y, request.suppression, buttons);
  root.frame = NSMakeRect(0, 0, kWidth, y);
  sheet.contentView = root;
  [sheet setContentSize:NSMakeSize(kWidth, y)];
  [sheet setAccessibilityDefaultButton:accept];
  sheet.initialFirstResponder = request.input ?: accept;
  _request = request;
  __weak PCJavaScriptDialogRequest* weakRequest = request;
  request.closeObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:NSWindowWillCloseNotification
                  object:window
                   queue:nil
              usingBlock:^(NSNotification* notification) {
                PCJavaScriptDialogRequest* current = weakRequest;
                [current.owner parentWindowWillClose:notification.object];
                [current finishAccepted:NO override:nil fromUser:NO];
              }];
  [_presentation window:window
             beginSheet:sheet
      completionHandler:^(NSModalResponse) {
        [request finishAccepted:NO override:nil fromUser:NO];
      }];
  if (!request.completion) {
    return;
  }
  if (request.input) {
    [sheet makeFirstResponder:request.input];
  }
  request.allowAfter = _scheduler.systemUptime + .5;
  request.inputTimer = [_scheduler timerWithTimeInterval:.5
                                                 repeats:NO
                                                   block:^(NSTimer*) {
                                                     PCJavaScriptDialogRequest* current = weakRequest;
                                                     if (current.completion) {
                                                       current.accept.enabled = YES;
                                                     }
                                                   }];
  [_scheduler addTimer:request.inputTimer forMode:NSRunLoopCommonModes];
  [_scheduler addTimer:request.inputTimer forMode:NSModalPanelRunLoopMode];
}

- (void)requestFinished:(PCJavaScriptDialogRequest*)request {
  if (_request == request) {
    _request = nil;
  }
}
- (void)parentWindowWillClose:(NSWindow*)window {
  _closingWindow = window;
}
- (void)handleAccepted:(BOOL)accepted promptOverride:(NSString*)input {
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  [_request finishAccepted:accepted override:input fromUser:NO];
}
- (void)cancel {
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  [_request finishAccepted:NO override:nil fromUser:NO];
}
- (void)pageHostWillDetach {
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  _detaching = YES;
  [self cancel];
}
- (void)pageHostDidAttach {
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  NSWindow* window = _pageView.window;
  if (!_invalidated && window && window != _closingWindow) {
    _detaching = NO;
  }
}
- (void)invalidate {
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  _invalidated = YES;
  [self cancel];
}
- (void)dealloc {
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  [_request finishAccepted:NO override:nil fromUser:NO];
}
@end
