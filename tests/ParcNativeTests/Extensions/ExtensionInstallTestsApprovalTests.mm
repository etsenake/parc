#import "ExtensionInstallTestsSupport.h"

using namespace ExtensionInstallTestsSupportFunctions;

__attribute__((objc_runtime_name("ParcNativeTests_ExtensionInstallTestsApprovalTests")))
@interface ExtensionInstallTestsApprovalTests : ExtensionInstallTestsSupport
@end

@implementation ExtensionInstallTestsApprovalTests

- (PCExtensionInstallPresenter*)shownJustificationRequest {
  PCExtensionInstallPresenter* p = [[PCExtensionInstallPresenter alloc] initWithWindow:_w
                                                                                 title:@"Request example?"
                                                                                  icon:nil
                                                                               heading:@"Your administrator reviews requests."
                                                                           permissions:@[]
                                                                               details:@[]
                                                                           acceptLabel:@"Request"
                                                                           cancelLabel:@"Cancel"
                                                                         checkboxLabel:nil
                                                                              validate:^BOOL {
                                                                                return YES;
                                                                              }
                                                                          inputAllowed:self.inputAllowed
                                                                                result:self.result];
  p.presentation = ParcNativePresentation();
  p.scheduler = ParcNativeScheduler();
  [p configureJustificationLabel:@"Why do you need it?"
                     placeholder:@"Reason"
                     counterText:^NSString*(NSUInteger length) {
                       return [NSString stringWithFormat:@"%lu/280", (unsigned long)length];
                     }];
  [p start];
  Pump();
  return p;
}

- (NSTextView*)reasonIn:(NSView*)card {
  NSTextView* reason = nil;
  for (NSView* view = card; view && !reason; view = view.subviews.firstObject) {
    if ([view isKindOfClass:NSScrollView.class]) reason = ((NSScrollView*)view).documentView;
  }
  return reason;
}

- (void)testAJustificationCountsTheEditedText {
  PCExtensionInstallPresenter* p = [self shownJustificationRequest];
  NSView* card = View(p.sheet.contentView, @"PCDialogCard");
  NSTextView* reason = [self reasonIn:card];
  EXPECT(card && [reason isKindOfClass:NSTextView.class] && [reason.accessibilityLabel isEqual:@"Why do you need it?"]);
  EXPECT(Text(p.sheet.contentView, @"Request example?") && Text(p.sheet.contentView, @"0/280"));
  [p.sheet makeFirstResponder:reason];
  reason.string = @"Needed for work";
  [reason didChangeText];
  EXPECT(Text(p.sheet.contentView, @"15/280"));
  EXPECT([p.justification isEqual:@"Needed for work"]);
  [p invalidate];
}

- (void)testAJustificationFitsItsSheetAndButtonsWithoutAmbiguity {
  PCExtensionInstallPresenter* p = [self shownJustificationRequest];
  NSView* card = View(p.sheet.contentView, @"PCDialogCard");
  NSTextView* reason = [self reasonIn:card];
  EXPECT(NSWidth(p.sheet.frame) == 450 && (p.sheet.styleMask & NSWindowStyleMaskFullSizeContentView));
  [p.sheet makeFirstResponder:reason];
  reason.string = @"Needed for work";
  [reason didChangeText];
  NSButton* request = Button(p.sheet.contentView, @"Request");
  EXPECT(request.keyEquivalent.length == 0);
  NSView* sheetRoot = p.sheet.contentView;
  [sheetRoot layoutSubtreeIfNeeded];
  const NSRect requestFrame = [request convertRect:request.bounds toView:sheetRoot];
  NSButton* cancel = Button(sheetRoot, @"Cancel");
  const NSRect cancelFrame = [cancel convertRect:cancel.bounds toView:sheetRoot];
  const NSRect cardFrame = [card convertRect:card.bounds toView:sheetRoot];
  EXPECT(std::abs(NSMaxX(requestFrame) - (450 - 28 + .5)) <= .5 && NSWidth(requestFrame) > 40 &&
         NSMaxX(cancelFrame) < NSMinX(requestFrame) && NSContainsRect(sheetRoot.bounds, cancelFrame) &&
         NSContainsRect(sheetRoot.bounds, requestFrame) && NSMinY(requestFrame) > NSMaxY(cardFrame));
  BOOL ambiguous = NO;
  NSMutableArray<NSView*>* pending = [NSMutableArray arrayWithObject:sheetRoot];
  while (pending.count) {
    NSView* view = pending.lastObject;
    [pending removeLastObject];
    ambiguous = ambiguous || view.hasAmbiguousLayout;
    [pending addObjectsFromArray:view.subviews];
  }
  EXPECT(!ambiguous);
  [p invalidate];
}

- (void)testEscapeDuringCompositionKeepsTheRequestOpen {
  PCExtensionInstallPresenter* p = [self shownJustificationRequest];
  NSTextView* reason = [self reasonIn:View(p.sheet.contentView, @"PCDialogCard")];
  [p.sheet makeFirstResponder:reason];
  [reason setMarkedText:@"か" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
  NSEvent* escape = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                     location:NSZeroPoint
                                modifierFlags:0
                                    timestamp:ParcNativeNow()
                                 windowNumber:p.sheet.windowNumber
                                      context:nil
                                   characters:@"\033"
                  charactersIgnoringModifiers:@"\033"
                                    isARepeat:NO
                                      keyCode:53];
  EXPECT(![p.sheet performKeyEquivalent:escape] && _results == 0);
  [reason unmarkText];
  EXPECT([p.sheet performKeyEquivalent:escape]);
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallCancel);
  [p invalidate];
}

- (PCExtensionInstallPresenter*)shownParentApproval:(void (^)(NSInteger, NSString*))submit {
  PCExtensionInstallPresenter* p = [self make];
  [p configureParentAccounts:@[ @"parent@example.test", @"other@example.test" ]
                instructions:@[ @"A parent must approve this extension." ]
               passwordLabel:@"Parent password"
                      submit:submit];
  [p start];
  Pump();
  return p;
}

- (NSSecureTextField*)passwordInSheet:(NSWindow*)sheet {
  NSSecureTextField* secret = nil;
  NSMutableArray* queue = [NSMutableArray arrayWithObject:sheet.contentView];
  while (queue.count && !secret) {
    NSView* next = queue.firstObject;
    [queue removeObjectAtIndex:0];
    if ([next isKindOfClass:NSSecureTextField.class]) secret = (NSSecureTextField*)next;
    [queue addObjectsFromArray:next.subviews];
  }
  return secret;
}

- (void)testParentApprovalRequiresAndSubmitsThePassword {
  __block NSInteger submittedParent = -1;
  __block NSString* submitted = nil;
  PCExtensionInstallPresenter* p = [self shownParentApproval:^(NSInteger parent, NSString* credential) {
    submittedParent = parent;
    submitted = credential;
  }];
  NSSecureTextField* secret = [self passwordInSheet:p.sheet];
  EXPECT(secret && secret.focusRingType == NSFocusRingTypeNone &&
         [secret.superview.className isEqual:@"PCDialogInputField"] &&
         [secret.accessibilityLabel isEqual:@"Parent password"]);
  EXPECT(Text(p.sheet.contentView, @"A parent must approve this extension."));
  NSButton* add = Button(p.sheet.contentView, @"Add");
  Pump(.6);
  EXPECT(!add.enabled);
  secret.stringValue = @"hunter2";
  [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:secret];
  Pump(.1);
  EXPECT(add.enabled);
  SendClick(add);
  EXPECT(submittedParent == 0 && [submitted isEqual:@"hunter2"] && !secret.stringValue.length);
  [p invalidate];
}

- (void)testAParentApprovalErrorMakesThePasswordEditableAgain {
  PCExtensionInstallPresenter* p = [self shownParentApproval:^(NSInteger, NSString*) {}];
  NSSecureTextField* secret = [self passwordInSheet:p.sheet];
  NSButton* add = Button(p.sheet.contentView, @"Add");
  Pump(.6);
  secret.stringValue = @"hunter2";
  [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:secret];
  Pump(.1);
  SendClick(add);
  const CGFloat before = NSHeight(p.sheet.frame);
  [p setParentApprovalPending:YES error:@""];
  EXPECT(!secret.enabled && !add.enabled);
  [p setParentApprovalPending:NO
                        error:@"That password didn't work. Check it and try again, or ask "
                              @"another parent to approve this extension for you."];
  EXPECT(secret.enabled && NSHeight(p.sheet.frame) >= before);
  [p invalidate];
}

- (void)testParentApprovalCanBeCancelledAfterAnError {
  PCExtensionInstallPresenter* p = [self shownParentApproval:^(NSInteger, NSString*) {}];
  NSSecureTextField* secret = [self passwordInSheet:p.sheet];
  NSButton* add = Button(p.sheet.contentView, @"Add");
  Pump(.6);
  secret.stringValue = @"hunter2";
  [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:secret];
  Pump(.1);
  SendClick(add);
  [p setParentApprovalPending:YES error:@""];
  [p setParentApprovalPending:NO
                        error:@"That password didn't work. Check it and try again, or ask "
                              @"another parent to approve this extension for you."];
  [p.sheet cancelOperation:nil];
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallCancel);
  [p invalidate];
}

@end
