
#ifndef MEDIA_FILTERS_PARC_SOURCE_BUFFER_STREAM_STATE_H_
#define MEDIA_FILTERS_PARC_SOURCE_BUFFER_STREAM_STATE_H_

#include <stddef.h>

#include <optional>
#include <utility>
#include <vector>

#include "base/time/time.h"
#include "media/base/media_export.h"
#include "media/base/ranges.h"
#include "media/base/stream_parser.h"
#include "media/base/timestamp_constants.h"

namespace media {

class SourceBufferStream;
class StreamParserBuffer;

class MEDIA_EXPORT ParcSourceBufferStreamState {
 public:
  using BufferQueue = StreamParser::BufferQueue;

  ParcSourceBufferStreamState();
  ParcSourceBufferStreamState(const ParcSourceBufferStreamState&) = delete;
  ParcSourceBufferStreamState& operator=(
      const ParcSourceBufferStreamState&) = delete;
  ~ParcSourceBufferStreamState();

  static base::TimeDelta KeyframeAtOrBefore(const SourceBufferStream& stream,
                                            base::TimeDelta time);
  static void RemoveBefore(SourceBufferStream& stream,
                           base::TimeDelta end,
                           base::TimeDelta duration);
  static void RemoveFrom(SourceBufferStream& stream,
                         base::TimeDelta start,
                         base::TimeDelta duration,
                         base::TimeDelta end = kInfiniteDuration);
  static void Remove(SourceBufferStream& stream,
                     base::TimeDelta start,
                     base::TimeDelta end,
                     base::TimeDelta duration);
  static size_t RemovalSize(SourceBufferStream& stream,
                            base::TimeDelta start,
                            base::TimeDelta end,
                            base::TimeDelta duration);
  static void UseSafariMediaSource(SourceBufferStream& stream, bool safari);
  static void ShareMediaSourceBuffered(SourceBufferStream& stream,
                                       base::TimeDelta start,
                                       Ranges<base::TimeDelta> audio);

  bool enabled() const { return enabled_; }

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
  void BridgeGap(SourceBufferStream& stream);
  void SeekAcrossGap(SourceBufferStream& stream, base::TimeDelta timestamp);

  bool end_of_stream_suspended() const {
    return end_of_stream_suspended_;
  }
  void set_end_of_stream_suspended(bool suspended) {
    end_of_stream_suspended_ = suspended;
  }

 private:
  using Interval = std::pair<base::TimeDelta, base::TimeDelta>;
  using Intervals = std::vector<Interval>;

  static base::TimeDelta RemoveEnd(SourceBufferStream& stream,
                                   base::TimeDelta end,
                                   base::TimeDelta duration);

  void SetSafariMediaSource(bool safari);
  void SetMediaSourceBuffered(base::TimeDelta start,
                              Ranges<base::TimeDelta> audio);
  size_t RemovalSizeTo(const SourceBufferStream& stream,
                       base::TimeDelta start,
                       base::TimeDelta remove_end) const;
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

}

#endif
