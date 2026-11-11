// Copyright 2026 Parc contributors.
// Installed at //media/filters/parc_chunk_demuxer_hand_off.h.

#ifndef MEDIA_FILTERS_PARC_CHUNK_DEMUXER_HAND_OFF_H_
#define MEDIA_FILTERS_PARC_CHUNK_DEMUXER_HAND_OFF_H_

#include <stdint.h>

#include <memory>
#include <optional>
#include <set>
#include <vector>

#include "base/containers/circular_deque.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/time/time.h"
#include "media/base/demuxer_stream.h"
#include "media/base/media_resource.h"
#include "media/base/media_track.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/timestamp_constants.h"

namespace media {

class ChunkDemuxer;
class ChunkDemuxerStream;

// One ChunkDemuxerStream's side of a hand-off from the renderer reading it to
// another (PipelineImpl's to the FairPlay Renderer). The other reads
// reader(), which returns nothing until SplitAt() splits the stream: from
// then on the stream's own reader gets what comes before the split, then end
// of stream, and reader() what follows, so each renderer plays its part of
// one timeline. The stream owns this and makes every call but reader()'s
// Read() with its lock held, at the points of its read path the hand-off
// joins.
class ParcStreamHandOff {
 public:
  explicit ParcStreamHandOff(ChunkDemuxerStream* stream);
  ParcStreamHandOff(const ParcStreamHandOff&) = delete;
  ParcStreamHandOff& operator=(const ParcStreamHandOff&) = delete;
  ~ParcStreamHandOff();

  DemuxerStream* reader();
  // The stream's own reader reads what comes before a split asked for.
  bool split_asked() const { return target_.has_value(); }

  // See ChunkDemuxerStream::ParcSplitAt().
  std::optional<base::TimeDelta> SplitAt(base::TimeDelta time,
                                         bool unread,
                                         bool* reader_there);
  // Answers the stream's own pending read from what comes before the split.
  void CompleteStreamRead();

  // reader()'s pending read: answered if it can be, aborted, or given end of
  // stream (the stream shut down or was disabled).
  void CompleteRead();
  void AbortRead();
  void EndRead();
  // After the stream was sought: only reader() reads on.
  void RestartAfterSeek();
  // The hand-off ends. If the stream's reader didn't get its end of stream,
  // what was taken from the stream for the split goes back to it.
  void End();

 private:
  using BufferQueue = base::circular_deque<scoped_refptr<StreamParserBuffer>>;
  class Reader;

  // reader()'s DemuxerStream::Read(); takes the stream's lock.
  void Read(uint32_t count, DemuxerStream::ReadCB read_cb);
  // Moves buffers from the stream into |before_| until the split.
  void PullToSplit();

  const raw_ptr<ChunkDemuxerStream> stream_;
  std::unique_ptr<Reader> reader_;
  std::optional<base::TimeDelta> target_;  // Set by SplitAt().
  bool split_ = false;
  // Once split: where, whether at a config change, whether the stream's
  // reader had read up to it (nothing went into |before_|), and whether that
  // reader got its end of stream; the last two fix the split.
  base::TimeDelta split_time_;
  bool config_split_ = false;
  bool reader_there_ = false;
  bool end_sent_ = false;
  // What the stream's reader gets before the split, and the latest end
  // among them.
  BufferQueue before_;
  base::TimeDelta before_end_ = kNoTimestamp;
  // reader()'s first buffer (end of stream included), or null when the split
  // is at a config change or the stream was unread.
  scoped_refptr<StreamParserBuffer> first_;
  DemuxerStream::ReadCB read_cb_;
  uint32_t count_ = 0;
};

// The streams a renderer taking over reads (ChunkDemuxer::ParcBeginHandOff()),
// each stream's hand-off reader in GetAllStreams()'s order, and the split
// asked for, which waits for the data that places it. ChunkDemuxer owns this
// and calls AskSplit() and ContinueSplit() with its lock held.
class ParcDemuxerHandOff final : public MediaResource {
 public:
  using Streams = std::vector<std::unique_ptr<ChunkDemuxerStream>>;

  explicit ParcDemuxerHandOff(ChunkDemuxer* demuxer);
  ~ParcDemuxerHandOff() override;

  // MediaResource implementation.
  std::vector<raw_ptr<DemuxerStream>> GetAllStreams() final;
  bool ParcMayAddStreams() final;

  // See Demuxer::ParcSplitForHandOff().
  void AskSplit(base::TimeDelta not_before,
                base::OnceCallback<void(base::TimeDelta)> split_cb);
  // Places the split asked for across the enabled streams that started, once
  // the data that places it is there, unless a seek is on its way
  // (|returning_data| false): every stream splits at one video keyframe, with
  // audio within a sample of it. A stream no renderer read yet (a late
  // SourceBuffer's, still in |unstarted_tracks|) then starts there.
  void ContinueSplit(bool returning_data,
                     const Streams& video_streams,
                     const Streams& audio_streams,
                     std::set<MediaTrack::Id>& unstarted_tracks);

 private:
  const raw_ptr<ChunkDemuxer> demuxer_;
  base::TimeDelta split_not_before_;
  base::OnceCallback<void(base::TimeDelta)> split_cb_;
};

}  // namespace media

#endif  // MEDIA_FILTERS_PARC_CHUNK_DEMUXER_HAND_OFF_H_
