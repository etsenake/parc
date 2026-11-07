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

#import "fairplay_hls_frame_stats.h"
#import "fairplay_hls_player_layer.h"

#include <cstdarg>
#include <thread>
#include <atomic>
#include <memory>
#include <mutex>
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

// WebKit's source for an AVPlayer's frame counts (PAL AVFoundationSPI.h).
@interface AVPlayerLayer (ParcVideoPerformanceMetrics)
- (AVVideoPerformanceMetrics*)videoPerformanceMetrics API_AVAILABLE(macos(14.4));
@end

// The GPU process's layer trees live in CAContexts that the browser shows
// through CALayerHosts (ui/base/cocoa/remote_layer_api.h).
typedef uint32_t ParcCGSConnectionID;
extern "C" ParcCGSConnectionID CGSMainConnectionID(void);
@interface CAContext : NSObject
+ (instancetype)contextWithCGSConnection:(uint32_t)connection options:(NSDictionary*)options;
@property(readonly) uint32_t contextId;
@property(retain) CALayer* layer;
@end
@interface CALayerHost : CALayer
@property uint32_t contextId;
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

// What FillProtectedLayer does for an AVPlayerLayer (fairplay-compositing):
// the tree's scale factor (its window's display) as the contents scale, as
// WebKit gives its AVPlayerLayer the page's (mediaPlayerContentsScale), then
// the host's bounds, which hand the core's layer its player.
void Place(AVPlayerLayer* layer, CALayer* host, NSWindow* window) {
  OnMain(^{
    const CGFloat scale = window.backingScaleFactor;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (layer.contentsScale != scale) {
      layer.contentsScale = scale;
    }
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
  PCHlsPlayerLayer* layer = nil;

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
    p.player.muted = YES;  // Video only matters here; no sound out loud.
    // The core's layer (fairplay_hls_player_layer.h): the player arrives
    // once Place sizes it.
    p.layer = [PCHlsPlayerLayer layer];
    [CATransaction commit];
    [p.layer parcAttachPlayerWhenSized:p.player];
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

  Place(p.layer, page.host, page.window);
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
  Place(p.layer, pip.host, pip.window);
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
  Place(p.layer, page.host, page.window);
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
  Place(p.layer, page.host, page.window);
  Sleep(0.5);
  Frames f8 = ReadFrames(p.layer);
  Sleep(2);
  Frames f9 = ReadFrames(p.layer);
  Check(ReadyForDisplay(p.layer), "hidden: readyForDisplay again once placed");
  Check(f9.total > f8.total, "hidden: frames continue once placed again",
        Format("%ld -> %ld", f8.total, f9.total));

  // Teardown on the media thread, as the player's destructor does it.
  PCHlsPlayerLayer* layer = p.layer;
  OnMedia(^{
    player.rate = 0;
    [layer parcDetachPlayer];
  });
  Detach(layer);
  Check(layer.player == nil, "teardown: layer let go of its player off the main thread");
  OnMain(^{
    [page.window close];
    [pip.window close];
  });
}


// ---------------------------------------------------------------------------
// Frame statistics: fairplay_hls_frame_stats turns the layer's counts into
// the deltas PipelineImpl adds up, polling while playing.

namespace fp = parc::fairplay;

void Accumulator() {
  fp::FrameCountAccumulator acc;
  fp::FrameCountDelta d = acc.Advance({12, 1});
  Check(d.decoded == 12 && d.dropped == 1, "accumulator: the first reading counts in full");
  d = acc.Advance({40, 1});
  Check(d.decoded == 28 && d.dropped == 0, "accumulator: later readings add what moved");
  d = acc.Advance({40, 1});
  Check(d.empty(), "accumulator: an unchanged reading adds nothing");
  d = acc.Advance({7, 0});
  Check(d.decoded == 7 && d.dropped == 0,
        "accumulator: a smaller total is a restarted decoder and counts in full",
        Format("+%u decoded, +%u dropped", d.decoded, d.dropped));
  d = acc.Advance({9, 2});
  Check(d.decoded == 2 && d.dropped == 2, "accumulator: the new run then adds what moved");
  acc.Advance({1000, 5});
  d = acc.Advance({300, 8});
  Check(d.decoded == 300 && d.dropped == 8,
        "accumulator: a restart counts both readings in full, even a dropped count that grew",
        Format("+%u decoded, +%u dropped", d.decoded, d.dropped));
  d = acc.Advance({300, 3});
  Check(d.decoded == 300 && d.dropped == 3, "accumulator: a dropped count going back is a restart too");
  d = acc.Advance({-5, -1});
  Check(d.empty(), "accumulator: negative readings add nothing");
}

// Reports land on the media queue, as on the player's sequence.
struct Reports {
  std::mutex lock;
  int64_t decoded = 0;
  int64_t dropped = 0;
  int count = 0;
  std::pair<int64_t, int> Get() {
    std::lock_guard<std::mutex> hold(lock);
    return {decoded, count};
  }
};

void FrameStats() {
  Host page = MakeHost(NSMakeRect(80, 380, 640, 360), @"page");
  Player p = MakePlayer([NSURL URLWithString:@(kBipBop)]);
  Check(WaitReady(p, 20), "frame stats: item ready to play");
  Place(p.layer, page.host, page.window);

  auto reports = std::make_shared<Reports>();
  __block std::unique_ptr<fp::HlsFrameStats> stats;
  PCHlsPlayerLayer* layer = p.layer;
  AVPlayer* player = p.player;
  OnMedia(^{
    fp::PostTask post = [](std::function<void()> task) {
      dispatch_async(MediaQueue(), ^{
        task();
      });
    };
    stats = std::make_unique<fp::HlsFrameStats>(layer, post, [reports](const fp::FrameCountDelta& d) {
      std::lock_guard<std::mutex> hold(reports->lock);
      reports->decoded += d.decoded;
      reports->dropped += d.dropped;
      ++reports->count;
    });
    player.rate = 1;
    stats->SetPlaying(true);
  });
  Check(WaitFor(15, [&] { return reports->Get().first > 0; }), "frame stats: the first report arrives");
  const auto [d0, n0] = reports->Get();
  const double t0 = p.Time();
  Sleep(3);
  const auto [d1, n1] = reports->Get();
  const double t1 = p.Time();
  const fp::DecoderFrameCounts raw = fp::ReadDecoderFrameCounts(layer).value_or(fp::DecoderFrameCounts{});
  Check(d1 - d0 > 30, "frame stats: decoded frames advance with playback",
        Format("+%lld over %.2f s of media in %d reports", d1 - d0, t1 - t0, n1 - n0));
  Check(n1 - n0 >= 8 && n1 - n0 <= 14, "frame stats: about four reports a second while playing",
        Format("%d reports in 3 s", n1 - n0));
  Note(Format("summed %lld, layer total now %lld (equal unless the decoder restarted)", d1,
              raw.total));

  // Pause: one last count, then nothing. That count is the only reading after
  // the clock stops, so the sum reaching the layer's total (more if the
  // decoder restarted during the run) proves it.
  OnMedia(^{
    player.rate = 0;
    stats->SetPlaying(false);
  });
  Sleep(0.5);
  const auto [d2, n2] = reports->Get();
  const int64_t paused_total = fp::ReadDecoderFrameCounts(layer).value_or(fp::DecoderFrameCounts{}).total;
  Check(d2 >= paused_total, "frame stats: stopping counts once more, up to the layer's total",
        Format("summed %lld, layer %lld", d2, paused_total));
  Sleep(2);
  const auto [d3, n3] = reports->Get();
  Check(d3 == d2 && n3 == n2, "frame stats: paused, no reports and the count stands",
        Format("%lld -> %lld", d2, d3));

  // Resume.
  OnMedia(^{
    player.rate = 1;
    stats->SetPlaying(true);
  });
  Sleep(2.5);
  const auto [d4, n4] = reports->Get();
  Check(d4 > d3, "frame stats: counts resume with playback", Format("+%lld", d4 - d3));

  // Destroyed while polling: nothing reported afterwards.
  OnMedia(^{
    stats.reset();
  });
  const auto [d5, n5] = reports->Get();
  Sleep(1.5);
  const auto [d6, n6] = reports->Get();
  Check(n6 == n5, "frame stats: no report after destruction", Format("%d -> %d", n5, n6));
  (void)d5;
  (void)d6;
  (void)n4;

  OnMedia(^{
    player.rate = 0;
    [layer parcDetachPlayer];
  });
  Detach(layer);
  const std::optional<fp::DecoderFrameCounts> orphan = fp::ReadDecoderFrameCounts(layer);
  Check(!orphan || orphan->total > 0, "frame stats: a layer without its player reads safely",
        orphan ? Format("%lld frames", orphan->total) : "no reading");
  Check(!fp::ReadDecoderFrameCounts([AVPlayerLayer playerLayerWithPlayer:nil]),
        "frame stats: a layer that never played gives no reading");
  OnMain(^{
    [page.window close];
  });
}


// ---------------------------------------------------------------------------
// Picture in Picture and fullscreen across CAContexts: the page's compositor
// and Parc's PiP window each draw into their own CAContext in the GPU
// process, shown in the browser through a CALayerHost. The layer moves
// between the two contexts' trees; fullscreen is a resize of the page's.

struct RemoteHost {
  NSWindow* window = nil;
  CAContext* context = nil;
  CALayer* root = nil;
  CALayerHost* layer_host = nil;
  CALayer* host = nil;  // The content layer's host inside the context.
};

RemoteHost MakeRemoteHost(NSRect frame, NSString* title) {
  __block RemoteHost r;
  OnMain(^{
    r.window = [[NSWindow alloc] initWithContentRect:frame
                                           styleMask:NSWindowStyleMaskTitled
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
    r.window.releasedWhenClosed = NO;
    r.window.title = title;
    r.window.contentView.wantsLayer = YES;
    // Kept on screen from the top-left corner of the visible frame.
    const NSRect visible = NSScreen.mainScreen.visibleFrame;
    [r.window setFrameTopLeftPoint:NSMakePoint(NSMinX(visible) + frame.origin.x,
                                               NSMaxY(visible) - frame.origin.y)];
    // As CALayerTreeCoordinator makes its context and root layer.
    r.root = [CALayer layer];
    r.root.geometryFlipped = YES;
    r.root.opaque = YES;
    r.root.anchorPoint = CGPointZero;
    r.root.bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
    r.context = [CAContext contextWithCGSConnection:CGSMainConnectionID() options:@{}];
    r.context.layer = r.root;
    r.host = [CALayer layer];
    r.host.anchorPoint = CGPointZero;
    r.host.frame = r.root.bounds;
    [r.root addSublayer:r.host];
    r.layer_host = [CALayerHost layer];
    r.layer_host.contextId = r.context.contextId;
    r.layer_host.anchorPoint = CGPointZero;
    r.layer_host.frame = r.window.contentView.bounds;
    [r.window.contentView.layer addSublayer:r.layer_host];
    [r.window orderFrontRegardless];
  });
  return r;
}

void Resize(RemoteHost& r, CGSize size) {
  RemoteHost* rp = &r;
  OnMain(^{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // Grows down and right from the window's top-left corner, so it stays on
    // screen.
    const NSPoint top_left = NSMakePoint(NSMinX(rp->window.frame), NSMaxY(rp->window.frame));
    [rp->window setContentSize:NSMakeSize(size.width, size.height)];
    [rp->window setFrameTopLeftPoint:top_left];
    rp->root.bounds = CGRectMake(0, 0, size.width, size.height);
    rp->host.frame = rp->root.bounds;
    rp->layer_host.frame = rp->window.contentView.bounds;
    [CATransaction commit];
  });
}

double VideoHeight(AVPlayerItem* item) {
  __block double height = 0;
  OnMedia(^{
    height = item.presentationSize.height;
  });
  return height;
}

void RemotePiP() {
  // Offsets from the visible frame's top-left corner. The PiP window comes
  // later, beside the page once it is back to its inline size.
  RemoteHost page = MakeRemoteHost(NSMakeRect(20, 20, 640, 360), @"page (CAContext)");
  __block CGFloat scale = 0;
  OnMain(^{
    scale = page.window.backingScaleFactor;
  });
  Check(scale == 2, "remote: the page is on a 2x display", Format("%.1fx", scale));
  // FairPlayHlsPlayer::Start with the element's size from the render process
  // (SetVideoLayerSize), as WebKit's order: the player, then its layer staged
  // at that size in a CAContext of its own, which hands it the player, then
  // the item, all in one turn of the media thread.
  Player p;
  Player* pp = &p;
  const CGFloat element_scale = scale;
  __block bool player_before_item = false;
  OnMedia(^{
    pp->player = [[AVPlayer alloc] init];
    pp->player.automaticallyWaitsToMinimizeStalling = YES;
    pp->player.muted = YES;
    [CATransaction begin];
    pp->layer = [PCHlsPlayerLayer layer];
    [CATransaction commit];
    [pp->layer parcAttachPlayerWhenSized:pp->player];
    [pp->layer parcStageWithSize:CGSizeMake(640, 360) scale:element_scale];
    player_before_item = pp->layer.player == pp->player;
    pp->item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:@(kBipBop)]];
    [pp->player replaceCurrentItemWithPlayerItem:pp->item];
  });
  Check(player_before_item, "remote: the staged layer has the player before the item");
  Check(WaitReady(p, 20), "remote: item ready to play");
  Place(p.layer, page.host, page.window);
  AVPlayer* player = p.player;
  __block CGFloat placed_scale = 0;
  OnMain(^{
    placed_scale = p.layer.contentsScale;
  });
  Check(p.layer.player == player && placed_scale == scale,
        "remote: the page's tree takes it with the display's scale and its player",
        Format("contentsScale %.1f", placed_scale));
  OnMedia(^{
    player.rate = 1;
  });
  Check(WaitFor(15, [&] { return ReadyForDisplay(p.layer); }),
        "remote: readyForDisplay in the page compositor's context");
  // AVFoundation picks variants by the layer's size on screen, which it finds
  // inside a context with no window too, as in Safari: 720p, and still not
  // 1080p 8 s later (a larger layer gets 1080p within a second, below), even
  // after the earlier sections left it a bandwidth estimate for 1080p.
  const bool reached_720 = WaitFor(15, [&] { return VideoHeight(p.item) >= 720; });
  const bool stayed_below_1080 = !WaitFor(8, [&] { return VideoHeight(p.item) >= 1080; });
  Note("variants: " + Variants(p.item));
  Check(reached_720 && stayed_below_1080,
        "remote: the variant follows the 640x360 pt layer on a 2x display (720p, not 1080p)",
        Format("%.0fp", VideoHeight(p.item)));

  // Fullscreen is a resize of the page's context: 1280x720 pt.
  Resize(page, CGSizeMake(1280, 720));
  Place(p.layer, page.host, page.window);
  __block CGRect video_rect;
  OnMain(^{
    video_rect = p.layer.videoRect;
  });
  Check(CGRectEqualToRect(video_rect, CGRectMake(0, 0, 1280, 720)),
        "fullscreen: the layer fills the resized host",
        Format("videoRect %.0fx%.0f", video_rect.size.width, video_rect.size.height));
  Check(WaitFor(15, [&] { return VideoHeight(p.item) >= 1080; }),
        "fullscreen: AVFoundation switches up to the largest variant for the larger layer",
        Format("%.0fp", VideoHeight(p.item)));
  Frames f0 = ReadFrames(p.layer);
  Sleep(2);
  Frames f1 = ReadFrames(p.layer);
  Check(f1.total != f0.total && ReadyForDisplay(p.layer), "fullscreen: still playing",
        Format("%ld -> %ld", f0.total, f1.total));

  // Leaving fullscreen, then PiP: the PiP window's context takes the layer.
  Resize(page, CGSizeMake(640, 360));
  Place(p.layer, page.host, page.window);
  RemoteHost pip = MakeRemoteHost(NSMakeRect(700, 20, 320, 180), @"pip (CAContext)");
  Sleep(1);
  Place(p.layer, pip.host, pip.window);
  Sleep(0.5);
  Frames f2 = ReadFrames(p.layer);
  const double t2 = p.Time();
  Sleep(2.5);
  Frames f3 = ReadFrames(p.layer);
  const double t3 = p.Time();
  Check(ReadyForDisplay(p.layer), "remote pip: readyForDisplay in the PiP window's context");
  Check(f3.total != f2.total, "remote pip: frames keep coming",
        Format("%ld -> %ld", f2.total, f3.total));
  Check(t3 - t2 > 2.0, "remote pip: the clock keeps running", Format("+%.2f s", t3 - t2));

  // Leaving PiP.
  Place(p.layer, page.host, page.window);
  Sleep(0.5);
  Frames f4 = ReadFrames(p.layer);
  Sleep(2);
  Frames f5 = ReadFrames(p.layer);
  Check(ReadyForDisplay(p.layer) && f5.total != f4.total,
        "remote pip: playing again in the page's context",
        Format("%ld -> %ld", f4.total, f5.total));
  // Fullscreen again after PiP: AVFoundation returns to its earlier best
  // variant (it doesn't go above it after a spell at PiP size, separate runs
  // showed). Recorded, not checked.
  OnMain(^{
    [pip.window orderOut:nil];
  });
  Resize(page, CGSizeMake(1280, 720));
  Place(p.layer, page.host, page.window);
  Sleep(8);
  Note(Format("fullscreen again after PiP: %.0fp after 8 s", VideoHeight(p.item)));

  PCHlsPlayerLayer* layer = p.layer;
  OnMedia(^{
    player.rate = 0;
    [layer parcDetachPlayer];
  });
  Detach(layer);
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
    {"Accumulator", Accumulator},
    {"FrameStats", FrameStats},
    {"RemotePiP", RemotePiP},
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
