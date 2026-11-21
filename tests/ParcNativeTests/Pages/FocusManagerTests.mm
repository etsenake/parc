#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"

#include <cstdio>
#include <cstdlib>

#import "focus_manager.h"
#import "page_host.h"

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
@interface FocusView : NSView
@property(nonatomic) BOOL acceptsFocus;
@property(nonatomic) NSUInteger requests;
@end
@implementation FocusView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _acceptsFocus = YES;
  }
  return self;
}
- (BOOL)acceptsFirstResponder {
  return _acceptsFocus;
}
- (BOOL)becomeFirstResponder {
  ++_requests;
  return _acceptsFocus;
}
@end

@interface GateWindow : NSWindow
@property(nonatomic, weak) NSResponder* blockedTarget;
@property(nonatomic) BOOL acceptWithoutChanging;
@property(nonatomic) NSUInteger blockedRequests;
@property(nonatomic) BOOL reportsNilResponder;
- (void)simulateMissingFirstResponder;
@end
@implementation GateWindow
- (NSResponder*)firstResponder {
  return _reportsNilResponder ? nil : [super firstResponder];
}
- (void)simulateMissingFirstResponder {
  [self willChangeValueForKey:@"firstResponder"];
  _reportsNilResponder = YES;
  [self didChangeValueForKey:@"firstResponder"];
}
- (BOOL)makeFirstResponder:(NSResponder*)responder {
  if (responder && responder == self.blockedTarget) {
    ++_blockedRequests;
    return self.acceptWithoutChanging;
  }
  if (_reportsNilResponder) {
    [self willChangeValueForKey:@"firstResponder"];
    _reportsNilResponder = NO;
    BOOL result = [super makeFirstResponder:responder];
    [self didChangeValueForKey:@"firstResponder"];
    return result;
  }
  return [super makeFirstResponder:responder];
}
@end

static NSWindow* Window(Class cls = NSWindow.class) {
  NSWindow* window = [[cls alloc]
      initWithContentRect:NSMakeRect(0, 0, 480, 320)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  return window;
}
static FocusView* View(NSWindow* window) {
  FocusView* view = [[FocusView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
  [window.contentView addSubview:view];
  return view;
}
static void Drain(void) {
  ParcNativeSettle();
}
static PCNativeFocusRegistration* Register(PCNativeFocusManager* manager,
                                           NSResponder* responder,
                                           NSString* key) {
  PCNativeFocusRegistration* token = [manager registerResponder:responder
                                                         forKey:key
                                                      didBecome:nil
                                                      didResign:nil];
  Check(token != nil, "native responder registration succeeds");
  return token;
}

@interface ParcNativeTests_FocusManagerTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_FocusManagerTests

- (void)observeFocus:(void (^)(NSWindow*, FocusView*, FocusView*, PCNativeFocusManager*, NSMutableArray*))check {
  NSWindow* window = Window();
  FocusView *a = View(window), *b = View(window);
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
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
  [window close];
}

- (void)testRequestsReportTheActualFirstResponder {
  [self observeFocus:^(NSWindow* window, FocusView* a, FocusView* , PCNativeFocusManager* manager, NSMutableArray* events) {
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
  [self observeFocus:^(NSWindow* , FocusView* a, FocusView* , PCNativeFocusManager* manager, NSMutableArray* ) {
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
  [self observeFocus:^(NSWindow* window, FocusView* , FocusView* b, PCNativeFocusManager* manager, NSMutableArray* events) {
    [manager requestFocusForKey:@"page:A"];
    Check([window makeFirstResponder:b], "external native control changes focus");
    Check([events isEqual:@[ @"A+", @"A-", @"B+" ]],
          "external native focus gives old resign before new become without "
          "polling");
    [manager reconcileFirstResponder];
    Check(events.count == 3, "reconciliation suppresses duplicate callbacks");
  }];
}

- (void)testUnknownResponderKeysAreRejected {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
  Check([manager requestFocusForKey:@"missing"] == PCNativeFocusRequestRejected,
        "unknown responder identity is rejected");
  [manager invalidate];
  [window close];
}

- (void)testDetachingTheTargetRejectsFocus {
  NSWindow *a = Window(), *b = Window();
  FocusView *target = View(a), *sentinel = View(a);
  [a makeFirstResponder:sentinel];
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:a];
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  [target removeFromSuperview];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "detached responder is rejected");
  [token invalidate];
  [manager invalidate];
  [a close];
  [b close];
}

- (void)testWrongWindowRequestsPreserveExistingFocus {
  NSWindow *a = Window(), *b = Window();
  FocusView *target = View(a), *sentinel = View(a);
  [a makeFirstResponder:sentinel];
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:a];
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  [b.contentView addSubview:target];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "same live target in another actual window is rejected");
  Check(a.firstResponder == sentinel,
        "wrong-window request leaves native focus intact");
  [token invalidate];
  [manager invalidate];
  [a close];
  [b close];
}

- (void)testReattachedTargetsAreEligible {
  NSWindow *a = Window(), *b = Window();
  FocusView *target = View(a), *sentinel = View(a);
  [a makeFirstResponder:sentinel];
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:a];
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  [target removeFromSuperview];
  [b.contentView addSubview:target];
  [target removeFromSuperview];
  [a.contentView addSubview:target];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
        "reattached same-window target is eligible");
  [token invalidate];
  [manager invalidate];
  [a close];
  [b close];
}

- (void)testCyclicResponderChainsAreRejected {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
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
  [window close];
}

- (void)testRequestingAnAncestorPreservesItsFocusedChild {
  NSWindow* window = Window();
  FocusView* parent = View(window);
  FocusView* child = [[FocusView alloc] initWithFrame:parent.bounds];
  [parent addSubview:child];
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
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
  [window close];
}

- (void)testRequestingTheFieldPreservesItsActiveSelection {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
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
  [window close];
}

- (void)withRefusedTarget:(void (^)(GateWindow*, FocusView*, PCNativeFocusManager*, NSTimeInterval*))check {
  GateWindow* window = (GateWindow*)Window(GateWindow.class);
  FocusView* sentinel = View(window);
  FocusView* target = View(window);
  [window makeFirstResponder:sentinel];
  __block NSTimeInterval now = 100;
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window
                                             clock:^{
                                               return now;
                                             }];
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  window.blockedTarget = target;
  check(window, sentinel, manager, &now);
  [token invalidate];
  [manager invalidate];
  [window close];
}

- (void)testRefusalPreservesTheActualResponder {
  [self withRefusedTarget:^(GateWindow* window, FocusView* sentinel, PCNativeFocusManager* manager, NSTimeInterval* ) {
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
          "reported AppKit refusal is not success");
    Check(window.firstResponder == sentinel,
          "refused request preserves actual focus");
  }];
}

- (void)testPendingRequestsRetryOnlyAtTheTwoSecondBoundary {
  [self withRefusedTarget:^(GateWindow* window, FocusView* , PCNativeFocusManager* manager, NSTimeInterval* now) {
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
  [self withRefusedTarget:^(GateWindow* window, FocusView* sentinel, PCNativeFocusManager* manager, NSTimeInterval* ) {
    window.acceptWithoutChanging = YES;
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
          "native acceptance is distinct from observed focus");
    Check(manager.focusedKey == nil && window.firstResponder == sentinel,
          "accepted deferred request does not invent actual focus");
  }];
}

- (void)testFocusingAnotherTargetSupersedesAPendingRequest {
  [self withRefusedTarget:^(GateWindow* window, FocusView* , PCNativeFocusManager* manager, NSTimeInterval* ) {
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

- (void)testStaleTokensCannotUnregisterTheirReplacement {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
  FocusView *old = View(window), *replacement = View(window);
  PCNativeFocusRegistration* oldToken = Register(manager, old, @"page");
  PCNativeFocusRegistration* newToken = Register(manager, replacement, @"page");
  [oldToken invalidate];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted &&
            window.firstResponder == replacement,
        "stale token cannot remove replacement generation");
  [newToken invalidate];
  [manager invalidate];
  [window close];
}

- (void)testInvalidatingATokenRemovesItsResponder {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
  PCNativeFocusRegistration* newToken = Register(manager, View(window), @"page");
  [newToken invalidate];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "explicit token removal ends registration");
  [manager invalidate];
  [window close];
}

- (void)testRegistrationsHoldTheirRespondersWeakly {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
  __weak FocusView* weakView;
  PCNativeFocusRegistration* weakToken;
  @autoreleasepool {
    FocusView* transient = [[FocusView alloc] initWithFrame:NSZeroRect];
    weakView = transient;
    weakToken = Register(manager, transient, @"weak");
  }
  Check(weakView == nil, "registration does not own responder lifetime");
  Check([manager requestFocusForKey:@"weak"] == PCNativeFocusRequestRejected,
        "deallocated weak responder cannot be focused");
  [weakToken invalidate];
  [manager invalidate];
  [window close];
}

- (void)testReleasingTheTokenUnregistersItsResponder {
  NSWindow* window = Window();
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
  FocusView* old = View(window);
  @autoreleasepool {
    PCNativeFocusRegistration* releasedToken =
        Register(manager, old, @"released");
    Check(releasedToken != nil, "scoped token exists");
  }
  Check(
      [manager requestFocusForKey:@"released"] == PCNativeFocusRequestRejected,
      "token deallocation unregisters without explicit call");
  [manager invalidate];
  [window close];
}

- (void)testClosingAWindowReleasesItsFocusManagerAttachment {
  __weak NSWindow* weakWindow;
  PCNativeFocusManager* orphan;
  @autoreleasepool {
    NSWindow* temporary = Window();
    weakWindow = temporary;
    orphan = [[PCNativeFocusManager alloc] initWithWindow:temporary];
    [temporary close];
  }
  Check(orphan.isInvalidated, "window close automatically tears down manager");
  Check(weakWindow == nil && orphan.window == nil,
        "manager does not retain closed window");
}

- (void)testResignCallbacksCanSupersedeTheIntermediateResponder {
  NSWindow* window = Window();
  FocusView *a = View(window), *b = View(window), *c = View(window);
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
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
  [window close];
}

- (void)testARegisteringOwnerCanInvalidateDuringItsBecomeCallback {
  NSWindow* window = Window();
  FocusView *a = View(window), *b = View(window);
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window];
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
  [window close];
}

- (void)withPageHost:(void (^)(NSWindow*, PCNativePageHost*, NSView*, FocusView*))check {
  NSWindow* window = Window();
  NSView* page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
  FocusView* renderer = [[FocusView alloc] initWithFrame:page.bounds];
  [page addSubview:renderer];
  PCNativePageHost* host = [PCNativePageHost hostWithContentView:page
                                                        observer:nil];
  [window.contentView addSubview:host];
  check(window, host, page, renderer);
  [host invalidate];
  [window close];
}

- (void)testDeferredPageFocusResolvesToTheRenderer {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusView* renderer) {
    FocusView* sentinel = View(window);
    [window makeFirstResponder:sentinel];
    PCNativeFocusManager* manager =
        [[PCNativeFocusManager alloc] initWithWindow:window];
    PCNativeFocusRegistration* token = Register(manager, host, @"page");
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
          "manager requests the real deferred page host");
    Drain();
    Check(window.firstResponder == renderer,
          "page host focuses renderer through actual queued work");
    Check([manager requestFocusForKey:@"page"] ==
              PCNativeFocusRequestAlreadyFocused,
          "manager preserves renderer descendant focus");
    [token invalidate];
    [manager invalidate];
  }];
}

- (void)testManagersRejectAHostMovedToAnotherWindow {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusView* ) {
    NSWindow* destination = Window();
    PCNativeFocusManager* manager =
        [[PCNativeFocusManager alloc] initWithWindow:window];
    PCNativeFocusRegistration* token = Register(manager, host, @"page");
    [host removeFromSuperview];
    [destination.contentView addSubview:host];
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
          "old window manager rejects the live reparented host");
    [token invalidate];
    [manager invalidate];
    [destination close];
  }];
}

- (void)testAControlCanSupersedeQueuedPageFocus {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusView* renderer) {
    FocusView* control = View(window);
    Check([window makeFirstResponder:host], "real page host queues native focus");
    Check([window makeFirstResponder:control], "native control supersedes queued page focus");
    Drain();
    Check(window.firstResponder == control && renderer.requests == 0,
          "deferred renderer request cannot steal from a later native control");
  }];
}

- (void)testQueuedFocusCannotMigrateToAnotherWindow {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusView* renderer) {
    NSWindow* destination = Window();
    FocusView* otherControl = View(destination);
    Check([window makeFirstResponder:host], "original page can request focus again");
    [host removeFromSuperview];
    [destination.contentView addSubview:host];
    Check([destination makeFirstResponder:otherControl], "destination window owns its own responder");
    Drain();
    Check(destination.firstResponder == otherControl && renderer.requests == 0,
          "queued work never retargets a moved page to its new physical window");
    [destination close];
  }];
}

- (void)testAReplacementRendererNeedsAFreshRequest {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* page, FocusView* renderer) {
    FocusView* control = View(window);
    Check([window makeFirstResponder:control], "original window returns to native control");
    Check([window makeFirstResponder:host], "page accepts another explicit request");
    [renderer removeFromSuperview];
    FocusView* replacement = [[FocusView alloc] initWithFrame:page.bounds];
    [page addSubview:replacement];
    Drain();
    Check(replacement.requests == 0, "replacement renderer cannot inherit a queued focus request");
    Check([window makeFirstResponder:control], "control remains available after renderer replacement");
    Check([window makeFirstResponder:host], "fresh original-owner request admits actual new renderer");
    Drain();
    Check(window.firstResponder == replacement && replacement.requests == 1,
          "fresh request reaches actual renderer through original host");
  }];
}

- (void)testInvalidationCancelsQueuedRendererFocus {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusView* renderer) {
    [window makeFirstResponder:host];
    [host invalidate];
    Drain();
    XCTAssertEqual(renderer.requests, 0u);
  }];
}

- (void)withFallback:(void (^)(GateWindow*, FocusView*, FocusView*, FocusView*, PCNativeFocusManager*, NSTimeInterval*))check {
  GateWindow* window = (GateWindow*)Window(GateWindow.class);
  FocusView *sentinel = View(window), *target = View(window),
            *fallback = View(window);
  [window makeFirstResponder:sentinel];
  __block NSTimeInterval now = 100;
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window
                                             clock:^{
                                               return now;
                                             }];
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  PCNativeFocusRegistration* fallbackToken =
      Register(manager, fallback, @"fallback");
  manager.fallbackKey = @"fallback";
  check(window, sentinel, target, fallback, manager, &now);
  [token invalidate];
  [fallbackToken invalidate];
  [manager invalidate];
  [window close];
}

- (void)testFallbackPreservesAnExistingResponder {
  [self withFallback:^(GateWindow* window, FocusView* sentinel, FocusView* , FocusView* , PCNativeFocusManager* manager, NSTimeInterval* ) {
    [manager reconcileFirstResponder];
    Check(window.firstResponder == sentinel,
          "fallback never steals nonnil native focus");
  }];
}

- (void)testFallbackWaitsForThePendingRequestToExpire {
  [self withFallback:^(GateWindow* window, FocusView* , FocusView* target, FocusView* fallback, PCNativeFocusManager* manager, NSTimeInterval* now) {
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
  [self withFallback:^(GateWindow* window, FocusView* , FocusView* target, FocusView* fallback, PCNativeFocusManager* manager, NSTimeInterval* ) {
    window.blockedTarget = target;
    [manager requestFocusForKey:@"page"];
    [target removeFromSuperview];
    [window simulateMissingFirstResponder];
    Check(window.firstResponder == fallback,
          "detached pending target cannot block valid fallback");
  }];
}

- (void)testUnregisteringAPendingTargetReleasesIt {
  GateWindow* retentionWindow = (GateWindow*)Window(GateWindow.class);
  PCNativeFocusManager* retentionManager =
      [[PCNativeFocusManager alloc] initWithWindow:retentionWindow];
  PCNativeFocusRegistration* pendingToken;
  __weak FocusView* weakPending;
  @autoreleasepool {
    FocusView* temporary = View(retentionWindow);
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
  [retentionWindow close];
}

- (void)testObserversReleaseTheirFocusManager {
  GateWindow* retentionWindow = (GateWindow*)Window(GateWindow.class);
  PCNativeFocusManager* retentionManager =
      [[PCNativeFocusManager alloc] initWithWindow:retentionWindow];
  __weak PCNativeFocusManager* weakManager = retentionManager;
  retentionManager = nil;
  Check(weakManager == nil, "KVO and close observer do not retain manager");
  FocusView* after = View(retentionWindow);
  Check([retentionWindow makeFirstResponder:after],
        "window remains usable after manager deallocation");
  [retentionWindow close];
}

- (void)testAResignCallbackCanReleaseItsManagerDuringDelivery {
  NSWindow* window = Window();
  FocusView *a = View(window), *b = View(window), *sentinel = View(window);
  [window makeFirstResponder:sentinel];
  __block PCNativeFocusManager* owner =
      [[PCNativeFocusManager alloc] initWithWindow:window];
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
  [window close];
}

- (void)testABecomeCallbackCanReleaseItsManagerDuringDelivery {
  NSWindow* window = Window();
  FocusView *a = View(window), *b = View(window), *sentinel = View(window);
  [window makeFirstResponder:sentinel];
  __block PCNativeFocusManager* owner =
      [[PCNativeFocusManager alloc] initWithWindow:window];
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
  [window close];
}

@end
