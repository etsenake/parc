#import "focus_manager.h"

#import "dialog_style.h"

#include <cmath>

static void* const PCFocusObservationContext =
    (void*)&PCFocusObservationContext;
static const NSTimeInterval PCFocusPendingInterval = 2.0;

static BOOL ChainContains(NSResponder* start, NSResponder* target) {
  if (!start || !target) {
    return NO;
  }
  NSHashTable<NSResponder*>* seen = [NSHashTable
      hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
  for (NSResponder* value = start; value; value = value.nextResponder) {
    if (value == target) {
      return YES;
    }
    if ([seen containsObject:value]) {
      return NO;
    }
    [seen addObject:value];
  }
  return NO;
}

static NSResponder* NormalizedResponder(NSResponder* responder) {
  if (![responder isKindOfClass:NSView.class]) {
    return responder;
  }
  NSView* view = (NSView*)responder;
  for (NSView* parent = view.superview; parent; parent = parent.superview) {
    if ([parent isKindOfClass:NSTextField.class]) {
      return parent;
    }
  }
  return responder;
}

@interface PCFocusEntry : NSObject
@property(nonatomic, copy) NSString* key;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, weak) NSResponder* responder;
@property(nonatomic, copy, nullable) void (^didBecome)(void);
@property(nonatomic, copy, nullable) void (^didResign)(void);
@end
@implementation PCFocusEntry
@synthesize key = _key;
@synthesize generation = _generation;
@synthesize responder = _responder;
@synthesize didBecome = _didBecome;
@synthesize didResign = _didResign;
@end

@interface PCNativeFocusManager () {
  __weak NSWindow* _window;
  NSMutableDictionary<NSString*, PCFocusEntry*>* _entries;
  NSTimeInterval (^_clock)(void);
  __weak NSResponder* _lastObserved;
  BOOL _hasObserved;
  BOOL _observing;
  BOOL _invalidated;
  BOOL _checkingFallback;
  NSUInteger _nextGeneration;
  // The original pending value retains its target until cleared. This is not
  // the registration ownership: unregister/invalidate/detachment releases it.
  NSResponder* _pendingResponder;
  NSString* _pendingKey;
  NSUInteger _pendingGeneration;
  NSTimeInterval _pendingTimestamp;
  id _closeObserver;
}
- (void)removeKey:(NSString*)key generation:(NSUInteger)generation;
- (void)clearPending;
- (BOOL)pendingIsFresh;
- (nullable PCFocusEntry*)entryForResponder:(nullable NSResponder*)responder;
- (BOOL)isCurrentEntry:(PCFocusEntry*)entry;
@end

@interface PCNativeFocusRegistration () {
  __weak PCNativeFocusManager* _manager;
  id<PCNativeScheduling> _scheduler;
  NSString* _key;
  NSUInteger _generation;
}
- (instancetype)initWithManager:(PCNativeFocusManager*)manager
                            key:(NSString*)key
                     generation:(NSUInteger)generation;
@end

@implementation PCNativeFocusRegistration
- (instancetype)initWithManager:(PCNativeFocusManager*)manager
                            key:(NSString*)key
                     generation:(NSUInteger)generation {
  self = [super init];
  if (self) {
    _manager = manager;
    _scheduler = manager.scheduler;
    _key = [key copy];
    _generation = generation;
  }
  return self;
}
- (void)invalidate {
  PCNativeFocusManager* manager = _manager;
  NSString* key = _key;
  NSUInteger generation = _generation;
  _manager = nil;
  _key = nil;
  if (!manager || !key) {
    return;
  }
  if (NSThread.isMainThread) {
    [manager removeKey:key generation:generation];
  } else {
    __weak PCNativeFocusManager* weakManager = manager;
    [_scheduler dispatchToMainQueue:^{
      [weakManager removeKey:key generation:generation];
    }];
  }
}
- (void)dealloc {
  [self invalidate];
}
@end

@implementation PCNativeFocusManager
@synthesize fallbackKey = _fallbackKey;
@synthesize scheduler = _scheduler;
- (instancetype)initWithWindow:(NSWindow*)window {
  __block __weak PCNativeFocusManager* manager = nil;
  self = [self initWithWindow:window
                        clock:^{
                          id<PCNativeScheduling> scheduler =
                              manager ? manager.scheduler
                                      : PCNativeSystemScheduling.sharedScheduling;
                          return scheduler.currentDate.timeIntervalSince1970;
                        }];
  manager = self;
  return self;
}
- (instancetype)initWithWindow:(NSWindow*)window
                         clock:(NSTimeInterval (^)(void))clock {
  NSAssert(NSThread.isMainThread, @"Native focus requires the main thread");
  NSParameterAssert(window);
  NSParameterAssert(clock);
  self = [super init];
  if (self) {
    _window = window;
    _clock = [clock copy];
    _scheduler = PCNativeSystemScheduling.sharedScheduling;
    _entries = [NSMutableDictionary dictionary];
    _observing = YES;
    [window addObserver:self
             forKeyPath:@"firstResponder"
                options:NSKeyValueObservingOptionInitial |
                        NSKeyValueObservingOptionNew
                context:PCFocusObservationContext];
    __weak PCNativeFocusManager* weakSelf = self;
    _closeObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window
                     queue:nil
                usingBlock:^(NSNotification* notification) {
                  (void)notification;
                  [weakSelf invalidate];
                }];
  }
  return self;
}
- (NSWindow*)window {
  return _window;
}
- (BOOL)isInvalidated {
  return _invalidated;
}
- (NSString*)focusedKey {
  NSAssert(NSThread.isMainThread, @"Native focus requires the main thread");
  if (_invalidated || !_window) {
    return nil;
  }
  NSResponder* actual = NormalizedResponder(_window.firstResponder);
  if (!ChainContains(actual, _window)) {
    return nil;
  }
  return [self entryForResponder:actual].key;
}
- (PCNativeFocusRegistration*)registerResponder:(NSResponder*)responder
                                         forKey:(NSString*)key
                                      didBecome:(void (^)(void))didBecome
                                      didResign:(void (^)(void))didResign {
  NSAssert(NSThread.isMainThread, @"Native focus requires the main thread");
  if (_invalidated || !_window || !responder || !key.length) {
    return nil;
  }
  // Registration may precede attachment. Requests validate the actual chain.
  PCFocusEntry* entry = [PCFocusEntry new];
  entry.key = key;
  entry.generation = ++_nextGeneration;
  entry.responder = responder;
  entry.didBecome = didBecome;
  entry.didResign = didResign;
  if ([_pendingKey isEqualToString:key]) {
    [self clearPending];
  }
  _entries[key] = entry;
  return [[PCNativeFocusRegistration alloc] initWithManager:self
                                                        key:key
                                                 generation:entry.generation];
}
- (BOOL)isCurrentEntry:(PCFocusEntry*)entry {
  return entry && !_invalidated && _entries[entry.key] == entry &&
         entry.responder != nil;
}
- (PCFocusEntry*)entryForResponder:(NSResponder*)responder {
  if (!responder) {
    return nil;
  }
  // The original callback lookup compares the normalized actual responder,
  // not all its ancestor registrations. An ancestor may preserve a request
  // without receiving a falsely claimed focus-completion callback.
  for (PCFocusEntry* entry in _entries.allValues) {
    if (entry.responder == responder) {
      return entry;
    }
  }
  return nil;
}
- (void)removeKey:(NSString*)key generation:(NSUInteger)generation {
  NSAssert(NSThread.isMainThread, @"Native focus requires the main thread");
  PCFocusEntry* entry = _entries[key];
  if (!entry || entry.generation != generation) {
    return;
  }
  [_entries removeObjectForKey:key];
  if ([_pendingKey isEqualToString:key] && _pendingGeneration == generation) {
    [self clearPending];
  }
}
- (void)clearPending {
  _pendingResponder = nil;
  _pendingKey = nil;
  _pendingGeneration = 0;
  _pendingTimestamp = 0;
}
- (BOOL)pendingIsFresh {
  if (!_pendingResponder) {
    return NO;
  }
  if (!_window || !ChainContains(_pendingResponder, _window) ||
      _entries[_pendingKey].generation != _pendingGeneration) {
    [self clearPending];
    return NO;
  }
  NSTimeInterval age = _clock() - _pendingTimestamp;
  return std::isfinite(age) && age < PCFocusPendingInterval;
}
- (PCNativeFocusRequestResult)requestFocusForKey:(NSString*)key {
  // Native responder methods and shell callbacks may release their owner.
  // Keep this delivery alive through the entire method, not just its last use.
  __attribute__((objc_precise_lifetime)) PCNativeFocusManager* delivery = self;
  (void)delivery;
  NSAssert(NSThread.isMainThread, @"Native focus requires the main thread");
  if (_invalidated || !key.length) {
    return PCNativeFocusRequestRejected;
  }
  NSWindow* window = _window;
  PCFocusEntry* entry = _entries[key];
  NSResponder* target = entry.responder;
  if (!window || !target || !ChainContains(target, window)) {
    [self pendingIsFresh];
    return PCNativeFocusRequestRejected;
  }
  NSResponder* actual = window.firstResponder;
  if (NormalizedResponder(actual) == target || ChainContains(actual, target)) {
    return PCNativeFocusRequestAlreadyFocused;
  }
  if ([self pendingIsFresh] && _pendingResponder == target) {
    return PCNativeFocusRequestPending;
  }
  if (!target.acceptsFirstResponder || ![self isCurrentEntry:entry] ||
      !ChainContains(target, window)) {
    return PCNativeFocusRequestRejected;
  }
  NSTimeInterval now = _clock();
  if (!std::isfinite(now)) {
    return PCNativeFocusRequestRejected;
  }
  _pendingResponder = target;
  _pendingKey = [key copy];
  _pendingGeneration = entry.generation;
  _pendingTimestamp = now;
  BOOL accepted = [window makeFirstResponder:target];
  // Do not overwrite pending state here: synchronous KVO/callbacks may have
  // observed success, invalidated the manager or issued a newer request.
  [self reconcileFirstResponder];
  return accepted ? PCNativeFocusRequestAccepted : PCNativeFocusRequestRejected;
}
- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id>*)change
                       context:(void*)context {
  if (context != PCFocusObservationContext) {
    [super observeValueForKeyPath:keyPath
                         ofObject:object
                           change:change
                          context:context];
    return;
  }
  if (!_invalidated && object == _window) {
    [self reconcileFirstResponder];
  }
}
- (void)reconcileFirstResponder {
  __attribute__((objc_precise_lifetime)) PCNativeFocusManager* delivery = self;
  (void)delivery;
  NSAssert(NSThread.isMainThread, @"Native focus requires the main thread");
  if (_invalidated) {
    return;
  }
  NSWindow* window = _window;
  if (!window) {
    [self invalidate];
    return;
  }
  NSResponder* current = NormalizedResponder(window.firstResponder);
  NSResponder* previous = _lastObserved;
  BOOL changed = !_hasObserved || current != previous;
  if (changed) {
    _hasObserved = YES;
    _lastObserved = current;
    if ([self pendingIsFresh] && current == _pendingResponder) {
      [self clearPending];
    }
    PCFocusEntry* oldEntry = [self entryForResponder:previous];
    PCFocusEntry* newEntry = [self entryForResponder:current];
    if ([self isCurrentEntry:oldEntry] && oldEntry.didResign) {
      oldEntry.didResign();
    }
    // Re-check after arbitrary native shell callbacks; never announce an
    // intermediate target that a resign callback already replaced or closed.
    if (_invalidated || NormalizedResponder(window.firstResponder) != current) {
      return;
    }
    if ([self isCurrentEntry:newEntry] && newEntry.didBecome) {
      newEntry.didBecome();
    }
  }
  if (!_invalidated && !current && !window.firstResponder &&
      !_checkingFallback && ![self pendingIsFresh] && _fallbackKey.length) {
    _checkingFallback = YES;
    [self requestFocusForKey:_fallbackKey];
    _checkingFallback = NO;
  }
}
- (void)invalidate {
  NSAssert(NSThread.isMainThread, @"Native focus requires the main thread");
  if (_invalidated) {
    return;
  }
  _invalidated = YES;
  if (_observing) {
    [_window removeObserver:self
                 forKeyPath:@"firstResponder"
                    context:PCFocusObservationContext];
    _observing = NO;
  }
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
    _closeObserver = nil;
  }
  [self clearPending];
  [_entries removeAllObjects];
  _lastObserved = nil;
  _fallbackKey = nil;
  _window = nil;
}
- (void)dealloc {
  // The manager's API/lifetime belongs to the main-thread window owner.
  if (_observing) {
    [_window removeObserver:self
                 forKeyPath:@"firstResponder"
                    context:PCFocusObservationContext];
  }
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
}
@end
