// Copyright 2026 Parc contributors.
// Installed at //media/filters/parc_source_buffer_stream_state.cc.

#include "media/filters/parc_source_buffer_stream_state.h"

#include <algorithm>
#include <iterator>

#include "media/base/stream_parser_buffer.h"
#include "media/base/timestamp_constants.h"
#include "media/filters/source_buffer_range.h"
#include "media/filters/source_buffer_stream.h"

namespace media {
namespace {

using Interval = std::pair<base::TimeDelta, base::TimeDelta>;
using Intervals = std::vector<Interval>;

// WebKit's PlatformTimeRanges::timeFudgeFactor is 2002/24000 seconds.
// Chromium rounds that strictly-open boundary to 83416 microseconds.
bool WithinTimeFudgeFactor(base::TimeDelta gap) {
  return gap.is_positive() && gap < base::Microseconds(83416);
}

Intervals::const_iterator FirstEndingAfter(const Intervals& intervals,
                                           base::TimeDelta time) {
  return std::partition_point(
      intervals.begin(), intervals.end(),
      [time](const Interval& interval) { return interval.second <= time; });
}

bool Holds(const Intervals& intervals, base::TimeDelta time) {
  const auto it = FirstEndingAfter(intervals, time);
  return it != intervals.end() && it->first <= time;
}

void Insert(Intervals* intervals,
            base::TimeDelta start,
            base::TimeDelta end) {
  intervals->insert(FirstEndingAfter(*intervals, start), {start, end});
}

void Cut(Intervals* intervals,
         base::TimeDelta start,
         base::TimeDelta end) {
  const auto first = FirstEndingAfter(*intervals, start);
  if (first == intervals->end() || end <= first->first) {
    return;
  }
  Intervals rest;
  auto last = first;
  for (; last != intervals->end() && last->first < end; ++last) {
    if (last->first < start) {
      rest.emplace_back(last->first, start);
    }
    if (end < last->second) {
      rest.emplace_back(end, last->second);
    }
  }
  intervals->insert(intervals->erase(first, last), rest.begin(), rest.end());
}

Intervals Coalesce(const Intervals& intervals, base::TimeDelta slack) {
  Intervals coalesced;
  for (const Interval& interval : intervals) {
    if (!coalesced.empty() &&
        interval.first <= coalesced.back().second + slack) {
      coalesced.back().second =
          std::max(coalesced.back().second, interval.second);
    } else {
      coalesced.push_back(interval);
    }
  }
  return coalesced;
}

base::TimeDelta Nearest(const Ranges<base::TimeDelta>& ranges,
                        base::TimeDelta time) {
  base::TimeDelta nearest = kNoTimestamp;
  base::TimeDelta nearest_distance = base::TimeDelta::Max();
  for (size_t i = 0; i < ranges.size(); ++i) {
    if (time >= ranges.start(i) && time <= ranges.end(i)) {
      return time;
    }
    for (const base::TimeDelta boundary : {ranges.start(i), ranges.end(i)}) {
      if ((boundary - time).magnitude() < nearest_distance) {
        nearest = boundary;
        nearest_distance = (boundary - time).magnitude();
      }
    }
  }
  return nearest;
}

}  // namespace

ParcSourceBufferStreamState::ParcSourceBufferStreamState() = default;
ParcSourceBufferStreamState::~ParcSourceBufferStreamState() = default;

void ParcSourceBufferStreamState::SetSafariMediaSource(bool safari) {
  enabled_ = safari;
  filled_gaps_.clear();
  frames_.reset();
}

void ParcSourceBufferStreamState::SetMediaSourceBuffered(
    base::TimeDelta start,
    Ranges<base::TimeDelta> audio) {
  media_source_start_ = start;
  audio_buffered_ = std::move(audio);
}

void ParcSourceBufferStreamState::PrepareForAppend(
    const SourceBufferStream& stream,
    Ranges<base::TimeDelta>* buffered) {
  if (!enabled_) {
    return;
  }
  frames_.reset();
  filled_gaps_ = KeptFilledGaps(stream);
  *buffered = BufferedTime(stream);
}

const ParcSourceBufferStreamState::Intervals&
ParcSourceBufferStreamState::Frames(const SourceBufferStream& stream) const {
  if (!frames_) {
    Intervals intervals;
    for (const auto& range : stream.ranges_) {
      for (const auto& buffer : range->buffers_) {
        intervals.emplace_back(
            buffer->timestamp(),
            buffer->timestamp() +
                std::max(buffer->duration(), base::Microseconds(1)));
      }
    }
    std::sort(intervals.begin(), intervals.end());
    frames_ = Coalesce(intervals, base::Microseconds(1));
  }
  return *frames_;
}

ParcSourceBufferStreamState::Intervals
ParcSourceBufferStreamState::KeptFilledGaps(
    const SourceBufferStream& stream) const {
  const Intervals& frames = Frames(stream);
  Intervals kept;
  for (const Interval& gap : Coalesce(filled_gaps_, {})) {
    if (Holds(frames, gap.first - base::Microseconds(1)) &&
        Holds(frames, gap.second)) {
      kept.push_back(gap);
    }
  }
  return kept;
}

Ranges<base::TimeDelta> ParcSourceBufferStreamState::BufferedTime(
    const SourceBufferStream& stream) const {
  const Intervals& frames = Frames(stream);
  const Intervals kept = KeptFilledGaps(stream);
  Intervals intervals;
  intervals.reserve(frames.size() + kept.size());
  std::merge(frames.begin(), frames.end(), kept.begin(), kept.end(),
             std::back_inserter(intervals));
  Ranges<base::TimeDelta> buffered;
  for (const Interval& interval : Coalesce(intervals, {})) {
    buffered.Add(interval.first, interval.second);
  }
  return buffered;
}

void ParcSourceBufferStreamState::FillSmallGaps(
    Ranges<base::TimeDelta>* buffered,
    const BufferQueue& buffers) {
  if (!enabled_) {
    return;
  }
  const base::TimeDelta kRounding = base::Microseconds(1);
  Intervals added;
  for (const auto& buffer : buffers) {
    const base::TimeDelta frame_start = buffer->timestamp();
    const base::TimeDelta frame_end =
        frame_start + std::max(buffer->duration(), kRounding);
    base::TimeDelta start = frame_start;
    base::TimeDelta end = frame_end;
    const base::TimeDelta nearest_start = Nearest(*buffered, start);
    const base::TimeDelta nearest_end = Nearest(*buffered, end);
    if (nearest_start != kNoTimestamp &&
        WithinTimeFudgeFactor(start - nearest_start)) {
      if (start - nearest_start > kRounding) {
        Insert(&added, nearest_start, start);
      }
      start = nearest_start;
    }
    if (nearest_end != kNoTimestamp &&
        WithinTimeFudgeFactor(nearest_end - end)) {
      if (nearest_end - end > kRounding) {
        Insert(&added, end, nearest_end);
      }
      end = nearest_end;
    }
    Cut(&filled_gaps_, frame_start, frame_end);
    Cut(&added, frame_start, frame_end);
    buffered->Add(start, end);
  }
  Intervals gaps;
  gaps.reserve(filled_gaps_.size() + added.size());
  std::merge(filled_gaps_.begin(), filled_gaps_.end(), added.begin(),
             added.end(), std::back_inserter(gaps));
  filled_gaps_ = std::move(gaps);
  frames_.reset();
}

void ParcSourceBufferStreamState::FramesChanged() {
  frames_.reset();
}

base::TimeDelta ParcSourceBufferStreamState::GapToleranceAt(
    base::TimeDelta time) const {
  const base::TimeDelta kStartGapAllowance = base::Seconds(1);
  if (time >= base::TimeDelta() && time < kStartGapAllowance &&
      media_source_start_ != kNoTimestamp &&
      media_source_start_ <= kStartGapAllowance &&
      time < media_source_start_) {
    return kStartGapAllowance;
  }
  for (size_t i = 0; i < audio_buffered_.size(); ++i) {
    if (time >= audio_buffered_.start(i) &&
        time <= audio_buffered_.end(i)) {
      return base::Milliseconds(250);
    }
  }
  return base::Milliseconds(125);
}

void ParcSourceBufferStreamState::NoteOutput(
    const StreamParserBuffer& buffer) {
  if (!enabled_) {
    return;
  }
  const base::TimeDelta end =
      buffer.timestamp() + std::max(buffer.duration(), base::TimeDelta());
  if (highest_output_end_ == kNoTimestamp || end > highest_output_end_) {
    highest_output_end_ = end;
  }
}

void ParcSourceBufferStreamState::ResetOutput() {
  highest_output_end_ = kNoTimestamp;
}

size_t ParcSourceBufferStreamState::RemovalSize(
    const SourceBufferStream& stream,
    base::TimeDelta start,
    base::TimeDelta remove_end) const {
  size_t size = 0;
  for (const auto& range : stream.ranges_) {
    if (range->GetStartTimestamp() >= remove_end) {
      break;
    }
    const auto split = range->GetFirstKeyframeAt(remove_end, false);
    const size_t end_index =
        split == range->keyframe_map_.end()
            ? range->buffers_.size()
            : static_cast<size_t>(split->second -
                                  range->keyframe_map_index_base_);
    for (size_t i = range->GetBufferIndexAt(start, false); i < end_index; ++i) {
      size += range->buffers_[i]->GetMemoryUsage();
    }
  }
  return size;
}

}  // namespace media
