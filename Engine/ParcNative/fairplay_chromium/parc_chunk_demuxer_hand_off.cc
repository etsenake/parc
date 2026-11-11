// Copyright 2026 Parc contributors.
// Installed at //media/filters/parc_chunk_demuxer_hand_off.cc.

#include "media/filters/parc_chunk_demuxer_hand_off.h"

#include <utility>

#include "base/check.h"
#include "base/notreached.h"
#include "base/synchronization/lock.h"
#include "base/task/bind_post_task.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/parc_demuxer_stream_extension.h"
#include "media/base/video_decoder_config.h"
#include "media/filters/chunk_demuxer.h"
#include "media/filters/source_buffer_stream.h"

namespace media {

// The incoming renderer's side of a stream's hand-off.
class ParcStreamHandOff::Reader final : public DemuxerStream,
                                        public ParcDemuxerStreamExtension {
 public:
  Reader(ParcStreamHandOff* hand_off, ChunkDemuxerStream* stream)
      : hand_off_(hand_off), stream_(stream) {}

  void Read(uint32_t count, ReadCB read_cb) final {
    hand_off_->Read(count, std::move(read_cb));
  }
  Type type() const final { return stream_->type(); }
  StreamLiveness liveness() const final { return stream_->liveness(); }
  AudioDecoderConfig audio_decoder_config() final {
    return stream_->audio_decoder_config();
  }
  VideoDecoderConfig video_decoder_config() final {
    return stream_->video_decoder_config();
  }
  bool SupportsConfigChanges() final { return true; }
  ParcDemuxerStreamExtension* GetParcExtension() final { return this; }

  // ParcDemuxerStreamExtension methods.
  bool ParcIsEnabled() const final { return stream_->ParcIsEnabled(); }
  DemuxerStream* ParcHandOffSource() final { return stream_; }

 private:
  const raw_ptr<ParcStreamHandOff> hand_off_;
  const raw_ptr<ChunkDemuxerStream> stream_;
};

ParcStreamHandOff::ParcStreamHandOff(ChunkDemuxerStream* stream)
    : stream_(stream), reader_(std::make_unique<Reader>(this, stream)) {}

ParcStreamHandOff::~ParcStreamHandOff() = default;

DemuxerStream* ParcStreamHandOff::reader() {
  return reader_.get();
}

std::optional<base::TimeDelta> ParcStreamHandOff::SplitAt(base::TimeDelta time,
                                                          bool unread,
                                                          bool* reader_there) {
  ChunkDemuxerStream& stream = *stream_;
  stream.lock_.AssertAcquired();
  if (unread) {
    stream.stream_->Seek(time);
    target_ = time;
    split_ = true;
    split_time_ = time;
  } else {
    // A split at a config change stays, as one the stream's reader already
    // read to its end: neither can move.
    const bool fixed = split_ && (config_split_ || end_sent_);
    if (!fixed && (!target_ || *target_ < time)) {
      target_ = time;
      split_ = false;
    }
    PullToSplit();
  }
  if (!split_) {
    return std::nullopt;
  }
  if (reader_there) {
    *reader_there = reader_there_;
  }
  if (stream.read_cb_) {
    stream.CompletePendingReadIfPossible_Locked();
  }
  if (read_cb_) {
    CompleteRead();
  }
  return split_time_;
}

void ParcStreamHandOff::PullToSplit() {
  ChunkDemuxerStream& stream = *stream_;
  stream.lock_.AssertAcquired();
  if (stream.state_ == ChunkDemuxerStream::SHUTDOWN || split_) {
    return;
  }
  const bool video = stream.type_ == DemuxerStream::VIDEO;
  auto starts_after = [&](const StreamParserBuffer& buffer) {
    return buffer.end_of_stream() ||
           (buffer.timestamp() >= *target_ && (!video || buffer.is_key_frame()));
  };
  bool pulled = false;
  while (true) {
    if (first_) {
      if (starts_after(*first_)) {
        break;
      }
      const StreamParserBuffer& taken = *first_;
      if (before_end_ == kNoTimestamp ||
          taken.timestamp() + taken.duration() > before_end_) {
        before_end_ = taken.timestamp() + taken.duration();
      }
      before_.push_back(std::move(first_));
      pulled = true;
    }
    // What an earlier hand-off gave back comes before the stream's buffers.
    if (!stream.parc_returned_.empty()) {
      first_ = std::move(stream.parc_returned_.front());
      stream.parc_returned_.pop_front();
      continue;
    }
    if (stream.stream_->IsNextBufferConfigChanged()) {
      config_split_ = true;
      break;
    }
    scoped_refptr<StreamParserBuffer> buffer;
    switch (stream.stream_->GetNextBuffer(&buffer)) {
      case SourceBufferStreamStatus::kSuccess:
        first_ = std::move(buffer);
        break;
      case SourceBufferStreamStatus::kNeedBuffer:
        return;
      case SourceBufferStreamStatus::kEndOfStream:
        first_ = StreamParserBuffer::CreateEOSBuffer();
        break;
      case SourceBufferStreamStatus::kConfigChange:
        NOTREACHED();  // IsNextBufferConfigChanged() said no.
    }
  }
  split_ = true;
  reader_there_ = !pulled && before_.empty();
  if (first_ && !first_->end_of_stream()) {
    split_time_ = first_->timestamp();
  } else if (before_end_ != kNoTimestamp) {
    split_time_ = before_end_;
  } else {
    split_time_ = *target_;
  }
}

void ParcStreamHandOff::CompleteStreamRead() {
  ChunkDemuxerStream& stream = *stream_;
  stream.lock_.AssertAcquired();
  PullToSplit();
  if (before_.empty() && !split_) {
    return;
  }
  DemuxerStream::DecoderBufferVector out;
  while (!before_.empty() && out.size() < stream.requested_buffer_count_) {
    out.emplace_back(std::move(before_.front()));
    before_.pop_front();
  }
  if (out.empty()) {
    out.emplace_back(StreamParserBuffer::CreateEOSBuffer());
    end_sent_ = true;
  }
  stream.requested_buffer_count_ = 0;
  std::move(stream.read_cb_).Run(DemuxerStream::kOk, std::move(out));
}

void ParcStreamHandOff::Read(uint32_t count, DemuxerStream::ReadCB read_cb) {
  ChunkDemuxerStream& stream = *stream_;
  base::AutoLock auto_lock(stream.lock_);
  DCHECK(!read_cb_);
  read_cb_ = base::BindPostTaskToCurrentDefault(std::move(read_cb));
  count_ = count;
  CompleteRead();
}

void ParcStreamHandOff::CompleteRead() {
  ChunkDemuxerStream& stream = *stream_;
  stream.lock_.AssertAcquired();
  if (!read_cb_) {
    return;
  }
  if (!stream.is_enabled_ || stream.state_ == ChunkDemuxerStream::SHUTDOWN) {
    std::move(read_cb_).Run(DemuxerStream::kOk,
                            {StreamParserBuffer::CreateEOSBuffer()});
    return;
  }
  if (stream.state_ == ChunkDemuxerStream::RETURNING_ABORT_FOR_READS) {
    std::move(read_cb_).Run(DemuxerStream::kAborted, {});
    return;
  }
  if (stream.state_ != ChunkDemuxerStream::RETURNING_DATA_FOR_READS ||
      !split_) {
    return;
  }
  if (first_) {
    std::move(read_cb_).Run(DemuxerStream::kOk, {std::move(first_)});
    return;
  }
  if (!stream.parc_returned_.empty()) {
    std::move(read_cb_).Run(DemuxerStream::kOk,
                            {std::move(stream.parc_returned_.front())});
    stream.parc_returned_.pop_front();
    return;
  }
  auto [status, buffers] = stream.GetPendingBuffers_Locked(count_);
  if (status == SourceBufferStreamStatus::kNeedBuffer && buffers.empty()) {
    return;
  }
  if (status == SourceBufferStreamStatus::kConfigChange) {
    std::move(read_cb_).Run(DemuxerStream::kConfigChanged, {});
    return;
  }
  std::move(read_cb_).Run(DemuxerStream::kOk, std::move(buffers));
}

void ParcStreamHandOff::AbortRead() {
  stream_->lock_.AssertAcquired();
  if (read_cb_) {
    std::move(read_cb_).Run(DemuxerStream::kAborted, {});
  }
}

void ParcStreamHandOff::EndRead() {
  stream_->lock_.AssertAcquired();
  if (read_cb_) {
    std::move(read_cb_).Run(DemuxerStream::kOk,
                            {StreamParserBuffer::CreateEOSBuffer()});
  }
}

void ParcStreamHandOff::RestartAfterSeek() {
  stream_->lock_.AssertAcquired();
  if (target_) {
    before_.clear();
    first_ = nullptr;
    split_ = true;
    end_sent_ = true;
  }
}

void ParcStreamHandOff::End() {
  ChunkDemuxerStream& stream = *stream_;
  stream.lock_.AssertAcquired();
  if (end_sent_) {
    return;
  }
  // The split didn't happen for the stream's reader, which reads on.
  if (first_ && !first_->end_of_stream()) {
    before_.push_back(std::move(first_));
  }
  for (auto& buffer : before_) {
    stream.parc_returned_.push_back(std::move(buffer));
  }
}

ParcDemuxerHandOff::ParcDemuxerHandOff(ChunkDemuxer* demuxer)
    : demuxer_(demuxer) {}

ParcDemuxerHandOff::~ParcDemuxerHandOff() = default;

std::vector<raw_ptr<DemuxerStream>> ParcDemuxerHandOff::GetAllStreams() {
  std::vector<raw_ptr<DemuxerStream>> readers;
  for (DemuxerStream* stream : demuxer_->GetAllStreams()) {
    readers.push_back(
        static_cast<ChunkDemuxerStream*>(stream)->ParcHandOffReader());
  }
  return readers;
}

bool ParcDemuxerHandOff::ParcMayAddStreams() {
  return demuxer_->ParcMayAddStreams();
}

void ParcDemuxerHandOff::AskSplit(
    base::TimeDelta not_before,
    base::OnceCallback<void(base::TimeDelta)> split_cb) {
  split_not_before_ = not_before;
  split_cb_ = std::move(split_cb);
}

void ParcDemuxerHandOff::ContinueSplit(
    bool returning_data,
    const Streams& video_streams,
    const Streams& audio_streams,
    std::set<MediaTrack::Id>& unstarted_tracks) {
  // Not while a seek is on its way: its time decides.
  if (!split_cb_ || !returning_data) {
    return;
  }
  base::TimeDelta at = split_not_before_;
  for (bool moved = true; moved;) {
    moved = false;
    for (bool video : {true, false}) {
      for (const auto& stream : video ? video_streams : audio_streams) {
        if (!stream->IsEnabled() ||
            unstarted_tracks.contains(stream->media_track_id())) {
          continue;
        }
        // Audio splits within a sample of video's keyframe; only audio its
        // renderer already read further moves the split to a later one.
        bool reader_there = false;
        std::optional<base::TimeDelta> split =
            stream->ParcSplitAt(at, false, &reader_there);
        if (!split) {
          return;  // Placed once more data is appended.
        }
        if (*split > at && (video || reader_there)) {
          at = *split;
          moved = true;
        }
      }
    }
  }
  // A stream no renderer read yet (a late SourceBuffer's) starts there.
  for (const Streams* streams : {&audio_streams, &video_streams}) {
    for (const auto& stream : *streams) {
      if (stream->IsEnabled() &&
          unstarted_tracks.erase(stream->media_track_id())) {
        stream->ParcSplitAt(at, true);
      }
    }
  }
  std::move(split_cb_).Run(at);
}

}  // namespace media
