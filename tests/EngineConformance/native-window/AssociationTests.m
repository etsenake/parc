#import <AppKit/AppKit.h>
#import "browser_window.h"

#include <stdio.h>
#include <stdlib.h>

static unsigned assertions;
static unsigned groups;

static void Check(BOOL condition, const char* message) {
  ++assertions;
  if (!condition) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
  }
}

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
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  return window;
}

static void Post(NSNotificationName name, NSWindow* window) {
  [NSNotificationCenter.defaultCenter postNotificationName:name object:window];
}

static void TestAttachmentAndNotificationIdentity(void) {
  ++groups;
  NSWindow* first = Window();
  NSWindow* other = Window();
  AssociationObserver* observer = [AssociationObserver new];
  PCNativeWindowAssociation* association =
      [[PCNativeWindowAssociation alloc] initWithObserver:observer];
  Check(association.window == nil && !association.invalidated, "starts detached");
  Check([association attachToWindow:first], "attach supplied shell window");
  Check(association.window == first, "supplied window identity is preserved");
  Check(observer.events.count == 0, "attachment does not synthesize activation");
  Check([association attachToWindow:first], "same-window attachment is idempotent");
  Check(![association attachToWindow:other], "live association cannot silently move");
  Check(association.window == first, "rejected move preserves original window");
  Post(NSWindowDidBecomeKeyNotification, other);
  Check(observer.events.count == 0, "other window's notification is ignored");
  Post(NSWindowDidBecomeKeyNotification, first);
  Post(NSWindowDidResignKeyNotification, first);
  Post(NSWindowDidEnterFullScreenNotification, first);
  Post(NSWindowDidExitFullScreenNotification, first);
  Check([observer.events isEqual:@[
    @(PCNativeWindowEventDidBecomeKey), @(PCNativeWindowEventDidResignKey),
    @(PCNativeWindowEventDidEnterFullScreen), @(PCNativeWindowEventDidExitFullScreen)
  ]], "native notification names route to exact event values once");
  Check(observer.lastWindow == first, "event carries actual window");
  [association detach];
  Check(association.window == nil && !association.invalidated,
        "detach clears association without terminal invalidation");
  Post(NSWindowDidBecomeKeyNotification, first);
  Check(observer.events.count == 4, "detached notifications are removed");
  Check([association attachToWindow:other], "explicit detachment permits reassociation");
  Post(NSWindowDidBecomeKeyNotification, first);
  Check(observer.events.count == 4, "old window remains ignored after reassociation");
  Post(NSWindowDidBecomeKeyNotification, other);
  Check(observer.events.count == 5 && observer.lastWindow == other,
        "new association receives only new window events");
  [association invalidate];
  [first close];
  [other close];
}

static void TestActualCloseAndReentrantAttach(void) {
  ++groups;
  NSWindow* first = Window();
  NSWindow* next = Window();
  AssociationObserver* observer = [AssociationObserver new];
  observer.reattachAfterClose = next;
  PCNativeWindowAssociation* association =
      [[PCNativeWindowAssociation alloc] initWithObserver:observer];
  [association attachToWindow:first];
  [first close];
  Check(observer.events.count == 1 &&
        observer.events.lastObject.integerValue == PCNativeWindowEventWillClose,
        "actual NSWindow.close produces a single native close event");
  Check(observer.closeSawDetachedAssociation,
        "native close clears weak attachment before notifying owner");
  Check(observer.lastWindow == first, "closing window remains valid during callback");
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

static void TestInvalidationAndWeakOwnership(void) {
  ++groups;
  NSWindow* window = Window();
  __weak AssociationObserver* weakObserver;
  PCNativeWindowAssociation* association;
  @autoreleasepool {
    AssociationObserver* observer = [AssociationObserver new];
    weakObserver = observer;
    association = [[PCNativeWindowAssociation alloc] initWithObserver:observer];
    [association attachToWindow:window];
  }
  Check(weakObserver == nil, "association does not own its shell observer");
  Post(NSWindowDidBecomeKeyNotification, window);
  Check(association.window == window, "missing observer does not destroy association");
  [association invalidate];
  [association invalidate];
  Check(association.invalidated && association.window == nil,
        "invalidation is terminal and idempotent");
  Check(![association attachToWindow:window], "terminal association cannot reattach");
  [association detach];
  Check(association.invalidated, "detach cannot undo invalidation");
  [window close];

  AssociationObserver* observer = [AssociationObserver new];
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

static void TestReentryAndSharedShellWindow(void) {
  ++groups;
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

static void TestMainThreadBoundary(void) {
  ++groups;
  AssociationObserver* observer = [AssociationObserver new];
  PCNativeWindowAssociation* association =
      [[PCNativeWindowAssociation alloc] initWithObserver:observer];
  dispatch_semaphore_t finished = dispatch_semaphore_create(0);
  __block BOOL rejected = NO;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
    @try {
      [association detach];
    } @catch (NSException* exception) {
      rejected = [exception.name isEqual:NSInternalInconsistencyException];
    }
    dispatch_semaphore_signal(finished);
  });
  Check(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC)) == 0,
        "background contract check completes");
  Check(rejected, "off-main native access fails before mutation");
  Check(!association.invalidated && association.window == nil,
        "thread violation leaves lifecycle state intact");
  [association invalidate];
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestAttachmentAndNotificationIdentity();
    TestActualCloseAndReentrantAttach();
    TestInvalidationAndWeakOwnership();
    TestReentryAndSharedShellWindow();
    TestMainThreadBoundary();
    printf("Native window association: %u assertions across %u groups passed\n",
           assertions, groups);
  }
  return 0;
}
