#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"

#include <cstdio>
#include <cstdlib>

#import "javascript_dialog_presenter.h"

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
static PCJavaScriptDialogPresenter* Offscreen(PCJavaScriptDialogPresenter* presenter) NS_RETURNS_RETAINED {
  presenter.presentation = ParcNativePresentation();
  presenter.scheduler = ParcNativeScheduler();
  return presenter;
}
static void Drain(void) {
  ParcNativeAdvance(0.12);
}
static NSWindow* Window(void) {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2000, -2000, 640, 480)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  ParcNativeMarkVisible(window);
  return window;
}
static NSView* Page(NSWindow* window) {
  NSView* page = [[NSView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:page];
  return page;
}
static NSButton* Button(NSView* view, NSString* title) {
  if ([view isKindOfClass:NSButton.class] &&
      [((NSButton*)view).title isEqualToString:title]) {
    return (NSButton*)view;
  }
  for (NSView* child in view.subviews) {
    NSButton* button = Button(child, title);
    if (button) {
      return button;
    }
  }
  return nil;
}
static NSTextField* Input(NSView* view) {
  if ([view isKindOfClass:NSTextField.class] && ((NSTextField*)view).editable) {
    return (NSTextField*)view;
  }
  for (NSView* child in view.subviews) {
    NSTextField* field = Input(child);
    if (field) {
      return field;
    }
  }
  return nil;
}
static void EnableAfterDelay(NSButton* button) {
  ParcNativeAdvance(0.5);
  PARC_CHECK(button.enabled);
}
static void Click(PCJavaScriptDialogPresenter* presenter, NSString* title) {
  NSButton* button = Button(presenter.presentedSheet.contentView, title);
  Check(button != nil, "actual native sheet contains requested button");
  EnableAfterDelay(button);
  [button performClick:nil];
  Drain();
}
static NSEvent* Key(NSWindow* window, NSString* characters, unsigned short code,
                    NSTimeInterval timestamp, BOOL repeat = NO) {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown
                          location:NSZeroPoint
                     modifierFlags:0
                         timestamp:timestamp
                      windowNumber:window.windowNumber
                           context:nil
                        characters:characters
       charactersIgnoringModifiers:characters
                         isARepeat:repeat
                           keyCode:code];
}
static NSTimeInterval Now(void) {
  return ParcNativeNow();
}
static void Present(PCJavaScriptDialogPresenter* presenter,
                    PCJavaScriptDialogKind kind,
                    PCJavaScriptDialogCompletion completion,
                    BOOL suppression = NO) {
  [presenter presentKind:kind
                    title:@"127.0.0.1:8080 says"
                  message:@"Fixture dialog"
              defaultText:@"seed 🪴"
        offersSuppression:suppression
               completion:completion];
}
static NSTextField* Label(NSView* view, NSString* text) {
  if ([view isKindOfClass:NSTextField.class] &&
      [((NSTextField*)view).stringValue isEqualToString:text]) {
    return (NSTextField*)view;
  }
  for (NSView* child in view.subviews) {
    NSTextField* field = Label(child, text);
    if (field) {
      return field;
    }
  }
  return nil;
}

@interface ParcNativeTests_JavaScriptDialogTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_JavaScriptDialogTests {
  NSWindow* _window;
  NSView* _page;
  PCJavaScriptDialogPresenter* _presenter;
  NSUInteger _results;
  BOOL _accepted;
  BOOL _suppressed;
  NSString* _input;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _presenter = Offscreen([[PCJavaScriptDialogPresenter alloc] initWithPageView:_page]);
}

- (void)tearDown {
  [_presenter invalidate];
  ParcNativeClose(_window);
  [super tearDown];
}

- (PCJavaScriptDialogCompletion)completion {
  return ^(BOOL accepted, NSString* input, BOOL suppressed) {
    ++self->_results;
    self->_accepted = accepted;
    self->_suppressed = suppressed;
    self->_input = input;
  };
}

- (NSWindow*)present:(PCJavaScriptDialogKind)kind suppression:(BOOL)suppression {
  Present(_presenter, kind, self.completion, suppression);
  return _presenter.presentedSheet;
}

- (NSWindow*)present:(PCJavaScriptDialogKind)kind {
  return [self present:kind suppression:NO];
}

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

- (void)testTheSamePageCannotStackAConfirmation {
  [self present:PCJavaScriptDialogConfirm];
  PCJavaScriptDialogPresenter* other = _presenter;
  __block BOOL rejected = NO;
  Present(other, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) { rejected = !accepted; });
  PARC_CHECK(rejected && _presenter.isPresenting && _results == 0);
}

- (void)testAnotherPageInTheWindowCannotStackAConfirmation {
  [self present:PCJavaScriptDialogConfirm];
  PCJavaScriptDialogPresenter* other = Offscreen([[PCJavaScriptDialogPresenter alloc] initWithPageView:Page(_window)]);
  __block BOOL rejected = NO;
  Present(other, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) { rejected = !accepted; });
  PARC_CHECK(rejected && _presenter.isPresenting && _results == 0);
}

- (void)testMovingThePageRejectsALateAcceptance {
  [self present:PCJavaScriptDialogConfirm];
  NSWindow* other = Window();
  [other.contentView addSubview:_page];
  [_presenter handleAccepted:YES promptOverride:nil];
  ParcNativeClose(other);
  PARC_CHECK(_results == 1 && !_accepted);
}

- (void)testANewRequestBindsToTheNewWindow {
  NSWindow* other = Window();
  [other.contentView addSubview:_page];
  PARC_CHECK(ParcNativeSheetParent([self present:PCJavaScriptDialogConfirm]) == other);
  ParcNativeClose(other);
}

- (void)testDetachingRejectsThePendingRequestImmediately {
  [self present:PCJavaScriptDialogConfirm];
  [_presenter pageHostWillDetach];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testADetachedPageCannotShowBeforeUnload {
  [_page removeFromSuperview];
  [self present:PCJavaScriptDialogBeforeUnload];
  PARC_CHECK(_results == 1 && !_accepted && !ParcNativeAttachedSheet(_window));
}

- (void)testClosingTheParentRejectsThePendingRequest {
  [self present:PCJavaScriptDialogConfirm];
  ParcNativeClose(_window);
  PARC_CHECK(_results == 1 && !_accepted);
}

- (void)testAClosedWindowCannotReceiveANewRequest {
  [self present:PCJavaScriptDialogConfirm];
  ParcNativeClose(_window);
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 2 && !_accepted && !_presenter.isPresenting);
}

- (void)testCompletionMayPresentANewConfirmation {
  Present(_presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
    PARC_CHECK(!accepted);
    [self present:PCJavaScriptDialogConfirm];
  });
  [_presenter cancel];
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted);
}

- (void)testDeallocationRejectsThePendingRequest {
  __weak PCJavaScriptDialogPresenter* weak = _presenter;
  @autoreleasepool {
    [self present:PCJavaScriptDialogConfirm];
    _presenter = nil;
  }
  PARC_CHECK(!weak && _results == 1 && !_accepted && !ParcNativeAttachedSheet(_window));
}

- (void)testAButtonCompletionCanReleaseThePresenter {
  __weak PCJavaScriptDialogPresenter* weak = _presenter;
  @autoreleasepool {
    Present(_presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
      PARC_CHECK(accepted);
      ++self->_results;
      self->_presenter = nil;
    });
    Click(_presenter, @"OK");
  }
  PARC_CHECK(!weak && _results == 1);
}

- (void)testAReleasedPageCannotPresent {
  __weak NSView* weak;
  @autoreleasepool {
    NSView* detached = [NSView new];
    weak = detached;
    _presenter = Offscreen([[PCJavaScriptDialogPresenter alloc] initWithPageView:detached]);
  }
  [self present:PCJavaScriptDialogAlert];
  PARC_CHECK(!weak && _results == 1 && !_accepted);
}

- (void)testDetachmentRejectsACallbackThatTriesToReopen {
  Present(_presenter, PCJavaScriptDialogBeforeUnload, ^(BOOL accepted, NSString*, BOOL) {
    PARC_CHECK(!accepted);
    [self present:PCJavaScriptDialogConfirm];
  });
  [_presenter pageHostWillDetach];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testDetachmentBlocksTheOldHierarchy {
  [_presenter pageHostWillDetach];
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testAnAttachSignalRequiresAnActualWindow {
  [_presenter pageHostWillDetach];
  [_page removeFromSuperview];
  [_presenter pageHostDidAttach];
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testReattachmentRequiresABalancedSignal {
  [_presenter pageHostWillDetach];
  [_page removeFromSuperview];
  [_presenter pageHostDidAttach];
  [_window.contentView addSubview:_page];
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testBalancedReattachmentAllowsANewDecision {
  [_presenter pageHostWillDetach];
  [_page removeFromSuperview];
  [_window.contentView addSubview:_page];
  [_presenter pageHostDidAttach];
  [self present:PCJavaScriptDialogConfirm];
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted && !_presenter.isPresenting);
}

- (void)testAttachmentCannotReviveAnInvalidatedPresenter {
  [_presenter invalidate];
  [_presenter pageHostDidAttach];
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testEndingOneWindowsSheetLeavesTheOtherPending {
  [self present:PCJavaScriptDialogConfirm];
  NSWindow* other = Window();
  PCJavaScriptDialogPresenter* second = Offscreen([[PCJavaScriptDialogPresenter alloc] initWithPageView:Page(other)]);
  Present(second, PCJavaScriptDialogConfirm, ^(BOOL, NSString*, BOOL) {});
  ParcNativeEndSheetWithCode(_window, _presenter.presentedSheet, NSModalResponseAbort);
  PARC_CHECK(_results == 1 && !_accepted && second.isPresenting && ParcNativeSheetParent(second.presentedSheet) == other);
  [second invalidate];
  ParcNativeClose(other);
}

- (void)testADecisionReleasesTheCompletionCapture {
  __weak NSObject* weak;
  @autoreleasepool {
    NSObject* capture = [NSObject new];
    weak = capture;
    Present(_presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
      PARC_CHECK(accepted && capture);
    });
  }
  PARC_CHECK(weak);
  @autoreleasepool { Click(_presenter, @"OK"); }
  PARC_CHECK(!weak);
}

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

- (void)testSuppressionExposesItsCheckboxState {
  NSView* view = [self present:PCJavaScriptDialogPrompt suppression:YES].contentView;
  NSButton* box = Button(view, @"Don't show this again");
  PARC_CHECK([box.accessibilityRole isEqual:NSAccessibilityCheckBoxRole] && [box.accessibilityValue isEqual:@"Not selected"]);
  [box performClick:nil];
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
