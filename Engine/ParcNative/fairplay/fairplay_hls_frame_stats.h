// Frame counts for the native HLS player (fairplay_chromium/NATIVE_HLS.md):
// what getVideoPlaybackQuality(), webkitDecodedFrameCount and
// webkitDroppedFrameCount read, as PipelineStatistics deltas like the MSE
// renderer's (fairplay_renderer_adapter.mm).
//
// The source is WebKit's for an AVPlayer: -[AVPlayerLayer
// videoPerformanceMetrics] (MediaPlayerPrivateAVFoundationObjC::
// videoPlaybackQualityMetrics), the decoder's own counts of frames decoded
// and dropped. Unlike an AVSampleBufferDisplayLayer's, this count restarts
// when AVFoundation rebuilds its decoder (seen on a variant switch), so a
// total below the previous one is a new run and counts in full.
//
// Objective-C++ only (it names AVPlayerLayer).
#pragma once

#include <cstdint>
#include <functional>
#include <memory>

#include "fairplay_types.h"

@class AVPlayerLayer;

namespace parc::fairplay {

// Frames decoded and dropped since the previous report.
struct FrameCountDelta {
  uint32_t decoded = 0;
  uint32_t dropped = 0;

  bool empty() const { return !decoded && !dropped; }
};

// Cumulative counts as AVFoundation reports them for its current decoder.
struct DecoderFrameCounts {
  int64_t total = 0;
  int64_t dropped = 0;
};

// Turns successive cumulative readings into deltas. A reading with either
// count below the previous one is a restarted decoder: all of it is new.
class FrameCountAccumulator {
 public:
  FrameCountDelta Advance(const DecoderFrameCounts& counts);

 private:
  DecoderFrameCounts last_;
};

// Reads the layer's counts, or nothing when the layer has none (no player,
// nothing counted yet, or an OS without the metrics). Can block briefly, as
// WebKit notes: call it off the owner sequence. Thread-safe.
std::optional<DecoderFrameCounts> ReadDecoderFrameCounts(AVPlayerLayer* layer);

class HlsFrameStats {
 public:
  // Polls the layer every 250 ms while playing, as the MSE renderer's adapter
  // does, on a private serial queue. |report| runs on the owner sequence
  // (|post_task|) with each non-empty delta. Every method is called on the
  // owner sequence.
  HlsFrameStats(AVPlayerLayer* layer,
                PostTask post_task,
                std::function<void(const FrameCountDelta&)> report);
  // No report runs after this returns.
  ~HlsFrameStats();

  HlsFrameStats(const HlsFrameStats&) = delete;
  HlsFrameStats& operator=(const HlsFrameStats&) = delete;

  // Started at a rate above 0. Stopping (pause, seek, end) counts once more,
  // so frames decoded until then don't wait for playback to resume.
  void SetPlaying(bool playing);

  struct State;

 private:
  std::shared_ptr<State> state_;
  bool playing_ = false;
};

}  // namespace parc::fairplay
