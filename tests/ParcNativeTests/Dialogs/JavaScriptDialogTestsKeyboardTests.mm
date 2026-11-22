#import "JavaScriptDialogTestsSupport.h"

using namespace JavaScriptDialogTestsSupportFunctions;

__attribute__((objc_runtime_name("ParcNativeTests_JavaScriptDialogTestsKeyboardTests")))
@interface JavaScriptDialogTestsKeyboardTests : JavaScriptDialogTestsSupport
@end

@implementation JavaScriptDialogTestsKeyboardTests

- (void)testTheAlertDisplaysItsTitleAndMessage {
  NSWindow* sheet = [self present:PCJavaScriptDialogAlert];
  PARC_CHECK(Label(sheet.contentView, @"127.0.0.1:8080 says") && Label(sheet.contentView, @"Fixture dialog"));
}

- (void)testVoiceOverNamesTheAlertByItsTitle {
  NSWindow* sheet = [self present:PCJavaScriptDialogAlert];
  PARC_CHECK([sheet.accessibilityLabel isEqual:@"127.0.0.1:8080 says"]);
}

- (void)testAPlainAlertOnlyOffersOK {
  NSWindow* sheet = [self present:PCJavaScriptDialogAlert];
  PARC_CHECK(Button(sheet.contentView, @"OK") && !Button(sheet.contentView, @"Cancel") &&
               !Input(sheet.contentView) && !Button(sheet.contentView, @"Don't show this again"));
}

- (void)testEscapeLeavesAnAlertPending {
  NSWindow* sheet = [self present:PCJavaScriptDialogAlert];
  [sheet cancelOperation:nil];
  PARC_CHECK(_presenter.isPresenting && !_results);
}

- (void)testOKIsInertUntilTheProtectionDelayExpires {
  NSWindow* sheet = [self present:PCJavaScriptDialogConfirm];
  NSButton* ok = Button(sheet.contentView, @"OK");
  PARC_CHECK(!ok.enabled);
  ParcNativeAdvance(0.5);
  PARC_CHECK(ok.enabled);
}

- (void)testEarlyReturnLeavesTheConfirmationPending {
  NSWindow* sheet = [self present:PCJavaScriptDialogConfirm];
  [sheet performKeyEquivalent:Key(sheet, @"\r", 36, Now())];
  PARC_CHECK(!_results && _presenter.isPresenting);
}

- (void)testHeldReturnLeavesTheConfirmationPending {
  NSWindow* sheet = [self present:PCJavaScriptDialogConfirm];
  ParcNativeAdvance(0.5);
  [sheet performKeyEquivalent:Key(sheet, @"\r", 36, Now(), YES)];
  PARC_CHECK(!_results && _presenter.isPresenting);
}

- (void)testReturnFromBeforePresentationIsIgnored {
  NSWindow* sheet = [self present:PCJavaScriptDialogConfirm];
  ParcNativeAdvance(0.5);
  [sheet performKeyEquivalent:Key(sheet, @"\r", 36, Now() - 5)];
  PARC_CHECK(!_results && _presenter.isPresenting);
}

- (void)testFreshReturnAccepts {
  NSWindow* sheet = [self present:PCJavaScriptDialogConfirm];
  ParcNativeAdvance(0.5);
  [sheet performKeyEquivalent:Key(sheet, @"\r", 36, Now())];
  PARC_CHECK(_results == 1 && _accepted);
}

- (void)testKeypadEnterAccepts {
  NSWindow* sheet = [self present:PCJavaScriptDialogConfirm];
  ParcNativeAdvance(0.5);
  [sheet performKeyEquivalent:Key(sheet, @"\003", 76, Now())];
  PARC_CHECK(_results == 1 && _accepted);
}

- (void)testEscapeImmediatelyRejects {
  NSWindow* sheet = [self present:PCJavaScriptDialogConfirm];
  [sheet performKeyEquivalent:Key(sheet, @"\033", 53, Now())];
  PARC_CHECK(_results == 1 && !_accepted);
}

- (void)testVoiceOverNamesThePromptField {
  NSWindow* sheet = [self present:PCJavaScriptDialogPrompt];
  NSTextField* field = Input(sheet.contentView);
  PARC_CHECK([field.accessibilityLabel isEqual:@"Response"]);
}

- (void)testThePromptUsesTheFieldsOwnFocusTreatment {
  NSWindow* sheet = [self present:PCJavaScriptDialogPrompt];
  NSTextField* field = Input(sheet.contentView);
  PARC_CHECK(field.focusRingType == NSFocusRingTypeNone);
}

- (void)testThePromptStartsEditingItsField {
  NSWindow* sheet = [self present:PCJavaScriptDialogPrompt];
  NSTextField* field = Input(sheet.contentView);
  PARC_CHECK(sheet.initialFirstResponder == field && [field.currentEditor isKindOfClass:NSTextView.class]);
}

- (void)testCancelUsesTheEscapeKey {
  NSWindow* sheet = [self present:PCJavaScriptDialogPrompt];
  PARC_CHECK([Button(sheet.contentView, @"Cancel").keyEquivalent isEqual:@"\033"]);
}

- (void)testCompositionKeepsReturnAndEscape {
  NSWindow* sheet = [self present:PCJavaScriptDialogPrompt];
  ParcNativeAdvance(0.5);
  NSTextView* editor = (NSTextView*)Input(sheet.contentView).currentEditor;
  [editor setMarkedText:@"か" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
  PARC_CHECK(editor.hasMarkedText);
  BOOL entered = [sheet performKeyEquivalent:Key(sheet, @"\r", 36, Now())];
  BOOL escaped = [sheet performKeyEquivalent:Key(sheet, @"\033", 53, Now())];
  [editor unmarkText];
  PARC_CHECK(!entered && !escaped && !_results && _presenter.isPresenting);
}

@end
