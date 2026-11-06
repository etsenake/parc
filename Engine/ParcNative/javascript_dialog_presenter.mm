#import "javascript_dialog_presenter.h"

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
@interface PCJavaScriptDialogRequest : NSObject
@property(nonatomic, weak) PCJavaScriptDialogPresenter* owner;
@property(nonatomic, weak) NSView* page;
@property(nonatomic, weak) NSWindow* parent;
@property(nonatomic, strong) NSAlert* alert;
@property(nonatomic, strong) NSTextField* input;
@property(nonatomic, strong) NSButton* suppression;
@property(nonatomic, strong) id closeObserver;
@property(nonatomic, copy) PCJavaScriptDialogCompletion completion;
// fromUser is NO for programmatic handling, cancellation and teardown; only a
//
//
- (void)finishAccepted:(BOOL)accepted
              override:(NSString*)input
              fromUser:(BOOL)fromUser;
@end

@implementation PCJavaScriptDialogRequest
@synthesize owner = _owner;
@synthesize page = _page;
@synthesize parent = _parent;
@synthesize alert = _alert;
@synthesize input = _input;
@synthesize suppression = _suppression;
@synthesize closeObserver = _closeObserver;
@synthesize completion = _completion;
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
  //
  const BOOL suppress = fromUser && attached && self.suppression &&
                        self.suppression.state == NSControlStateValueOn;
  NSAlert* alert = self.alert;
  self.alert = nil;
  self.input = nil;
  self.suppression = nil;
  if (self.closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:self.closeObserver];
    self.closeObserver = nil;
  }
  [self.owner requestFinished:self];
  self.owner = nil;
  if (alert.window.sheetParent) {
    [alert.window.sheetParent endSheet:alert.window
                            returnCode:accepted ? NSAlertFirstButtonReturn
                                                : NSAlertSecondButtonReturn];
  }
  [alert.window orderOut:nil];
  completion(accepted, result, suppress);
}
@end

@implementation PCJavaScriptDialogPresenter
- (instancetype)initWithPageView:(NSView*)pageView {
  NSParameterAssert(pageView);
  NSCAssert(NSThread.isMainThread,
            @"JavaScript dialogs require the main thread");
  if ((self = [super init])) {
    _pageView = pageView;
  }
  return self;
}

- (BOOL)isPresenting {
  return _request != nil;
}
- (NSWindow*)presentedSheet {
  return _request.alert.window;
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
      window == _closingWindow || window.attachedSheet) {
    completion(NO, @"", NO);
    return;
  }
  PCJavaScriptDialogRequest* request = [PCJavaScriptDialogRequest new];
  request.owner = self;
  request.page = page;
  request.parent = window;
  request.completion = completion;
  //
  // engine's ("<origin> says", "Leave site?"); the page text is informative.
  NSAlert* alert = [NSAlert new];
  request.alert = alert;
  alert.messageText = title.length ? title : @"This page says";
  alert.informativeText = message;
  [alert addButtonWithTitle:@"OK"];
  if (kind != PCJavaScriptDialogAlert) {
    [alert addButtonWithTitle:@"Cancel"];
    alert.buttons[1].keyEquivalent = @"\033";
  }
  NSMutableArray<NSView*>* accessories = [NSMutableArray array];
  if (kind == PCJavaScriptDialogPrompt) {
    NSTextField* field = [NSTextField new];
    field.stringValue = defaultText;
    field.accessibilityLabel = @"Response";
    request.input = field;
    [accessories addObject:field];
  }
  if (offersSuppression && kind != PCJavaScriptDialogBeforeUnload) {
    NSButton* box = [NSButton new];
    [box setButtonType:NSButtonTypeSwitch];
    box.title = @"Don't show this again";
    request.suppression = box;
    [accessories addObject:box];
  }
  if (accessories.count) {
    //
    // view in the top gravity area.
    NSStackView* stack = [[NSStackView alloc]
        initWithFrame:NSMakeRect(0, 0, 280, 24.0 * accessories.count)];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    for (NSView* view in accessories) {
      [stack addView:view inGravity:NSStackViewGravityTop];
    }
    alert.accessoryView = stack;
  }
  if (request.input) {
    alert.window.initialFirstResponder = request.input;
  }
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
  // Never nil: this is a page-bound sheet, not NSAlert's app-modal path.
  [alert beginSheetModalForWindow:window
                completionHandler:^(NSModalResponse result) {
                  [request finishAccepted:result == NSAlertFirstButtonReturn
                                 override:nil
                                 fromUser:YES];
                }];
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
