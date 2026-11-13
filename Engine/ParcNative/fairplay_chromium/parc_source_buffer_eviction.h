#ifndef MEDIA_FILTERS_PARC_SOURCE_BUFFER_EVICTION_H_
#define MEDIA_FILTERS_PARC_SOURCE_BUFFER_EVICTION_H_

#include <stddef.h>
#include <stdint.h>

#include <optional>
#include <string_view>
#include <vector>

#include "base/functional/callback.h"
#include "base/time/time.h"
#include "media/base/media_export.h"
#include "media/base/ranges.h"

namespace media {

class ChunkDemuxerStream;
class MediaTracks;
class StreamParser;
class SourceBufferState;
class VideoDecoderConfig;

class MEDIA_EXPORT ParcSourceBufferEviction {
 public:
  ParcSourceBufferEviction();
  ParcSourceBufferEviction(const ParcSourceBufferEviction&) = delete;
  ParcSourceBufferEviction& operator=(const ParcSourceBufferEviction&) = delete;
  ~ParcSourceBufferEviction();

  static ParcSourceBufferEviction& Of(SourceBufferState& state);
  static bool IsActive(const SourceBufferState& state);
  static Ranges<base::TimeDelta> AudioBufferedRanges(
      const SourceBufferState& state,
      base::TimeDelta duration);
  static bool LeftOutOfMediaSource(const SourceBufferState& state);
  static bool PurgedWhileInactive(const SourceBufferState& state);
  static void SetClearDolbyVisionAllowed(SourceBufferState& state,
                                         bool allowed);
  static void SetDolbyVisionCallback(SourceBufferState& state,
                                     base::RepeatingClosure callback);
  static void SetSafariInitSegmentRules(SourceBufferState& state, bool safari);

  void PurgeForMemoryPressure(
      SourceBufferState& state,
      base::TimeDelta media_time,
      bool active,
      base::TimeDelta duration,
      const Ranges<base::TimeDelta>& buffered,
      const Ranges<base::TimeDelta>& audio,
      bool safari_eviction);
  bool IsBufferFullFor(const SourceBufferState& state,
                       size_t new_data_size) const;
  bool CanAppend(const SourceBufferState& state,
                 size_t new_data_size) const;
  bool EvictFrames(SourceBufferState& state,
                   base::TimeDelta media_time,
                   size_t new_data_size,
                   base::TimeDelta duration,
                   const Ranges<base::TimeDelta>& buffered,
                   const Ranges<base::TimeDelta>& audio,
                   bool memory_pressure);
  void ComputeEvictionData(SourceBufferState& state,
                           base::TimeDelta media_time,
                           base::TimeDelta duration,
                           const Ranges<base::TimeDelta>& buffered,
                           const Ranges<base::TimeDelta>& audio);

  bool safari_init_segment_rules() const { return safari_init_segment_rules_; }
  void ApplyInitSegmentRules(std::optional<std::string_view>& expected_codecs,
                             StreamParser& stream_parser) const;
  bool AcceptsInitSegment(const SourceBufferState& state,
                          const MediaTracks& tracks) const;
  bool PlaysClearDolbyVision(const VideoDecoderConfig& video_config) const;
  void OnDolbyVisionAppended();

  bool purged_while_inactive() const { return purged_while_inactive_; }
  static size_t MaximumBufferSize(bool has_video);

 private:
  std::vector<ChunkDemuxerStream*> Streams(
      const SourceBufferState& state) const;
  uint64_t ContentSize(const SourceBufferState& state) const;

  bool purged_while_inactive_ = false;
  uint64_t evictable_size_ = 0;
  bool clear_dolby_vision_allowed_ = false;
  base::RepeatingClosure dolby_vision_cb_;
  bool safari_init_segment_rules_ = false;
};

}

#endif
