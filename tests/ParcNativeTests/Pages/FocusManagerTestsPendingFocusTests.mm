#import "FocusManagerTestsSupport.h"

using namespace FocusManagerTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_FocusManagerTestsPendingFocusTests")))
@interface FocusManagerTestsPendingFocusTests : ParcNativeTestCase
@end

@implementation FocusManagerTestsPendingFocusTests

- (void)withRefusedTarget:(void (^)(FocusManagerTestsGateWindow*, FocusManagerTestsFocusView*, PCNativeFocusManager*, NSTimeInterval*))check {
  FocusManagerTestsGateWindow* window = (FocusManagerTestsGateWindow*)Window(FocusManagerTestsGateWindow.class);
  FocusManagerTestsFocusView* sentinel = View(window);
  FocusManagerTestsFocusView* target = View(window);
  [window makeFirstResponder:sentinel];
  __block NSTimeInterval now = 100;
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window
                                             clock:^{
                                               return now;
                                             }]);
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  window.blockedTarget = target;
  check(window, sentinel, manager, &now);
  [token invalidate];
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testRefusalPreservesTheActualResponder {
  [self withRefusedTarget:^(FocusManagerTestsGateWindow* window, FocusManagerTestsFocusView* sentinel, PCNativeFocusManager* manager, NSTimeInterval* ) {
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
          "reported AppKit refusal is not success");
    Check(window.firstResponder == sentinel,
          "refused request preserves actual focus");
  }];
}

- (void)testPendingRequestsRetryOnlyAtTheTwoSecondBoundary {
  [self withRefusedTarget:^(FocusManagerTestsGateWindow* window, FocusManagerTestsFocusView* , PCNativeFocusManager* manager, NSTimeInterval* now) {
    [manager requestFocusForKey:@"page"];
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestPending,
          "same refused target is pending until threshold");
    *now = 101.999;
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestPending,
          "strictly less than two seconds suppresses resend");
    Check(window.blockedRequests == 1, "suppression sends no native request");
    *now = 102;
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
          "exactly two seconds permits another native attempt");
    Check(window.blockedRequests == 2,
          "boundary retries only when explicitly requested");
  }];
}

- (void)testAppKitAcceptanceDoesNotInventObservedFocus {
  [self withRefusedTarget:^(FocusManagerTestsGateWindow* window, FocusManagerTestsFocusView* sentinel, PCNativeFocusManager* manager, NSTimeInterval* ) {
    window.acceptWithoutChanging = YES;
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
          "native acceptance is distinct from observed focus");
    Check(manager.focusedKey == nil && window.firstResponder == sentinel,
          "accepted deferred request does not invent actual focus");
  }];
}

- (void)testFocusingAnotherTargetSupersedesAPendingRequest {
  [self withRefusedTarget:^(FocusManagerTestsGateWindow* window, FocusManagerTestsFocusView* , PCNativeFocusManager* manager, NSTimeInterval* ) {
    PCNativeFocusRegistration* other = Register(manager, View(window), @"other");
    [manager requestFocusForKey:@"page"];
    Check([manager requestFocusForKey:@"other"] == PCNativeFocusRequestAccepted,
          "different target can supersede pending request");
    Check([manager.focusedKey isEqual:@"other"],
          "new real focus determines identity");
    window.blockedTarget = nil;
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
          "old pending state does not prevent later genuine focus");
    [other invalidate];
  }];
}

- (void)withFallback:(void (^)(FocusManagerTestsGateWindow*, FocusManagerTestsFocusView*, FocusManagerTestsFocusView*, FocusManagerTestsFocusView*, PCNativeFocusManager*, NSTimeInterval*))check {
  FocusManagerTestsGateWindow* window = (FocusManagerTestsGateWindow*)Window(FocusManagerTestsGateWindow.class);
  FocusManagerTestsFocusView *sentinel = View(window), *target = View(window),
            *fallback = View(window);
  [window makeFirstResponder:sentinel];
  __block NSTimeInterval now = 100;
  PCNativeFocusManager* manager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:window
                                             clock:^{
                                               return now;
                                             }]);
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  PCNativeFocusRegistration* fallbackToken =
      Register(manager, fallback, @"fallback");
  manager.fallbackKey = @"fallback";
  check(window, sentinel, target, fallback, manager, &now);
  [token invalidate];
  [fallbackToken invalidate];
  [manager invalidate];
  ParcNativeClose(window);
}

- (void)testFallbackPreservesAnExistingResponder {
  [self withFallback:^(FocusManagerTestsGateWindow* window, FocusManagerTestsFocusView* sentinel, FocusManagerTestsFocusView* , FocusManagerTestsFocusView* , PCNativeFocusManager* manager, NSTimeInterval* ) {
    [manager reconcileFirstResponder];
    Check(window.firstResponder == sentinel,
          "fallback never steals nonnil native focus");
  }];
}

- (void)testFallbackWaitsForThePendingRequestToExpire {
  [self withFallback:^(FocusManagerTestsGateWindow* window, FocusManagerTestsFocusView* , FocusManagerTestsFocusView* target, FocusManagerTestsFocusView* fallback, PCNativeFocusManager* manager, NSTimeInterval* now) {
    window.blockedTarget = target;
    [manager requestFocusForKey:@"page"];
    [window simulateMissingFirstResponder];
    Check(
        window.firstResponder == nil && fallback.requests == 0,
        "controlled nil focus preserves a fresh pending target without fallback");
    *now = 102;
    [manager reconcileFirstResponder];
    Check(window.firstResponder == fallback,
          "explicit nil-focus reconcile uses selected fallback after pending "
          "expires");
    Check([manager.focusedKey isEqual:@"fallback"],
          "fallback identity is actual native focus");
  }];
}

- (void)testDetachingAPendingTargetAllowsFallback {
  [self withFallback:^(FocusManagerTestsGateWindow* window, FocusManagerTestsFocusView* , FocusManagerTestsFocusView* target, FocusManagerTestsFocusView* fallback, PCNativeFocusManager* manager, NSTimeInterval* ) {
    window.blockedTarget = target;
    [manager requestFocusForKey:@"page"];
    [target removeFromSuperview];
    [window simulateMissingFirstResponder];
    Check(window.firstResponder == fallback,
          "detached pending target cannot block valid fallback");
  }];
}

- (void)testUnregisteringAPendingTargetReleasesIt {
  FocusManagerTestsGateWindow* retentionWindow = (FocusManagerTestsGateWindow*)Window(FocusManagerTestsGateWindow.class);
  PCNativeFocusManager* retentionManager =
      Offscreen([[PCNativeFocusManager alloc] initWithWindow:retentionWindow]);
  PCNativeFocusRegistration* pendingToken;
  __weak FocusManagerTestsFocusView* weakPending;
  @autoreleasepool {
    FocusManagerTestsFocusView* temporary = View(retentionWindow);
    weakPending = temporary;
    retentionWindow.blockedTarget = temporary;
    pendingToken = Register(retentionManager, temporary, @"pending");
    [retentionManager requestFocusForKey:@"pending"];
    [temporary removeFromSuperview];
  }
  Check(weakPending != nil,
        "pending value temporarily retains target as recovered");
  [pendingToken invalidate];
  Check(weakPending == nil,
        "registration removal releases pending target during teardown");
  ParcNativeClose(retentionWindow);
}

@end
