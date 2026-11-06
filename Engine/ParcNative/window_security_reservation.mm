#import "window_security_reservation.h"

#import <objc/runtime.h>
NSNotificationName const PCNativeWindowSecurityStateChanged =
    @"PCNativeWindowSecurityStateChanged";
static char kStateKey;
@interface PCNativeWindowSecurityState : NSObject
@property(nonatomic, weak) NSWindow* window;
@property(nonatomic) BOOL closed;
@property(nonatomic, strong) NSHashTable* leases;
@property(nonatomic, strong) id closeObserver;
- (void)notify;
@end
@interface PCNativeWindowSecurityReservation ()
@property(nonatomic, strong) PCNativeWindowSecurityState* state;
@property(nonatomic) BOOL held;
@end
@implementation PCNativeWindowSecurityState
@synthesize window = _window, closed = _closed, leases = _leases,
            closeObserver = _closeObserver;
- (void)notify {
  NSWindow* window = self.window;
  if (window) {
    [NSNotificationCenter.defaultCenter
        postNotificationName:PCNativeWindowSecurityStateChanged
                      object:window];
  }
}
- (void)dealloc {
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
}
@end
static PCNativeWindowSecurityState* State(NSWindow* window, BOOL create) {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if (!window) {
    return nil;
  }
  PCNativeWindowSecurityState* state =
      objc_getAssociatedObject(window, &kStateKey);
  if (!state && create) {
    state = [PCNativeWindowSecurityState new];
    state.window = window;
    state.leases = [NSHashTable weakObjectsHashTable];
    objc_setAssociatedObject(window, &kStateKey, state,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak PCNativeWindowSecurityState* weak = state;
    state.closeObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window
                     queue:nil
                usingBlock:^(NSNotification*) {
                  PCNativeWindowSecurityState* current = weak;
                  if (!current || current.closed) {
                    return;
                  }
                  current.closed = YES;
                  NSArray* leases = current.leases.allObjects;
                  [current.leases removeAllObjects];
                  for (PCNativeWindowSecurityReservation* lease in leases) {
                    lease.held = NO;
                  }
                  [current notify];
                }];
  }
  return state;
}
BOOL PCNativeWindowHasSecurityReservation(NSWindow* window) {
  PCNativeWindowSecurityState* state = State(window, NO);
  return state && !state.closed && state.leases.count != 0;
}
@implementation PCNativeWindowSecurityReservation
@synthesize state = _state, held = _held;
+ (instancetype)acquireForWindow:(NSWindow*)window {
  PCNativeWindowSecurityState* state = State(window, YES);
  if (state.closed || !state.window) {
    return nil;
  }
  __attribute__((objc_precise_lifetime))
  PCNativeWindowSecurityReservation* lease = [self new];
  lease.state = state;
  lease.held = YES;
  [state.leases addObject:lease];
  [state notify];
  return lease;
}
- (NSWindow*)window {
  return _state.window;
}
- (BOOL)isActive {
  return _held && _state.window && !_state.closed;
}
- (BOOL)isOnlyReservation {
  return self.active && _state.leases.count == 1 &&
         [_state.leases containsObject:self];
}
- (void)invalidate {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if (!_held) {
    return;
  }
  _held = NO;
  PCNativeWindowSecurityState* state = _state;
  [state.leases removeObject:self];
  [state notify];
}
- (void)dealloc {
  [self invalidate];
}
@end
