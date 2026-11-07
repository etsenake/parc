// Proofs for the presentation side of Parc's native HLS route
// (Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md), run against real
// AVFoundation with Apple's public HLS examples. See README.md.
//
// The player is made and driven on a serial queue with no run loop, as the
// GPU process's media service thread is. Layer placement happens on the main
// thread, as CARendererLayerTree does it.

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <cstdarg>
#include <thread>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

// WebKit's source for an AVPlayer's frame counts (PAL AVFoundationSPI.h).
@interface AVPlayerLayer (ParcVideoPerformanceMetrics)
- (AVVideoPerformanceMetrics*)videoPerformanceMetrics API_AVAILABLE(macos(14.4));
@end

namespace {

constexpr const char* kBipBop =
    "https://devstreaming-cdn.apple.com/videos/streaming/examples/"
    "bipbop_16x9/bipbop_16x9_variant.m3u8";

int g_failures = 0;
int g_checks = 0;
std::string g_only;

bool Check(bool ok, const std::string& name, const std::string& detail = "") {
  ++g_checks;
  if (!ok) ++g_failures;
  std::printf("[%s] %s%s%s\n", ok ? "PASS" : "FAIL", name.c_str(),
              detail.empty() ? "" : " - ", detail.c_str());
  std::fflush(stdout);
  return ok;
}

void Note(const std::string& text) {
  std::printf("       %s\n", text.c_str());
  std::fflush(stdout);
}

void Sleep(double seconds) {
  [NSThread sleepForTimeInterval:seconds];
}

// Polls `ready` every 50 ms on the calling (non-main) thread.
bool WaitFor(double timeout, const std::function<bool()>& ready) {
  const double end = CACurrentMediaTime() + timeout;
  while (CACurrentMediaTime() < end) {
    if (ready()) return true;
    Sleep(0.05);
  }
  return ready();
}

void OnMain(dispatch_block_t block) {
  dispatch_sync(dispatch_get_main_queue(), block);
}

std::string Format(const char* format, ...) __attribute__((format(printf, 1, 2)));
std::string Format(const char* format, ...) {
  char buffer[512];
  va_list args;
  va_start(args, format);
  std::vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  return buffer;
}

// The media thread stand-in: a serial queue, no run loop.
dispatch_queue_t MediaQueue() {
  static dispatch_queue_t queue =
      dispatch_queue_create("parc.fairplay.hls.media", DISPATCH_QUEUE_SERIAL);
  return queue;
}

void OnMedia(dispatch_block_t block) {
  dispatch_sync(MediaQueue(), block);
}

// A window with a plain host layer, as a compositor's content layer host.
struct Host {
  NSWindow* window = nil;
  CALayer* host = nil;
};

Host MakeHost(NSRect frame, NSString* title) {
  __block Host result;
  OnMain(^{
    NSWindow* window =
        [[NSWindow alloc] initWithContentRect:frame
                                    styleMask:NSWindowStyleMaskTitled
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    window.releasedWhenClosed = NO;
    window.title = title;
    NSView* view = window.contentView;
    view.wantsLayer = YES;
    CALayer* host = [CALayer layer];
    host.anchorPoint = CGPointZero;
    host.frame = view.bounds;
    host.backgroundColor = NSColor.blackColor.CGColor;
    [view.layer addSublayer:host];
    [window orderFrontRegardless];
    result.window = window;
    result.host = host;
  });
  return result;
}

// What FillProtectedLayer does for an AVPlayerLayer (fairplay-compositing).
void Place(AVPlayerLayer* layer, CALayer* host) {
  OnMain(^{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (layer.superlayer != host) {
      [layer removeFromSuperlayer];
      [host addSublayer:layer];
    }
    layer.anchorPoint = CGPointZero;
    layer.position = CGPointZero;
    layer.bounds = host.bounds;
    layer.videoGravity = AVLayerVideoGravityResize;
    [CATransaction commit];
  });
}

void Detach(AVPlayerLayer* layer) {
  OnMain(^{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer removeFromSuperlayer];
    [CATransaction commit];
  });
}

struct Frames {
  bool available = false;
  long total = 0;
  long dropped = 0;
  long corrupted = 0;
};

// Read off the main thread, as WebKit reads it on a background work queue.
Frames ReadFrames(AVPlayerLayer* layer) {
  Frames frames;
  if (@available(macOS 14.4, *)) {
    if (![layer respondsToSelector:@selector(videoPerformanceMetrics)]) return frames;
    AVVideoPerformanceMetrics* metrics = [layer videoPerformanceMetrics];
    if (!metrics) return frames;
    frames.available = true;
    frames.total = metrics.totalNumberOfFrames;
    frames.dropped = metrics.numberOfDroppedFrames;
    frames.corrupted = metrics.numberOfCorruptedFrames;
  }
  return frames;
}

// The access log's variant changes, as indicated bitrate and video size.
std::string Variants(AVPlayerItem* item) {
  __block std::string text;
  OnMedia(^{
    for (AVPlayerItemAccessLogEvent* event in item.accessLog.events) {
      text += Format("%.0fk/%ld dropped ", event.indicatedBitrate / 1000,
                     (long)event.numberOfDroppedVideoFrames);
    }
    text += Format("now %.0fx%.0f", item.presentationSize.width, item.presentationSize.height);
  });
  return text;
}

struct Player {
  AVPlayer* player = nil;
  AVPlayerItem* item = nil;
  AVPlayerLayer* layer = nil;

  double Time() const {
    __block double t = NAN;
    AVPlayerItem* i = item;
    OnMedia(^{
      t = CMTimeGetSeconds(i.currentTime);
    });
    return t;
  }
};

Player MakePlayer(NSURL* url) {
  __block Player p;
  OnMedia(^{
    [CATransaction begin];
    p.item = [AVPlayerItem playerItemWithURL:url];
    p.player = [AVPlayer playerWithPlayerItem:p.item];
    p.player.automaticallyWaitsToMinimizeStalling = YES;
    p.layer = [AVPlayerLayer playerLayerWithPlayer:p.player];
    [CATransaction commit];
  });
  return p;
}

bool WaitReady(Player& p, double timeout) {
  AVPlayerItem* item = p.item;
  return WaitFor(timeout, [item] {
    __block AVPlayerItemStatus status = AVPlayerItemStatusUnknown;
    OnMedia(^{
      status = item.status;
    });
    return status == AVPlayerItemStatusReadyToPlay;
  });
}

bool ReadyForDisplay(AVPlayerLayer* layer) {
  __block BOOL ready = NO;
  OnMain(^{
    ready = layer.readyForDisplay;
  });
  return ready;
}

// ---------------------------------------------------------------------------
// Display: the AVPlayerLayer placed like the MSE route's layer, moved between
// hosts as Picture in Picture and tab moves do, and detached as a hidden tab's
// tree drops it.

void Display() {
  Host page = MakeHost(NSMakeRect(80, 380, 640, 360), @"page");
  Host pip = MakeHost(NSMakeRect(760, 380, 320, 180), @"pip");
  Player p = MakePlayer([NSURL URLWithString:@(kBipBop)]);
  Check(p.layer != nil, "display: AVPlayerLayer made on a queue with no run loop");
  Check(WaitReady(p, 20), "display: item ready to play");

  Place(p.layer, page.host);
  AVPlayer* player = p.player;
  OnMedia(^{
    player.rate = 1;
  });
  Check(WaitFor(15, [&] { return ReadyForDisplay(p.layer); }),
        "display: readyForDisplay in the page host");
  __block CGRect video_rect;
  __block CGRect bounds;
  OnMain(^{
    video_rect = p.layer.videoRect;
    bounds = p.layer.bounds;
  });
  Check(CGRectEqualToRect(video_rect, bounds), "display: Resize gravity fills the quad",
        Format("videoRect %.0fx%.0f, bounds %.0fx%.0f", video_rect.size.width,
               video_rect.size.height, bounds.size.width, bounds.size.height));

  // Frame counts come from the layer, read off the main thread.
  Frames f0 = ReadFrames(p.layer);
  Check(f0.available, "frames: -[AVPlayerLayer videoPerformanceMetrics] answers");
  const double t0 = p.Time();
  Sleep(3);
  Frames f1 = ReadFrames(p.layer);
  const double t1 = p.Time();
  Check(f1.total > f0.total, "frames: total advances while playing",
        Format("%ld -> %ld over %.2f s of media", f0.total, f1.total, t1 - t0));
  Note(Format("dropped %ld, corrupted %ld", f1.dropped, f1.corrupted));

  // Picture in Picture: the PiP window's tree takes the layer.
  Place(p.layer, pip.host);
  Sleep(0.5);
  Frames f2 = ReadFrames(p.layer);
  const double t2 = p.Time();
  Sleep(2.5);
  Frames f3 = ReadFrames(p.layer);
  const double t3 = p.Time();
  Check(ReadyForDisplay(p.layer), "pip: readyForDisplay after moving to the PiP host");
  Check(f3.total > f2.total, "pip: frames keep coming in the PiP host",
        Format("%ld -> %ld", f2.total, f3.total));
  Check(t3 - t2 > 2.0, "pip: the clock keeps running", Format("+%.2f s", t3 - t2));
  OnMain(^{
    video_rect = p.layer.videoRect;
    bounds = pip.host.bounds;
  });
  Check(CGRectEqualToRect(video_rect, bounds), "pip: fills the PiP host",
        Format("videoRect %.0fx%.0f", video_rect.size.width, video_rect.size.height));

  // Leaving PiP: back to the page.
  Place(p.layer, page.host);
  Sleep(0.5);
  Frames f4 = ReadFrames(p.layer);
  Sleep(2);
  Frames f5 = ReadFrames(p.layer);
  // A larger layer makes AVFoundation switch up a variant, and the new
  // decoder starts its count again: a count below the last one is a new run.
  Check(f5.total != f4.total && f5.total > 0, "pip: frames continue back in the page",
        Format("%ld -> %ld (%s)", f4.total, f5.total,
               f5.total < f4.total ? "counter restarted" : "same counter"));
  Note("variants: " + Variants(p.item));

  // Hidden tab: the layer is in no tree for a while.
  Detach(p.layer);
  const double t6 = p.Time();
  Frames f6 = ReadFrames(p.layer);
  Sleep(3);
  Frames f7 = ReadFrames(p.layer);
  const double t7 = p.Time();
  Check(t7 - t6 > 2.5, "hidden: the clock keeps running with the layer in no tree",
        Format("+%.2f s", t7 - t6));
  Note(Format("frames while detached: %ld -> %ld", f6.total, f7.total));
  Place(p.layer, page.host);
  Sleep(0.5);
  Frames f8 = ReadFrames(p.layer);
  Sleep(2);
  Frames f9 = ReadFrames(p.layer);
  Check(ReadyForDisplay(p.layer), "hidden: readyForDisplay again once placed");
  Check(f9.total > f8.total, "hidden: frames continue once placed again",
        Format("%ld -> %ld", f8.total, f9.total));

  // Teardown on the media thread, as the player's destructor does it.
  AVPlayerLayer* layer = p.layer;
  OnMedia(^{
    player.rate = 0;
    [CATransaction begin];
    layer.player = nil;
    [CATransaction commit];
  });
  Detach(layer);
  Check(layer.player == nil, "teardown: layer let go of its player off the main thread");
  OnMain(^{
    [page.window close];
    [pip.window close];
  });
}

struct Section {
  const char* name;
  void (*run)();
};

const Section kSections[] = {
    {"Display", Display},
};

}  // namespace

int main(int argc, char** argv) {
  @autoreleasepool {
    for (int i = 1; i + 1 < argc; i += 2) {
      if (std::string(argv[i]) == "--only") g_only = argv[i + 1];
    }
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    std::thread([] {
      int status = 0;
      @autoreleasepool {
        bool ran = false;
        for (const Section& section : kSections) {
          if (!g_only.empty() && g_only != section.name) continue;
          ran = true;
          std::printf("== %s\n", section.name);
          @autoreleasepool {
            section.run();
          }
        }
        if (!ran) Check(false, "--only names a section", g_only);
        std::printf("%d checks, %d failed\n", g_checks, g_failures);
        std::fflush(stdout);
        status = g_failures ? 1 : 0;
      }
      // Exit from the main thread, outside AppKit's work.
      dispatch_async(dispatch_get_main_queue(), ^{
        std::exit(status);
      });
    }).detach();
    [NSApp run];
  }
  return 0;
}
