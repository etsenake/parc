#import "ParcNativeClock.h"

#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>
#import <dlfcn.h>
#import <objc/runtime.h>

@interface ParcScheduledTimer : NSObject
@property(nonatomic, strong) NSTimer* timer;
@property(nonatomic) NSTimeInterval due;
@property(nonatomic) NSTimeInterval interval;
@property(nonatomic) BOOL repeats;
@property(nonatomic) NSUInteger order;
@end
@implementation ParcScheduledTimer
@end

static NSTimeInterval clockOffset;
static NSMutableArray<ParcScheduledTimer*>* scheduledTimers;
static NSUInteger timerOrder;
static const void* bundleBase;
static const NSTimeInterval kNever = 1e9;
static const NSTimeInterval kTimerLatency = 1e-4;
static NSTimeInterval (*realUptime)(id, SEL);

NSTimeInterval ParcNativeNow(void) {
  return realUptime(NSProcessInfo.processInfo, @selector(systemUptime)) + clockOffset;
}

static BOOL CalledFromTestBundle(void* address) {
  Dl_info info;
  return dladdr(address, &info) && info.dli_fbase == bundleBase;
}

static NSTimer* Capture(NSTimer* timer, NSTimeInterval interval, BOOL repeats) {
  ParcScheduledTimer* entry = [ParcScheduledTimer new];
  entry.timer = timer;
  entry.interval = MAX(interval, 0.0001);
  entry.due = ParcNativeNow() + entry.interval;
  entry.repeats = repeats;
  entry.order = ++timerOrder;
  [scheduledTimers addObject:entry];
  return timer;
}

static void SwizzleClass(Class cls, SEL selector, id block, IMP* original) {
  Method method = class_getClassMethod(cls, selector);
  *original = method_setImplementation(method, imp_implementationWithBlock(block));
}

typedef NSTimer* (*BlockTimerIMP)(id, SEL, NSTimeInterval, BOOL, void (^)(NSTimer*));
typedef NSTimer* (*TargetTimerIMP)(id, SEL, NSTimeInterval, id, SEL, id, BOOL);
static IMP timerWithBlock, scheduledWithBlock, timerWithTarget, scheduledWithTarget;
static IMP runGroup;

static void InstallTimers(void) {
  SwizzleClass(NSTimer.class, @selector(timerWithTimeInterval:repeats:block:),
      ^NSTimer*(id cls, NSTimeInterval interval, BOOL repeats, void (^block)(NSTimer*)) {
        if (!CalledFromTestBundle(__builtin_return_address(0))) {
          return ((BlockTimerIMP)timerWithBlock)(cls, @selector(timerWithTimeInterval:repeats:block:), interval,
                                                 repeats, block);
        }
        NSTimer* timer = ((BlockTimerIMP)timerWithBlock)(cls, @selector(timerWithTimeInterval:repeats:block:),
                                                         kNever, repeats, block);
        return Capture(timer, interval, repeats);
      }, &timerWithBlock);
  SwizzleClass(NSTimer.class, @selector(scheduledTimerWithTimeInterval:repeats:block:),
      ^NSTimer*(id cls, NSTimeInterval interval, BOOL repeats, void (^block)(NSTimer*)) {
        if (!CalledFromTestBundle(__builtin_return_address(0))) {
          return ((BlockTimerIMP)scheduledWithBlock)(cls, @selector(scheduledTimerWithTimeInterval:repeats:block:),
                                                     interval, repeats, block);
        }
        NSTimer* timer = ((BlockTimerIMP)scheduledWithBlock)(
            cls, @selector(scheduledTimerWithTimeInterval:repeats:block:), kNever, repeats, block);
        return Capture(timer, interval, repeats);
      }, &scheduledWithBlock);
  SwizzleClass(NSTimer.class, @selector(timerWithTimeInterval:target:selector:userInfo:repeats:),
      ^NSTimer*(id cls, NSTimeInterval interval, id target, SEL action, id info, BOOL repeats) {
        SEL selector = @selector(timerWithTimeInterval:target:selector:userInfo:repeats:);
        if (!CalledFromTestBundle(__builtin_return_address(0))) {
          return ((TargetTimerIMP)timerWithTarget)(cls, selector, interval, target, action, info, repeats);
        }
        NSTimer* timer = ((TargetTimerIMP)timerWithTarget)(cls, selector, kNever, target, action, info, repeats);
        return Capture(timer, interval, repeats);
      }, &timerWithTarget);
  SwizzleClass(NSTimer.class, @selector(scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:),
      ^NSTimer*(id cls, NSTimeInterval interval, id target, SEL action, id info, BOOL repeats) {
        SEL selector = @selector(scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:);
        if (!CalledFromTestBundle(__builtin_return_address(0))) {
          return ((TargetTimerIMP)scheduledWithTarget)(cls, selector, interval, target, action, info, repeats);
        }
        NSTimer* timer =
            ((TargetTimerIMP)scheduledWithTarget)(cls, selector, kNever, target, action, info, repeats);
        return Capture(timer, interval, repeats);
      }, &scheduledWithTarget);
}

static void InstallClock(void) {
  Method uptime = class_getInstanceMethod([NSProcessInfo.processInfo class], @selector(systemUptime));
  realUptime = (NSTimeInterval(*)(id, SEL))method_getImplementation(uptime);
  method_setImplementation(uptime, imp_implementationWithBlock(^NSTimeInterval(id info) {
    NSTimeInterval real = realUptime(info, @selector(systemUptime));
    return CalledFromTestBundle(__builtin_return_address(0)) ? real + clockOffset : real;
  }));
}

static void InstallDates(void) {
  typedef NSDate* (*DateIMP)(id, SEL);
  typedef NSDate* (*DateSinceNowIMP)(id, SEL, NSTimeInterval);
  static IMP realDate, realSinceNow;
  SwizzleClass(NSDate.class, @selector(date), ^NSDate*(id cls) {
    NSDate* now = ((DateIMP)realDate)(cls, @selector(date));
    if (!CalledFromTestBundle(__builtin_return_address(0))) return now;
    return [now dateByAddingTimeInterval:clockOffset];
  }, &realDate);
  SwizzleClass(NSDate.class, @selector(dateWithTimeIntervalSinceNow:), ^NSDate*(id cls, NSTimeInterval seconds) {
    if (CalledFromTestBundle(__builtin_return_address(0))) seconds += clockOffset;
    return ((DateSinceNowIMP)realSinceNow)(cls, @selector(dateWithTimeIntervalSinceNow:), seconds);
  }, &realSinceNow);
  Method sinceNow = class_getInstanceMethod(NSDate.class, @selector(timeIntervalSinceNow));
  IMP realInterval = method_getImplementation(sinceNow);
  method_setImplementation(sinceNow, imp_implementationWithBlock(^NSTimeInterval(NSDate* date) {
    NSTimeInterval interval = ((NSTimeInterval(*)(id, SEL))realInterval)(date, @selector(timeIntervalSinceNow));
    return CalledFromTestBundle(__builtin_return_address(0)) ? interval - clockOffset : interval;
  }));
}

static void InstallAnimations(void) {
  typedef void (*RunGroupIMP)(id, SEL, void (^)(NSAnimationContext*), void (^)(void));
  SwizzleClass(NSAnimationContext.class, @selector(runAnimationGroup:completionHandler:),
      ^(id cls, void (^changes)(NSAnimationContext*), void (^completion)(void)) {
        if (!CalledFromTestBundle(__builtin_return_address(0))) {
          ((RunGroupIMP)runGroup)(cls, @selector(runAnimationGroup:completionHandler:), changes, completion);
          return;
        }
        ((RunGroupIMP)runGroup)(cls, @selector(runAnimationGroup:completionHandler:),
            ^(NSAnimationContext* context) {
              context.duration = 0;
              changes(context);
            },
            completion);
      }, &runGroup);
  Method setDuration = class_getInstanceMethod(NSAnimationContext.class, @selector(setDuration:));
  IMP realSetDuration = method_getImplementation(setDuration);
  method_setImplementation(setDuration, imp_implementationWithBlock(^(id context, NSTimeInterval duration) {
    if (CalledFromTestBundle(__builtin_return_address(0))) duration = 0;
    ((void (*)(id, SEL, NSTimeInterval))realSetDuration)(context, @selector(setDuration:), duration);
  }));
  for (NSString* name in @[ @"NSMoveHelper", @"NSSheetMoveHelper" ]) {
    Method duration = class_getInstanceMethod(NSClassFromString(name), NSSelectorFromString(@"animationDuration"));
    if (duration) method_setImplementation(duration, imp_implementationWithBlock(^double(id helper) {
      return 0;
    }));
  }
}

void ParcNativeSettle(void) {
  const CFAbsoluteTime limit = CFAbsoluteTimeGetCurrent() + 1;
  for (int idle = 0; idle < 2;) {
    if (CFAbsoluteTimeGetCurrent() > limit) {
      fprintf(stderr, "ParcNativeSettle: run loop never went idle\n");
      return;
    }
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
      drained = YES;
    });
    for (int turn = 0; !drained && turn < 100; ++turn) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
    BOOL handled = NO;
    NSEvent* event;
    while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                       untilDate:nil
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES])) {
      [NSApp sendEvent:event];
      handled = YES;
    }
    if (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true) == kCFRunLoopRunHandledSource) handled = YES;
    idle = handled ? 0 : idle + 1;
  }
}

static ParcScheduledTimer* NextDue(NSTimeInterval now) {
  ParcScheduledTimer* next = nil;
  for (ParcScheduledTimer* entry in [scheduledTimers copy]) {
    if (!entry.timer.valid) {
      [scheduledTimers removeObject:entry];
      continue;
    }
    if (entry.due <= now && (!next || entry.due < next.due || (entry.due == next.due && entry.order < next.order))) {
      next = entry;
    }
  }
  return next;
}

void ParcNativeAdvance(NSTimeInterval seconds) {
  ParcNativeSettle();
  const NSTimeInterval target = ParcNativeNow() + seconds;
  while (true) {
    ParcScheduledTimer* next = NextDue(target);
    if (!next) break;
    NSTimeInterval now = ParcNativeNow();
    if (next.due + kTimerLatency > now) clockOffset += next.due + kTimerLatency - now;
    if (next.repeats) {
      next.due += next.interval;
    } else {
      [scheduledTimers removeObject:next];
    }
    [next.timer fire];
    if (!next.repeats) [next.timer invalidate];
    ParcNativeSettle();
  }
  NSTimeInterval now = ParcNativeNow();
  if (target > now) clockOffset += target - now;
}

@interface ParcNativeClockObserver : NSObject <XCTestObservation>
@end
@implementation ParcNativeClockObserver
- (void)testCaseDidFinish:(XCTestCase*)testCase {
  for (ParcScheduledTimer* entry in scheduledTimers) [entry.timer invalidate];
  [scheduledTimers removeAllObjects];
}
@end

__attribute__((constructor)) static void InstallParcNativeClock(void) {
  Dl_info info;
  if (dladdr((const void*)&InstallParcNativeClock, &info)) bundleBase = info.dli_fbase;
  scheduledTimers = [NSMutableArray array];
  InstallClock();
  InstallDates();
  InstallTimers();
  InstallAnimations();
  [XCTestObservationCenter.sharedTestObservationCenter addTestObserver:[ParcNativeClockObserver new]];
}
