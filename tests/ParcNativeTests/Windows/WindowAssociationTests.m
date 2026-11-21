#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "browser_window.h"

#include <pthread.h>

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)

@interface AssociationObserver : NSObject <PCNativeWindowAssociationObserver>
@property(nonatomic, strong) NSMutableArray<NSNumber*>* events;
@property(nonatomic, weak) NSWindow* lastWindow;
@property(nonatomic, weak) NSWindow* reattachAfterClose;
@property(nonatomic) BOOL invalidateOnEvent;
@property(nonatomic) BOOL closeSawDetachedAssociation;
@end

@implementation AssociationObserver
- (instancetype)init {
  self = [super init];
  if (self) _events = [NSMutableArray array];
  return self;
}
- (void)nativeWindowAssociation:(PCNativeWindowAssociation*)association
               didReceiveEvent:(PCNativeWindowEvent)event
                        window:(NSWindow*)window {
  Check(NSThread.isMainThread, "observer runs on the native UI thread");
  self.lastWindow = window;
  [self.events addObject:@(event)];
  if (event == PCNativeWindowEventWillClose) {
    self.closeSawDetachedAssociation = association.window == nil;
    if (self.reattachAfterClose) {
      Check([association attachToWindow:self.reattachAfterClose],
            "close callback may attach a new shell window");
    }
  } else {
    Check(association.window == window, "event identifies the associated window");
  }
  if (self.invalidateOnEvent) [association invalidate];
}
@end

static NSWindow* Window(void) {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 480, 320)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  return window;
}

static void Post(NSNotificationName name, NSWindow* window) {
  [NSNotificationCenter.defaultCenter postNotificationName:name object:window];
}

static void* RunBlock(void* context) {
  @autoreleasepool {
    void (^work)(void) = (__bridge void (^)(void))context;
    work();
  }
  return NULL;
}

@interface ParcNativeTests_WindowAssociationTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_WindowAssociationTests {
  AssociationObserver* observer;
  PCNativeWindowAssociation* association;
}

- (void)setUp {
  [super setUp];
  observer = [AssociationObserver new];
  association = [[PCNativeWindowAssociation alloc] initWithObserver:observer];
}

- (void)tearDown {
  [association invalidate];
  association = nil;
  observer = nil;
  [super tearDown];
}

- (void)testNewAssociationsStartDetached {
  Check(association.window == nil && !association.invalidated, "starts detached");
}

- (void)testAttachmentPreservesTheSuppliedWindowWithoutActivatingIt {
  NSWindow* first = Window();
  Check([association attachToWindow:first], "attach supplied shell window");
  Check(association.window == first, "supplied window identity is preserved");
  Check(observer.events.count == 0, "attachment does not synthesize activation");
  [first close];
}

- (void)testAttachingTheSameWindowTwiceSucceeds {
  NSWindow* first = Window();
  Check([association attachToWindow:first], "attach supplied shell window");
  Check([association attachToWindow:first], "same-window attachment is idempotent");
  [first close];
}

- (void)testAttachingAnotherWindowRequiresDetachingFirst {
  NSWindow* first = Window();
  NSWindow* other = Window();
  Check([association attachToWindow:first], "attach supplied shell window");
  Check(![association attachToWindow:other], "live association cannot silently move");
  Check(association.window == first, "rejected move preserves original window");
  [first close];
  [other close];
}

- (void)testOtherWindowsDoNotDeliverEvents {
  NSWindow* first = Window();
  NSWindow* other = Window();
  Check([association attachToWindow:first], "attach supplied shell window");
  Post(NSWindowDidBecomeKeyNotification, other);
  Check(observer.events.count == 0, "other window's notification is ignored");
  [first close];
  [other close];
}

- (void)checkNotification:(NSNotificationName)notification event:(PCNativeWindowEvent)event {
  NSWindow* first = Window();
  Check([association attachToWindow:first], "attach supplied shell window");
  Post(notification, first);
  XCTAssertEqualObjects(observer.events, (@[@(event)]));
  Check(observer.lastWindow == first, "event carries actual window");
  [first close];
}

- (void)testDidBecomeKeyReachesTheAssociatedWindow {
  [self checkNotification:NSWindowDidBecomeKeyNotification event:PCNativeWindowEventDidBecomeKey];
}

- (void)testDidResignKeyReachesTheAssociatedWindow {
  [self checkNotification:NSWindowDidResignKeyNotification event:PCNativeWindowEventDidResignKey];
}

- (void)testDidEnterFullScreenReachesTheAssociatedWindow {
  [self checkNotification:NSWindowDidEnterFullScreenNotification event:PCNativeWindowEventDidEnterFullScreen];
}

- (void)testDidExitFullScreenReachesTheAssociatedWindow {
  [self checkNotification:NSWindowDidExitFullScreenNotification event:PCNativeWindowEventDidExitFullScreen];
}

- (void)testDetachingRemovesWindowNotifications {
  NSWindow* first = Window();
  Check([association attachToWindow:first], "attach supplied shell window");
  [association detach];
  Check(association.window == nil && !association.invalidated,
        "detach clears association without terminal invalidation");
  Post(NSWindowDidBecomeKeyNotification, first);
  XCTAssertEqual(observer.events.count, 0u);
  [first close];
}

- (void)testReattachmentReceivesEventsOnlyFromTheNewWindow {
  NSWindow* first = Window();
  NSWindow* other = Window();
  Check([association attachToWindow:first], "attach supplied shell window");
  [association detach];
  Check([association attachToWindow:other], "explicit detachment permits reassociation");
  Post(NSWindowDidBecomeKeyNotification, first);
  Post(NSWindowDidBecomeKeyNotification, other);
  XCTAssertEqualObjects(observer.events, (@[@(PCNativeWindowEventDidBecomeKey)]));
  XCTAssertEqual(observer.lastWindow, other);
  [first close];
  [other close];
}

- (void)testClosingDetachesBeforeDeliveringTheCloseEvent {
  NSWindow* first = Window();
  [association attachToWindow:first];
  [first close];
  Check(observer.events.count == 1 &&
        observer.events.lastObject.integerValue == PCNativeWindowEventWillClose,
        "actual NSWindow.close produces a single native close event");
  Check(observer.closeSawDetachedAssociation,
        "native close clears weak attachment before notifying owner");
  Check(observer.lastWindow == first, "closing window remains valid during callback");
}

- (void)testAReentrantCloseCanAttachAnotherWindow {
  NSWindow* first = Window();
  NSWindow* next = Window();
  observer.reattachAfterClose = next;
  [association attachToWindow:first];
  [first close];
  Check(association.window == next, "close callback's new attachment survives return");
  Post(NSWindowDidBecomeKeyNotification, first);
  Check(observer.events.count == 1, "old close clears all old notifications");
  Post(NSWindowDidBecomeKeyNotification, next);
  Check(observer.events.count == 2, "reentrant attachment is fully registered");
  observer.reattachAfterClose = nil;
  [next close];
  Check(association.window == nil && observer.events.count == 3,
        "second actual close leaves association detached");
  [association invalidate];
}

- (void)testLosingTheObserverLeavesTheAssociationAlive {
  NSWindow* window = Window();
  __weak AssociationObserver* weakObserver;
  PCNativeWindowAssociation* weakOwner;
  @autoreleasepool {
    AssociationObserver* delegate = [AssociationObserver new];
    weakObserver = delegate;
    weakOwner = [[PCNativeWindowAssociation alloc] initWithObserver:delegate];
    [weakOwner attachToWindow:window];
  }
  Check(weakObserver == nil, "weakOwner does not own its shell observer");
  Post(NSWindowDidBecomeKeyNotification, window);
  Check(weakOwner.window == window, "missing observer does not destroy weakOwner");
  [weakOwner invalidate];
  [window close];
}

- (void)testInvalidationPermanentlyDetachesTheWindow {
  NSWindow* window = Window();
  [association attachToWindow:window];
  [association invalidate];
  [association invalidate];
  Check(association.invalidated && association.window == nil,
        "invalidation is terminal and idempotent");
  Check(![association attachToWindow:window], "terminal association cannot reattach");
  [association detach];
  Check(association.invalidated, "detach cannot undo invalidation");
  [window close];
}

- (void)testDetachingReleasesTheWindow {
  PCNativeWindowAssociation* weakWindowAssociation =
      [[PCNativeWindowAssociation alloc] initWithObserver:observer];
  __weak NSWindow* weakWindow;
  @autoreleasepool {
    NSWindow* temporary = Window();
    weakWindow = temporary;
    [weakWindowAssociation attachToWindow:temporary];
    [weakWindowAssociation detach];
    [temporary close];
  }
  Check(weakWindow == nil, "association and observer do not retain detached shell window");
  [weakWindowAssociation invalidate];
}

- (void)testReleasingAnAssociationUnregistersItsNotifications {
  NSWindow* retainedByShell = Window();
  __weak PCNativeWindowAssociation* weakAssociation;
  @autoreleasepool {
    PCNativeWindowAssociation* temporary =
        [[PCNativeWindowAssociation alloc] initWithObserver:observer];
    weakAssociation = temporary;
    [temporary attachToWindow:retainedByShell];
  }
  Check(weakAssociation == nil, "notification registration does not retain association");
  NSUInteger prior = observer.events.count;
  Post(NSWindowDidBecomeKeyNotification, retainedByShell);
  Check(observer.events.count == prior, "final release removes native notifications");
  [retainedByShell close];
}

- (void)testInvalidatingDuringDeliveryPreservesTheOtherAssociation {
  NSWindow* window = Window();
  AssociationObserver* first = [AssociationObserver new];
  AssociationObserver* second = [AssociationObserver new];
  first.invalidateOnEvent = YES;
  PCNativeWindowAssociation* a =
      [[PCNativeWindowAssociation alloc] initWithObserver:first];
  PCNativeWindowAssociation* b =
      [[PCNativeWindowAssociation alloc] initWithObserver:second];
  Check([a attachToWindow:window] && [b attachToWindow:window],
        "independent browser/profile associations can share shell window");
  Post(NSWindowDidBecomeKeyNotification, window);
  Check(a.invalidated && a.window == nil, "observer may invalidate during event delivery");
  Check(!b.invalidated && b.window == window,
        "one browser's invalidation preserves other association");
  Post(NSWindowDidResignKeyNotification, window);
  Check(first.events.count == 1 && second.events.count == 2,
        "invalidated observer is not called again");
  [window close];
  Check(second.closeSawDetachedAssociation && b.window == nil,
        "remaining association observes real close and clears before callback");
  [b invalidate];
}

- (void)testBackgroundDetachRaisesBeforeMutatingTheAssociation {
  __block BOOL rejected = NO;
  PCNativeWindowAssociation* target = association;
  NSWindow* window = Window();
  [target attachToWindow:window];
  void (^work)(void) = ^{
    @try {
      [target detach];
    } @catch (NSException* exception) {
      rejected = [exception.name isEqual:NSInternalInconsistencyException];
    }
  };
  pthread_t worker;
  int error = pthread_create(&worker, NULL, RunBlock, (__bridge void*)work);
  XCTAssertEqual(error, 0);
  if (error == 0) {
    XCTAssertEqual(pthread_join(worker, NULL), 0);
    XCTAssertTrue(rejected);
    XCTAssertEqual(target.window, window);
    XCTAssertFalse(target.invalidated);
  }
  [window close];
}

@end
