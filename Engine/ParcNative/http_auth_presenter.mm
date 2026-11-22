// Copyright 2026 Parc contributors.
#import "http_auth_presenter.h"

#import "dialog_style.h"

using namespace parc_dialog;

@interface PCHTTPAuthPresenter () <NSTextFieldDelegate> {
  __weak NSView* _page;
  __weak NSWindow* _window;
  NSWindow* _sheet;
  NSTextField* _username;
  NSSecureTextField* _password;
  NSButton* _signIn;
  BOOL (^_validate)(void);
  void (^_result)(PCHTTPAuthChoice, NSString*, NSString*);
  id _closeObserver;
  BOOL _started;
  BOOL _terminal;
  BOOL _invalidated;
}
- (void)accept:(id)sender;
- (void)cancel:(id)sender;
- (void)finish:(PCHTTPAuthChoice)choice;
- (void)acceptFromKeyboard;
- (BOOL)composing;
@end
@interface PCHTTPAuthSheet : NSWindow
@property(nonatomic, weak) PCHTTPAuthPresenter* request;
@end
@implementation PCHTTPAuthSheet
@synthesize request = _request;
- (void)cancelOperation:(id)sender {
  [self.request cancel:sender];
}
// Return and Escape answer from any focus, except while an input method is
// composing in a field. Keypad Enter types U+0003, which misses
// Sign in's Return equivalent.
- (BOOL)performKeyEquivalent:(NSEvent*)event {
  if (event.type != NSEventTypeKeyDown) {
    return [super performKeyEquivalent:event];
  }
  if (self.request.composing) {
    return NO;
  }
  const BOOL plain = !(event.modifierFlags &
                       (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                        NSEventModifierFlagOption | NSEventModifierFlagShift));
  if (plain && (event.keyCode == 76 ||
                [event.charactersIgnoringModifiers isEqualToString:@"\003"])) {
    [self.request acceptFromKeyboard];
    return YES;
  }
  return [super performKeyEquivalent:event];
}
@end

@implementation PCHTTPAuthPresenter
@synthesize presentation = _presentation;
@synthesize scheduler = _scheduler;
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                   authority:(NSString*)authority
                 explanation:(NSString*)explanation
                       proxy:(BOOL)proxy
                    validate:(BOOL (^)(void))validate
                      result:(void (^)(PCHTTPAuthChoice, NSString*, NSString*))
                                 result {
  NSParameterAssert(page && window && authority.length && validate && result);
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if ((self = [super init])) {
    _page = page;
    _window = window;
    _validate = [validate copy];
    _result = [result copy];
    _presentation = PCNativeSystemPresentation.sharedPresentation;
    _scheduler = PCNativeSystemScheduling.sharedScheduling;
    PCHTTPAuthSheet* sheet = [[PCHTTPAuthSheet alloc]
        initWithContentRect:NSMakeRect(0, 0, kWidth, 400)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _sheet = sheet;
    PrepareSheet(sheet);
    sheet.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;
    sheet.releasedWhenClosed = NO;
    sheet.request = self;
    // "Sign in to <host>", else the authority itself. The subtitle reports
    // Chromium's potentially-trustworthy test, which is exactly when the
    // engine supplies no explanation. For a proxy Chromium's authority is the
    // sentence "The proxy <url> requires a username and password."; NSURL
    // finds no host in it, so the title carries the whole sentence.
    (void)proxy;
    NSString* host = [NSURL URLWithString:authority].host;
    NSString* titleText =
        [@"Sign in to " stringByAppendingString:host.length ? host : authority];
    sheet.title = titleText;
    sheet.accessibilityLabel = titleText;
    PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
    __block CGFloat y = kInset;
    NSRect markRect;
    NSImage* mark = ParcMark(&markRect);
    PCDialogPictureIcon* art = [[PCDialogPictureIcon alloc] initWithImage:mark
                                                               imageRect:markRect];
    [art setAccessibilityElement:NO];
    art.frameOrigin = NSMakePoint(kInset, y);
    [root addSubview:art];
    y = AddHeading(root, titleText,
                   explanation.length ? @"Your connection to this site is not private."
                                      : @"Your connection to this site is private.",
                   y + kArtSize, 200);
    const CGFloat width = kWidth - 2 * kInset;
    NSTextField* (^addField)(NSString*, BOOL) = ^NSTextField*(NSString* name, BOOL secure) {
      NSTextField* label = Label(name, [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
                                 PopoverMessage(), 0);
      [root addSubview:label];
      y += PlaceLabel(label, kInset, y, width) + 6;
      PCDialogInputField* input = [[PCDialogInputField alloc] initWithText:@"" secure:secure];
      input.frame = NSMakeRect(kInset, y, width, 36);
      input.field.placeholderString = name;
      input.field.accessibilityLabel = name;
      [root addSubview:input];
      y += 36;
      return input.field;
    };
    y += 18;
    _username = addField(@"Username", NO);
    _username.identifier = @"http-auth-username";
    _username.delegate = self;
    y += 14;
    _password = (NSSecureTextField*)addField(@"Password", YES);
    _password.identifier = @"http-auth-password";
    _password.delegate = self;
    y += 22;
    PCDialogButton* cancel = [[PCDialogButton alloc] initWithTitle:@"Cancel" primary:NO];
    cancel.target = self;
    cancel.action = @selector(cancel:);
    cancel.keyEquivalent = @"\033";
    cancel.identifier = @"http-auth-cancel";
    PCDialogButton* signIn = [[PCDialogButton alloc] initWithTitle:@"Sign in" primary:YES];
    signIn.target = self;
    signIn.action = @selector(accept:);
    signIn.keyEquivalent = @"\r";
    signIn.identifier = @"http-auth-sign-in";
    _signIn = signIn;
    y = PlaceFooter(root, y, nil, @[ signIn, cancel ]);
    root.frame = NSMakeRect(0, 0, kWidth, y);
    sheet.contentView = root;
    [sheet setContentSize:NSMakeSize(kWidth, y)];
    [sheet setAccessibilityDefaultButton:signIn];
    [sheet center];
    sheet.initialFirstResponder = _username;
    __weak PCHTTPAuthPresenter* weak = self;
    _closeObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window
                     queue:nil
                usingBlock:^(NSNotification*) {
                  [weak invalidate];
                }];
  }
  return self;
}
- (NSWindow*)sheet {
  return _sheet;
}
- (BOOL)valid {
  __attribute__((objc_precise_lifetime)) PCHTTPAuthPresenter* keep = self;
  (void)keep;
  NSView* page = _page;
  NSWindow* window = _window;
  if (_invalidated || !page || !window || page.window != window ||
      ![_presentation isWindowVisible:window] || window.miniaturized ||
      page.hiddenOrHasHiddenAncestor) {
    return NO;
  }
  BOOL valid = _validate && _validate();
  return valid && !_invalidated && _page == page && _window == window &&
         page.window == window && [_presentation isWindowVisible:window] && !window.miniaturized &&
         !page.hiddenOrHasHiddenAncestor;
}
- (void)show {
  if (_started || _terminal) {
    return;
  }
  _started = YES;
  [_scheduler
      performInModes:@[ NSRunLoopCommonModes, NSModalPanelRunLoopMode ]
               block:^{
                 __attribute__((objc_precise_lifetime)) NSWindow* window =
                     self->_window;
                 __attribute__((objc_precise_lifetime)) NSView* page =
                     self->_page;
                 (void)page;
                 if (self->_terminal) {
                   return;
                 }
                 if (![self valid] || !window || [self->_presentation attachedSheetOfWindow:window]) {
                   [self finish:PCHTTPAuthInterrupted];
                   return;
                 }
                 [self->_presentation window:window beginSheet:self->_sheet
                     completionHandler:^(NSModalResponse) {
                       [self finish:PCHTTPAuthInterrupted];
                     }];
                 if (self->_terminal || ![self valid] ||
                     [self->_presentation attachedSheetOfWindow:window] != self->_sheet ||
                     [self->_presentation sheetParentOfWindow:self->_sheet] != window ||
                     ![self->_presentation isWindowVisible:self->_sheet]) {
                   [self finish:PCHTTPAuthInterrupted];
                   return;
                 }
                 [self->_sheet makeFirstResponder:self->_username];
               }];
}
- (void)focus {
  if (!_terminal && [_presentation isWindowVisible:_sheet] && [_presentation sheetParentOfWindow:_sheet] == _window &&
      [self valid]) {
    [_presentation makeKeyWindow:_sheet];
  }
}
- (void)autofillUsername:(NSString*)username password:(NSString*)password {
  if (!_terminal && !_username.stringValue.length) {
    _username.stringValue = username;
    _password.stringValue = password;
    if ([_presentation isWindowVisible:_sheet]) {
      [_username selectText:nil];
    }
  }
}
- (BOOL)composing {
  NSResponder* responder = _sheet.firstResponder;
  return [responder isKindOfClass:NSTextView.class] && ((NSTextView*)responder).hasMarkedText;
}
- (void)acceptFromKeyboard {
  [self accept:_signIn];
}
// Return signs in and Escape cancels, after any input-method composition.
- (BOOL)control:(NSControl*)control
               textView:(NSTextView*)textView
    doCommandBySelector:(SEL)selector {
  if (textView.hasMarkedText) {
    return NO;
  }
  if (selector == @selector(insertNewline:)) {
    [self accept:_signIn];
    return YES;
  }
  if (selector == @selector(cancelOperation:)) {
    [self cancel:control];
    return YES;
  }
  return NO;
}
- (void)accept:(NSButton*)sender {
  if (sender.window == _sheet && sender.enabled && [_presentation isWindowVisible:_sheet] &&
      [_presentation sheetParentOfWindow:_sheet] == _window && [self valid]) {
    [self finish:PCHTTPAuthAccept];
  }
}
- (void)cancel:(id)sender {
  [self finish:PCHTTPAuthCancel];
}
- (void)finish:(PCHTTPAuthChoice)choice {
  __attribute__((objc_precise_lifetime)) PCHTTPAuthPresenter* keep = self;
  (void)keep;
  if (_terminal) {
    return;
  }
  _terminal = YES;
  NSString* username =
      choice == PCHTTPAuthAccept ? [_username.stringValue copy] : @"";
  NSString* password =
      choice == PCHTTPAuthAccept ? [_password.stringValue copy] : @"";
  _username.stringValue = @"";
  _password.stringValue = @"";
  if ([_presentation sheetParentOfWindow:_sheet]) {
    [_presentation window:[_presentation sheetParentOfWindow:_sheet] endSheet:_sheet];
  }
  [_presentation orderOutWindow:_sheet];
  auto result = _result;
  _result = nil;
  // The controller defers the Chromium continuation non-nestably. No native
  // state is touched after invoking a result that may release this presenter.
  if (result) {
    result(choice, username, password);
  }
}
- (void)invalidate {
  _invalidated = YES;
  [self finish:PCHTTPAuthInterrupted];
}
- (void)dealloc {
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
}
@end
