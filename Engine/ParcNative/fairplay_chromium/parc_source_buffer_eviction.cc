#include "media/filters/parc_source_buffer_eviction.h"

#include <algorithm>
#include <utility>

#include "base/numerics/checked_math.h"
#include "media/base/media_log.h"
#include "media/base/media_track.h"
#include "media/base/media_tracks.h"
#include "media/base/stream_parser.h"
#include "media/base/timestamp_constants.h"
#include "media/base/video_codecs.h"
#include "media/base/video_decoder_config.h"
#include "media/filters/chunk_demuxer.h"
#include "media/filters/parc_chunk_demuxer_hand_off.h"
#include "media/filters/source_buffer_state.h"

namespace media {
namespace {
base::TimeDelta PreviousSyncTime(
    base::TimeDelta media_time,
    const std::vector<ChunkDemuxerStream*>& streams) {
  base::TimeDelta previous_sync = media_time;
  for (ChunkDemuxerStream* stream : streams) {
    const base::TimeDelta keyframe =
        ParcChunkDemuxer::KeyframeAtOrBefore(*stream, media_time);
    if (keyframe != kNoTimestamp && keyframe < previous_sync) {
      previous_sync = keyframe;
    }
  }
  return previous_sync;
}

Ranges<base::TimeDelta> OwnRanges(
    const std::vector<ChunkDemuxerStream*>& streams,
    base::TimeDelta duration) {
  SourceBufferState::RangesList track_ranges;
  for (ChunkDemuxerStream* stream : streams) {
    track_ranges.push_back(stream->GetBufferedRanges(duration));
  }
  return SourceBufferState::ComputeRangesIntersection(track_ranges,
                                                      /*ended=*/false);
}

base::TimeDelta PlayableEnd(base::TimeDelta media_time,
                            const Ranges<base::TimeDelta>& own,
                            const Ranges<base::TimeDelta>& buffered,
                            const Ranges<base::TimeDelta>& audio) {
  const auto tolerance = [&](base::TimeDelta time) {
    const base::TimeDelta kStartGapAllowance = base::Seconds(1);
    if (time >= base::TimeDelta() && time < kStartGapAllowance &&
        buffered.size() && buffered.start(0) <= kStartGapAllowance &&
        time < buffered.start(0)) {
      return kStartGapAllowance;
    }
    for (size_t i = 0; i < audio.size(); ++i) {
      if (time >= audio.start(i) && time <= audio.end(i)) {
        return base::Milliseconds(250);
      }
    }
    return base::Milliseconds(125);
  };

  for (size_t i = 0; i < own.size(); ++i) {
    if (media_time < own.start(i) || media_time >= own.end(i)) {
      continue;
    }
    for (size_t j = i; j + 1 < own.size(); ++j) {
      if (own.start(j + 1) - own.end(j) > tolerance(own.end(j))) {
        return own.end(j);
      }
    }
    return own.end(own.size() - 1);
  }
  return kNoTimestamp;
}

base::TimeDelta MinimumBufferedTime(
    const std::vector<ChunkDemuxerStream*>& streams,
    base::TimeDelta duration) {
  base::TimeDelta minimum = kInfiniteDuration;
  for (ChunkDemuxerStream* stream : streams) {
    const Ranges<base::TimeDelta> ranges = stream->GetBufferedRanges(duration);
    if (ranges.size()) {
      minimum = std::min(minimum, ranges.start(0));
    }
  }
  return minimum;
}

base::TimeDelta MaximumBufferedTime(
    const std::vector<ChunkDemuxerStream*>& streams,
    base::TimeDelta duration) {
  base::TimeDelta maximum = kNoTimestamp;
  for (ChunkDemuxerStream* stream : streams) {
    const Ranges<base::TimeDelta> ranges = stream->GetBufferedRanges(duration);
    if (ranges.size()) {
      maximum = std::max(maximum, ranges.end(ranges.size() - 1));
    }
  }
  return maximum;
}

}

ParcSourceBufferEviction::ParcSourceBufferEviction() = default;
ParcSourceBufferEviction::~ParcSourceBufferEviction() = default;

ParcSourceBufferEviction& ParcSourceBufferEviction::Of(
    SourceBufferState& state) {
  return *state.parc_eviction_;
}

bool ParcSourceBufferEviction::IsActive(const SourceBufferState& state) {
  for (const auto& it : state.audio_streams_) {
    if (it.second->IsEnabled()) {
      return true;
    }
  }
  for (const auto& it : state.video_streams_) {
    if (it.second->IsEnabled()) {
      return true;
    }
  }
  return false;
}

bool ParcSourceBufferEviction::LeftOutOfMediaSource(
    const SourceBufferState& state) {
  if (!state.parc_eviction_->purged_while_inactive() || IsActive(state)) {
    return false;
  }
  for (const auto& it : state.audio_streams_) {
    if (it.second->GetMemoryUsage()) {
      return false;
    }
  }
  for (const auto& it : state.video_streams_) {
    if (it.second->GetMemoryUsage()) {
      return false;
    }
  }
  return true;
}

bool ParcSourceBufferEviction::PurgedWhileInactive(
    const SourceBufferState& state) {
  return state.parc_eviction_->purged_while_inactive();
}

Ranges<base::TimeDelta> ParcSourceBufferEviction::AudioBufferedRanges(
    const SourceBufferState& state,
    base::TimeDelta duration) {
  Ranges<base::TimeDelta> ranges;
  for (const auto& it : state.audio_streams_) {
    const Ranges<base::TimeDelta> stream_ranges =
        it.second->GetBufferedRanges(duration);
    for (size_t i = 0; i < stream_ranges.size(); ++i) {
      ranges.Add(stream_ranges.start(i), stream_ranges.end(i));
    }
  }
  return ranges;
}

void ParcSourceBufferEviction::SetClearDolbyVisionAllowed(
    SourceBufferState& state,
    bool allowed) {
  state.parc_eviction_->clear_dolby_vision_allowed_ = allowed;
}

void ParcSourceBufferEviction::SetDolbyVisionCallback(
    SourceBufferState& state,
    base::RepeatingClosure callback) {
  state.parc_eviction_->dolby_vision_cb_ = std::move(callback);
}

void ParcSourceBufferEviction::SetSafariInitSegmentRules(
    SourceBufferState& state,
    bool safari) {
  state.parc_eviction_->safari_init_segment_rules_ = safari;
}

void ParcSourceBufferEviction::ApplyInitSegmentRules(
    std::optional<std::string_view>& expected_codecs,
    StreamParser& stream_parser) const {
  if (safari_init_segment_rules_) {
    expected_codecs.reset();
    stream_parser.ParcIgnoreDeclaredCodecs();
  }
}

bool ParcSourceBufferEviction::AcceptsInitSegment(
    const SourceBufferState& state,
    const MediaTracks& tracks) const {
  if (!safari_init_segment_rules_ || !state.first_init_segment_received_) {
    return true;
  }
  size_t audio_tracks = 0;
  size_t video_tracks = 0;
  for (const auto& track : tracks.tracks()) {
    if (track->type() == MediaTrack::Type::kAudio) {
      ++audio_tracks;
    } else if (track->type() == MediaTrack::Type::kVideo) {
      ++video_tracks;
    }
  }
  if (audio_tracks != state.audio_streams_.size() ||
      video_tracks != state.video_streams_.size()) {
    MEDIA_LOG(ERROR, state.media_log_)
        << "Initialization segment has " << audio_tracks << " audio and "
        << video_tracks << " video tracks; the first had "
        << state.audio_streams_.size() << " and "
        << state.video_streams_.size() << ".";
    return false;
  }
  return true;
}

bool ParcSourceBufferEviction::PlaysClearDolbyVision(
    const VideoDecoderConfig& video_config) const {
  return clear_dolby_vision_allowed_ &&
         (video_config.profile() == DOLBYVISION_PROFILE5 ||
          video_config.profile() == DOLBYVISION_PROFILE8 ||
          (safari_init_segment_rules_ &&
           video_config.profile() == DOLBYVISION_PROFILE10));
}

void ParcSourceBufferEviction::OnDolbyVisionAppended() {
  if (dolby_vision_cb_) {
    dolby_vision_cb_.Run();
  }
}

std::vector<ChunkDemuxerStream*> ParcSourceBufferEviction::Streams(
    const SourceBufferState& state) const {
  std::vector<ChunkDemuxerStream*> streams;
  for (const auto& it : state.audio_streams_) {
    streams.push_back(it.second);
  }
  for (const auto& it : state.video_streams_) {
    streams.push_back(it.second);
  }
  return streams;
}

uint64_t ParcSourceBufferEviction::ContentSize(
    const SourceBufferState& state) const {
  uint64_t size = 0;
  for (ChunkDemuxerStream* stream : Streams(state)) {
    size += stream->GetMemoryUsage();
  }
  return size;
}

void ParcSourceBufferEviction::PurgeForMemoryPressure(
    SourceBufferState& state,
    base::TimeDelta media_time,
    bool active,
    base::TimeDelta duration,
    const Ranges<base::TimeDelta>& buffered,
    const Ranges<base::TimeDelta>& audio,
    bool safari_eviction) {
  const std::vector<ChunkDemuxerStream*> streams = Streams(state);

  if (!active) {
    for (ChunkDemuxerStream* stream : streams) {
      ParcChunkDemuxer::RemoveFrom(*stream, base::TimeDelta(), duration);
    }
    purged_while_inactive_ = true;
    return;
  }

  if (safari_eviction) {
    EvictFrames(state, media_time,
                MaximumBufferSize(!state.video_streams_.empty()), duration,
                buffered, audio, true);
    return;
  }

  const base::TimeDelta kTimeChunk = base::Milliseconds(3750);
  const base::TimeDelta front_end =
      std::min(media_time - kTimeChunk,
               PreviousSyncTime(media_time, streams));
  for (ChunkDemuxerStream* stream : streams) {
    ParcChunkDemuxer::RemoveBefore(*stream, front_end, duration);
  }

  const base::TimeDelta playable_end =
      PlayableEnd(media_time, OwnRanges(streams, duration), buffered, audio);
  const base::TimeDelta back_start =
      playable_end != kNoTimestamp ? playable_end : media_time + kTimeChunk;
  for (ChunkDemuxerStream* stream : streams) {
    ParcChunkDemuxer::RemoveFrom(*stream, back_start, duration);
  }
}

size_t ParcSourceBufferEviction::MaximumBufferSize(bool has_video) {
  constexpr size_t kMaximumSourceBufferSize = 318767104;
  size_t maximum = static_cast<size_t>(kMaximumSourceBufferSize * .05f);
  if (has_video) {
    maximum += static_cast<size_t>(kMaximumSourceBufferSize * .95f);
  }
  return maximum;
}

bool ParcSourceBufferEviction::IsBufferFullFor(
    const SourceBufferState& state,
    size_t new_data_size) const {
  base::CheckedNumeric<size_t> required = new_data_size;
  for (ChunkDemuxerStream* stream : Streams(state)) {
    required += stream->GetMemoryUsage();
  }
  return !required.IsValid() ||
         required.ValueOrDie() >=
             MaximumBufferSize(!state.video_streams_.empty());
}

bool ParcSourceBufferEviction::CanAppend(const SourceBufferState& state,
                                         size_t new_data_size) const {
  return ContentSize(state) - evictable_size_ + new_data_size <=
         MaximumBufferSize(!state.video_streams_.empty());
}

bool ParcSourceBufferEviction::EvictFrames(
    SourceBufferState& state,
    base::TimeDelta media_time,
    size_t new_data_size,
    base::TimeDelta duration,
    const Ranges<base::TimeDelta>& buffered,
    const Ranges<base::TimeDelta>& audio,
    bool memory_pressure) {
  const std::vector<ChunkDemuxerStream*> streams = Streams(state);
  const auto remove = [&](base::TimeDelta start, base::TimeDelta end) {
    for (ChunkDemuxerStream* stream : streams) {
      if (memory_pressure) {
        ParcChunkDemuxer::RemoveFrom(*stream, start, duration, end);
      } else {
        ParcChunkDemuxer::Remove(*stream, start, end, duration);
      }
    }
  };
  const base::TimeDelta kInitialTimeChunk = base::Seconds(30);
  const base::TimeDelta kTimeChunkLowThreshold = base::Seconds(3);

  bool full = true;
  for (base::TimeDelta chunk = kInitialTimeChunk;
       full && chunk >= kTimeChunkLowThreshold; chunk /= 2) {
    const base::TimeDelta maximum_end =
        std::min(media_time - chunk, PreviousSyncTime(media_time, streams));
    do {
      const base::TimeDelta start = MinimumBufferedTime(streams, duration);
      const base::TimeDelta end = std::min(start + chunk, maximum_end);
      if (start >= end) {
        break;
      }
      remove(start, end);
      if (MinimumBufferedTime(streams, duration) == start) {
        break;
      }
      full = IsBufferFullFor(state, new_data_size);
    } while (full);
  }
  if (!full) {
    return false;
  }

  for (base::TimeDelta chunk = kInitialTimeChunk;
       full && chunk >= kTimeChunkLowThreshold; chunk /= 2) {
    do {
      const Ranges<base::TimeDelta> own = OwnRanges(streams, duration);
      if (!own.size() || own.end(own.size() - 1) <= media_time) {
        break;
      }
      const base::TimeDelta end = own.end(own.size() - 1);
      const base::TimeDelta playable_end =
          PlayableEnd(media_time, own, buffered, audio);
      const base::TimeDelta start =
          std::max(playable_end != kNoTimestamp ? playable_end
                                               : media_time + chunk,
                   end - chunk);
      if (start >= end) {
        break;
      }
      const uint64_t size_before = ContentSize(state);
      remove(start, end);
      if (MaximumBufferedTime(streams, duration) == end ||
          ContentSize(state) == size_before) {
        break;
      }
      full = IsBufferFullFor(state, new_data_size);
    } while (full);
  }
  return full;
}

void ParcSourceBufferEviction::ComputeEvictionData(
    SourceBufferState& state,
    base::TimeDelta media_time,
    base::TimeDelta duration,
    const Ranges<base::TimeDelta>& buffered,
    const Ranges<base::TimeDelta>& audio) {
  const std::vector<ChunkDemuxerStream*> streams = Streams(state);
  const auto removal_size = [&](base::TimeDelta start, base::TimeDelta end) {
    uint64_t size = 0;
    for (ChunkDemuxerStream* stream : streams) {
      size += ParcChunkDemuxer::RemovalSize(*stream, start, end, duration);
    }
    return size;
  };
  const base::TimeDelta kTimeChunk = base::Seconds(3);

  uint64_t evictable = 0;
  const base::TimeDelta front_start = MinimumBufferedTime(streams, duration);
  const base::TimeDelta front_end =
      std::min(media_time - kTimeChunk,
               PreviousSyncTime(media_time, streams));
  if (front_start < front_end) {
    evictable += removal_size(front_start, front_end);
  }

  const Ranges<base::TimeDelta> own = OwnRanges(streams, duration);
  if (own.size() && own.end(own.size() - 1) > media_time) {
    const base::TimeDelta playable_end =
        PlayableEnd(media_time, own, buffered, audio);
    const base::TimeDelta back_start =
        playable_end != kNoTimestamp ? playable_end : media_time + kTimeChunk;
    const base::TimeDelta back_end = own.end(own.size() - 1);
    if (back_start < back_end) {
      evictable += removal_size(back_start, back_end);
    }
  }
  evictable_size_ = evictable;
}

}
