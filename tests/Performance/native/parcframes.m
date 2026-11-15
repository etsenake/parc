// Adapted from Ardia's apps/browser/scripts/perf/acframes.m (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#include <stdatomic.h>
#include <time.h>

static FILE *gOut;
static NSString *gDir;

static double EpochMs(void) {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

typedef struct {
  char k, th;
  double a, b, c, d;
} Rec;
#define RING (1 << 17)
static Rec gRing[RING];
static _Atomic unsigned long gHead, gTail;

static void Push(char k, char th, double a, double b, double c, double d) {
  unsigned long h = atomic_fetch_add(&gHead, 1);
  if (h - atomic_load(&gTail) >= RING) return;
  gRing[h % RING] = (Rec){k, th, a, b, c, d};
}

static void Flush(void) {
  unsigned long h = atomic_load(&gHead), t = atomic_load(&gTail);
  for (; t < h; t++) {
    Rec r = gRing[t % RING];
    switch (r.k) {
      case 'f': fprintf(gOut, "{\"k\":\"f\",\"ts\":%.3f,\"now\":%.3f,\"tgt\":%.3f,\"mc\":%.3f}\n", r.a, r.b, r.c, r.d); break;
      case 'r': fprintf(gOut, "{\"k\":\"r\",\"th\":\"%c\",\"a\":%.3f,\"d\":%.3f}\n", r.th, r.a, r.b); break;
      case 'k': fprintf(gOut, "{\"k\":\"key\",\"made\":%.3f,\"seen\":%.3f}\n", r.a, r.b); break;
    }
  }
  atomic_store(&gTail, t);
  fflush(gOut);
}

static _Atomic long gTicks;

static mach_port_t gMainThread;
static double ThreadCpuMs(mach_port_t t) {
  if (!t) return -1;
  thread_basic_info_data_t i;
  mach_msg_type_number_t n = THREAD_BASIC_INFO_COUNT;
  if (thread_info(t, THREAD_BASIC_INFO, (thread_info_t)&i, &n) != KERN_SUCCESS) return -1;
  return (i.user_time.seconds + i.system_time.seconds) * 1e3 + (i.user_time.microseconds + i.system_time.microseconds) / 1e3;
}

typedef struct {
  char th;
  double start;
} LoopState;
static LoopState gMainLoop = {'m', 0};

static void LoopActivity(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
  LoopState *st = info;
  if (activity == kCFRunLoopAfterWaiting) {
    st->start = EpochMs();
  } else if (st->start > 0) {
    double end = EpochMs();
    if (end - st->start >= 0.05) Push('r', st->th, st->start, end - st->start, 0, 0);
    st->start = 0;
  }
}

static void ObserveLoop(CFRunLoopRef loop, LoopState *st) {
  CFRunLoopObserverContext ctx = {0, st, NULL, NULL, NULL};
  CFRunLoopObserverRef o = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopAfterWaiting | kCFRunLoopBeforeWaiting, true, 0x7FFFFFF0, LoopActivity, &ctx);
  CFRunLoopAddObserver(loop, o, kCFRunLoopCommonModes);
}

@interface PCFramesProbe : NSObject
+ (instancetype)shared;
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic, copy) NSString *screenName;
@property(nonatomic) NSInteger maxFPS;
- (BOOL)booted;
- (void)boot;
@end

@implementation PCFramesProbe {
  void (^_step)(double ts, BOOL *done);
  NSString *_driverId;
  NSString *_driverOp;
  NSString *_lastCmd;
  BOOL _booted;
}

+ (instancetype)shared {
  static PCFramesProbe *p;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ p = [PCFramesProbe new]; });
  return p;
}

- (void)answer:(NSString *)cid with:(NSDictionary *)body {
  NSMutableDictionary *d = [body mutableCopy];
  d[@"id"] = cid;
  NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
  NSString *tmp = [gDir stringByAppendingPathComponent:@"bench-frames-result.tmp"];
  [json writeToFile:tmp atomically:NO];
  rename(tmp.UTF8String, [gDir stringByAppendingPathComponent:@"bench-frames-result.json"].UTF8String);
}

- (NSWindow *)appWindow {
  for (NSWindow *w in NSApp.windows)
    if (w.isVisible && w.frame.size.width >= 300 && w.frame.size.height >= 200) return w;
  return nil;
}

- (BOOL)booted {
  return _booted;
}

- (void)boot {
  NSWindow *w = NSApp ? [self appWindow] : nil;
  if (!w) return;
  if (_booted) return;
  _booted = YES;
  [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
    double now = EpochMs();
    Push('k', 0, now - (NSProcessInfo.processInfo.systemUptime - event.timestamp) * 1000, now, 0, 0);
    return event;
  }];
  [self startOn:w];
}

- (void)startOn:(NSWindow *)w {
  NSScreen *screen = w.screen ?: NSScreen.screens.firstObject;
  self.screenName = screen.localizedName;
  self.maxFPS = screen.maximumFramesPerSecond;
  self.link = [screen displayLinkWithTarget:self selector:@selector(tick:)];
  self.link.preferredFrameRateRange = CAFrameRateRangeMake(self.maxFPS, self.maxFPS, self.maxFPS);
  [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  ObserveLoop(CFRunLoopGetMain(), &gMainLoop);
  fprintf(gOut, "{\"k\":\"info\",\"screen\":\"%s\",\"maxFPS\":%ld,\"at\":%.3f}\n", self.screenName.UTF8String, (long)self.maxFPS, EpochMs());
}

- (void)tick:(CADisplayLink *)l {
  double now = EpochMs();
  double off = now - CACurrentMediaTime() * 1000;
  double ts = l.timestamp * 1000 + off;
  if (gMainLoop.start > 0) {
    if (now - gMainLoop.start >= 0.05) Push('r', 'm', gMainLoop.start, now - gMainLoop.start, 0, 0);
    gMainLoop.start = now;
  }
  Push('f', 0, ts, now, l.targetTimestamp * 1000 + off, ThreadCpuMs(gMainThread));
  atomic_fetch_add(&gTicks, 1);
  if (_step) {
    BOOL done = NO;
    _step(ts, &done);
    if (done) {
      _step = nil;
      [self answer:_driverId with:@{@"ok": @YES, @"op": _driverOp}];
    }
  }
}

- (NSScrollView *)tallestScrollView {
  NSScrollView *best = nil;
  CGFloat bestHeight = 0;
  for (NSWindow *w in NSApp.windows) {
    if (!w.isVisible || w.contentView == nil) continue;
    NSMutableArray<NSView *> *todo = [NSMutableArray arrayWithObject:w.contentView];
    while (todo.count) {
      NSView *v = todo.lastObject;
      [todo removeLastObject];
      if ([v isKindOfClass:NSScrollView.class]) {
        NSScrollView *sv = (NSScrollView *)v;
        CGFloat h = sv.documentView.frame.size.height;
        if (h > sv.contentView.bounds.size.height * 1.5 && h > bestHeight) (best = sv), (bestHeight = h);
      }
      [todo addObjectsFromArray:v.subviews];
    }
  }
  return best;
}

- (void)setScrollY:(CGFloat)y of:(NSScrollView *)sv {
  NSClipView *clip = sv.contentView;
  CGFloat docH = sv.documentView.frame.size.height, viewH = clip.bounds.size.height;
  y = MAX(0, MIN(y, docH - viewH));
  CGFloat originY = sv.documentView.isFlipped ? y : docH - viewH - y;
  [clip scrollToPoint:NSMakePoint(clip.bounds.origin.x, originY)];
  [sv reflectScrolledClipView:clip];
}

- (void)runScroll:(NSDictionary *)cmd id:(NSString *)cid {
  NSScrollView *sv = [self tallestScrollView];
  if (!sv) return [self answer:cid with:@{@"ok": @NO, @"error": @"no tall scroll view"}];
  double distance = [cmd[@"distance"] doubleValue] ?: 3000, secs = [cmd[@"seconds"] doubleValue] ?: 1;
  BOOL back = [cmd[@"back"] boolValue];
  [self setScrollY:0 of:sv];
  __block double t0 = 0;
  _driverId = cid;
  _driverOp = @"scroll";
  __weak PCFramesProbe *weak = self;
  _step = ^(double ts, BOOL *done) {
    if (t0 == 0) t0 = ts;
    double t = (ts - t0) / 1000, total = back ? secs * 2 : secs;
    double phase = t < secs ? t / secs : (t - secs) / secs;
    double eased = 1 - pow(1 - MIN(phase, 1), 3);
    double y = t < secs ? distance * eased : distance * (1 - eased);
    [weak setScrollY:y of:sv];
    if (t >= total) *done = YES;
  };
}

- (void)handle:(NSDictionary *)cmd {
  NSString *cid = cmd[@"id"], *op = cmd[@"op"];
  if ([op isEqualToString:@"info"]) {
    return [self answer:cid with:@{@"ok": @YES, @"screen": self.screenName ?: @"", @"maxFPS": @(self.maxFPS), @"link": @(self.link != nil)}];
  } else if ([op isEqualToString:@"counters"]) {
    return [self answer:cid with:@{@"ok": @YES, @"ticks": @(gTicks)}];
  } else if ([op isEqualToString:@"scroll"]) {
    return [self runScroll:cmd id:cid];
  }
  [self answer:cid with:@{@"ok": @NO, @"error": @"unknown op"}];
}

@end

__attribute__((constructor)) static void Start(void) {
  const char *dir = getenv("PARC_BENCH_DIR");
  if (!dir || !getenv("PARC_BENCH_FRAMES")) return;
  if (![NSBundle.mainBundle.bundlePath hasSuffix:@".app"] || [NSBundle.mainBundle.bundlePath containsString:@"Helper"]) return;
  gMainThread = mach_thread_self();
  gDir = [NSString stringWithUTF8String:dir];
  gOut = fopen([gDir stringByAppendingPathComponent:@"bench-frames.jsonl"].UTF8String, "a");
  if (!gOut) return;
  static dispatch_queue_t q;
  static dispatch_source_t timer;
  q = dispatch_queue_create("parcframes.writer", DISPATCH_QUEUE_SERIAL);
  timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
  dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 5 * NSEC_PER_MSEC, 1 * NSEC_PER_MSEC);
  __block int n = 0;
  __block NSData *last = nil;
  NSString *cmdPath = [gDir stringByAppendingPathComponent:@"bench-frames-cmd.json"];
  dispatch_source_set_event_handler(timer, ^{
    if (++n % 10 == 0) Flush();
    NSData *data = [NSData dataWithContentsOfFile:cmdPath];
    if (data.length && ![data isEqualToData:last]) {
      NSDictionary *cmd = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if (cmd) {
        last = data;
        dispatch_async(dispatch_get_main_queue(), ^{ [PCFramesProbe.shared handle:cmd]; });
      }
    }
  });
  dispatch_resume(timer);
  CFRunLoopTimerRef boot = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.1, 0.1, 0, 0, ^(CFRunLoopTimerRef t) {
    [PCFramesProbe.shared boot];
    if ([PCFramesProbe.shared booted]) CFRunLoopTimerInvalidate(t);
  });
  CFRunLoopAddTimer(CFRunLoopGetMain(), boot, kCFRunLoopCommonModes);
}
