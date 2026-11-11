// Copyright 2026 Parc contributors.
// Installed at //media/filters/parc_source_buffer_eviction.h.

#ifndef MEDIA_FILTERS_PARC_SOURCE_BUFFER_EVICTION_H_
#define MEDIA_FILTERS_PARC_SOURCE_BUFFER_EVICTION_H_

#include <stddef.h>
#include <stdint.h>

#include <vector>

#include "base/time/time.h"
#include "media/base/ranges.h"

namespace media {

class ChunkDemuxerStream;
class SourceBufferState;

// Safari's SourceBuffer eviction and ManagedMediaSource purge policy. The
// ChunkDemuxer and SourceBufferState hooks invoke it under the same lock as
// before; stream lookups and removals remain on their existing primitives.
class ParcSourceBufferEviction {
 public:
  ParcSourceBufferEviction();
  ParcSourceBufferEviction(const ParcSourceBufferEviction&) = delete;
  ParcSourceBufferEviction& operator=(const ParcSourceBufferEviction&) = delete;
  ~ParcSourceBufferEviction();

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

  bool purged_while_inactive() const { return purged_while_inactive_; }
  static size_t MaximumBufferSize(bool has_video);

 private:
  std::vector<ChunkDemuxerStream*> Streams(
      const SourceBufferState& state) const;
  uint64_t ContentSize(const SourceBufferState& state) const;

  bool purged_while_inactive_ = false;
  uint64_t evictable_size_ = 0;
};

}  // namespace media

#endif  // MEDIA_FILTERS_PARC_SOURCE_BUFFER_EVICTION_H_
