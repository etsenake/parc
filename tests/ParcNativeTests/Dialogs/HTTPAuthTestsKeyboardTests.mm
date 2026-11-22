#import "HTTPAuthTestsSupport.h"

using namespace HTTPAuthTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_HTTPAuthTestsKeyboardTests")))
@interface HTTPAuthTestsKeyboardTests : ParcNativeTestCase
@end

@implementation HTTPAuthTestsKeyboardTests {
  NSWindow* _window;
  NSView* _page;
  HTTPAuthTestsState* _state;
  PCHTTPAuthPresenter* _presenter;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _state = [HTTPAuthTestsState new];
  HTTPAuthTestsState* state = _state;
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
  ParcNativeClose(_window);
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
