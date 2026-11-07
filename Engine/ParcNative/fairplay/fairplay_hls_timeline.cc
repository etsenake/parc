#include "fairplay_hls_timeline.h"

#include <cmath>
#include <limits>

namespace parc::fairplay {

double HlsDurationSeconds(const HlsTime& duration) {
  switch (duration.kind) {
    case HlsTimeKind::kNumeric:
      return duration.seconds;
    case HlsTimeKind::kIndefinite:
      return std::numeric_limits<double>::infinity();
    case HlsTimeKind::kInvalid:
      return 0;
  }
  return 0;
}

std::optional<HlsSeekableWindow> HlsSeekable(const std::vector<HlsSeekableRangeInput>& ranges,
                                             double duration_seconds) {
  // platformMaxTimeSeekable: the duration when the list is empty, otherwise
  // the largest end of a valid, non-empty range, from 0.
  double end = 0;
  // platformMinTimeSeekable: 0 for an empty list or one with no valid,
  // non-empty range.
  double start = 0;
  if (ranges.empty()) {
    end = duration_seconds;
  } else {
    double smallest_start = std::numeric_limits<double>::infinity();
    bool has_valid_range = false;
    for (const HlsSeekableRangeInput& range : ranges) {
      if (!range.valid || range.empty) {
        continue;
      }
      has_valid_range = true;
      if (smallest_start > range.start) {
        smallest_start = range.start;
      }
      if (end < range.end) {
        end = range.end;
      }
    }
    start = has_valid_range ? smallest_start : 0;
  }
  // MediaPlayerPrivateInterface::seekable(): nothing seekable when the end is
  // 0.
  if (end == 0) {
    return std::nullopt;
  }
  return HlsSeekableWindow{start, end};
}

std::optional<double> HlsStartDate(double current_date_since_1970, double current_time_seconds) {
  // "No live streams were made during the epoch (1970)": AVFoundation
  // answers 0 when the media has no date.
  if (!current_date_since_1970) {
    return std::nullopt;
  }
  // WebKit rounds away the error of subtracting the two.
  double start = std::round(current_date_since_1970 - current_time_seconds);
  if (!std::isfinite(start)) {
    return std::nullopt;
  }
  return start;
}

void HlsTimeline::Start(const HlsTime& duration,
                        const std::vector<HlsSeekableRangeInput>& seekable,
                        std::optional<double> start_date) {
  duration_ = duration;
  ranges_ = seekable;
  start_date_ = start_date;
  seekable_ = HlsSeekable(ranges_, HlsDurationSeconds(duration_));
}

bool HlsTimeline::DurationChanged(const HlsTime& duration) {
  if (duration == duration_) {
    return false;
  }
  // WebKit fires no durationchange for a change from an invalid duration:
  // the element announces the first duration with loadedmetadata.
  bool was_valid = duration_.kind != HlsTimeKind::kInvalid;
  double before = HlsDurationSeconds(duration_);
  duration_ = duration;
  return was_valid && before != HlsDurationSeconds(duration_);
}

bool HlsTimeline::SeekableChanged(const std::vector<HlsSeekableRangeInput>& seekable) {
  ranges_ = seekable;
  return UpdateWindow();
}

bool HlsTimeline::ReadyStateChanged(std::optional<double> start_date) {
  bool changed = start_date != start_date_;
  start_date_ = start_date;
  // WebKit caches the window's ends and computes an end of 0 again on every
  // request, so only an empty window can change here.
  if (!seekable_) {
    changed |= UpdateWindow();
  }
  return changed;
}

std::vector<HlsSeekableWindow> HlsTimeline::SeekableRanges() const {
  if (!seekable_) {
    return {};
  }
  return {*seekable_};
}

bool HlsTimeline::UpdateWindow() {
  std::optional<HlsSeekableWindow> window = HlsSeekable(ranges_, HlsDurationSeconds(duration_));
  if (window == seekable_) {
    return false;
  }
  seekable_ = window;
  return true;
}

}  // namespace parc::fairplay
