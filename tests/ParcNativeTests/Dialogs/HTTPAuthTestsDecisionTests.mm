#import "HTTPAuthTestsSupport.h"

using namespace HTTPAuthTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_HTTPAuthTestsDecisionTests")))
@interface HTTPAuthTestsDecisionTests : ParcNativeTestCase
@end

@implementation HTTPAuthTestsDecisionTests {
  NSWindow* _window;
  NSView* _page;
  HTTPAuthTestsState* _state;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _state = [HTTPAuthTestsState new];
  _state.outcome = PCHTTPAuthInterrupted;
}

- (void)tearDown {
  ParcNativeClose(_window);
  [super tearDown];
}

- (PCHTTPAuthPresenter*)presenterForProxy:(bool)proxy {
  HTTPAuthTestsState* state = _state;
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
        Check(!ParcNativeAttachedSheet(window), "sheet removed before controller decision");
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
  SendClick(static_cast<NSButton*>(Find(r.sheet.contentView, @"http-auth-sign-in")));
  Pump();
}

- (void)testAnUnpresentedPresenterOwnsAWindowThatIsNotFalselyPresented {
  PCHTTPAuthPresenter* r = [self presenterForProxy:false];
  Check(r.sheet && !ParcNativeVisible(r.sheet), "real window exists but is not falsely presented");
}

- (void)testShowIsDeferredEvenWhenCalledTwice {
  PCHTTPAuthPresenter* r = [self presenterForProxy:false];
  [r show];
  [r show];
  Check(_state.count == 0, "show is deferred");
}

- (void)testTheExactNativeSheetAttachesToTheOriginatingWindow {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check(ParcNativeVisible(r.sheet) && ParcNativeSheetParent(r.sheet) == _window, "exact native sheet attached");
}

- (void)testThePasswordControlIsSecure {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check([PasswordField(r) isKindOfClass:NSSecureTextField.class], "secure password control");
}

- (void)testTheTitleUsesEighteenPointMedium {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check([Label(r.sheet.contentView, @"Sign in to login.example").font
            isEqual:[NSFont systemFontOfSize:18 weight:NSFontWeightMedium]],
        "Parc uses an 18-point medium title");
}

- (void)testTheFieldsUseFourteenPoint {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check(UsernameField(r).font.pointSize == 14 && PasswordField(r).font.pointSize == 14,
        "Parc uses 14-point fields");
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

- (void)testTheTitleNamesTheHost {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check(Label(r.sheet.contentView, @"Sign in to login.example"), "the title names the host");
}

- (void)testNoExplanationMeansTheConnectionIsPrivate {
  PCHTTPAuthPresenter* r = [self shownPresenterForProxy:false];
  Check(Label(r.sheet.contentView, @"Your connection to this site is private."),
        "no explanation means private");
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
