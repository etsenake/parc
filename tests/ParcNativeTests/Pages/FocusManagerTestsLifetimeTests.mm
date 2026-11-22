#import "FocusManagerTestsSupport.h"

using namespace FocusManagerTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_FocusManagerTestsLifetimeTests")))
@interface FocusManagerTestsLifetimeTests : ParcNativeTestCase
@end

@implementation FocusManagerTestsLifetimeTests

- (void)testStaleTokensCannotUnregisterTheirReplacement {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  FocusManagerTestsFocusView *old = View(window), *replacement = View(window);
  PCNativeFocusRegistration* oldToken = Register(manager, old, @"page");
  PCNativeFocusRegistration* newToken = Register(manager, replacement, @"page");
  [oldToken invalidate];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted &&
            window.firstResponder == replacement,
        "stale token cannot remove replacement generation");
  [newToken invalidate];
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testInvalidatingATokenRemovesItsResponder {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  PCNativeFocusRegistration* newToken = Register(manager, View(window), @"page");
  [newToken invalidate];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "explicit token removal ends registration");
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testRegistrationsHoldTheirRespondersWeakly {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  __weak FocusManagerTestsFocusView* weakView;
  PCNativeFocusRegistration* weakToken;
  @autoreleasepool {
    FocusManagerTestsFocusView* transient = [[FocusManagerTestsFocusView alloc] initWithFrame:NSZeroRect];
    weakView = transient;
    weakToken = Register(manager, transient, @"weak");
  }
  Check(weakView == nil, "registration does not own responder lifetime");
  Check([manager requestFocusForKey:@"weak"] == PCNativeFocusRequestRejected,
        "deallocated weak responder cannot be focused");
  [weakToken invalidate];
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testReleasingTheTokenUnregistersItsResponder {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  FocusManagerTestsFocusView* old = View(window);
  @autoreleasepool {
    PCNativeFocusRegistration* releasedToken =
        Register(manager, old, @"released");
    Check(releasedToken != nil, "scoped token exists");
  }
  Check(
      [manager requestFocusForKey:@"released"] == PCNativeFocusRequestRejected,
      "token deallocation unregisters without explicit call");
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testClosingAWindowReleasesItsFocusManagerAttachment {
  __weak NSWindow* weakWindow;
  PCNativeFocusManager* orphan;
  @autoreleasepool {
    NSWindow* temporary = Window();
    weakWindow = temporary;
    orphan = Offscreen([[PCNativeFocusManager alloc] initWithWindow:temporary]);
    ParcNativeClose(temporary);
  }
  Check(orphan.isInvalidated, "window close automatically tears down manager");
  Check(weakWindow == nil && orphan.window == nil,
        "manager does not retain closed window");
}

- (void)testResignCallbacksCanSupersedeTheIntermediateResponder {
  NSWindow* window = Window();
  FocusManagerTestsFocusView *a = View(window), *b = View(window), *c = View(window);
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  __weak PCNativeFocusManager* weakManager = manager;
  NSMutableArray* events = [NSMutableArray array];
  PCNativeFocusRegistration* ta = [manager registerResponder:a
      forKey:@"A"
      didBecome:^{
        [events addObject:@"A+"];
      }
      didResign:^{
        [events addObject:@"A-"];
        [weakManager requestFocusForKey:@"C"];
      }];
  PCNativeFocusRegistration* tb = [manager registerResponder:b
      forKey:@"B"
      didBecome:^{
        [events addObject:@"B+"];
      }
      didResign:^{
        [events addObject:@"B-"];
      }];
  PCNativeFocusRegistration* tc = [manager registerResponder:c
                                                      forKey:@"C"
                                                   didBecome:^{
                                                     [events addObject:@"C+"];
                                                   }
                                                   didResign:nil];
  [manager requestFocusForKey:@"A"];
  [manager requestFocusForKey:@"B"];
  Check(window.firstResponder == c,
        "resign callback may make a newer real focus request");
  Check(![events containsObject:@"B+"],
        "superseded intermediate focus receives no stale become callback");
  Check([events containsObject:@"C+"] && [manager.focusedKey isEqual:@"C"],
        "reentrant final focus remains coherent");
  [ta invalidate];
  [tb invalidate];
  [tc invalidate];
  ParcNativeClose(window);
}

- (void)testARegisteringOwnerCanInvalidateDuringItsBecomeCallback {
  NSWindow* window = Window();
  FocusManagerTestsFocusView *a = View(window), *b = View(window);
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  __weak PCNativeFocusManager* weakManager = manager;
  NSMutableArray* events = [NSMutableArray array];
  PCNativeFocusRegistration* closing = [manager registerResponder:a
      forKey:@"closing"
      didBecome:^{
        [weakManager invalidate];
      }
      didResign:^{
        [events addObject:@"late"];
      }];
  [manager requestFocusForKey:@"closing"];
  Check(manager.isInvalidated, "callback can invalidate manager safely");
  NSUInteger count = events.count;
  [window makeFirstResponder:b];
  [manager reconcileFirstResponder];
  [manager invalidate];
  Check(events.count == count,
        "invalidated manager has no later native callbacks");
  Check([manager requestFocusForKey:@"C"] == PCNativeFocusRequestRejected,
        "terminal manager cannot request focus");
  [closing invalidate];
  ParcNativeClose(window);
}

- (void)testObserversReleaseTheirFocusManager {
  FocusManagerTestsGateWindow* retentionWindow = (FocusManagerTestsGateWindow*)Window(FocusManagerTestsGateWindow.class);
  PCNativeFocusManager* retentionManager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:retentionWindow]);
  __weak PCNativeFocusManager* weakManager = retentionManager;
  retentionManager = nil;
  Check(weakManager == nil, "KVO and close observer do not retain manager");
  FocusManagerTestsFocusView* after = View(retentionWindow);
  Check([retentionWindow makeFirstResponder:after],
        "window remains usable after manager deallocation");
  ParcNativeClose(retentionWindow);
}

- (void)testAResignCallbackCanReleaseItsManagerDuringDelivery {
  NSWindow* window = Window();
  FocusManagerTestsFocusView *a = View(window), *b = View(window), *sentinel = View(window);
  [window makeFirstResponder:sentinel];
  __block PCNativeFocusManager* owner =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  __weak PCNativeFocusManager* weakOwner = owner;
  __block BOOL aliveAfterRelease = NO, deliveredBecome = NO;
  PCNativeFocusRegistration* ta = [owner registerResponder:a
                                                    forKey:@"A"
                                                 didBecome:nil
                                                 didResign:^{
                                                   owner = nil;
                                                   aliveAfterRelease =
                                                       weakOwner != nil;
                                                 }];
  PCNativeFocusRegistration* tb = [owner registerResponder:b
                                                    forKey:@"B"
                                                 didBecome:^{
                                                   deliveredBecome =
                                                       weakOwner != nil;
                                                 }
                                                 didResign:nil];
  [owner requestFocusForKey:@"A"];
  Check([window makeFirstResponder:b],
        "native transition can release focus-manager owner");
  Check(
      aliveAfterRelease && deliveredBecome,
      "delivery retains manager through resign and subsequent become callback");
  Check(owner == nil && weakOwner == nil,
        "delivery releases manager and removes observations after callbacks "
        "finish");
  [ta invalidate];
  [tb invalidate];
  ParcNativeClose(window);
}

- (void)testABecomeCallbackCanReleaseItsManagerDuringDelivery {
  NSWindow* window = Window();
  FocusManagerTestsFocusView *a = View(window), *b = View(window), *sentinel = View(window);
  [window makeFirstResponder:sentinel];
  __block PCNativeFocusManager* owner =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
  __weak PCNativeFocusManager* weakOwner = owner;
  __block BOOL aliveDuringBecome = NO;
  PCNativeFocusRegistration* becomeToken =
      [owner registerResponder:a
                        forKey:@"A"
                     didBecome:^{
                       owner = nil;
                       aliveDuringBecome = weakOwner != nil;
                     }
                     didResign:nil];
  Check([window makeFirstResponder:a],
        "native become callback can release manager owner");
  Check(
      aliveDuringBecome && weakOwner == nil,
      "become delivery keeps manager alive only through reconciliation scope");
  [becomeToken invalidate];
  Check([window makeFirstResponder:b],
        "native window remains usable after callback-driven teardown");
  ParcNativeClose(window);
}

@end
