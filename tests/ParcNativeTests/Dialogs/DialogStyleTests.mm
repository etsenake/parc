#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"

#import "dialog_style.h"

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)

static void Drain(void) {
  ParcNativeAdvance(0.12);
}
static NSWindow* Window(void) {
  NSWindow* window = ParcNativeOffscreenWindow(NSMakeRect(-2000, -2000, 640, 480), NSWindowStyleMaskBorderless);
  ParcNativeMarkVisible(window);
  return window;
}
static NSEvent* KeyEvent(NSWindow* window, NSString* characters, unsigned short code, NSEventModifierFlags flags,
                         BOOL repeat) {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown
                          location:NSZeroPoint
                     modifierFlags:flags
                         timestamp:NSProcessInfo.processInfo.systemUptime
                      windowNumber:window.windowNumber
                           context:nil
                        characters:characters
       charactersIgnoringModifiers:characters
                         isARepeat:repeat
                           keyCode:code];
}
static NSEvent* Key(NSWindow* window, NSString* characters, unsigned short code) {
  return KeyEvent(window, characters, code, 0, NO);
}
static NSButton* Button(NSView* view, NSString* title) {
  if ([view isKindOfClass:NSButton.class] && [((NSButton*)view).title isEqualToString:title]) {
    return (NSButton*)view;
  }
  for (NSView* child in view.subviews) {
    if (NSButton* button = Button(child, title)) return button;
  }
  return nil;
}
static BOOL Inside(NSView* view) {
  return NSContainsRect(view.window.contentView.bounds, view.frame);
}

@interface PromptOutcome : NSObject
@property NSModalResponse response;
@property int count;
@end
@implementation PromptOutcome
@end

@interface DialogPromptTests : ParcNativeTestCase
@end

@implementation DialogPromptTests {
  NSWindow* _window;
  PromptOutcome* _outcome;
}

+ (NSApplicationActivationPolicy)activationPolicy {
  return NSApplicationActivationPolicyAccessory;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _outcome = [PromptOutcome new];
}

- (void)tearDown {
  [_window close];
  [super tearDown];
}

- (PCDialogPrompt*)present:(BOOL)cancelRole {
  PromptOutcome* outcome = _outcome;
  PCDialogPrompt* prompt = [[PCDialogPrompt alloc] initWithTitle:@"Page Unresponsive"
                                                         message:@"Example\nSecond line"];
  [prompt addButtonWithTitle:@"Wait" role:PCDialogPromptPrimary response:NSAlertFirstButtonReturn];
  [prompt addButtonWithTitle:cancelRole ? @"Never Mind" : @"Exit Page"
                        role:cancelRole ? PCDialogPromptCancel : PCDialogPromptAuxiliary
                    response:NSAlertSecondButtonReturn];
  [prompt beginSheetModalForWindow:_window
                 completionHandler:^(NSModalResponse value) {
                   outcome.response = value;
                   ++outcome.count;
                 }];
  return prompt;
}

- (void)testThePromptIsAPageWindowSheetAndNotAppModal {
  PCDialogPrompt* prompt = [self present:NO];
  Check(_window.attachedSheet == prompt.window, "the prompt is attached to the page window");
  Check(NSApp.modalWindow == nil, "the prompt is not app-modal");
}

- (void)testTheSheetIsNamedByItsTitleForVoiceOver {
  PCDialogPrompt* prompt = [self present:NO];
  Check([prompt.window.accessibilityLabel isEqualToString:@"Page Unresponsive"],
        "VoiceOver names the sheet by its title");
}

- (void)testTheAuxiliaryButtonSitsLeftOfTheReturnButton {
  NSWindow* sheet = [self present:NO].window;
  NSButton* wait = Button(sheet.contentView, @"Wait");
  NSButton* exitPage = Button(sheet.contentView, @"Exit Page");
  Check(wait && exitPage && NSMinX(exitPage.frame) < NSMinX(wait.frame),
        "auxiliary sits left of the Return button");
}

- (void)testTheReturnButtonIsTheDefaultButton {
  NSWindow* sheet = [self present:NO].window;
  Check(sheet.accessibilityDefaultButton == Button(sheet.contentView, @"Wait"), "Return button is the default");
}

- (void)testEscapeDoesNothingWithoutACancelOrChosenEscapeButton {
  NSWindow* sheet = [self present:NO].window;
  [sheet cancelOperation:nil];
  Drain();
  Check(_outcome.count == 0 && _window.attachedSheet == sheet,
        "Escape does nothing without a Cancel or chosen Escape button");
}

- (void)testAPresentedPromptStaysAliveWithoutAnOwner {
  __weak PCDialogPrompt* weakPrompt = nil;
  @autoreleasepool {
    weakPrompt = [self present:NO];
  }
  Drain();
  Check(weakPrompt != nil, "a presented prompt stays alive without an owner");
}

- (void)testClickingTheAuxiliaryButtonEndsTheSheetWithItsResponse {
  PCDialogPrompt* prompt = [self present:NO];
  [Button(prompt.window.contentView, @"Exit Page") performClick:nil];
  Drain();
  Check(_outcome.count == 1 && _outcome.response == NSAlertSecondButtonReturn && !_window.attachedSheet,
        "auxiliary click ends the sheet with its response");
}

- (void)testThePromptIsReleasedOnceItsSheetEnds {
  __weak PCDialogPrompt* weakPrompt = nil;
  @autoreleasepool {
    PCDialogPrompt* prompt = [self present:NO];
    weakPrompt = prompt;
    [Button(prompt.window.contentView, @"Exit Page") performClick:nil];
    Drain();
  }
  Drain();
  Check(weakPrompt == nil, "the prompt is released once its sheet ends");
}

- (void)testReturnAnswersThePrimaryButton {
  NSWindow* sheet = [self present:NO].window;
  Check([sheet performKeyEquivalent:Key(sheet, @"\r", 36)], "Return handled");
  Drain();
  Check(_outcome.count == 1 && _outcome.response == NSAlertFirstButtonReturn, "Return answers the primary");
}

- (void)testKeypadEnterAnswersThePrimaryButton {
  NSWindow* sheet = [self present:NO].window;
  Check([sheet performKeyEquivalent:Key(sheet, @"\003", 76)], "keypad Enter handled");
  Drain();
  Check(_outcome.count == 1 && _outcome.response == NSAlertFirstButtonReturn, "keypad Enter answers the primary");
}

- (void)testEscapeAnswersTheChosenEscapeButton {
  PCDialogPrompt* prompt = [self present:NO];
  prompt.escapeButton = Button(prompt.window.contentView, @"Wait");
  [prompt.window cancelOperation:nil];
  Drain();
  Check(_outcome.count == 1 && _outcome.response == NSAlertFirstButtonReturn,
        "Escape answers the chosen Escape button");
}

- (void)testEscapeAnswersTheCancelButton {
  NSWindow* sheet = [self present:YES].window;
  Check([sheet performKeyEquivalent:Key(sheet, @"\033", 53)], "Escape handled");
  Drain();
  Check(_outcome.count == 1 && _outcome.response == NSAlertSecondButtonReturn, "Escape answers Cancel");
}

- (void)testAnotherOwnerEndingTheSheetReportsItsCodeOnce {
  PCDialogPrompt* prompt = [self present:YES];
  [_window endSheet:prompt.window returnCode:NSModalResponseCancel];
  Drain();
  Check(_outcome.count == 1 && _outcome.response == NSModalResponseCancel,
        "another owner ending the sheet reports its code once");
}

@end

@interface DialogFooterWrappingTests : ParcNativeTestCase
@end

@implementation DialogFooterWrappingTests {
  NSWindow* _window;
  PCDialogPrompt* _prompt;
  NSButton* _open;
  NSButton* _cancel;
  NSButton* _always;
}

+ (NSApplicationActivationPolicy)activationPolicy {
  return NSApplicationActivationPolicyAccessory;
}

- (void)setUp {
  [super setUp];
  _window = Window();
}

- (void)tearDown {
  [_window close];
  [super tearDown];
}

- (void)presentThreeButtons {
  _prompt = [[PCDialogPrompt alloc] initWithTitle:@"Open in app?" message:nil];
  _open = [_prompt addButtonWithTitle:@"Open “Long Application”"
                                 role:PCDialogPromptPrimary
                             response:NSAlertFirstButtonReturn];
  _cancel = [_prompt addButtonWithTitle:@"Cancel" role:PCDialogPromptCancel response:NSAlertSecondButtonReturn];
  _always = [_prompt addButtonWithTitle:@"Always open “Long Application”"
                                   role:PCDialogPromptAuxiliary
                               response:NSAlertThirdButtonReturn];
  [_prompt beginSheetModalForWindow:_window completionHandler:nil];
}

- (void)testLongButtonsStayInsideTheSheet {
  [self presentThreeButtons];
  Check(Inside(_open) && Inside(_cancel) && Inside(_always), "long buttons stay inside the sheet");
}

- (void)testTheAuxiliaryWrapsAboveWhileCancelStaysBesideTheReturnButton {
  [self presentThreeButtons];
  Check(NSMaxY(_always.frame) <= NSMinY(_open.frame) && NSMinX(_cancel.frame) < NSMinX(_open.frame),
        "the auxiliary wraps above; Cancel stays beside the Return button");
}

- (void)testAnOverLongButtonIsCappedInsideTheSheetAndKeepsItsFullTitle {
  PCDialogPrompt* huge = [[PCDialogPrompt alloc] initWithTitle:@"Long" message:nil];
  NSMutableString* title = [NSMutableString stringWithString:@"Open"];
  for (int i = 0; i < 20; ++i) [title appendString:@" Application"];
  NSButton* wide = [huge addButtonWithTitle:title role:PCDialogPromptPrimary response:NSAlertFirstButtonReturn];
  [huge beginSheetModalForWindow:_window completionHandler:nil];
  Check(Inside(wide) && [wide.title isEqualToString:title],
        "an over-long button is capped inside the sheet and keeps its full title");
}

@end

@interface PanelFixture : NSObject
@property(strong) NSWindow* window;
@property(strong) PCDialogPanel* panel;
@property(strong) PCDialogInputField* input;
@property(strong) NSBlockOperation* okTarget;
@property(strong) NSBlockOperation* cancelTarget;
@property int accepted;
@property int cancelled;
@end
@implementation PanelFixture
@end

@interface DialogPanelCompositionTests : ParcNativeTestCase
@end

@implementation DialogPanelCompositionTests {
  PanelFixture* _fixture;
}

+ (NSApplicationActivationPolicy)activationPolicy {
  return NSApplicationActivationPolicyAccessory;
}

- (void)setUp {
  [super setUp];
  PanelFixture* fixture = [PanelFixture new];
  fixture.window = Window();
  fixture.panel = [[PCDialogPanel alloc] initWithContentRect:NSMakeRect(0, 0, 450, 200)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
  fixture.panel.releasedWhenClosed = NO;
  PCDialogButton* ok = [[PCDialogButton alloc] initWithTitle:@"OK" primary:YES];
  PCDialogButton* cancel = [[PCDialogButton alloc] initWithTitle:@"Cancel" primary:NO];
  ok.keyEquivalent = @"\r";
  cancel.keyEquivalent = @"\033";
  fixture.input = [[PCDialogInputField alloc] initWithText:@"seed" secure:NO];
  fixture.input.frame = NSMakeRect(20, 20, 300, NSHeight(fixture.input.frame));
  ok.frame = NSMakeRect(300, 120, 80, 38);
  cancel.frame = NSMakeRect(200, 120, 90, 38);
  for (NSView* view in @[ fixture.input, ok, cancel ]) [fixture.panel.contentView addSubview:view];
  fixture.panel.enterButton = ok;
  fixture.panel.escapeButton = cancel;
  __weak PanelFixture* weakFixture = fixture;
  fixture.okTarget = [NSBlockOperation blockOperationWithBlock:^{
    ++weakFixture.accepted;
  }];
  fixture.cancelTarget = [NSBlockOperation blockOperationWithBlock:^{
    ++weakFixture.cancelled;
  }];
  ok.target = fixture.okTarget;
  ok.action = @selector(main);
  cancel.target = fixture.cancelTarget;
  cancel.action = @selector(main);
  [fixture.window beginSheet:fixture.panel completionHandler:nil];
  Drain();
  _fixture = fixture;
}

- (void)tearDown {
  [_fixture.window endSheet:_fixture.panel];
  [_fixture.window close];
  [super tearDown];
}

- (NSTextView*)focusedEditor {
  [_fixture.panel makeFirstResponder:_fixture.input.field];
  return (NSTextView*)_fixture.input.field.currentEditor;
}

- (void)startComposing {
  NSTextView* editor = [self focusedEditor];
  [editor setMarkedText:@"か" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)testTheFieldEdits {
  Check([[self focusedEditor] isKindOfClass:NSTextView.class], "field edits");
}

- (void)testTheFieldSitsOnA36PointCardWithTextPaddingAndNoFocusRing {
  PCDialogInputField* input = _fixture.input;
  Check(input.field.focusRingType == NSFocusRingTypeNone && NSHeight(input.frame) == 36 &&
            NSMinX(input.field.frame) == 10,
        "field sits on a 36-point card with 12-point text padding and no focus ring");
}

- (void)testAPressOnTheCardsPaddingFocusesTheField {
  PCDialogInputField* input = _fixture.input;
  NSEvent* press = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:_fixture.panel.windowNumber
                                       context:nil
                                   eventNumber:0
                                    clickCount:1
                                      pressure:1];
  [input mouseDown:press];
  Check(input.field.currentEditor != nil, "a press on the card's padding focuses the field");
}

- (void)testCompositionKeepsReturnKeypadEnterAndEscape {
  [self startComposing];
  PCDialogPanel* panel = _fixture.panel;
  Check(![panel performKeyEquivalent:Key(panel, @"\r", 36)] && ![panel performKeyEquivalent:Key(panel, @"\003", 76)] &&
            ![panel performKeyEquivalent:Key(panel, @"\033", 53)],
        "composition keeps Return, keypad Enter and Escape");
}

- (void)testCompositionNeverAnswersThePanel {
  [self startComposing];
  [_fixture.panel cancelOperation:nil];
  Check(_fixture.accepted == 0 && _fixture.cancelled == 0, "composition never answers the panel");
}

- (void)testKeypadEnterClicksTheEnterButton {
  PCDialogPanel* panel = _fixture.panel;
  Check([panel performKeyEquivalent:Key(panel, @"\003", 76)] && _fixture.accepted == 1,
        "keypad Enter clicks the Enter button");
}

- (void)testEscapeClicksTheEscapeButton {
  [_fixture.panel cancelOperation:nil];
  Check(_fixture.cancelled == 1, "Escape clicks the Escape button");
}

- (void)testASecureFieldIsASecureTextField {
  PCDialogInputField* secure = [[PCDialogInputField alloc] initWithText:@"" secure:YES];
  Check([secure.field isKindOfClass:NSSecureTextField.class], "secure field is an NSSecureTextField");
}

@end

@interface CheckboxFixture : NSObject
@property(strong) NSWindow* window;
@property(strong) PCDialogCheckbox* box;
@property(strong) NSBlockOperation* target;
@property int changes;
@end
@implementation CheckboxFixture
@end

@interface DialogCheckboxTests : ParcNativeTestCase
@end

@implementation DialogCheckboxTests {
  CheckboxFixture* _fixture;
  NSSize _size;
}

+ (NSApplicationActivationPolicy)activationPolicy {
  return NSApplicationActivationPolicyAccessory;
}

- (void)setUp {
  [super setUp];
  CheckboxFixture* fixture = [CheckboxFixture new];
  fixture.window = Window();
  fixture.box = [[PCDialogCheckbox alloc] initWithTitle:@"Report abuse" target:nil action:nil];
  __weak CheckboxFixture* weakFixture = fixture;
  fixture.target = [NSBlockOperation blockOperationWithBlock:^{
    ++weakFixture.changes;
  }];
  fixture.box.target = fixture.target;
  fixture.box.action = @selector(main);
  _size = [fixture.box sizeForWidth:300];
  fixture.box.frame = NSMakeRect(20, 20, _size.width, _size.height);
  [fixture.window.contentView addSubview:fixture.box];
  [fixture.window makeFirstResponder:fixture.box];
  _fixture = fixture;
}

- (void)tearDown {
  [_fixture.window close];
  [super tearDown];
}

- (void)testTheCheckboxHasTheCheckBoxRoleAndStartsNotSelected {
  PCDialogCheckbox* box = _fixture.box;
  Check([box.accessibilityRole isEqualToString:NSAccessibilityCheckBoxRole] &&
            [box.accessibilityValue isEqualToString:@"Not selected"],
        "checkbox role, not selected");
}

- (void)testTheCheckboxFitsItsWidthWithAFullLine {
  Check(_size.width <= 300 && _size.height >= 17, "checkbox fits its width with a full line");
}

- (void)testSpaceTogglesAndReportsSelected {
  PCDialogCheckbox* box = _fixture.box;
  [box keyDown:Key(_fixture.window, @" ", 49)];
  Check(box.state == NSControlStateValueOn && _fixture.changes == 1 &&
            [box.accessibilityValue isEqualToString:@"Selected"],
        "Space toggles and reports Selected");
}

- (void)testReturnPassesOn {
  PCDialogCheckbox* box = _fixture.box;
  [box keyDown:Key(_fixture.window, @"\r", 36)];
  Check(box.state == NSControlStateValueOff && _fixture.changes == 0, "Return passes on");
}

- (void)testOptionSpaceDoesNotToggle {
  PCDialogCheckbox* box = _fixture.box;
  [box keyDown:KeyEvent(_fixture.window, @" ", 49, NSEventModifierFlagOption, NO)];
  Check(box.state == NSControlStateValueOff && _fixture.changes == 0, "Option-Space does not toggle");
}

- (void)testAHeldSpaceDoesNotToggle {
  PCDialogCheckbox* box = _fixture.box;
  [box keyDown:KeyEvent(_fixture.window, @" ", 49, 0, YES)];
  Check(box.state == NSControlStateValueOff && _fixture.changes == 0, "a held Space does not toggle");
}

- (void)testTheOffAndOnMarksAreTheButtonsOwnTintedImages {
  PCDialogCheckbox* box = _fixture.box;
  Check(box.image && box.alternateImage && box.contentTintColor,
        "the off and on marks are the button's own tinted images");
}

- (void)testAClickTogglesAndAnotherClickTogglesBack {
  PCDialogCheckbox* box = _fixture.box;
  [box performClick:nil];
  Check(box.state == NSControlStateValueOn && _fixture.changes == 1, "click toggles on");
  [box performClick:nil];
  Check(box.state == NSControlStateValueOff && _fixture.changes == 2, "click toggles back");
}

@end
