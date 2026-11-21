#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"

#import "http_auth_presenter.h"
#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
static void Pump() {
  ParcNativeAdvance(.08);
}
static NSWindow* Window(bool visible = true) {
  NSWindow* w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2300, -2300, 640, 480)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  w.releasedWhenClosed = NO;
  if (visible) {
    ParcNativeMarkVisible(w);
  }
  return w;
}
static NSView* Page(NSWindow* w) {
  NSView* p = [[NSView alloc] initWithFrame:w.contentView.bounds];
  [w.contentView addSubview:p];
  return p;
}
static NSTextField* Label(NSView* v, NSString* text) {
  if ([v isKindOfClass:NSTextField.class] &&
      [static_cast<NSTextField*>(v).stringValue isEqual:text]) {
    return static_cast<NSTextField*>(v);
  }
  for (NSView* child in v.subviews) {
    if (auto f = Label(child, text)) {
      return f;
    }
  }
  return nil;
}
static NSView* Find(NSView* v, NSString* name) {
  if ([v.identifier isEqual:name] ||
      ([v isKindOfClass:NSButton.class] &&
       [static_cast<NSButton*>(v).title isEqual:name])) {
    return v;
  }
  for (NSView* child in v.subviews) {
    if (auto f = Find(child, name)) {
      return f;
    }
  }
  return nil;
}
static PCHTTPAuthPresenter* Make(NSView* p,
                                 NSWindow* w,
                                 bool proxy,
                                 BOOL (^valid)(void),
                                 void (^result)(PCHTTPAuthChoice,
                                                NSString*,
                                                NSString*)) {
  return [[PCHTTPAuthPresenter alloc]
      initWithPage:p
            window:w
         authority:proxy ? @"The proxy http://proxy.example:8080 requires a "
                           @"username and password."
                         : @"https://login.example:8443"
       explanation:proxy ? @"Your connection is not private." : @""
             proxy:proxy
          validate:valid
            result:result];
}
@interface AuthState : NSObject
@property int count;
@property PCHTTPAuthChoice outcome;
@property(copy) NSString* user;
@property(copy) NSString* secret;
@end
@implementation AuthState
@end

static NSTextField* UsernameField(PCHTTPAuthPresenter* r) {
  return static_cast<NSTextField*>(Find(r.sheet.contentView, @"http-auth-username"));
}
static NSSecureTextField* PasswordField(PCHTTPAuthPresenter* r) {
  return static_cast<NSSecureTextField*>(Find(r.sheet.contentView, @"http-auth-password"));
}
static NSEvent* KeyDown(NSWindow* sheet, NSString* characters, unsigned short code) {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown
                          location:NSZeroPoint
                     modifierFlags:0
                         timestamp:NSProcessInfo.processInfo.systemUptime
                      windowNumber:sheet.windowNumber
                           context:nil
                        characters:characters
       charactersIgnoringModifiers:characters
                         isARepeat:NO
                           keyCode:code];
}

@interface ParcNativeTests_HTTPAuthDecisionTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_HTTPAuthDecisionTests {
  NSWindow* _window;
  NSView* _page;
  AuthState* _state;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _state = [AuthState new];
  _state.outcome = PCHTTPAuthInterrupted;
}

- (void)tearDown {
  [_window close];
  [super tearDown];
}

- (PCHTTPAuthPresenter*)presenterForProxy:(bool)proxy {
  AuthState* state = _state;
  NSWindow* window = _window;
  return Make(
      _page, _window, proxy,
      ^{
        return YES;
      },
      ^(PCHTTPAuthChoice choice, NSString* user, NSString* secret) {
        ++state.count;
        state.outcome = choice;
        state.user = user;
        state.secret = secret;
        Check(!window.attachedSheet, "sheet removed before controller decision");
      });
}

- (PCHTTPAuthPresenter*)shownPresenterForProxy:(bool)proxy {
  PCHTTPAuthPresenter* r = [self presenterForProxy:proxy];
  [r show];
  Pump();
  return r;
}

- (void)signInWithUsername:(NSString*)user password:(NSString*)password presenter:(PCHTTPAuthPresenter*)r {
  UsernameField(r).stringValue = user;
  PasswordField(r).stringValue = password;
  [static_cast<NSButton*>(Find(r.sheet.contentView, @"http-auth-sign-in")) performClick:nil];
  Pump();
}

- (void)testAnUnpresentedPresenterOwnsAWindowThatIsNotFalselyPresented {
  PCHTTPAuthPresenter* r = [self presenterForProxy:false];
  Check(r.sheet && !r.sheet.visible, "real window exists but is not falsely presented");
}

- (void)testShowIsDeferredEvenWhenCalledTwice {
  PCHTTPAuthPresenter* r = [self presenterForProxy:false];
  [r show];
  [r show];
  Check(_state.count == 0, "show is deferred");
}

- (void)testTheExactNativeSheetAttachesToTheOriginatingWindow {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check(r.sheet.visible && r.sheet.sheetParent == _window, "exact native sheet attached");
}

- (void)testThePasswordControlIsSecure {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check([PasswordField(r) isKindOfClass:NSSecureTextField.class], "secure password control");
}

- (void)testTheTitleIsEighteenPointMediumAndTheFieldsFourteenPoint {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check([Label(r.sheet.contentView, @"Sign in to login.example").font
            isEqual:[NSFont systemFontOfSize:18 weight:NSFontWeightMedium]] &&
            UsernameField(r).font.pointSize == 14 && PasswordField(r).font.pointSize == 14,
        "Parc's 18-point medium title and 14-point fields");
}

- (void)testTheFieldsDrawParcsEditTreatmentInsteadOfTheFocusRing {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check(UsernameField(r).focusRingType == NSFocusRingTypeNone && PasswordField(r).focusRingType == NSFocusRingTypeNone,
        "fields draw Parc's edit treatment instead of the focus ring");
}

- (void)testTheFieldsKeepTheirVoiceOverLabels {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check([UsernameField(r).accessibilityLabel isEqual:@"Username"] &&
            [PasswordField(r).accessibilityLabel isEqual:@"Password"],
        "fields keep their VoiceOver labels");
}

- (void)testTheTitleNamesTheHostAndNoExplanationMeansPrivate {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check(Label(r.sheet.contentView, @"Sign in to login.example") &&
            Label(r.sheet.contentView, @"Your connection to this site is private."),
        "the title names the host; no explanation means private");
}

- (void)testTheFieldLabelsAndPlaceholdersAreShown {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check(Label(r.sheet.contentView, @"Username") && Label(r.sheet.contentView, @"Password") &&
            [UsernameField(r).placeholderString isEqual:@"Username"],
        "the field labels and placeholders");
}

- (void)testTheDialogIsFullSizeContentAtLeastFourHundredPointsWide {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check(r.sheet.contentView.frame.size.width >= 400 && (r.sheet.styleMask & NSWindowStyleMaskFullSizeContentView),
        "full-size-content Parc dialog at least 400 points wide");
}

- (void)testAutofillIsDeliveredToTheActualFields {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  [r autofillUsername:@"saved" password:@"original"];
  Check([UsernameField(r).stringValue isEqual:@"saved"] && [PasswordField(r).stringValue isEqual:@"original"],
        "autofill delivered to actual fields");
}

- (void)testLateAutofillPreservesTheEditedIdentity {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  [r autofillUsername:@"saved" password:@"original"];
  UsernameField(r).stringValue = @"edited";
  [r autofillUsername:@"later" password:@"wrong"];
  Check([UsernameField(r).stringValue isEqual:@"edited"] && [PasswordField(r).stringValue isEqual:@"original"],
        "late autofill preserves edited identity");
}

- (void)testSignInAcceptsOnceWithTheExactInput {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  [self signInWithUsername:@"edited" password:@"submitted" presenter:r];
  Check(_state.count == 1 && _state.outcome == PCHTTPAuthAccept, "explicit accept once");
  Check([_state.user isEqual:@"edited"] && [_state.secret isEqual:@"submitted"], "exact input delivered");
}

- (void)testTheFieldsAreClearedOnceTheRequestIsTerminal {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  NSTextField* username = UsernameField(r);
  NSSecureTextField* password = PasswordField(r);
  [self signInWithUsername:@"edited" password:@"submitted" presenter:r];
  Check(username.stringValue.length == 0 && password.stringValue.length == 0, "terminal fields cleared");
}

- (void)testATerminalRequestCannotReplay {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  [self signInWithUsername:@"edited" password:@"submitted" presenter:r];
  [r invalidate];
  [r show];
  Pump();
  Check(_state.count == 1, "terminal request cannot replay");
}

- (void)testAnEngineExplanationMeansAConnectionThatIsNotPrivate {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:true];
  Check(Label(r.sheet.contentView, @"Your connection to this site is not private."),
        "an engine explanation means a connection that is not private");
}

- (void)testTheCancelAndSignInButtonsExist {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:true];
  Check(Find(r.sheet.contentView, @"Cancel") && Find(r.sheet.contentView, @"Sign in"),
        "the Cancel and Sign in buttons");
}

- (void)testAProxyTitleCarriesChromiumsWholeProxySentence {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:true];
  Check(Label(r.sheet.contentView,
              @"Sign in to The proxy http://proxy.example:8080 requires a username and password."),
        "a proxy title carries Chromium's whole proxy sentence");
}

- (void)testEscapeMeansExplicitCancellationWithoutCredentials {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:true];
  [r.sheet cancelOperation:nil];
  Pump();
  Check(_state.count == 1 && _state.outcome == PCHTTPAuthCancel, "Escape means explicit cancellation");
  Check(!_state.user.length && !_state.secret.length, "cancel returns no credentials");
}

@end

@interface ParcNativeTests_HTTPAuthKeyboardTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_HTTPAuthKeyboardTests {
  NSWindow* _window;
  NSView* _page;
  AuthState* _state;
  PCHTTPAuthPresenter* _presenter;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _state = [AuthState new];
  AuthState* state = _state;
  _presenter = Make(
      _page, _window, false,
      ^{
        return YES;
      },
      ^(PCHTTPAuthChoice choice, NSString*, NSString*) {
        ++state.count;
        state.outcome = choice;
      });
  [_presenter show];
  Pump();
}

- (void)tearDown {
  [_window close];
  [super tearDown];
}

- (NSTextView*)composingEditorIn:(NSTextField*)field {
  [_presenter.sheet makeFirstResponder:field];
  NSTextView* editor = static_cast<NSTextView*>(field.currentEditor);
  [editor setMarkedText:@"か" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
  return editor;
}

- (void)testTheUsernameEditsWhenTheSheetOpens {
  Check([UsernameField(_presenter).currentEditor isKindOfClass:NSTextView.class], "username edits when the sheet opens");
}

- (void)testReturnAndEscapeGoToTheInputMethodWhileComposingAUsername {
  [self composingEditorIn:UsernameField(_presenter)];
  NSWindow* sheet = _presenter.sheet;
  Check(![sheet performKeyEquivalent:KeyDown(sheet, @"\r", 36)] && ![sheet performKeyEquivalent:KeyDown(sheet, @"\033", 53)],
        "Return and Escape go to the input method while composing");
}

- (void)testComposingAUsernameNeverAnswersTheSignInSheet {
  [self composingEditorIn:UsernameField(_presenter)];
  NSWindow* sheet = _presenter.sheet;
  [sheet performKeyEquivalent:KeyDown(sheet, @"\r", 36)];
  [sheet performKeyEquivalent:KeyDown(sheet, @"\033", 53)];
  Pump();
  Check(_state.count == 0, "composition never answers the sign-in sheet");
}

- (void)testComposingAPasswordKeepsReturnAndEscape {
  NSTextView* editor = [self composingEditorIn:PasswordField(_presenter)];
  NSWindow* sheet = _presenter.sheet;
  if (editor.hasMarkedText) {
    Check(![sheet performKeyEquivalent:KeyDown(sheet, @"\r", 36)] && ![sheet performKeyEquivalent:KeyDown(sheet, @"\033", 53)],
          "composition in the password field keeps Return and Escape");
  }
}

- (void)testComposingAPasswordNeverAnswersTheSheet {
  NSTextView* editor = [self composingEditorIn:PasswordField(_presenter)];
  NSWindow* sheet = _presenter.sheet;
  if (editor.hasMarkedText) {
    [sheet performKeyEquivalent:KeyDown(sheet, @"\r", 36)];
    [sheet performKeyEquivalent:KeyDown(sheet, @"\033", 53)];
  }
  Pump();
  Check(_state.count == 0, "password-field composition never answers the sheet");
}

- (void)testReturnSignsInWithFocusOnAButton {
  NSWindow* sheet = _presenter.sheet;
  [sheet makeFirstResponder:Find(sheet.contentView, @"http-auth-cancel")];
  Check([sheet performKeyEquivalent:KeyDown(sheet, @"\r", 36)], "Return signs in with focus on a button");
  Pump();
  Check(_state.count == 1 && _state.outcome == PCHTTPAuthAccept, "Return from any focus signs in");
}

- (void)testKeypadEnterSignsIn {
  NSWindow* sheet = _presenter.sheet;
  Check([sheet performKeyEquivalent:KeyDown(sheet, @"\003", 76)], "keypad Enter is handled");
  Pump();
  Check(_state.count == 1 && _state.outcome == PCHTTPAuthAccept, "keypad Enter signs in");
}

- (void)testEscapeCancelsWithoutAFocusedField {
  NSWindow* sheet = _presenter.sheet;
  [sheet makeFirstResponder:nil];
  Check([sheet performKeyEquivalent:KeyDown(sheet, @"\033", 53)], "Escape is handled without a focused field");
  Pump();
  Check(_state.count == 1 && _state.outcome == PCHTTPAuthCancel, "Escape from any focus cancels");
}

@end

@interface ParcNativeTests_HTTPAuthInvalidationTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_HTTPAuthInvalidationTests {
  NSWindow* _window;
  NSView* _page;
  PCHTTPAuthPresenter* _presenter;
  AuthState* _state;
}

- (void)tearDown {
  [_window close];
  [super tearDown];
}

- (void)showInWindowVisible:(BOOL)visible valid:(BOOL)valid {
  _window = Window(visible);
  _page = Page(_window);
  _state = [AuthState new];
  AuthState* state = _state;
  _presenter = Make(
      _page, _window, false,
      ^{
        return valid;
      },
      ^(PCHTTPAuthChoice choice, NSString*, NSString*) {
        ++state.count;
        state.outcome = choice;
      });
  [_presenter show];
}

- (void)expectInterruptedOnce {
  Pump();
  Check(_state.count == 1 && _state.outcome == PCHTTPAuthInterrupted,
        "invalid owner cannot present or supply credentials");
  Check(!_window.attachedSheet, "interrupted sheet absent");
  [_presenter invalidate];
  Pump();
  Check(_state.count == 1, "interruption remains once-only");
}

- (void)testAnInvisibleWindowInterruptsTheRequest {
  [self showInWindowVisible:NO valid:YES];
  [self expectInterruptedOnce];
}

- (void)testAFailedValidationInterruptsTheRequest {
  [self showInWindowVisible:YES valid:NO];
  [self expectInterruptedOnce];
}

- (void)testARemovedPageInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  [_page removeFromSuperview];
  [self expectInterruptedOnce];
}

- (void)testInvalidatingInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  [_presenter invalidate];
  [self expectInterruptedOnce];
}

- (void)testAClosedWindowInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  [_window close];
  [self expectInterruptedOnce];
}

- (void)testAHiddenPageInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  _page.hidden = YES;
  [self expectInterruptedOnce];
}

@end

@interface ParcNativeTests_HTTPAuthReentryTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_HTTPAuthReentryTests {
  NSWindow* _window;
  NSView* _page;
  AuthState* _state;
  PCHTTPAuthPresenter* _presenter;
  PCHTTPAuthPresenter* _replacement;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _state = [AuthState new];
}

- (void)tearDown {
  [_window close];
  [super tearDown];
}

- (void)testValidationCannotResurrectPresentation {
  AuthState* state = _state;
  __block bool reenter = false;
  __block PCHTTPAuthPresenter* r;
  r = Make(
      _page, _window, false,
      ^{
        if (reenter) {
          [r invalidate];
        }
        return YES;
      },
      ^(PCHTTPAuthChoice choice, NSString*, NSString*) {
        ++state.count;
        Check(choice == PCHTTPAuthInterrupted, "validation reentry interrupts");
      });
  reenter = true;
  [r show];
  Pump();
  Check(state.count == 1 && !_window.attachedSheet, "validation callback cannot resurrect presentation");
  r = nil;
}

- (void)cancelWhileReplacingTheOwner {
  AuthState* state = _state;
  NSView* page = _page;
  NSWindow* window = _window;
  __weak ParcNativeTests_HTTPAuthReentryTests* weakSelf = self;
  __block PCHTTPAuthPresenter* r;
  r = Make(
      page, window, false,
      ^{
        return YES;
      },
      ^(PCHTTPAuthChoice, NSString*, NSString*) {
        ++state.count;
        r = nil;
        ParcNativeTests_HTTPAuthReentryTests* strongSelf = weakSelf;
        strongSelf->_replacement = Make(
            page, window, true,
            ^{
              return YES;
            },
            ^(PCHTTPAuthChoice, NSString*, NSString*) {
              ++state.count;
            });
        [strongSelf->_replacement show];
      });
  _presenter = r;
  [r show];
  Pump();
  [r.sheet cancelOperation:nil];
  Pump();
  r = nil;
}

- (void)testTheOwnerCanBeReleasedAndReplacedDuringTheNativeCallback {
  [self cancelWhileReplacingTheOwner];
  Check(_state.count == 1 && _replacement.sheet.sheetParent == _window,
        "owner release and replacement during native callback");
}

- (void)testAReplacementSeparatelyCompletes {
  [self cancelWhileReplacingTheOwner];
  [_replacement invalidate];
  Pump();
  Check(_state.count == 2, "replacement separately completes");
}

@end
