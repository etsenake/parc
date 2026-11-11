// Copyright 2026 Parc contributors.
// Installed at //media/filters/parc_source_buffer_stream_state.h.

#ifndef MEDIA_FILTERS_PARC_SOURCE_BUFFER_STREAM_STATE_H_
#define MEDIA_FILTERS_PARC_SOURCE_BUFFER_STREAM_STATE_H_

#include <stddef.h>

#include <optional>
#include <utility>
#include <vector>

#include "base/time/time.h"
#include "media/base/ranges.h"
#include "media/base/stream_parser.h"
#include "media/base/timestamp_constants.h"

namespace media {

class SourceBufferStream;
class StreamParserBuffer;

// WebKit-compatible interval and gap policy kept out of Chromium's
// SourceBufferStream and SourceBufferRange headers. The stream still owns every
// cursor change and calls this object at the same append, seek, remove, and
// read points.
class ParcSourceBufferStreamState {
 public:
  using BufferQueue = StreamParser::BufferQueue;

  ParcSourceBufferStreamState();
  ParcSourceBufferStreamState(const ParcSourceBufferStreamState&) = delete;
  ParcSourceBufferStreamState& operator=(
      const ParcSourceBufferStreamState&) = delete;
  ~ParcSourceBufferStreamState();

  void SetSafariMediaSource(bool safari);
  bool enabled() const { return enabled_; }

  void SetMediaSourceBuffered(base::TimeDelta start,
                              Ranges<base::TimeDelta> audio);
  void PrepareForAppend(const SourceBufferStream& stream,
                        Ranges<base::TimeDelta>* buffered);
  void FillSmallGaps(Ranges<base::TimeDelta>* buffered,
                     const BufferQueue& buffers);
  void FramesChanged();
  Ranges<base::TimeDelta> BufferedTime(
      const SourceBufferStream& stream) const;
  base::TimeDelta GapToleranceAt(base::TimeDelta time) const;

  base::TimeDelta highest_output_end() const {
    return highest_output_end_;
  }
  void NoteOutput(const StreamParserBuffer& buffer);
  void ResetOutput();

  bool end_of_stream_suspended() const {
    return end_of_stream_suspended_;
  }
  void set_end_of_stream_suspended(bool suspended) {
    end_of_stream_suspended_ = suspended;
  }

  size_t RemovalSize(const SourceBufferStream& stream,
                     base::TimeDelta start,
                     base::TimeDelta remove_end) const;

 private:
  using Interval = std::pair<base::TimeDelta, base::TimeDelta>;
  using Intervals = std::vector<Interval>;

  const Intervals& Frames(const SourceBufferStream& stream) const;
  Intervals KeptFilledGaps(const SourceBufferStream& stream) const;

  bool enabled_ = false;
  bool end_of_stream_suspended_ = false;
  base::TimeDelta media_source_start_ = kNoTimestamp;
  Ranges<base::TimeDelta> audio_buffered_;
  base::TimeDelta highest_output_end_ = kNoTimestamp;
  Intervals filled_gaps_;
  mutable std::optional<Intervals> frames_;
};

}  // namespace media

#endif  // MEDIA_FILTERS_PARC_SOURCE_BUFFER_STREAM_STATE_H_
