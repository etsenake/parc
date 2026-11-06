// Copyright 2026 Parc contributors.
#import "http_auth_presenter.h"

//
//
//
static NSColor* PCAuthColor(NSColor* light, NSColor* dark) {
  return [NSColor colorWithName:nil
                dynamicProvider:^NSColor*(NSAppearance* appearance) {
                  NSAppearanceName match =
                      [appearance bestMatchFromAppearancesWithNames:@[
                        NSAppearanceNameAqua, NSAppearanceNameDarkAqua
                      ]];
                  return [match isEqualToString:NSAppearanceNameDarkAqua]
                             ? dark
                             : light;
                }];
}
static NSColor* PCAuthForegroundPrimary(void) {
  return PCAuthColor(
      [NSColor colorWithDisplayP3Red:0.0549 green:0.0588 blue:0.0627 alpha:0.9],
      [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.8]);
}
static NSColor* PCAuthForegroundSecondary(void) {
  return PCAuthColor([NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0.5],
                     [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.5]);
}
static NSColor* PCAuthItemBackground(void) {
  return PCAuthColor(
      [NSColor colorWithDisplayP3Red:0.055 green:0.059 blue:0.063 alpha:0.05],
      [NSColor colorWithDisplayP3Red:0.98 green:0.984 blue:1 alpha:0.1]);
}
static NSColor* PCAuthVibrantText(void) {
  return PCAuthColor(
      [NSColor colorWithSRGBRed:0.047 green:0.314 blue:1 alpha:1],
      [NSColor colorWithSRGBRed:0.165 green:0.714 blue:0.965 alpha:1]);
}
//
//
// it the 13-point system font.
static NSFont* PCAuthBodyFont(void) {
  return [NSFont systemFontOfSize:13];
}
// The title: that label font's family at NSFontManager weight 7, traits 0,
//
static NSFont* PCAuthTitleFont(void) {
  NSFont* label = PCAuthBodyFont();
  NSFont* weighted = label.familyName
                         ? [NSFontManager.sharedFontManager
                               fontWithFamily:label.familyName
                                       traits:0
                                       weight:7
                                         size:label.pointSize]
                         : nil;
  return [weighted ?: label fontWithSize:18];
}
// The value of kCACornerCurveContinuous, without a QuartzCore link dependency.
static NSString* const kPCContinuousCorner = @"continuous";
static void PCAuthPin(NSView* child, NSView* parent, CGFloat inset) {
  child.translatesAutoresizingMaskIntoConstraints = NO;
  [parent addSubview:child];
  [NSLayoutConstraint activateConstraints:@[
    [child.topAnchor constraintEqualToAnchor:parent.topAnchor constant:inset],
    [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor
                                        constant:inset],
    [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor
                                         constant:-inset],
    [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor
                                       constant:-inset],
  ]];
}
static NSTextField* PCAuthLabel(NSString* text) {
  NSTextField* label = [NSTextField labelWithString:text];
  label.font = PCAuthBodyFont();
  label.textColor = PCAuthForegroundSecondary();
  label.drawsBackground = NO;
  label.focusRingType = NSFocusRingTypeNone;
  label.bezeled = NO;
  return label;
}

// The bordered field container: radius 5, a 2-point VibrantText border while
// its field edits, the item background.
@interface PCHTTPAuthFieldBox : NSView
@property(nonatomic, strong) NSTextField* field;
@end
@interface PCHTTPAuthTextField : NSTextField
@property(nonatomic, weak) PCHTTPAuthFieldBox* box;
@end
@interface PCHTTPAuthSecureField : NSSecureTextField
@property(nonatomic, weak) PCHTTPAuthFieldBox* box;
@end
@implementation PCHTTPAuthTextField
@synthesize box = _box;
- (BOOL)becomeFirstResponder {
  BOOL result = [super becomeFirstResponder];
  self.box.needsDisplay = YES;
  return result;
}
- (void)textDidEndEditing:(NSNotification*)notification {
  [super textDidEndEditing:notification];
  self.box.needsDisplay = YES;
}
@end
@implementation PCHTTPAuthSecureField
@synthesize box = _box;
- (BOOL)becomeFirstResponder {
  BOOL result = [super becomeFirstResponder];
  self.box.needsDisplay = YES;
  return result;
}
- (void)textDidEndEditing:(NSNotification*)notification {
  [super textDidEndEditing:notification];
  self.box.needsDisplay = YES;
}
@end
@implementation PCHTTPAuthFieldBox
@synthesize field = _field;
- (instancetype)initWithSecure:(BOOL)secure placeholder:(NSString*)placeholder {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.wantsLayer = YES;
    NSTextField* field;
    if (secure) {
      PCHTTPAuthSecureField* secureField = [PCHTTPAuthSecureField new];
      secureField.box = self;
      field = secureField;
    } else {
      PCHTTPAuthTextField* plain = [PCHTTPAuthTextField new];
      plain.box = self;
      field = plain;
    }
    _field = field;
    field.font = PCAuthBodyFont();
    field.textColor = PCAuthForegroundPrimary();
    field.drawsBackground = NO;
    field.usesSingleLineMode = YES;
    field.cell.wraps = NO;
    field.cell.scrollable = YES;
    field.focusRingType = NSFocusRingTypeNone;
    field.bezeled = NO;
    field.placeholderString = placeholder;
    field.accessibilityLabel = placeholder;
    PCAuthPin(field, self, 7);
  }
  return self;
}
- (BOOL)wantsUpdateLayer {
  return YES;
}
- (BOOL)pcEditing {
  NSResponder* responder = self.window.firstResponder;
  return responder == _field ||
         ([responder isKindOfClass:NSText.class] &&
          ((NSText*)responder).delegate == (id)_field);
}
- (void)updateLayer {
  CALayer* layer = self.layer;
  layer.cornerRadius = 5;
  layer.cornerCurve = kPCContinuousCorner;
  layer.borderWidth = 2;
  const BOOL editing = [self pcEditing];
  [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
    layer.borderColor = editing ? PCAuthVibrantText().CGColor
                                : NSColor.clearColor.CGColor;
    layer.backgroundColor = PCAuthItemBackground().CGColor;
  }];
}
@end

//
// radius 5 (continuous) and its own background and title colors.
@interface PCHTTPAuthButton : NSView
@property(nonatomic, strong) NSButton* button;
@property(nonatomic, strong) NSColor* fill;
@end
@implementation PCHTTPAuthButton
@synthesize button = _button;
@synthesize fill = _fill;
- (instancetype)initWithTitle:(NSString*)title
                         fill:(NSColor*)fill
                         text:(NSColor*)text
                       target:(id)target
                       action:(SEL)action {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.wantsLayer = YES;
    _fill = fill;
    NSButton* button = [NSButton buttonWithTitle:title
                                          target:target
                                          action:action];
    _button = button;
    button.bordered = NO;
    NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    button.attributedTitle = [[NSAttributedString alloc]
        initWithString:title
            attributes:@{
              NSForegroundColorAttributeName : text,
              NSFontAttributeName : PCAuthBodyFont(),
              NSParagraphStyleAttributeName : paragraph,
            }];
    PCAuthPin(button, self, 7);
  }
  return self;
}
- (BOOL)wantsUpdateLayer {
  return YES;
}
- (void)updateLayer {
  CALayer* layer = self.layer;
  layer.cornerRadius = 5;
  layer.cornerCurve = kPCContinuousCorner;
  [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
    layer.backgroundColor = self->_fill.CGColor;
  }];
}
@end

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
@end
@interface PCHTTPAuthSheet : NSWindow
@property(nonatomic, weak) PCHTTPAuthPresenter* request;
@end
@implementation PCHTTPAuthSheet
@synthesize request = _request;
- (void)cancelOperation:(id)sender {
  [self.request cancel:sender];
}
@end

@implementation PCHTTPAuthPresenter
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
    //
    // content, transparent title bar, 400 points, then a sheet on the page's
    //
    PCHTTPAuthSheet* sheet = [[PCHTTPAuthSheet alloc]
        initWithContentRect:NSMakeRect(0, 0, 400, 400)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _sheet = sheet;
    sheet.opaque = NO;
    sheet.titlebarAppearsTransparent = YES;
    sheet.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;
    sheet.releasedWhenClosed = NO;
    sheet.request = self;
    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    view.wantsLayer = YES;
    view.layer.cornerRadius = 5;
    view.layer.cornerCurve = kPCContinuousCorner;
    sheet.contentView = view;
    //
    // subtitle reports Chromium's potentially-trustworthy test, which is
    // exactly when the engine supplies no explanation.
    //
    // origin, or for a proxy the sentence "The proxy <url> requires a username
    //
    //
    // never reads the proxy flag here.
    (void)proxy;
    NSString* host = [NSURL URLWithString:authority].host;
    NSTextField* title = PCAuthLabel(
        [@"Sign in to " stringByAppendingString:host.length ? host
                                                            : authority]);
    title.font = PCAuthTitleFont();
    NSTextField* subtitle =
        PCAuthLabel(explanation.length
                        ? @"Your connection to this site is not private."
                        : @"Your connection to this site is private.");
    PCHTTPAuthFieldBox* usernameBox =
        [[PCHTTPAuthFieldBox alloc] initWithSecure:NO placeholder:@"Username"];
    PCHTTPAuthFieldBox* passwordBox =
        [[PCHTTPAuthFieldBox alloc] initWithSecure:YES placeholder:@"Password"];
    _username = usernameBox.field;
    _username.identifier = @"http-auth-username";
    _username.delegate = self;
    _password = (NSSecureTextField*)passwordBox.field;
    _password.identifier = @"http-auth-password";
    _password.delegate = self;
    NSTextField* usernameLabel = PCAuthLabel(@"Username");
    NSTextField* passwordLabel = PCAuthLabel(@"Password");
    usernameLabel.alignment = NSTextAlignmentRight;
    passwordLabel.alignment = NSTextAlignmentRight;
    NSStackView* usernameStack =
        [NSStackView stackViewWithViews:@[ usernameLabel, usernameBox ]];
    NSStackView* passwordStack =
        [NSStackView stackViewWithViews:@[ passwordLabel, passwordBox ]];
    PCHTTPAuthButton* cancel =
        [[PCHTTPAuthButton alloc] initWithTitle:@"Cancel"
                                           fill:PCAuthItemBackground()
                                           text:PCAuthForegroundPrimary()
                                         target:self
                                         action:@selector(cancel:)];
    PCHTTPAuthButton* signIn =
        [[PCHTTPAuthButton alloc] initWithTitle:@"Sign in"
                                           fill:PCAuthVibrantText()
                                           text:NSColor.whiteColor
                                         target:self
                                         action:@selector(accept:)];
    cancel.button.identifier = @"http-auth-cancel";
    signIn.button.identifier = @"http-auth-sign-in";
    _signIn = signIn.button;
    NSStackView* buttons = [NSStackView stackViewWithViews:@[ cancel, signIn ]];
    for (NSView* child in @[
           title, subtitle, usernameStack, passwordStack, buttons
         ]) {
      child.translatesAutoresizingMaskIntoConstraints = NO;
      [view addSubview:child];
    }
    //
    [NSLayoutConstraint activateConstraints:@[
      [title.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
      [title.leadingAnchor constraintEqualToAnchor:view.leadingAnchor
                                          constant:20],
      [title.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor
                                                     constant:-20],
      [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                         constant:20],
      [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
      [subtitle.trailingAnchor
          constraintLessThanOrEqualToAnchor:title.trailingAnchor],
      [usernameBox.widthAnchor constraintEqualToConstant:300],
      [passwordBox.widthAnchor constraintEqualToConstant:300],
      [usernameLabel.widthAnchor constraintEqualToConstant:65],
      [passwordLabel.widthAnchor constraintEqualToConstant:65],
      [usernameStack.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor
                                              constant:15],
      [usernameStack.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
      [usernameStack.heightAnchor constraintEqualToConstant:40],
      [usernameStack.trailingAnchor
          constraintLessThanOrEqualToAnchor:title.trailingAnchor],
      [passwordStack.topAnchor constraintEqualToAnchor:usernameStack.bottomAnchor
                                              constant:15],
      [passwordStack.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
      [passwordStack.trailingAnchor
          constraintLessThanOrEqualToAnchor:title.trailingAnchor],
      [passwordStack.heightAnchor constraintEqualToConstant:40],
      [cancel.widthAnchor constraintEqualToConstant:75],
      [signIn.widthAnchor constraintEqualToConstant:75],
      [buttons.topAnchor constraintEqualToAnchor:passwordStack.bottomAnchor
                                        constant:15],
      [buttons.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
      [buttons.heightAnchor constraintEqualToConstant:40],
      [buttons.bottomAnchor constraintEqualToAnchor:view.bottomAnchor
                                           constant:-15],
    ]];
    [view layoutSubtreeIfNeeded];
    NSSize fitting = view.fittingSize;
    [sheet setContentSize:NSMakeSize(MAX(400, fitting.width), fitting.height)];
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
                 __attribute__((objc_precise_lifetime)) NSWindow* window =
                     self->_window;
                 __attribute__((objc_precise_lifetime)) NSView* page =
                     self->_page;
                 (void)page;
                 if (self->_terminal) {
                   return;
                 }
                 if (![self valid] || !window || window.attachedSheet) {
                   [self finish:PCHTTPAuthInterrupted];
                   return;
                 }
                 [window beginSheet:self->_sheet
                     completionHandler:^(NSModalResponse) {
                       [self finish:PCHTTPAuthInterrupted];
                     }];
                 if (self->_terminal || ![self valid] ||
                     window.attachedSheet != self->_sheet ||
                     self->_sheet.sheetParent != window ||
                     !self->_sheet.visible) {
                   [self finish:PCHTTPAuthInterrupted];
                   return;
                 }
                 [self->_sheet makeFirstResponder:self->_username];
               }];
}
- (void)focus {
  if (!_terminal && _sheet.visible && _sheet.sheetParent == _window &&
      [self valid]) {
    [_sheet makeKeyWindow];
  }
}
- (void)autofillUsername:(NSString*)username password:(NSString*)password {
  if (!_terminal && !_username.stringValue.length) {
    _username.stringValue = username;
    _password.stringValue = password;
    if (_sheet.visible) {
      [_username selectText:nil];
    }
  }
}
//
- (BOOL)control:(NSControl*)control
               textView:(NSTextView*)textView
    doCommandBySelector:(SEL)selector {
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
  if (sender.window == _sheet && sender.enabled && _sheet.visible &&
      _sheet.sheetParent == _window && [self valid]) {
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
  if (_sheet.sheetParent) {
    [_sheet.sheetParent endSheet:_sheet];
  }
  [_sheet orderOut:nil];
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
