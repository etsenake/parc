#import "JavaScriptDialogTestsSupport.h"

using namespace JavaScriptDialogTestsSupportFunctions;

__attribute__((objc_runtime_name("ParcNativeTests_JavaScriptDialogTestsDecisionsTests")))
@interface JavaScriptDialogTestsDecisionsTests : JavaScriptDialogTestsSupport
@end

@implementation JavaScriptDialogTestsDecisionsTests

- (void)testAnAlertBelongsToItsPageWindow {
  NSWindow* sheet = [self present:PCJavaScriptDialogAlert];
  PARC_CHECK(_presenter.isPresenting && ParcNativeSheetParent(sheet) == _window && !NSApp.modalWindow);
}

- (void)testAlertAcknowledges {
  [self present:PCJavaScriptDialogAlert];
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted && !_input.length);
}

- (void)testCancelRejectsConfirmation {
  [self present:PCJavaScriptDialogConfirm];
  Click(_presenter, @"Cancel");
  PARC_CHECK(_results == 1 && !_accepted && !_input.length);
}

- (void)testOKAcceptsConfirmation {
  [self present:PCJavaScriptDialogConfirm];
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted && !_input.length);
}

- (void)testCancelStaysOnThePage {
  [self present:PCJavaScriptDialogBeforeUnload];
  Click(_presenter, @"Cancel");
  PARC_CHECK(_results == 1 && !_accepted && !_input.length);
}

- (void)testOKLeavesThePage {
  [self present:PCJavaScriptDialogBeforeUnload];
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted && !_input.length);
}

- (void)testALateDecisionCannotRepeatTheCompletion {
  [self present:PCJavaScriptDialogAlert];
  Click(_presenter, @"OK");
  [_presenter cancel];
  [_presenter handleAccepted:YES promptOverride:nil];
  PARC_CHECK(_results == 1);
}

- (void)testTheSheetIsDetachedBeforeCompletion {
  Present(_presenter, PCJavaScriptDialogConfirm, ^(BOOL, NSString*, BOOL) {
    PARC_CHECK(!self->_presenter.isPresenting && !ParcNativeAttachedSheet(self->_window));
    ++self->_results;
  });
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1);
}

- (void)testAPromptStartsWithItsUnicodeDefault {
  NSWindow* sheet = [self present:PCJavaScriptDialogPrompt];
  PARC_CHECK([Input(sheet.contentView).stringValue isEqual:@"seed 🪴"]);
}

- (void)testOKReturnsTheEditedPromptValue {
  NSWindow* sheet = [self present:PCJavaScriptDialogPrompt];
  Input(sheet.contentView).stringValue = @"typed é 🧪";
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted && [_input isEqual:@"typed é 🧪"]);
}

- (void)testAnEmptyOverrideReplacesTheDefault {
  [self present:PCJavaScriptDialogPrompt];
  [_presenter handleAccepted:YES promptOverride:@""];
  PARC_CHECK(_results == 1 && _accepted && !_input.length);
}

- (void)testANilOverrideKeepsTheCurrentText {
  [self present:PCJavaScriptDialogPrompt];
  [_presenter handleAccepted:YES promptOverride:nil];
  PARC_CHECK(_results == 1 && [_input isEqual:@"seed 🪴"]);
}

- (void)testARejectedPromptReturnsNoText {
  [self present:PCJavaScriptDialogPrompt];
  [_presenter handleAccepted:NO promptOverride:@"not returned"];
  PARC_CHECK(_results == 1 && !_accepted && !_input.length);
}

- (void)testBeforeUnloadUsesTheSiteTitleAndMessage {
  [_presenter presentKind:PCJavaScriptDialogBeforeUnload title:@"Leave site?"
                  message:@"Changes you made may not be saved." defaultText:@""
        offersSuppression:YES completion:self.completion];
  NSView* content = _presenter.presentedSheet.contentView;
  PARC_CHECK(Label(content, @"Leave site?") && Label(content, @"Changes you made may not be saved."));
}

- (void)testBeforeUnloadOffersOnlyOKAndCancel {
  NSView* content = [self present:PCJavaScriptDialogBeforeUnload suppression:YES].contentView;
  PARC_CHECK(Button(content, @"OK") && Button(content, @"Cancel") && !Button(content, @"Leave Page") &&
             !Button(content, @"Don't show this again"));
}

- (void)testOKConfirmsAReload {
  [_presenter presentKind:PCJavaScriptDialogBeforeUnload title:@"Reload site?" message:@"Reload?"
              defaultText:@"" offersSuppression:NO completion:self.completion];
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted);
}

- (void)testInvalidatingTwiceRejectsBeforeUnloadOnce {
  [self present:PCJavaScriptDialogBeforeUnload];
  [_presenter invalidate];
  [_presenter invalidate];
  PARC_CHECK(_results == 1 && !_accepted);
}

- (void)testSuppressionExposesItsCheckboxState {
  NSView* view = [self present:PCJavaScriptDialogPrompt suppression:YES].contentView;
  NSButton* box = Button(view, @"Don't show this again");
  PARC_CHECK([box.accessibilityRole isEqual:NSAccessibilityCheckBoxRole] && [box.accessibilityValue isEqual:@"Not selected"]);
  SendClick(box);
  PARC_CHECK([box.accessibilityValue isEqual:@"Selected"]);
}

- (void)testCancelReportsCheckedSuppression {
  NSButton* box = Button([self present:PCJavaScriptDialogConfirm suppression:YES].contentView, @"Don't show this again");
  box.state = NSControlStateValueOn;
  Click(_presenter, @"Cancel");
  PARC_CHECK(_results == 1 && !_accepted && _suppressed && !_input.length);
}

- (void)testOKLeavesUncheckedSuppressionOff {
  [self present:PCJavaScriptDialogConfirm suppression:YES];
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted && !_suppressed);
}

- (void)testProgrammaticAcceptanceIgnoresTheCheckbox {
  NSButton* box = Button([self present:PCJavaScriptDialogConfirm suppression:YES].contentView, @"Don't show this again");
  box.state = NSControlStateValueOn;
  [_presenter handleAccepted:YES promptOverride:nil];
  PARC_CHECK(_results == 1 && _accepted && !_suppressed);
}

- (void)testAnExternalSheetEndIgnoresTheCheckbox {
  NSButton* box = Button([self present:PCJavaScriptDialogConfirm suppression:YES].contentView, @"Don't show this again");
  box.state = NSControlStateValueOn;
  ParcNativeEndSheetWithCode(_window, _presenter.presentedSheet, NSModalResponseAbort);
  PARC_CHECK(_results == 1 && !_accepted && !_suppressed);
}

@end
