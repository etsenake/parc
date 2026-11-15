// Adapted from Ardia's apps/browser/scripts/perf/acmark.m (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.

#import <AppKit/AppKit.h>

static FILE *gOut;

__attribute__((constructor)) static void Start(void) {
  const char *dir = getenv("PARC_BENCH_DIR");
  if (!dir || !getenv("PARC_BENCH_KEYLOG")) return;
  if (![NSBundle.mainBundle.bundlePath hasSuffix:@".app"] || [NSBundle.mainBundle.bundlePath containsString:@"Helper"]) return;
  gOut = fopen([NSString stringWithFormat:@"%s/bench-marks.jsonl", dir].UTF8String, "a");
  if (!gOut) return;
  [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    fprintf(gOut, "{\"keydown\":%.1f,\"made\":%.1f,\"window\":%ld,\"char\":%d}\n", now,
            now - (NSProcessInfo.processInfo.systemUptime - event.timestamp) * 1000, (long)event.windowNumber, event.characters.length ? (int)[event.characters characterAtIndex:0] : 0);
    fflush(gOut);
    return event;
  }];
}
