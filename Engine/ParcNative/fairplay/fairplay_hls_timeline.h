// Native HLS duration, seekable window and start date as Safari reports them
// for an AVPlayer item (fairplay_chromium/NATIVE_HLS.md, Live and DVR).
// Plain C++: FairPlayHlsPlayer turns AVFoundation's values into these inputs.
//
// The rules are WebKit's (Source/WebCore/platform/graphics/avfoundation):
// MediaPlayerPrivateAVFoundationObjC::platformDuration, platformMinTimeSeekable,
// platformMaxTimeSeekable and getStartDate, MediaPlayerPrivateAVFoundation's
// duration() and seekable caches, and MediaPlayerPrivateInterface::seekable().
// Safari runs the player in WebKit's GPU process, and the page reads the
// values RemoteMediaPlayerProxy last sent it: the seekable window when
// seekableTimeRanges changes and at every ready-state change, the start date
// only at ready-state changes. HlsTimeline keeps that cache.
#pragma once

#include <optional>
#include <vector>

namespace parc::fairplay {

// What a CMTime holds, as WebKit tells them apart.
enum class HlsTimeKind {
  kNumeric,     // CMTIME_IS_NUMERIC.
  kIndefinite,  // CMTIME_IS_INDEFINITE: a live stream's duration.
  kInvalid,     // Anything else, positive infinity included.
};

struct HlsTime {
  HlsTimeKind kind = HlsTimeKind::kInvalid;
  double seconds = 0;  // CMTimeGetSeconds, meaningful when numeric.

  bool operator==(const HlsTime& other) const {
    return kind == other.kind && (kind != HlsTimeKind::kNumeric || seconds == other.seconds);
  }
};

// One entry of AVPlayerItem.seekableTimeRanges.
struct HlsSeekableRangeInput {
  bool valid = true;   // CMTIMERANGE_IS_VALID.
  bool empty = false;  // CMTIMERANGE_IS_EMPTY.
  double start = 0;    // CMTimeGetSeconds(range.start).
  double end = 0;      // CMTimeGetSeconds(CMTimeRangeGetEnd(range)).
};

// The one range the element's seekable attribute holds.
struct HlsSeekableWindow {
  double start = 0;
  double end = 0;

  bool operator==(const HlsSeekableWindow& other) const {
    return start == other.start && end == other.end;
  }
};

// The element's duration for an item duration: numeric → its seconds,
// indefinite → +infinity, invalid → 0.
double HlsDurationSeconds(const HlsTime& duration);

// The element's seekable window: from the smallest start to the largest end
// of the valid, non-empty ranges (start 0 when there are none), or up to
// |duration_seconds| when AVFoundation lists no range at all. nullopt (an
// empty seekable) when the end is 0.
std::optional<HlsSeekableWindow> HlsSeekable(const std::vector<HlsSeekableRangeInput>& ranges,
                                             double duration_seconds);

// getStartDate(): seconds since the epoch at media time 0, rounded to whole
// seconds, from AVPlayerItem.currentDate (EXT-X-PROGRAM-DATE-TIME) and
// currentTime. nullopt when the item has no date (currentDate nil, which
// AVFoundation reports as 0) or the result isn't finite.
std::optional<double> HlsStartDate(double current_date_since_1970, double current_time_seconds);

// The values the page sees, updated as Safari updates them. Every method
// returns whether what the page sees changed.
class HlsTimeline {
 public:
  // The item became ready to play.
  void Start(const HlsTime& duration,
             const std::vector<HlsSeekableRangeInput>& seekable,
             std::optional<double> start_date);

  // AVPlayerItem.duration changed. True when the element's duration changed
  // and so fires durationchange (WebKit's durationDidChange).
  bool DurationChanged(const HlsTime& duration);

  // AVPlayerItem.seekableTimeRanges changed. True when the window changed.
  bool SeekableChanged(const std::vector<HlsSeekableRangeInput>& seekable);

  // The element's ready state changed (the item's buffering state did):
  // Safari's proxy samples the start date again and asks for the seekable
  // window, which WebKit computes again only while its end is 0 (the end of
  // an item with no seekable range follows a duration that arrived since).
  // |start_date| is HlsStartDate now. True when either changed; check
  // start_date() and seekable() for which.
  bool ReadyStateChanged(std::optional<double> start_date);

  double duration() const { return HlsDurationSeconds(duration_); }
  const std::optional<HlsSeekableWindow>& seekable() const { return seekable_; }
  const std::optional<double>& start_date() const { return start_date_; }

  // The element's seekable attribute: one range, or none.
  std::vector<HlsSeekableWindow> SeekableRanges() const;

 private:
  bool UpdateWindow();

  HlsTime duration_;
  std::vector<HlsSeekableRangeInput> ranges_;
  std::optional<HlsSeekableWindow> seekable_;
  std::optional<double> start_date_;
};

}  // namespace parc::fairplay
