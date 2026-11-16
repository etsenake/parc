#import <AppKit/AppKit.h>
#include "../Support/TestFailure.h"

#include <cstdio>
#include <cstdlib>

#import "focus_manager.h"
#import "page_host.h"

static unsigned assertions = 0;
static unsigned groups = 0;
static void Check(BOOL condition, const char* message) {
  ++assertions;
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}
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
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
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
  __block BOOL done = NO;
  dispatch_async(dispatch_get_main_queue(), ^{
    done = YES;
  });
  NSDate* limit = [NSDate dateWithTimeIntervalSinceNow:2];
  while (!done && limit.timeIntervalSinceNow > 0) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
  }
  Check(done, "real main run loop delivers queued focus");
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

static void TestRealObservation(void) {
  ++groups;
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
  Check([manager requestFocusForKey:@"page:A"] == PCNativeFocusRequestAccepted,
        "real window accepts registered page focus");
  Check(window.firstResponder == a,
        "actual AppKit first responder becomes target");
  Check([manager.focusedKey isEqual:@"page:A"],
        "focused identity reflects actual responder");
  Check([events isEqual:@[ @"A+" ]], "real firstResponder KVO announces focus");
  NSUInteger requests = a.requests;
  Check([manager requestFocusForKey:@"page:A"] ==
            PCNativeFocusRequestAlreadyFocused,
        "duplicate actual focus is preserved");
  Check(a.requests == requests,
        "already-focused request does not reset native responder");
  Check([window makeFirstResponder:b], "external native control changes focus");
  Check([events isEqual:@[ @"A+", @"A-", @"B+" ]],
        "external native focus gives old resign before new become without "
        "polling");
  [manager reconcileFirstResponder];
  Check(events.count == 3, "reconciliation suppresses duplicate callbacks");
  Check([manager requestFocusForKey:@"missing"] == PCNativeFocusRequestRejected,
        "unknown responder identity is rejected");
  [ta invalidate];
  [tb invalidate];
  [manager invalidate];
  [window close];
}

static void TestWindowIdentityAndChains(void) {
  ++groups;
  NSWindow *a = Window(), *b = Window();
  FocusView *target = View(a), *sentinel = View(a);
  [a makeFirstResponder:sentinel];
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:a];
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  [target removeFromSuperview];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "detached responder is rejected");
  [b.contentView addSubview:target];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "same live target in another actual window is rejected");
  Check(a.firstResponder == sentinel,
        "wrong-window request leaves native focus intact");
  [target removeFromSuperview];
  [a.contentView addSubview:target];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
        "reattached same-window target is eligible");
  NSResponder *one = [NSResponder new], *two = [NSResponder new];
  one.nextResponder = two;
  two.nextResponder = one;
  PCNativeFocusRegistration* cycle = Register(manager, one, @"cycle");
  Check([manager requestFocusForKey:@"cycle"] == PCNativeFocusRequestRejected,
        "malformed responder cycle terminates without hanging");
  one.nextResponder = nil;
  two.nextResponder = nil;
  [cycle invalidate];
  [token invalidate];
  [manager invalidate];
  [a close];
  [b close];
}

static void TestDescendantAndTextEditing(void) {
  ++groups;
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
  [parentToken invalidate];
  [fieldToken invalidate];
  [manager invalidate];
  [window close];
}

static void TestPendingBoundary(void) {
  ++groups;
  GateWindow* window = (GateWindow*)Window(GateWindow.class);
  FocusView *sentinel = View(window), *target = View(window),
            *other = View(window);
  [window makeFirstResponder:sentinel];
  __block NSTimeInterval now = 100;
  PCNativeFocusManager* manager =
      [[PCNativeFocusManager alloc] initWithWindow:window
                                             clock:^{
                                               return now;
                                             }];
  PCNativeFocusRegistration* token = Register(manager, target, @"page");
  PCNativeFocusRegistration* otherToken = Register(manager, other, @"other");
  window.blockedTarget = target;
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "reported AppKit refusal is not success");
  Check(window.firstResponder == sentinel,
        "refused request preserves actual focus");
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestPending,
        "same refused target is pending until threshold");
  now = 101.999;
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestPending,
        "strictly less than two seconds suppresses resend");
  Check(window.blockedRequests == 1, "suppression sends no native request");
  now = 102;
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "exactly two seconds permits another native attempt");
  Check(window.blockedRequests == 2,
        "boundary retries only when explicitly requested");
  window.acceptWithoutChanging = YES;
  now = 104;
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
        "native acceptance is distinct from observed focus");
  Check(manager.focusedKey == nil && window.firstResponder == sentinel,
        "accepted deferred request does not invent actual focus");
  Check([manager requestFocusForKey:@"other"] == PCNativeFocusRequestAccepted,
        "different target can supersede pending request");
  Check([manager.focusedKey isEqual:@"other"],
        "new real focus determines identity");
  window.blockedTarget = nil;
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
        "old pending state does not prevent later genuine focus");
  [token invalidate];
  [otherToken invalidate];
  [manager invalidate];
  [window close];
}

static void TestRegistrationLifetime(void) {
  ++groups;
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
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "explicit token removal ends registration");
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

static void TestReentrantCallbacksAndTeardown(void) {
  ++groups;
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

static void TestDeferredPageHost(void) {
  ++groups;
  NSWindow *window = Window(), *destination = Window();
  NSView* page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
  FocusView* renderer = [[FocusView alloc] initWithFrame:page.bounds];
  [page addSubview:renderer];
  PCNativePageHost* host = [PCNativePageHost hostWithContentView:page
                                                        observer:nil];
  [window.contentView addSubview:host];
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
  [host removeFromSuperview];
  [destination.contentView addSubview:host];
  Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
        "old window manager rejects the live reparented host");
  [token invalidate];
  [manager invalidate];
  [host invalidate];
  [window close];
  [destination close];
}

static void TestDeferredFocusSupersession(void) {
  ++groups;
  NSWindow *window = Window(), *destination = Window();
  NSView* page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
  FocusView* renderer = [[FocusView alloc] initWithFrame:page.bounds];
  [page addSubview:renderer];
  PCNativePageHost* host = [PCNativePageHost hostWithContentView:page observer:nil];
  [window.contentView addSubview:host];
  FocusView *control = View(window), *otherControl = View(destination);
  Check([window makeFirstResponder:host], "real page host queues native focus");
  Check([window makeFirstResponder:control], "native control supersedes queued page focus");
  Drain();
  Check(window.firstResponder == control && renderer.requests == 0,
        "deferred renderer request cannot steal from a later native control");
  Check([window makeFirstResponder:host], "original page can request focus again");
  [host removeFromSuperview];
  [destination.contentView addSubview:host];
  Check([destination makeFirstResponder:otherControl], "destination window owns its own responder");
  Drain();
  Check(destination.firstResponder == otherControl && renderer.requests == 0,
        "queued work never retargets a moved page to its new physical window");
  [host removeFromSuperview]; [window.contentView addSubview:host];
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
  Check([window makeFirstResponder:control], "another genuine native transition succeeds");
  Check([window makeFirstResponder:host], "host can queue before terminal teardown");
  [host invalidate];
  Drain();
  Check(replacement.requests == 1, "terminal teardown cancels queued renderer work");
  [window close]; [destination close];
}

static void TestFallbackAndPendingCleanup(void) {
  ++groups;
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
  [manager reconcileFirstResponder];
  Check(window.firstResponder == sentinel,
        "fallback never steals nonnil native focus");
  window.blockedTarget = target;
  [manager requestFocusForKey:@"page"];
  [window simulateMissingFirstResponder];
  Check(
      window.firstResponder == nil && fallback.requests == 0,
      "controlled nil focus preserves a fresh pending target without fallback");
  now = 102;
  [manager reconcileFirstResponder];
  Check(window.firstResponder == fallback,
        "explicit nil-focus reconcile uses selected fallback after pending "
        "expires");
  Check([manager.focusedKey isEqual:@"fallback"],
        "fallback identity is actual native focus");
  [window makeFirstResponder:sentinel];
  [manager requestFocusForKey:@"page"];
  [target removeFromSuperview];
  [window simulateMissingFirstResponder];
  Check(window.firstResponder == fallback,
        "detached pending target cannot block valid fallback");
  [token invalidate];
  [fallbackToken invalidate];
  [manager invalidate];
  [window close];

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
  __weak PCNativeFocusManager* weakManager = retentionManager;
  retentionManager = nil;
  Check(weakManager == nil, "KVO and close observer do not retain manager");
  FocusView* after = View(retentionWindow);
  Check([retentionWindow makeFirstResponder:after],
        "window remains usable after manager deallocation");
  [retentionWindow close];
}

static void TestCallbackReleasesOwner(void) {
  ++groups;
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

  [window makeFirstResponder:sentinel];
  owner = [[PCNativeFocusManager alloc] initWithWindow:window];
  weakOwner = owner;
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

int main(void) {
  ParcExitOnUncaughtExceptions();
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestRealObservation();
    TestWindowIdentityAndChains();
    TestDescendantAndTextEditing();
    TestPendingBoundary();
    TestRegistrationLifetime();
    TestReentrantCallbacksAndTeardown();
    TestDeferredPageHost();
    TestDeferredFocusSupersession();
    TestFallbackAndPendingCleanup();
    TestCallbackReleasesOwner();
    std::printf("NativeFocusManager: %u assertions in %u groups passed\n",
                assertions, groups);
  }
  return 0;
}
