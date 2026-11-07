#import "fairplay_hls_frame_stats.h"

#import <AVFoundation/AVFoundation.h>

#include <algorithm>
#include <limits>

// WebKit's SPI (PAL's AVFoundationSPI.h): AVPlayerLayer has no public way to
// its metrics. The object answers WebKit's names (totalNumberOfVideoFrames,
// …) on the macOS versions Safari supports and the public names from macOS
// 14.4, so both are declared here, through a protocol so neither name's
// availability applies.
@interface AVPlayerLayer (ParcHlsVideoPerformanceMetrics)
- (id)videoPerformanceMetrics;
@end

@protocol ParcHlsVideoPerformanceMetrics <NSObject>
@optional
- (NSInteger)totalNumberOfFrames;
- (NSInteger)numberOfDroppedFrames;
- (unsigned long)totalNumberOfVideoFrames;
- (unsigned long)numberOfDroppedVideoFrames;
@end

namespace parc::fairplay {

namespace {

// RendererImpl reports with every frame; pages sample the counts, and Netflix
// gives up after 10 s without a new frame (as fairplay_renderer_adapter.mm).
constexpr int64_t kPollIntervalNs = 250 * NSEC_PER_MSEC;
constexpr int64_t kPollLeewayNs = 25 * NSEC_PER_MSEC;

uint32_t Clamp(int64_t value) {
  return static_cast<uint32_t>(
      std::clamp<int64_t>(value, 0, std::numeric_limits<uint32_t>::max()));
}

}  // namespace

FrameCountDelta FrameCountAccumulator::Advance(const DecoderFrameCounts& counts) {
  const int64_t total = std::max<int64_t>(counts.total, 0);
  const int64_t dropped = std::max<int64_t>(counts.dropped, 0);
  // Either count going back means a new decoder: both readings are new.
  const bool restarted = total < last_.total || dropped < last_.dropped;
  FrameCountDelta delta;
  delta.decoded = Clamp(restarted ? total : total - last_.total);
  delta.dropped = Clamp(restarted ? dropped : dropped - last_.dropped);
  last_ = {total, dropped};
  return delta;
}

std::optional<DecoderFrameCounts> ReadDecoderFrameCounts(AVPlayerLayer* layer) {
  if (![layer respondsToSelector:@selector(videoPerformanceMetrics)]) {
    return std::nullopt;
  }
  id<ParcHlsVideoPerformanceMetrics> metrics = [layer videoPerformanceMetrics];
  if (!metrics) {
    return std::nullopt;
  }
  DecoderFrameCounts counts;
  if ([metrics respondsToSelector:@selector(totalNumberOfFrames)] &&
      [metrics respondsToSelector:@selector(numberOfDroppedFrames)]) {
    counts.total = [metrics totalNumberOfFrames];
    counts.dropped = [metrics numberOfDroppedFrames];
  } else if ([metrics respondsToSelector:@selector(totalNumberOfVideoFrames)] &&
             [metrics respondsToSelector:@selector(numberOfDroppedVideoFrames)]) {
    counts.total = static_cast<int64_t>(std::min<unsigned long>(
        [metrics totalNumberOfVideoFrames], std::numeric_limits<int64_t>::max()));
    counts.dropped = static_cast<int64_t>(std::min<unsigned long>(
        [metrics numberOfDroppedVideoFrames], std::numeric_limits<int64_t>::max()));
  } else {
    return std::nullopt;
  }
  // Nothing decoded yet (or no player): not a reading, so a later one from
  // the same decoder isn't taken for a restart.
  if (counts.total <= 0 && counts.dropped <= 0) {
    return std::nullopt;
  }
  return counts;
}

// Shared by the owner and the queue; the last reference may go on either.
// The accumulator is touched only on the queue, |report| and |timer| only on
// the owner sequence. The layer is weak, so this never keeps it (and its
// player) alive.
struct HlsFrameStats::State {
  AVPlayerLayer* __weak layer = nil;
  PostTask post_task;
  std::function<void(const FrameCountDelta&)> report;
  dispatch_queue_t queue = nil;
  dispatch_source_t timer = nil;
  FrameCountAccumulator accumulator;
};

namespace {

// On the queue: one reading, its delta reported on the owner sequence.
void Poll(const std::shared_ptr<HlsFrameStats::State>& state) {
  std::optional<DecoderFrameCounts> counts;
  @autoreleasepool {
    AVPlayerLayer* layer = state->layer;
    counts = ReadDecoderFrameCounts(layer);
  }
  if (!counts) {
    return;
  }
  const FrameCountDelta delta = state->accumulator.Advance(*counts);
  if (delta.empty()) {
    return;
  }
  state->post_task([state, delta] {
    // A copy: the callback may destroy the HlsFrameStats, which clears it.
    if (std::function<void(const FrameCountDelta&)> report = state->report) {
      report(delta);
    }
  });
}

}  // namespace

HlsFrameStats::HlsFrameStats(AVPlayerLayer* layer,
                             PostTask post_task,
                             std::function<void(const FrameCountDelta&)> report)
    : state_(std::make_shared<State>()) {
  state_->layer = layer;
  state_->post_task = std::move(post_task);
  state_->report = std::move(report);
  state_->queue = dispatch_queue_create("parc.fairplay.hls.frame-stats",
                                        DISPATCH_QUEUE_SERIAL);
}

HlsFrameStats::~HlsFrameStats() {
  // Reports already posted see no callback and drop out. The callback goes
  // here, on the owner sequence, even if a reading in progress on the queue
  // keeps the state alive a little longer.
  state_->report = nullptr;
  if (state_->timer) {
    dispatch_source_cancel(state_->timer);
    state_->timer = nil;
  }
}

void HlsFrameStats::SetPlaying(bool playing) {
  if (playing == playing_) {
    return;
  }
  playing_ = playing;
  std::shared_ptr<State> state = state_;
  if (playing) {
    dispatch_source_t timer =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, state->queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, kPollIntervalNs),
                              kPollIntervalNs, kPollLeewayNs);
    // A slow reading coalesces the timer's fires instead of queueing them.
    dispatch_source_set_event_handler(timer, ^{
      Poll(state);
    });
    state->timer = timer;
    dispatch_resume(timer);
    return;
  }
  if (state->timer) {
    dispatch_source_cancel(state->timer);
    state->timer = nil;
  }
  dispatch_async(state->queue, ^{
    Poll(state);
  });
}

}  // namespace parc::fairplay
