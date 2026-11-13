#include "media/filters/parc_chunk_demuxer_hand_off.h"

#include <algorithm>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/notreached.h"
#include "base/strings/string_util.h"
#include "base/synchronization/lock.h"
#include "base/task/bind_post_task.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/mime_util.h"
#include "media/base/parc_demuxer_stream_extension.h"
#include "media/base/pipeline_metadata.h"
#include "media/base/video_decoder_config.h"
#include "media/filters/chunk_demuxer.h"
#include "media/filters/parc_mse_type_map.h"
#include "media/filters/parc_source_buffer_eviction.h"
#include "media/filters/parc_source_buffer_stream_state.h"
#include "media/filters/source_buffer_state.h"
#include "media/filters/source_buffer_stream.h"

namespace media {

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

DemuxerStream* ParcStreamHandOff::ReaderOf(ChunkDemuxerStream& stream) {
  base::AutoLock auto_lock(stream.lock_);
  if (!stream.parc_stream_hand_off_) {
    stream.parc_stream_hand_off_ = std::make_unique<ParcStreamHandOff>(&stream);
  }
  return stream.parc_stream_hand_off_->reader();
}

std::optional<base::TimeDelta> ParcStreamHandOff::SplitStreamAt(
    ChunkDemuxerStream& stream,
    base::TimeDelta time,
    bool unread,
    bool* reader_there) {
  base::AutoLock auto_lock(stream.lock_);
  if (!stream.parc_stream_hand_off_) {
    stream.parc_stream_hand_off_ = std::make_unique<ParcStreamHandOff>(&stream);
  }
  return stream.parc_stream_hand_off_->SplitAt(time, unread, reader_there);
}

void ParcStreamHandOff::EndStreamHandOff(ChunkDemuxerStream& stream) {
  base::AutoLock auto_lock(stream.lock_);
  if (stream.parc_stream_hand_off_) {
    stream.parc_stream_hand_off_->End();
  }
  stream.parc_stream_hand_off_.reset();
}

void ParcStreamHandOff::RestartStreamAfterSeek(ChunkDemuxerStream& stream) {
  stream.lock_.AssertAcquired();
  stream.parc_returned_.clear();
  if (stream.parc_stream_hand_off_) {
    stream.parc_stream_hand_off_->RestartAfterSeek();
  }
}

void ParcStreamHandOff::ReadReturned(ChunkDemuxerStream& stream) {
  stream.lock_.AssertAcquired();
  DemuxerStream::DecoderBufferVector out;
  while (!stream.parc_returned_.empty() &&
         out.size() < stream.requested_buffer_count_) {
    out.emplace_back(std::move(stream.parc_returned_.front()));
    stream.parc_returned_.pop_front();
  }
  stream.requested_buffer_count_ = 0;
  std::move(stream.read_cb_).Run(DemuxerStream::kOk, std::move(out));
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
        NOTREACHED();
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
        ParcStreamHandOff::ReaderOf(*static_cast<ChunkDemuxerStream*>(stream)));
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
        bool reader_there = false;
        std::optional<base::TimeDelta> split =
            ParcStreamHandOff::SplitStreamAt(*stream, at, false,
                                             &reader_there);
        if (!split) {
          return;
        }
        if (*split > at && (video || reader_there)) {
          at = *split;
          moved = true;
        }
      }
    }
  }
  for (const Streams* streams : {&audio_streams, &video_streams}) {
    for (const auto& stream : *streams) {
      if (stream->IsEnabled() &&
          unstarted_tracks.erase(stream->media_track_id())) {
        ParcStreamHandOff::SplitStreamAt(*stream, at, true);
      }
    }
  }
  std::move(split_cb_).Run(at);
}

ParcChunkDemuxer::ParcChunkDemuxer(ChunkDemuxer* demuxer) : demuxer_(demuxer) {}

ParcChunkDemuxer::~ParcChunkDemuxer() = default;

base::TimeDelta ParcChunkDemuxer::KeyframeAtOrBefore(
    const ChunkDemuxerStream& stream,
    base::TimeDelta time) {
  base::AutoLock auto_lock(stream.lock_);
  return ParcSourceBufferStreamState::KeyframeAtOrBefore(*stream.stream_,
                                                         time);
}

void ParcChunkDemuxer::RemoveBefore(ChunkDemuxerStream& stream,
                                    base::TimeDelta end,
                                    base::TimeDelta duration) {
  base::AutoLock auto_lock(stream.lock_);
  ParcSourceBufferStreamState::RemoveBefore(*stream.stream_, end, duration);
}

void ParcChunkDemuxer::RemoveFrom(ChunkDemuxerStream& stream,
                                  base::TimeDelta start,
                                  base::TimeDelta duration,
                                  base::TimeDelta end) {
  base::AutoLock auto_lock(stream.lock_);
  ParcSourceBufferStreamState::RemoveFrom(*stream.stream_, start, duration,
                                          end);
}

void ParcChunkDemuxer::Remove(ChunkDemuxerStream& stream,
                              base::TimeDelta start,
                              base::TimeDelta end,
                              base::TimeDelta duration) {
  base::AutoLock auto_lock(stream.lock_);
  ParcSourceBufferStreamState::Remove(*stream.stream_, start, end, duration);
}

size_t ParcChunkDemuxer::RemovalSize(ChunkDemuxerStream& stream,
                                     base::TimeDelta start,
                                     base::TimeDelta end,
                                     base::TimeDelta duration) {
  base::AutoLock auto_lock(stream.lock_);
  return ParcSourceBufferStreamState::RemovalSize(*stream.stream_, start, end,
                                                  duration);
}

void ParcChunkDemuxer::SetStreamSafariMediaSource(ChunkDemuxerStream& stream,
                                                  bool safari) {
  base::AutoLock auto_lock(stream.lock_);
  stream.parc_safari_media_source_ = safari;
  if (stream.stream_) {
    ParcSourceBufferStreamState::UseSafariMediaSource(*stream.stream_, safari);
  }
}

void ParcChunkDemuxer::ShareStreamMediaSourceBuffered(
    ChunkDemuxerStream& stream,
    base::TimeDelta start,
    Ranges<base::TimeDelta> audio) {
  base::AutoLock auto_lock(stream.lock_);
  if (!stream.stream_) {
    return;
  }
  ParcSourceBufferStreamState::ShareMediaSourceBuffered(*stream.stream_, start,
                                                        std::move(audio));
  if (stream.read_cb_) {
    stream.CompletePendingReadIfPossible_Locked();
  }
}

void ParcChunkDemuxer::StartStreamAt(ChunkDemuxerStream& stream,
                                     base::TimeDelta time) {
  base::AutoLock auto_lock(stream.lock_);
  if (stream.is_enabled_ && !stream.read_cb_) {
    stream.stream_->Seek(time);
  }
}

bool ParcChunkDemuxer::ParcPrefersFairPlayRenderer() {
  base::AutoLock auto_lock(demuxer_->lock_);
  return clear_dolby_vision_allowed_ && dolby_vision_appended_;
}

void ParcChunkDemuxer::ParcSetFastSeek(base::TimeDelta target,
                                       base::TimeDelta tolerance_before) {
  base::AutoLock auto_lock(demuxer_->lock_);
  if (tolerance_before.is_positive()) {
    requested_fast_seek_ = FastSeek{target, tolerance_before};
  } else {
    requested_fast_seek_.reset();
  }
}

std::optional<base::TimeDelta> ParcChunkDemuxer::ParcTakeFastSeekLanding() {
  base::AutoLock auto_lock(demuxer_->lock_);
  return std::exchange(fast_seek_landing_, std::nullopt);
}

base::TimeDelta ParcChunkDemuxer::FastSeekLanding(
    base::TimeDelta target,
    base::TimeDelta tolerance_before) const {
  demuxer_->lock_.AssertAcquired();
  const base::TimeDelta earliest = target - tolerance_before;
  base::TimeDelta landing = target;
  for (const ChunkDemuxer::OwnedChunkDemuxerStreamVector* streams :
       {&demuxer_->audio_streams_, &demuxer_->video_streams_}) {
    for (const auto& stream : *streams) {
      if (!stream->IsEnabled()) {
        continue;
      }
      const base::TimeDelta keyframe = KeyframeAtOrBefore(*stream, target);
      if (keyframe != kNoTimestamp && keyframe >= earliest &&
          keyframe < landing) {
        landing = keyframe;
      }
    }
  }
  return landing;
}

void ParcChunkDemuxer::TakeFastSeek(base::TimeDelta time) {
  demuxer_->lock_.AssertAcquired();
  fast_seek_.reset();
  fast_seek_landing_.reset();
  if (requested_fast_seek_ && requested_fast_seek_->target == time) {
    fast_seek_ = std::exchange(requested_fast_seek_, std::nullopt);
  }
}

void ParcChunkDemuxer::ComputeActiveEvictionData(base::TimeDelta time) {
  demuxer_->lock_.AssertAcquired();
  for (const auto& entry : demuxer_->source_state_map_) {
    if (ParcSourceBufferEviction::IsActive(*entry.second)) {
      ComputeEvictionData(entry.second.get(), time);
    }
  }
}

void ParcChunkDemuxer::LandTakenFastSeek(PipelineStatus status) {
  demuxer_->lock_.AssertAcquired();
  std::optional<FastSeek> fast_seek = std::exchange(fast_seek_, std::nullopt);
  if (!fast_seek || status != PIPELINE_OK) {
    return;
  }
  ChunkDemuxer& demuxer = *demuxer_;
  base::TimeDelta landing =
      FastSeekLanding(fast_seek->target, fast_seek->tolerance_before);
  if (landing != fast_seek->target) {
    demuxer.AbortPendingReads_Locked();
    demuxer.SeekAllSources(landing);
    if (demuxer.IsSeekWaitingForData_Locked()) {
      demuxer.AbortPendingReads_Locked();
      demuxer.SeekAllSources(fast_seek->target);
      landing = fast_seek->target;
    }
    demuxer.StartReturningData();
  }
  fast_seek_landing_ = landing;
}

MediaResource* ParcChunkDemuxer::ParcBeginHandOff() {
  base::AutoLock auto_lock(demuxer_->lock_);
  if (!demuxer_hand_off_ && safari_media_source_ &&
      (demuxer_->state_ == ChunkDemuxer::INITIALIZED ||
       demuxer_->state_ == ChunkDemuxer::ENDED)) {
    demuxer_hand_off_ = std::make_unique<ParcDemuxerHandOff>(demuxer_);
  }
  return demuxer_hand_off_.get();
}

void ParcChunkDemuxer::ParcSplitForHandOff(
    base::TimeDelta not_before,
    base::OnceCallback<void(base::TimeDelta)> split_cb) {
  base::AutoLock auto_lock(demuxer_->lock_);
  DCHECK(demuxer_hand_off_);
  demuxer_hand_off_->AskSplit(
      not_before, base::BindPostTaskToCurrentDefault(std::move(split_cb)));
  ContinueSplit();
}

void ParcChunkDemuxer::ContinueAskedSplit() {
  demuxer_->lock_.AssertAcquired();
  demuxer_hand_off_->ContinueSplit(returning_data_, demuxer_->video_streams_,
                                   demuxer_->audio_streams_, unstarted_tracks_);
}

void ParcChunkDemuxer::ParcEndHandOff() {
  base::AutoLock auto_lock(demuxer_->lock_);
  for (const auto* streams :
       {&demuxer_->audio_streams_, &demuxer_->video_streams_}) {
    for (const auto& stream : *streams) {
      ParcStreamHandOff::EndStreamHandOff(*stream);
    }
  }
  demuxer_hand_off_.reset();
}

bool ParcChunkDemuxer::CanAddIdAfterInit() const {
  demuxer_->lock_.AssertAcquired();
  return demuxer_->state_ == ChunkDemuxer::INITIALIZED && streams_added_cb_;
}

bool ParcChunkDemuxer::AwaitsLateInit(const std::string& id) const {
  demuxer_->lock_.AssertAcquired();
  return streams_added_cb_ &&
         (demuxer_->state_ == ChunkDemuxer::INITIALIZED ||
          demuxer_->state_ == ChunkDemuxer::ENDED) &&
         demuxer_->pending_source_init_ids_.contains(id);
}

void ParcChunkDemuxer::ConfigureSourceState(SourceBufferState& state) {
  ParcSourceBufferEviction::SetClearDolbyVisionAllowed(
      state, clear_dolby_vision_allowed_);
  ParcSourceBufferEviction::SetDolbyVisionCallback(
      state, base::BindRepeating(&ParcChunkDemuxer::OnDolbyVisionAppended,
                                 base::Unretained(this)));
  ParcSourceBufferEviction::SetSafariInitSegmentRules(
      state, safari_init_segment_rules_);
}

void ParcChunkDemuxer::OnDolbyVisionAppended() {
  demuxer_->lock_.AssertAcquired();
  if (std::exchange(dolby_vision_appended_, true) ||
      !clear_dolby_vision_allowed_) {
    return;
  }
  if (dolby_vision_appended_cb_) {
    dolby_vision_appended_cb_.Run();
  }
}

Demuxer::EncryptedMediaInitDataCB ParcChunkDemuxer::InitDataCB(
    const std::string& id) {
  return base::BindRepeating(&ParcChunkDemuxer::OnInitData,
                             base::Unretained(this), id);
}

void ParcChunkDemuxer::OnInitData(const std::string& id,
                                  EmeInitDataType type,
                                  const std::vector<uint8_t>& data) {
  if (source_key_cb_ &&
      (type == EmeInitDataType::SINF || type == EmeInitDataType::MPTS)) {
    source_key_cb_.Run(id, type, data);
    return;
  }
  demuxer_->encrypted_media_init_data_cb_.Run(type, data);
}

void ParcChunkDemuxer::OnRemoveId(const std::string& id) {
  if (source_key_cb_) {
    source_key_cb_.Run(id, EmeInitDataType::UNKNOWN, {});
  }
}

void ParcChunkDemuxer::ShareKnownMediaSourceBuffered(bool seek_was_waiting) {
  ChunkDemuxer& demuxer = *demuxer_;
  demuxer.lock_.AssertAcquired();
  if (demuxer.duration_ == kNoTimestamp) {
    return;
  }
  Ranges<base::TimeDelta> buffered;
  Ranges<base::TimeDelta> audio;
  MediaSourceRanges(&buffered, &audio);
  const base::TimeDelta start =
      buffered.empty() ? kNoTimestamp : buffered.start(0);
  for (const auto& stream : demuxer.audio_streams_) {
    ShareStreamMediaSourceBuffered(*stream, start, Ranges<base::TimeDelta>());
  }
  for (const auto& stream : demuxer.video_streams_) {
    ShareStreamMediaSourceBuffered(*stream, start, audio);
  }
  if (seek_was_waiting && !demuxer.IsSeekWaitingForData_Locked() &&
      demuxer.seek_cb_) {
    demuxer.RunSeekCB_Locked(PIPELINE_OK);
  }
}

bool ParcChunkDemuxer::ChangeEnabledAudioTracks(
    base::TimeDelta curr_time,
    bool seek_was_waiting,
    Demuxer::TrackChangeCB& change_completed_cb) {
  demuxer_->lock_.AssertAcquired();
  ChunkDemuxerStream* enabled_stream = nullptr;
  for (const auto& stream : demuxer_->audio_streams_) {
    if (audio_tracks_to_enable_) {
      stream->SetEnabled(
          audio_tracks_to_enable_->contains(stream->media_track_id()),
          curr_time);
    }
    if (!enabled_stream && stream->IsEnabled()) {
      enabled_stream = stream.get();
    }
  }
  audio_tracks_to_enable_.reset();
  AfterTracksChanged(DemuxerStream::AUDIO, curr_time, seek_was_waiting);
  std::move(change_completed_cb).Run(enabled_stream);
  return true;
}

void ParcChunkDemuxer::AfterTracksChanged(DemuxerStream::Type track_type,
                                          base::TimeDelta curr_time,
                                          bool seek_was_waiting) {
  ChunkDemuxer& demuxer = *demuxer_;
  demuxer.lock_.AssertAcquired();
  for (const auto& stream : track_type == DemuxerStream::AUDIO
                                ? demuxer.audio_streams_
                                : demuxer.video_streams_) {
    if (stream->IsEnabled() &&
        unstarted_tracks_.erase(stream->media_track_id())) {
      StartStreamAt(*stream, curr_time);
    }
  }
  ShareMediaSourceBuffered(seek_was_waiting);
  for (const auto& entry : demuxer.source_state_map_) {
    if (ParcSourceBufferEviction::PurgedWhileInactive(*entry.second)) {
      demuxer.host_->OnBufferedTimeRangesChanged(
          demuxer.GetBufferedRanges_Locked());
      break;
    }
  }
}

std::optional<StreamParserFactory::ParcSafariType>
ParcChunkDemuxer::SafariMediaSourceType(const std::string& content_type,
                                        const std::string& codecs) {
  std::vector<std::string> parsed_codec_ids;
  SplitCodecs(codecs, &parsed_codec_ids);
  return StreamParserFactory::ParcSafariMediaSourceType(
      base::ToLowerASCII(content_type), parsed_codec_ids);
}

std::unique_ptr<StreamParser> ParcChunkDemuxer::CreateSafariParser(
    const std::string& content_type,
    const std::string& codecs) {
  demuxer_->lock_.AssertAcquired();
  std::optional<StreamParserFactory::ParcSafariType> safari_type =
      SafariMediaSourceType(content_type, codecs);
  if (!safari_type) {
    return nullptr;
  }
  if (ParcIsSafariOggType(safari_type->type)) {
    return ParcCreateSafariOggParser(safari_type->type, safari_type->codecs);
  }
  std::unique_ptr<StreamParser> stream_parser = StreamParserFactory::Create(
      safari_type->type, safari_type->codecs, demuxer_->media_log_.get());
  if (!stream_parser && safari_type->codecs.empty()) {
    stream_parser = ParcCreateMseParserWithoutCodecs(safari_type->type);
  }
  return stream_parser;
}

bool ParcChunkDemuxer::ChangeTypeAllowed(const std::string& content_type,
                                         const std::string& codecs) {
  demuxer_->lock_.AssertAcquired();
  std::string filter_type = content_type;
  std::string filter_codecs = codecs;
  if (safari_init_segment_rules_) {
    std::optional<StreamParserFactory::ParcSafariType> safari_type =
        SafariMediaSourceType(content_type, codecs);
    if (!safari_type) {
      return false;
    }
    filter_type = safari_type->type;
    filter_codecs = base::JoinString(safari_type->codecs, ",");
  }
  return !change_type_filter_ ||
         change_type_filter_.Run(filter_type, filter_codecs);
}

bool ParcChunkDemuxer::EvictCodedFrames(SourceBufferState* state,
                                        base::TimeDelta media_time,
                                        size_t new_data_size) {
  ChunkDemuxer& demuxer = *demuxer_;
  demuxer.lock_.AssertAcquired();
  const bool seek_was_waiting = demuxer.IsSeekWaitingForData_Locked();
  bool evicted;
  if (safari_eviction_) {
    ParcSourceBufferEviction& eviction = ParcSourceBufferEviction::Of(*state);
    evicted = true;
    if (eviction.IsBufferFullFor(*state, new_data_size)) {
      const bool can_append = eviction.CanAppend(*state, new_data_size);
      Ranges<base::TimeDelta> buffered;
      Ranges<base::TimeDelta> audio;
      MediaSourceRanges(&buffered, &audio);
      const bool still_full = eviction.EvictFrames(
          *state, media_time, new_data_size,
          demuxer.duration_ == kNoTimestamp ? kInfiniteDuration
                                            : demuxer.duration_,
          buffered, audio, false);
      ComputeEvictionData(state, media_time);
      evicted = can_append || !still_full;
    }
  } else {
    evicted = state->EvictCodedFrames(media_time, new_data_size);
  }
  ShareMediaSourceBuffered(seek_was_waiting);
  return evicted;
}

void ParcChunkDemuxer::OnLateSourceInitDone(
    const std::string& source_id,
    const StreamParser::InitParameters& params) {
  ChunkDemuxer& demuxer = *demuxer_;
  demuxer.lock_.AssertAcquired();
  demuxer.pending_source_init_ids_.erase(source_id);
  SourceBufferState* source_state =
      demuxer.source_state_map_[source_id].get();
  if (returning_data_) {
    source_state->Seek(seek_time_);
    source_state->StartReturningData();
  } else {
    source_state->AbortReads();
  }

  const std::vector<raw_ptr<ChunkDemuxerStream>>& streams =
      demuxer.id_to_streams_map_[source_id];
  const bool other_audio = std::ranges::any_of(
      demuxer.audio_streams_,
      [&](const std::unique_ptr<ChunkDemuxerStream>& stream) {
        return stream->IsEnabled() &&
               std::ranges::find(streams, stream.get()) == streams.end();
      });
  PipelineMetadata added;
  std::vector<ChunkDemuxer::ParcAddedTrack> tracks;
  for (ChunkDemuxerStream* stream : streams) {
    if (params.liveness != StreamLiveness::kUnknown) {
      stream->SetLiveness(params.liveness);
    }
    if (!stream->IsEnabled()) {
      continue;
    }
    tracks.push_back({stream->type(), stream->media_track_id()});
    unstarted_tracks_.insert(stream->media_track_id());
    if (stream->type() == DemuxerStream::AUDIO) {
      if (!other_audio) {
        added.has_audio = true;
        added.audio_decoder_config = stream->audio_decoder_config();
      }
    } else if (stream->type() == DemuxerStream::VIDEO) {
      added.has_video = true;
      added.video_decoder_config = stream->video_decoder_config();
    }
  }
  if (!tracks.empty()) {
    streams_added_cb_.Run(added, tracks);
  }
}

bool ParcChunkDemuxer::InitiallyEnabled(const std::string& source_id,
                                        DemuxerStream::Type type,
                                        MediaTrack::Id media_track_id,
                                        bool first_of_type) {
  demuxer_->lock_.AssertAcquired();
  bool enabled = first_of_type;
  if (safari_media_source_ && type == DemuxerStream::AUDIO) {
    enabled = std::ranges::none_of(
        demuxer_->id_to_streams_map_[source_id], [](ChunkDemuxerStream* other) {
          return other->type() == DemuxerStream::AUDIO;
        });
  }
  if (enabled && type == DemuxerStream::AUDIO && audio_tracks_to_enable_) {
    audio_tracks_to_enable_->insert(media_track_id);
  }
  return enabled;
}

void ParcChunkDemuxer::ConfigureStream(ChunkDemuxerStream& stream) {
  SetStreamSafariMediaSource(stream, safari_media_source_);
}

void ParcChunkDemuxer::MediaSourceRanges(Ranges<base::TimeDelta>* buffered,
                                         Ranges<base::TimeDelta>* audio) const {
  const ChunkDemuxer& demuxer = *demuxer_;
  demuxer.lock_.AssertAcquired();
  const bool ended = demuxer.state_ == ChunkDemuxer::ENDED;
  SourceBufferState::RangesList active_ranges;
  for (const auto& entry : demuxer.source_state_map_) {
    const SourceBufferState* state = entry.second.get();
    if (!ParcSourceBufferEviction::IsActive(*state)) {
      continue;
    }
    active_ranges.push_back(state->GetBufferedRanges(demuxer.duration_, ended));
    const Ranges<base::TimeDelta> state_audio =
        ParcSourceBufferEviction::AudioBufferedRanges(*state,
                                                      demuxer.duration_);
    for (size_t i = 0; i < state_audio.size(); ++i) {
      audio->Add(state_audio.start(i), state_audio.end(i));
    }
  }
  *buffered =
      SourceBufferState::ComputeRangesIntersection(active_ranges, ended);
}

void ParcChunkDemuxer::ComputeEvictionData(SourceBufferState* state,
                                           base::TimeDelta media_time) {
  const ChunkDemuxer& demuxer = *demuxer_;
  demuxer.lock_.AssertAcquired();
  if (!safari_eviction_) {
    return;
  }
  Ranges<base::TimeDelta> buffered;
  Ranges<base::TimeDelta> audio;
  MediaSourceRanges(&buffered, &audio);
  ParcSourceBufferEviction::Of(*state).ComputeEvictionData(
      *state, media_time,
      demuxer.duration_ == kNoTimestamp ? kInfiniteDuration : demuxer.duration_,
      buffered, audio);
}

ParcDemuxerStreamExtension* ChunkDemuxerStream::GetParcExtension() {
  return this;
}

bool ChunkDemuxerStream::ParcIsEnabled() const {
  return IsEnabled();
}

DemuxerStream* ChunkDemuxerStream::ParcHandOffSource() {
  return this;
}

ParcDemuxerExtension* ChunkDemuxer::GetParcExtension() {
  return parc_.get();
}

bool ChunkDemuxer::ParcMayAddStreams() {
  base::AutoLock auto_lock(lock_);
  return !parc_->streams_added_cb_.is_null();
}

void ChunkDemuxer::ParcSetSourceKeyCallback(ParcSourceKeyCB callback) {
  base::AutoLock auto_lock(lock_);
  parc_->source_key_cb_ = std::move(callback);
}

void ChunkDemuxer::RestrictCanChangeType(ChangeTypeFilter filter) {
  base::AutoLock auto_lock(lock_);
  parc_->change_type_filter_ = std::move(filter);
}

void ChunkDemuxer::ParcSetSafariEviction(bool enabled) {
  base::AutoLock auto_lock(lock_);
  parc_->safari_eviction_ = enabled;
}

void ChunkDemuxer::ParcSetClearDolbyVisionAllowed(bool allowed) {
  base::AutoLock auto_lock(lock_);
  parc_->clear_dolby_vision_allowed_ = allowed;
  for (auto& entry : source_state_map_) {
    ParcSourceBufferEviction::SetClearDolbyVisionAllowed(*entry.second,
                                                         allowed);
  }
}

void ChunkDemuxer::ParcSetSafariInitSegmentRules(bool safari) {
  base::AutoLock auto_lock(lock_);
  parc_->safari_init_segment_rules_ = safari;
}

void ChunkDemuxer::ParcSetDolbyVisionAppendedCallback(
    base::RepeatingClosure callback) {
  base::AutoLock auto_lock(lock_);
  parc_->dolby_vision_appended_cb_ = std::move(callback);
}

void ChunkDemuxer::ParcAllowSourceBuffersAfterInit(
    ParcStreamsAddedCB streams_added_cb) {
  base::AutoLock auto_lock(lock_);
  parc_->streams_added_cb_ = std::move(streams_added_cb);
}

void ChunkDemuxer::ParcSetEnabledAudioTracks(
    const std::vector<MediaTrack::Id>& tracks) {
  base::AutoLock auto_lock(lock_);
  parc_->audio_tracks_to_enable_.emplace(tracks.begin(), tracks.end());
}

void ChunkDemuxer::ParcSetSafariMediaSource(bool safari) {
  base::AutoLock auto_lock(lock_);
  const bool seek_was_waiting = IsSeekWaitingForData_Locked();
  parc_->safari_media_source_ = safari;
  for (const OwnedChunkDemuxerStreamVector* streams :
       {&audio_streams_, &video_streams_}) {
    for (const auto& stream : *streams) {
      ParcChunkDemuxer::SetStreamSafariMediaSource(*stream, safari);
    }
  }
  parc_->ShareMediaSourceBuffered(seek_was_waiting);
}

std::optional<ChunkDemuxer::ParcBufferedState>
ChunkDemuxer::ParcGetBufferedState() const {
  base::AutoLock auto_lock(lock_);
  if (state_ == WAITING_FOR_INIT || state_ == PARSE_ERROR ||
      state_ == SHUTDOWN || duration_ == kNoTimestamp) {
    return std::nullopt;
  }
  ParcBufferedState result;
  result.buffered = GetBufferedRanges_Locked();
  for (const auto& entry : source_state_map_) {
    if (!ParcSourceBufferEviction::IsActive(*entry.second)) {
      continue;
    }
    const Ranges<base::TimeDelta> audio =
        ParcSourceBufferEviction::AudioBufferedRanges(*entry.second,
                                                      duration_);
    for (size_t i = 0; i < audio.size(); ++i) {
      result.audio.Add(audio.start(i), audio.end(i));
    }
  }
  result.duration = duration_;
  result.ended = state_ == ENDED;
  return result;
}

void ChunkDemuxer::ParcPurgeForMemoryPressure(const std::string& id,
                                              base::TimeDelta media_time,
                                              bool active) {
  DVLOG(1) << __func__ << "(" << id << ", " << media_time.InSecondsF() << ", "
           << active << ")";
  base::AutoLock auto_lock(lock_);

  auto itr = source_state_map_.find(id);
  if (itr == source_state_map_.end() || state_ == SHUTDOWN ||
      duration_ == kNoTimestamp) {
    return;
  }
  Ranges<base::TimeDelta> buffered;
  Ranges<base::TimeDelta> audio;
  parc_->MediaSourceRanges(&buffered, &audio);
  const bool seek_was_waiting = IsSeekWaitingForData_Locked();
  ParcSourceBufferEviction::Of(*itr->second)
      .PurgeForMemoryPressure(*itr->second, media_time, active, duration_,
                              buffered, audio, parc_->safari_eviction_);
  parc_->ComputeEvictionData(itr->second.get(), media_time);
  parc_->ShareMediaSourceBuffered(seek_was_waiting);
  host_->OnBufferedTimeRangesChanged(GetBufferedRanges_Locked());
}

void ChunkDemuxer::ParcUpdateEvictionData(const std::string& id,
                                          base::TimeDelta media_time) {
  base::AutoLock auto_lock(lock_);
  auto itr = source_state_map_.find(id);
  if (itr != source_state_map_.end() && state_ != SHUTDOWN) {
    parc_->ComputeEvictionData(itr->second.get(), media_time);
  }
}

}
