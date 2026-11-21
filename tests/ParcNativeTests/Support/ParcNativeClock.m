#import "ParcNativeClock.h"
#import "ParcNativeScheduling.h"

#undef dispatch_async
#undef timerWithTimeInterval
#undef runAnimationGroup

@interface ParcScheduledTimer : NSObject
@property(strong) NSTimer* timer;
@property NSTimeInterval interval;
@property NSTimeInterval due;
@property BOOL repeats;
@end
@implementation ParcScheduledTimer
@end

static NSTimeInterval now;
static NSMutableArray<dispatch_block_t>* pending;
static NSMutableArray<ParcScheduledTimer*>* timers;
static NSMapTable<NSTimer*, ParcScheduledTimer*>* unscheduled;

void ParcNativeResetClock(void) {
  for (ParcScheduledTimer* entry in timers) [entry.timer invalidate];
  now = 0;
  pending = [NSMutableArray array];
  timers = [NSMutableArray array];
  unscheduled = [NSMapTable weakToStrongObjectsMapTable];
}

NSTimeInterval ParcNativeNow(void) { return now; }

@implementation NSProcessInfo (ParcNativeClock)
- (NSTimeInterval)parcSystemUptime { return now; }
@end
@implementation NSDate (ParcNativeClock)
+ (NSDate*)parcDate { return [NSDate dateWithTimeIntervalSinceReferenceDate:now]; }
- (NSTimeInterval)parcTimeIntervalSinceNow { return self.timeIntervalSinceReferenceDate - now; }
@end
@implementation NSTimer (ParcNativeClock)
+ (NSTimer*)parcTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer*))block {
  NSTimer* timer = [NSTimer timerWithTimeInterval:interval repeats:repeats block:block];
  ParcScheduledTimer* entry = [ParcScheduledTimer new];
  entry.interval = interval;
  entry.due = now + interval;
  entry.repeats = repeats;
  [unscheduled setObject:entry forKey:timer];
  return timer;
}
+ (NSTimer*)parcScheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer*))block {
  NSTimer* timer = [self parcTimerWithTimeInterval:interval repeats:repeats block:block];
  [NSRunLoop.mainRunLoop parcAddTimer:timer forMode:NSDefaultRunLoopMode];
  return timer;
}
@end

void ParcNativeDispatch(dispatch_queue_t queue, dispatch_block_t block) {
  if (queue == dispatch_get_main_queue()) {
    [pending addObject:[block copy]];
  } else {
    dispatch_async(queue, block);
  }
}

@implementation NSRunLoop (ParcNativeClock)
- (void)parcAddTimer:(NSTimer*)timer forMode:(NSRunLoopMode)mode {
  ParcScheduledTimer* entry = [unscheduled objectForKey:timer];
  if (!entry) return;
  [unscheduled removeObjectForKey:timer];
  entry.timer = timer;
  [timers addObject:entry];
}
- (void)parcPerformInModes:(NSArray<NSRunLoopMode>*)modes block:(dispatch_block_t)block {
  [pending addObject:[block copy]];
}
@end

@implementation NSAnimationContext (ParcNativeClock)
+ (void)parcRunAnimationGroup:(void (^)(NSAnimationContext*))changes completionHandler:(dispatch_block_t)completion {
  [self runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = 0;
    changes(context);
  } completionHandler:nil];
  if (completion) [pending addObject:[completion copy]];
}
@end

void ParcNativeSettle(void) {
  while (pending.count) {
    dispatch_block_t block = pending.firstObject;
    [pending removeObjectAtIndex:0];
    block();
  }
}

void ParcNativeAdvance(NSTimeInterval seconds) {
  ParcNativeSettle();
  NSTimeInterval target = now + seconds;
  for (;;) {
    ParcScheduledTimer* next = nil;
    for (ParcScheduledTimer* entry in timers) {
      if (entry.timer.valid && entry.due <= target && (!next || entry.due < next.due)) next = entry;
    }
    if (!next) break;
    now = next.due;
    if (next.repeats) {
      NSCAssert(next.interval > 0, @"A repeating timer must advance the clock");
      next.due += next.interval;
    } else {
      [timers removeObject:next];
    }
    [next.timer fire];
    ParcNativeSettle();
  }
  now = target;
}
