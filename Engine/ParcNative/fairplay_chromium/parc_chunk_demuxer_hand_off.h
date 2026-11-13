#ifndef MEDIA_FILTERS_PARC_CHUNK_DEMUXER_HAND_OFF_H_
#define MEDIA_FILTERS_PARC_CHUNK_DEMUXER_HAND_OFF_H_

#include <stddef.h>
#include <stdint.h>

#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/containers/circular_deque.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/time/time.h"
#include "media/base/demuxer.h"
#include "media/base/demuxer_stream.h"
#include "media/base/media_export.h"
#include "media/base/media_resource.h"
#include "media/base/media_track.h"
#include "media/base/parc_demuxer_extension.h"
#include "media/base/pipeline_status.h"
#include "media/base/ranges.h"
#include "media/base/stream_parser.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/timestamp_constants.h"
#include "media/filters/chunk_demuxer.h"
#include "media/filters/parc_source_buffer_eviction.h"
#include "media/filters/stream_parser_factory.h"

namespace media {

class SourceBufferState;

class MEDIA_EXPORT ParcStreamHandOff {
 public:
  explicit ParcStreamHandOff(ChunkDemuxerStream* stream);
  ParcStreamHandOff(const ParcStreamHandOff&) = delete;
  ParcStreamHandOff& operator=(const ParcStreamHandOff&) = delete;
  ~ParcStreamHandOff();

  static DemuxerStream* ReaderOf(ChunkDemuxerStream& stream);
  static std::optional<base::TimeDelta> SplitStreamAt(
      ChunkDemuxerStream& stream,
      base::TimeDelta time,
      bool unread,
      bool* reader_there = nullptr);
  static void EndStreamHandOff(ChunkDemuxerStream& stream);
  static void RestartStreamAfterSeek(ChunkDemuxerStream& stream);
  static void ReadReturned(ChunkDemuxerStream& stream);

  DemuxerStream* reader();
  bool split_asked() const { return target_.has_value(); }

  std::optional<base::TimeDelta> SplitAt(base::TimeDelta time,
                                         bool unread,
                                         bool* reader_there);
  void CompleteStreamRead();

  void CompleteRead();
  void AbortRead();
  void EndRead();
  void RestartAfterSeek();
  void End();

 private:
  using BufferQueue = base::circular_deque<scoped_refptr<StreamParserBuffer>>;
  class Reader;

  void Read(uint32_t count, DemuxerStream::ReadCB read_cb);
  void PullToSplit();

  const raw_ptr<ChunkDemuxerStream> stream_;
  std::unique_ptr<Reader> reader_;
  std::optional<base::TimeDelta> target_;
  bool split_ = false;
  base::TimeDelta split_time_;
  bool config_split_ = false;
  bool reader_there_ = false;
  bool end_sent_ = false;
  BufferQueue before_;
  base::TimeDelta before_end_ = kNoTimestamp;
  scoped_refptr<StreamParserBuffer> first_;
  DemuxerStream::ReadCB read_cb_;
  uint32_t count_ = 0;
};

class ParcDemuxerHandOff final : public MediaResource {
 public:
  using Streams = std::vector<std::unique_ptr<ChunkDemuxerStream>>;

  explicit ParcDemuxerHandOff(ChunkDemuxer* demuxer);
  ~ParcDemuxerHandOff() override;

  std::vector<raw_ptr<DemuxerStream>> GetAllStreams() final;
  bool ParcMayAddStreams() final;

  void AskSplit(base::TimeDelta not_before,
                base::OnceCallback<void(base::TimeDelta)> split_cb);
  void ContinueSplit(bool returning_data,
                     const Streams& video_streams,
                     const Streams& audio_streams,
                     std::set<MediaTrack::Id>& unstarted_tracks);

 private:
  const raw_ptr<ChunkDemuxer> demuxer_;
  base::TimeDelta split_not_before_;
  base::OnceCallback<void(base::TimeDelta)> split_cb_;
};

class MEDIA_EXPORT ParcChunkDemuxer final : public ParcDemuxerExtension {
 public:
  explicit ParcChunkDemuxer(ChunkDemuxer* demuxer);
  ParcChunkDemuxer(const ParcChunkDemuxer&) = delete;
  ParcChunkDemuxer& operator=(const ParcChunkDemuxer&) = delete;
  ~ParcChunkDemuxer() override;

  static base::TimeDelta KeyframeAtOrBefore(const ChunkDemuxerStream& stream,
                                            base::TimeDelta time);
  static void RemoveBefore(ChunkDemuxerStream& stream,
                           base::TimeDelta end,
                           base::TimeDelta duration);
  static void RemoveFrom(ChunkDemuxerStream& stream,
                         base::TimeDelta start,
                         base::TimeDelta duration,
                         base::TimeDelta end = kInfiniteDuration);
  static void Remove(ChunkDemuxerStream& stream,
                     base::TimeDelta start,
                     base::TimeDelta end,
                     base::TimeDelta duration);
  static size_t RemovalSize(ChunkDemuxerStream& stream,
                            base::TimeDelta start,
                            base::TimeDelta end,
                            base::TimeDelta duration);

  bool ParcPrefersFairPlayRenderer() override;
  void ParcSetFastSeek(base::TimeDelta target,
                       base::TimeDelta tolerance_before) override;
  std::optional<base::TimeDelta> ParcTakeFastSeekLanding() override;
  MediaResource* ParcBeginHandOff() override;
  void ParcSplitForHandOff(
      base::TimeDelta not_before,
      base::OnceCallback<void(base::TimeDelta)> split_cb) override;
  void ParcEndHandOff() override;

  bool safari_init_segment_rules() const { return safari_init_segment_rules_; }
  void set_returning_data(bool returning_data) {
    returning_data_ = returning_data;
  }
  void OnSeekAllSources(base::TimeDelta seek_time) {
    seek_time_ = seek_time;
    unstarted_tracks_.clear();
  }
  void CancelFastSeek() { fast_seek_.reset(); }
  void TakeFastSeek(base::TimeDelta time);
  void OnSeek(base::TimeDelta time) {
    if (safari_eviction_) {
      ComputeActiveEvictionData(time);
    }
  }
  void LandFastSeek(PipelineStatus status) {
    if (fast_seek_) {
      LandTakenFastSeek(status);
    }
  }
  bool CanAddIdAfterInit() const;
  void ConfigureSourceState(SourceBufferState& state);
  Demuxer::EncryptedMediaInitDataCB InitDataCB(const std::string& id);
  void OnRemoveId(const std::string& id);
  void ShareMediaSourceBuffered(bool seek_was_waiting) {
    if (safari_media_source_) {
      ShareKnownMediaSourceBuffered(seek_was_waiting);
    }
  }
  bool ChangeAllAudioTracks(DemuxerStream::Type track_type,
                            base::TimeDelta curr_time,
                            bool seek_was_waiting,
                            Demuxer::TrackChangeCB& change_completed_cb) {
    return track_type == DemuxerStream::AUDIO && safari_media_source_ &&
           ChangeEnabledAudioTracks(curr_time, seek_was_waiting,
                                    change_completed_cb);
  }
  void AfterTracksChanged(DemuxerStream::Type track_type,
                          base::TimeDelta curr_time,
                          bool seek_was_waiting);
  std::unique_ptr<StreamParser> CreateSafariParser(
      const std::string& content_type,
      const std::string& codecs);
  bool ChangeTypeAllowed(const std::string& content_type,
                         const std::string& codecs);
  bool EvictCodedFrames(SourceBufferState* state,
                        base::TimeDelta media_time,
                        size_t new_data_size);
  void ContinueSplit() {
    if (demuxer_hand_off_) {
      ContinueAskedSplit();
    }
  }
  void ReportProgress() {
    if (safari_init_segment_rules_) {
      demuxer_->progress_cb_.Run();
    }
  }
  void OnLateSourceInitDone(const std::string& source_id,
                            const StreamParser::InitParameters& params);
  bool InitiallyEnabled(const std::string& source_id,
                        DemuxerStream::Type type,
                        MediaTrack::Id media_track_id,
                        bool first_of_type);
  void ConfigureStream(ChunkDemuxerStream& stream);
  bool LeftOutOfBufferedRanges(const std::string& id,
                               const SourceBufferState& state) const {
    return ParcSourceBufferEviction::LeftOutOfMediaSource(state) ||
           (streams_added_cb_ && AwaitsLateInit(id));
  }

 private:
  friend class ChunkDemuxer;

  struct FastSeek {
    base::TimeDelta target;
    base::TimeDelta tolerance_before;
  };

  static void SetStreamSafariMediaSource(ChunkDemuxerStream& stream,
                                         bool safari);
  static void ShareStreamMediaSourceBuffered(ChunkDemuxerStream& stream,
                                             base::TimeDelta start,
                                             Ranges<base::TimeDelta> audio);
  static void StartStreamAt(ChunkDemuxerStream& stream, base::TimeDelta time);
  static std::optional<StreamParserFactory::ParcSafariType>
  SafariMediaSourceType(const std::string& content_type,
                        const std::string& codecs);

  void ComputeActiveEvictionData(base::TimeDelta time);
  void LandTakenFastSeek(PipelineStatus status);
  void ShareKnownMediaSourceBuffered(bool seek_was_waiting);
  bool ChangeEnabledAudioTracks(base::TimeDelta curr_time,
                                bool seek_was_waiting,
                                Demuxer::TrackChangeCB& change_completed_cb);
  void ContinueAskedSplit();
  void OnInitData(const std::string& id,
                  EmeInitDataType type,
                  const std::vector<uint8_t>& data);
  void OnDolbyVisionAppended();
  bool AwaitsLateInit(const std::string& id) const;
  void MediaSourceRanges(Ranges<base::TimeDelta>* buffered,
                         Ranges<base::TimeDelta>* audio) const;
  void ComputeEvictionData(SourceBufferState* state,
                           base::TimeDelta media_time);
  base::TimeDelta FastSeekLanding(base::TimeDelta target,
                                  base::TimeDelta tolerance_before) const;

  const raw_ptr<ChunkDemuxer> demuxer_;
  ChunkDemuxer::ParcSourceKeyCB source_key_cb_;
  ChunkDemuxer::ChangeTypeFilter change_type_filter_;
  bool clear_dolby_vision_allowed_ = false;
  bool dolby_vision_appended_ = false;
  base::RepeatingClosure dolby_vision_appended_cb_;
  bool safari_init_segment_rules_ = false;
  bool safari_eviction_ = false;
  ChunkDemuxer::ParcStreamsAddedCB streams_added_cb_;
  bool returning_data_ = false;
  base::TimeDelta seek_time_;
  std::set<MediaTrack::Id> unstarted_tracks_;
  std::optional<std::set<MediaTrack::Id>> audio_tracks_to_enable_;
  bool safari_media_source_ = false;
  std::unique_ptr<ParcDemuxerHandOff> demuxer_hand_off_;
  std::optional<FastSeek> requested_fast_seek_;
  std::optional<FastSeek> fast_seek_;
  std::optional<base::TimeDelta> fast_seek_landing_;
};

}

#endif
