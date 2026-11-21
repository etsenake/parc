#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"

#include <cstdio>
#include <cstdlib>

#import "dialog_style.h"

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
static void Drain(void) {
  ParcNativeAdvance(0.12);
}
static NSWindow* Window(void) {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2000, -2000, 640, 480)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  [window orderFront:nil];
  return window;
}
static NSEvent* Key(NSWindow* window, NSString* characters, unsigned short code) {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown
                          location:NSZeroPoint
                     modifierFlags:0
                         timestamp:NSProcessInfo.processInfo.systemUptime
                      windowNumber:window.windowNumber
                           context:nil
                        characters:characters
       charactersIgnoringModifiers:characters
                         isARepeat:NO
                           keyCode:code];
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

static PCDialogPrompt* Present(NSWindow* window, NSModalResponse* response, int* count,
                               BOOL cancelRole) {
  PCDialogPrompt* prompt = [[PCDialogPrompt alloc] initWithTitle:@"Page Unresponsive"
                                                         message:@"Example\nSecond line"];
  [prompt addButtonWithTitle:@"Wait" role:PCDialogPromptPrimary response:NSAlertFirstButtonReturn];
  [prompt addButtonWithTitle:cancelRole ? @"Never Mind" : @"Exit Page"
                        role:cancelRole ? PCDialogPromptCancel : PCDialogPromptAuxiliary
                    response:NSAlertSecondButtonReturn];
  [prompt beginSheetModalForWindow:window
                 completionHandler:^(NSModalResponse value) {
                   *response = value;
                   ++*count;
                 }];
  return prompt;
}

static void TestPrompt(void) {
  NSWindow* window = Window();
  __block NSModalResponse response = 0;
  __block int count = 0;
  __weak PCDialogPrompt* weakPrompt = nil;
  @autoreleasepool {
    PCDialogPrompt* prompt = Present(window, &response, &count, NO);
    weakPrompt = prompt;
    NSWindow* sheet = prompt.window;
    Check(window.attachedSheet == sheet && NSApp.modalWindow == nil,
          "prompt is a page-window sheet, not app-modal");
    Check([sheet.accessibilityLabel isEqualToString:@"Page Unresponsive"],
          "VoiceOver names the sheet by its title");
    NSButton* wait = Button(sheet.contentView, @"Wait");
    NSButton* exitPage = Button(sheet.contentView, @"Exit Page");
    Check(wait && exitPage && NSMinX(exitPage.frame) < NSMinX(wait.frame),
          "auxiliary sits left of the Return button");
    Check(sheet.accessibilityDefaultButton == wait, "Return button is the default");
    [sheet cancelOperation:nil];
    Drain();
    Check(count == 0 && window.attachedSheet == sheet,
          "Escape does nothing without a Cancel or chosen Escape button");
  }
  Drain();
  Check(weakPrompt != nil, "a presented prompt stays alive without an owner");
  @autoreleasepool {
    [Button(window.attachedSheet.contentView, @"Exit Page") performClick:nil];
    Drain();
  }
  Check(count == 1 && response == NSAlertSecondButtonReturn && !window.attachedSheet,
        "auxiliary click ends the sheet with its response");
  Drain();
  Check(weakPrompt == nil, "the prompt is released once its sheet ends");

  PCDialogPrompt* prompt = Present(window, &response, &count, NO);
  Check([prompt.window performKeyEquivalent:Key(prompt.window, @"\r", 36)], "Return handled");
  Drain();
  Check(count == 2 && response == NSAlertFirstButtonReturn, "Return answers the primary");
  prompt = Present(window, &response, &count, NO);
  Check([prompt.window performKeyEquivalent:Key(prompt.window, @"\003", 76)],
        "keypad Enter handled");
  Drain();
  Check(count == 3 && response == NSAlertFirstButtonReturn, "keypad Enter answers the primary");
  prompt = Present(window, &response, &count, NO);
  prompt.escapeButton = Button(prompt.window.contentView, @"Wait");
  [prompt.window cancelOperation:nil];
  Drain();
  Check(count == 4 && response == NSAlertFirstButtonReturn,
        "Escape answers the chosen Escape button");
  prompt = Present(window, &response, &count, YES);
  Check([prompt.window performKeyEquivalent:Key(prompt.window, @"\033", 53)], "Escape handled");
  Drain();
  Check(count == 5 && response == NSAlertSecondButtonReturn, "Escape answers Cancel");
  prompt = Present(window, &response, &count, YES);
  [window endSheet:prompt.window returnCode:NSModalResponseCancel];
  Drain();
  Check(count == 6 && response == NSModalResponseCancel,
        "another owner ending the sheet reports its code once");
  [window close];
}

static BOOL Inside(NSView* view) {
  return NSContainsRect(view.window.contentView.bounds, view.frame);
}

static void TestFooterWrapping(void) {
  NSWindow* window = Window();
  PCDialogPrompt* prompt = [[PCDialogPrompt alloc] initWithTitle:@"Open in app?" message:nil];
  NSButton* open = [prompt addButtonWithTitle:@"Open “Long Application”"
                                         role:PCDialogPromptPrimary
                                     response:NSAlertFirstButtonReturn];
  NSButton* cancel = [prompt addButtonWithTitle:@"Cancel"
                                           role:PCDialogPromptCancel
                                       response:NSAlertSecondButtonReturn];
  NSButton* always = [prompt addButtonWithTitle:@"Always open “Long Application”"
                                           role:PCDialogPromptAuxiliary
                                       response:NSAlertThirdButtonReturn];
  [prompt beginSheetModalForWindow:window completionHandler:nil];
  Check(Inside(open) && Inside(cancel) && Inside(always), "long buttons stay inside the sheet");
  Check(NSMaxY(always.frame) <= NSMinY(open.frame) && NSMinX(cancel.frame) < NSMinX(open.frame),
        "the auxiliary wraps above; Cancel stays beside the Return button");
  PCDialogPrompt* huge = [[PCDialogPrompt alloc] initWithTitle:@"Long" message:nil];
  NSMutableString* title = [NSMutableString stringWithString:@"Open"];
  for (int i = 0; i < 20; ++i) [title appendString:@" Application"];
  NSButton* wide = [huge addButtonWithTitle:title role:PCDialogPromptPrimary
                                   response:NSAlertFirstButtonReturn];
  [window endSheet:prompt.window];
  [huge beginSheetModalForWindow:window completionHandler:nil];
  Check(Inside(wide) && [wide.title isEqualToString:title],
        "an over-long button is capped inside the sheet and keeps its full title");
  [window endSheet:huge.window];
  [window close];
}

static void TestPanelComposition(void) {
  NSWindow* window = Window();
  PCDialogPanel* panel = [[PCDialogPanel alloc] initWithContentRect:NSMakeRect(0, 0, 450, 200)
                                                          styleMask:NSWindowStyleMaskTitled
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
  panel.releasedWhenClosed = NO;
  __block int accepted = 0, cancelled = 0;
  PCDialogButton* ok = [[PCDialogButton alloc] initWithTitle:@"OK" primary:YES];
  PCDialogButton* cancel = [[PCDialogButton alloc] initWithTitle:@"Cancel" primary:NO];
  ok.keyEquivalent = @"\r";
  cancel.keyEquivalent = @"\033";
  NSObject* target = [NSObject new];
  (void)target;
  PCDialogInputField* input = [[PCDialogInputField alloc] initWithText:@"seed" secure:NO];
  input.frame = NSMakeRect(20, 20, 300, NSHeight(input.frame));
  ok.frame = NSMakeRect(300, 120, 80, 38);
  cancel.frame = NSMakeRect(200, 120, 90, 38);
  for (NSView* view in @[ input, ok, cancel ]) [panel.contentView addSubview:view];
  panel.enterButton = ok;
  panel.escapeButton = cancel;
  ok.target = [NSBlockOperation blockOperationWithBlock:^{ ++accepted; }];
  ok.action = @selector(main);
  cancel.target = [NSBlockOperation blockOperationWithBlock:^{ ++cancelled; }];
  cancel.action = @selector(main);
  id okTarget = ok.target, cancelTarget = cancel.target;
  [window beginSheet:panel completionHandler:nil];
  Drain();
  [panel makeFirstResponder:input.field];
  NSTextView* editor = (NSTextView*)input.field.currentEditor;
  Check([editor isKindOfClass:NSTextView.class], "field edits");
  Check(input.field.focusRingType == NSFocusRingTypeNone && NSHeight(input.frame) == 36 &&
            NSMinX(input.field.frame) == 10,
        "field sits on a 36-point card with 12-point text padding and no focus ring");
  [panel makeFirstResponder:nil];
  NSEvent* press = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:panel.windowNumber
                                       context:nil
                                   eventNumber:0
                                    clickCount:1
                                      pressure:1];
  [input mouseDown:press];
  Check(input.field.currentEditor != nil, "a press on the card's padding focuses the field");
  [editor setMarkedText:@"か" selectedRange:NSMakeRange(1, 0)
       replacementRange:NSMakeRange(NSNotFound, 0)];
  Check(![panel performKeyEquivalent:Key(panel, @"\r", 36)] &&
            ![panel performKeyEquivalent:Key(panel, @"\003", 76)] &&
            ![panel performKeyEquivalent:Key(panel, @"\033", 53)],
        "composition keeps Return, keypad Enter and Escape");
  [panel cancelOperation:nil];
  Check(accepted == 0 && cancelled == 0, "composition never answers the panel");
  [editor unmarkText];
  Check([panel performKeyEquivalent:Key(panel, @"\003", 76)] && accepted == 1,
        "keypad Enter clicks the Enter button");
  [panel cancelOperation:nil];
  Check(cancelled == 1, "Escape clicks the Escape button");
  PCDialogInputField* secure = [[PCDialogInputField alloc] initWithText:@"" secure:YES];
  Check([secure.field isKindOfClass:NSSecureTextField.class], "secure field is an NSSecureTextField");
  (void)okTarget;
  (void)cancelTarget;
  [window endSheet:panel];
  [window close];
}

static void TestCheckbox(void) {
  NSWindow* window = Window();
  __block int changes = 0;
  PCDialogCheckbox* box = [[PCDialogCheckbox alloc] initWithTitle:@"Report abuse"
                                                           target:nil
                                                           action:nil];
  NSBlockOperation* changed = [NSBlockOperation blockOperationWithBlock:^{ ++changes; }];
  box.target = changed;
  box.action = @selector(main);
  const NSSize size = [box sizeForWidth:300];
  box.frame = NSMakeRect(20, 20, size.width, size.height);
  [window.contentView addSubview:box];
  Check([box.accessibilityRole isEqualToString:NSAccessibilityCheckBoxRole] &&
            [box.accessibilityValue isEqualToString:@"Not selected"],
        "checkbox role, not selected");
  Check(size.width <= 300 && size.height >= 17, "checkbox fits its width with a full line");
  [window makeFirstResponder:box];
  [box keyDown:Key(window, @" ", 49)];
  Check(box.state == NSControlStateValueOn && changes == 1 &&
            [box.accessibilityValue isEqualToString:@"Selected"],
        "Space toggles and reports Selected");
  [box keyDown:Key(window, @"\r", 36)];
  Check(box.state == NSControlStateValueOn && changes == 1, "Return passes on");
  NSEvent* optionSpace = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                          location:NSZeroPoint
                                     modifierFlags:NSEventModifierFlagOption
                                         timestamp:NSProcessInfo.processInfo.systemUptime
                                      windowNumber:window.windowNumber
                                           context:nil
                                        characters:@" "
                       charactersIgnoringModifiers:@" "
                                         isARepeat:NO
                                           keyCode:49];
  [box keyDown:optionSpace];
  NSEvent* held = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                   location:NSZeroPoint
                              modifierFlags:0
                                  timestamp:NSProcessInfo.processInfo.systemUptime
                               windowNumber:window.windowNumber
                                    context:nil
                                 characters:@" "
                charactersIgnoringModifiers:@" "
                                  isARepeat:YES
                                    keyCode:49];
  [box keyDown:held];
  Check(box.state == NSControlStateValueOn && changes == 1,
        "Option-Space and a held Space do not toggle");
  Check(box.image && box.alternateImage && box.contentTintColor,
        "the off and on marks are the button's own tinted images");
  [box performClick:nil];
  Check(box.state == NSControlStateValueOff && changes == 2, "click toggles back");
  (void)changed;
  [window close];
}

@interface DialogStyleTests : ParcNativeTestCase
@end

@implementation DialogStyleTests

+ (NSApplicationActivationPolicy)activationPolicy {
  return NSApplicationActivationPolicyAccessory;
}

- (void)testPrompt {
  TestPrompt();
}

- (void)testFooterWrapping {
  TestFooterWrapping();
}

- (void)testPanelComposition {
  TestPanelComposition();
}

- (void)testCheckbox {
  TestCheckbox();
}

@end
