#import "FocusManagerTestsSupport.h"

using namespace FocusManagerTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_FocusManagerTestsRequestsTests")))
@interface FocusManagerTestsRequestsTests : ParcNativeTestCase
@end

@implementation FocusManagerTestsRequestsTests

- (void)observeFocus:(void (^)(NSWindow*, FocusManagerTestsFocusView*, FocusManagerTestsFocusView*, PCNativeFocusManager*, NSMutableArray*))check {
  NSWindow* window = Window();
  FocusManagerTestsFocusView *a = View(window), *b = View(window);
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  NSMutableArray* events = [NSMutableArray array];
  PCNativeFocusRegistration* ta = [manager registerResponder:a
      forKey:@"page:A"
      didBecome:^{
        [events addObject:@"A+"];
      }
      didResign:^{
        [events addObject:@"A-"];
      }];
  PCNativeFocusRegistration* tb = [manager registerResponder:b
      forKey:@"find:A"
      didBecome:^{
        [events addObject:@"B+"];
      }
      didResign:^{
        [events addObject:@"B-"];
      }];
  check(window, a, b, manager, events);
  [ta invalidate];
  [tb invalidate];
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testRequestsReportTheActualFirstResponder {
  [self observeFocus:^(NSWindow* window, FocusManagerTestsFocusView* a, FocusManagerTestsFocusView* , PCNativeFocusManager* manager, NSMutableArray* events) {
    Check([manager requestFocusForKey:@"page:A"] == PCNativeFocusRequestAccepted,
          "real window accepts registered page focus");
    Check(window.firstResponder == a,
          "actual AppKit first responder becomes target");
    Check([manager.focusedKey isEqual:@"page:A"],
          "focused identity reflects actual responder");
    Check([events isEqual:@[ @"A+" ]], "real firstResponder KVO announces focus");
  }];
}

- (void)testRequestingTheFocusedViewKeepsItsResponder {
  [self observeFocus:^(NSWindow* , FocusManagerTestsFocusView* a, FocusManagerTestsFocusView* , PCNativeFocusManager* manager, NSMutableArray* ) {
    [manager requestFocusForKey:@"page:A"];
    NSUInteger requests = a.requests;
    Check([manager requestFocusForKey:@"page:A"] ==
              PCNativeFocusRequestAlreadyFocused,
          "duplicate actual focus is preserved");
    Check(a.requests == requests,
          "already-focused request does not reset native responder");
  }];
}

- (void)testExternalFocusDeliversResignBeforeBecome {
  [self observeFocus:^(NSWindow* window, FocusManagerTestsFocusView* , FocusManagerTestsFocusView* b, PCNativeFocusManager* manager, NSMutableArray* events) {
    [manager requestFocusForKey:@"page:A"];
    Check([window makeFirstResponder:b], "external native control changes focus");
    Check([events isEqual:@[ @"A+", @"A-", @"B+" ]],
          "external native focus gives old resign before new become without "
          "polling");
  }];
}

- (void)testReconcilingExternalFocusDoesNotRepeatCallbacks {
  [self observeFocus:^(NSWindow* window, FocusManagerTestsFocusView* , FocusManagerTestsFocusView* b, PCNativeFocusManager* manager, NSMutableArray* events) {
    [manager requestFocusForKey:@"page:A"];
    Check([window makeFirstResponder:b], "external native control changes focus");
    [manager reconcileFirstResponder];
    Check(events.count == 3, "reconciliation suppresses duplicate callbacks");
  }];
}

- (void)testUnknownResponderKeysAreRejected {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  Check([manager requestFocusForKey:@"missing"] == PCNativeFocusRequestRejected,
        "unknown responder identity is rejected");
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testDetachingTheTargetRejectsFocus {
  NSWindow *a = Window(), *b = Window();
  FocusManagerTestsFocusView *target = View(a), *sentinel = View(a);
  [a makeFirstResponder:sentinel];
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:a]);
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  [target removeFromSuperview];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "detached responder is rejected");
  [token invalidate];
  [manager invalidate];
  ParcNativeClose(a);
  ParcNativeClose(b);
}

- (void)testWrongWindowRequestsPreserveExistingFocus {
  NSWindow *a = Window(), *b = Window();
  FocusManagerTestsFocusView *target = View(a), *sentinel = View(a);
  [a makeFirstResponder:sentinel];
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:a]);
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  [b.contentView addSubview:target];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "same live target in another actual window is rejected");
  Check(a.firstResponder == sentinel,
        "wrong-window request leaves native focus intact");
  [token invalidate];
  [manager invalidate];
  ParcNativeClose(a);
  ParcNativeClose(b);
}

- (void)testReattachedTargetsAreEligible {
  NSWindow *a = Window(), *b = Window();
  FocusManagerTestsFocusView *target = View(a), *sentinel = View(a);
  [a makeFirstResponder:sentinel];
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:a]);
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  [target removeFromSuperview];
  [b.contentView addSubview:target];
  [target removeFromSuperview];
  [a.contentView addSubview:target];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
        "reattached same-window target is eligible");
  [token invalidate];
  [manager invalidate];
  ParcNativeClose(a);
  ParcNativeClose(b);
}

- (void)testCyclicResponderChainsAreRejected {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  NSResponder *one = [NSResponder new], *two = [NSResponder new];
  one.nextResponder = two;
  two.nextResponder = one;
  PCNativeFocusRegistration* cycle = Register(manager, one, @"cycle");
  Check([manager requestFocusForKey:@"cycle"] == PCNativeFocusRequestRejected,
        "malformed responder cycle terminates without hanging");
  one.nextResponder = nil;
  two.nextResponder = nil;
  [cycle invalidate];
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testRequestingAnAncestorPreservesItsFocusedChild {
  NSWindow* window = Window();
  FocusManagerTestsFocusView* parent = View(window);
  FocusManagerTestsFocusView* child = [[FocusManagerTestsFocusView alloc] initWithFrame:parent.bounds];
  [parent addSubview:child];
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  PCNativeFocusRegistration* parentToken = Register(manager, parent, @"page");
  Check([window makeFirstResponder:child],
        "real descendant receives native focus");
  Check([manager requestFocusForKey:@"page"] ==
            PCNativeFocusRequestAlreadyFocused,
        "ancestor request preserves focused child");
  Check(window.firstResponder == child && parent.requests == 0,
        "preserving descendant does not restart page focus");
  Check(manager.focusedKey == nil,
        "ancestor preservation is not a false completion callback");
  [parentToken invalidate];
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testRequestingTheFieldPreservesItsActiveSelection {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  NSTextField* field =
      [[NSTextField alloc] initWithFrame:NSMakeRect(10, 70, 200, 24)];
  field.stringValue = @"selection stays";
  [window.contentView addSubview:field];
  __block unsigned fieldEvents = 0;
  PCNativeFocusRegistration* fieldToken = [manager registerResponder:field
                                                              forKey:@"find"
                                                           didBecome:^{
                                                             ++fieldEvents;
                                                           }
                                                           didResign:nil];
  Check([window makeFirstResponder:field],
        "native text field begins actual editing");
  NSText* editor = [window fieldEditor:NO forObject:field];
  Check(editor != nil && window.firstResponder == editor,
        "AppKit supplies real field editor");
  editor.selectedRange = NSMakeRange(2, 4);
  Check([manager requestFocusForKey:@"find"] ==
            PCNativeFocusRequestAlreadyFocused,
        "text field request preserves its existing editor");
  Check(NSEqualRanges(editor.selectedRange, NSMakeRange(2, 4)),
        "text selection survives normalized responder request");
  Check([manager.focusedKey isEqual:@"find"] && fieldEvents == 1,
        "field-editor normalization reports one field focus identity");
  [fieldToken invalidate];
  [manager invalidate];
  ParcNativeClose(window);
}

@end
