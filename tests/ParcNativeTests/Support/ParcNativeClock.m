#import "ParcNativeClock.h"

#import <AppKit/AppKit.h>

@interface ParcScheduledTimer : NSObject
@property(strong) NSTimer* timer;
@property NSTimeInterval interval;
@property NSTimeInterval due;
@property BOOL repeats;
@end
@implementation ParcScheduledTimer
@end

@implementation ParcNativeTestScheduler {
  NSTimeInterval _now;
  NSMutableArray<dispatch_block_t>* _pending;
  NSMutableArray<ParcScheduledTimer*>* _timers;
  NSMapTable<NSTimer*, ParcScheduledTimer*>* _unscheduled;
}

- (instancetype)init {
  if ((self = [super init])) {
    _pending = [NSMutableArray array];
    _timers = [NSMutableArray array];
    _unscheduled = [NSMapTable weakToStrongObjectsMapTable];
  }
  return self;
}

- (NSTimeInterval)now {
  return _now;
}

- (NSTimeInterval)systemUptime {
  return _now;
}

- (NSDate*)currentDate {
  return [NSDate dateWithTimeIntervalSinceReferenceDate:_now];
}

- (NSTimeInterval)timeIntervalSinceNowForDate:(NSDate*)date {
  return date ? date.timeIntervalSinceReferenceDate - _now : 0;
}

- (NSTimer*)timerWithTimeInterval:(NSTimeInterval)interval
                          repeats:(BOOL)repeats
                            block:(void (^)(NSTimer*))block {
  NSTimer* timer = [NSTimer timerWithTimeInterval:interval repeats:repeats block:block];
  ParcScheduledTimer* entry = [ParcScheduledTimer new];
  entry.interval = interval;
  entry.due = _now + interval;
  entry.repeats = repeats;
  [_unscheduled setObject:entry forKey:timer];
  return timer;
}

- (NSTimer*)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                   repeats:(BOOL)repeats
                                     block:(void (^)(NSTimer*))block {
  NSTimer* timer = [self timerWithTimeInterval:interval repeats:repeats block:block];
  [self addTimer:timer forMode:NSDefaultRunLoopMode];
  return timer;
}

- (void)addTimer:(NSTimer*)timer forMode:(NSRunLoopMode)mode {
  ParcScheduledTimer* entry = [_unscheduled objectForKey:timer];
  if (!entry) return;
  [_unscheduled removeObjectForKey:timer];
  entry.timer = timer;
  [_timers addObject:entry];
}

- (void)performInModes:(NSArray<NSRunLoopMode>*)modes block:(void (^)(void))block {
  [_pending addObject:[block copy]];
}

- (void)dispatchToMainQueue:(dispatch_block_t)block {
  [_pending addObject:[block copy]];
}

- (void)runAnimationGroup:(void (^)(NSAnimationContext*))changes
        completionHandler:(void (^)(void))completion {
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = 0;
    changes(context);
  } completionHandler:nil];
  if (completion) [_pending addObject:[completion copy]];
}

- (void)settle {
  while (_pending.count) {
    dispatch_block_t block = _pending.firstObject;
    [_pending removeObjectAtIndex:0];
    block();
  }
}

- (void)advance:(NSTimeInterval)seconds {
  [self settle];
  NSTimeInterval target = _now + seconds;
  for (;;) {
    ParcScheduledTimer* next = nil;
    for (ParcScheduledTimer* entry in _timers) {
      if (entry.timer.valid && entry.due <= target && (!next || entry.due < next.due)) next = entry;
    }
    if (!next) break;
    _now = next.due;
    if (next.repeats) {
      NSAssert(next.interval > 0, @"A repeating timer must advance the clock");
      next.due += next.interval;
    } else {
      [_timers removeObject:next];
    }
    [next.timer fire];
    [self settle];
  }
  _now = target;
}

- (void)invalidate {
  for (ParcScheduledTimer* entry in _timers) [entry.timer invalidate];
  [_timers removeAllObjects];
  [_pending removeAllObjects];
}

@end

void ParcNativeSettle(void) {
  [ParcNativeScheduler() settle];
}

void ParcNativeAdvance(NSTimeInterval seconds) {
  [ParcNativeScheduler() advance:seconds];
}

NSTimeInterval ParcNativeNow(void) {
  return ParcNativeScheduler().now;
}
