#include "content/renderer/media/fairplay/native_hls_demuxer.h"

#include <algorithm>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/task/bind_post_task.h"
#include "base/logging.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/cdm_context.h"
#include "media/base/channel_layout.h"
#include "media/base/decoder_buffer.h"
#include "media/base/demuxer_stream.h"
#include "media/base/eme_constants.h"
#include "media/base/encryption_scheme.h"
#include "media/base/media_log.h"
#include "media/base/media_track.h"
#include "media/base/ranges.h"
#include "media/base/sample_format.h"
#include "media/base/timestamp_constants.h"
#include "media/base/video_decoder_config.h"
#include "media/base/video_transformation.h"
#include "media/base/video_types.h"
#include "ui/gfx/geometry/rect.h"

namespace parc::fairplay {

namespace {

media::ParcInbandTextCue::Type ToParcCueType(
    media::mojom::FairPlayHlsCueType type) {
  switch (type) {
    case media::mojom::FairPlayHlsCueType::kWebVttHeader:
      return media::ParcInbandTextCue::Type::kWebVttHeader;
    case media::mojom::FairPlayHlsCueType::kWebVtt:
      return media::ParcInbandTextCue::Type::kWebVtt;
    case media::mojom::FairPlayHlsCueType::kAdd:
      return media::ParcInbandTextCue::Type::kAdd;
    case media::mojom::FairPlayHlsCueType::kUpdate:
      return media::ParcInbandTextCue::Type::kUpdate;
    case media::mojom::FairPlayHlsCueType::kRemove:
      return media::ParcInbandTextCue::Type::kRemove;
  }
  return media::ParcInbandTextCue::Type::kAdd;
}

media::ParcInbandTextCue::Align ToParcCueAlign(
    media::mojom::FairPlayHlsCueAlign align) {
  switch (align) {
    case media::mojom::FairPlayHlsCueAlign::kNone:
      return media::ParcInbandTextCue::Align::kNone;
    case media::mojom::FairPlayHlsCueAlign::kStart:
      return media::ParcInbandTextCue::Align::kStart;
    case media::mojom::FairPlayHlsCueAlign::kMiddle:
      return media::ParcInbandTextCue::Align::kMiddle;
    case media::mojom::FairPlayHlsCueAlign::kEnd:
      return media::ParcInbandTextCue::Align::kEnd;
  }
  return media::ParcInbandTextCue::Align::kNone;
}

media::Ranges<base::TimeDelta> ToRanges(
    const std::vector<media::mojom::FairPlayHlsTimeRangePtr>& ranges) {
  media::Ranges<base::TimeDelta> result;
  for (const auto& range : ranges) {
    if (range && range->start < range->end) {
      result.Add(range->start, range->end);
    }
  }
  return result;
}

}  // namespace

base::TimeDelta InterpolateNativeHlsTime(base::TimeDelta time,
                                         double rate,
                                         base::TimeTicks capture_time,
                                         base::TimeTicks now,
                                         base::TimeDelta duration) {
  base::TimeDelta result = time;
  if (rate > 0 && !capture_time.is_null() && now > capture_time) {
    result += (now - capture_time) * rate;
  }
  if (result < base::TimeDelta()) {
    result = base::TimeDelta();
  }
  if (duration != media::kInfiniteDuration && duration > base::TimeDelta() &&
      result > duration) {
    result = duration;
  }
  return result;
}

// One kind's stream as AVFoundation describes it. The renderer facade never
// reads it: AVPlayer decodes and presents in the GPU process.
class NativeHlsDemuxer::PlaceholderStream final : public media::DemuxerStream {
 public:
  explicit PlaceholderStream(media::AudioDecoderConfig config)
      : type_(AUDIO), audio_config_(std::move(config)) {}
  explicit PlaceholderStream(media::VideoDecoderConfig config)
      : type_(VIDEO), video_config_(std::move(config)) {}

  // media::DemuxerStream.
  void Read(uint32_t count, ReadCB read_cb) override {
    DLOG(ERROR) << "Native HLS streams carry no buffers";
    std::move(read_cb).Run(kAborted, {});
  }
  media::AudioDecoderConfig audio_decoder_config() override {
    return audio_config_;
  }
  media::VideoDecoderConfig video_decoder_config() override {
    return video_config_;
  }
  Type type() const override { return type_; }
  bool SupportsConfigChanges() override { return false; }

 private:
  const Type type_;
  media::AudioDecoderConfig audio_config_;
  media::VideoDecoderConfig video_config_;
};

NativeHlsDemuxer::NativeHlsDemuxer(
    media::ParcNativeHlsDemuxerParams params,
    mojo::PendingRemote<media::mojom::FairPlayHlsPlayer> player,
    mojo::PendingReceiver<media::mojom::FairPlayHlsPlayerClient> client)
    : url_(std::move(params.url)),
      mime_type_(std::move(params.mime_type)),
      media_task_runner_(std::move(params.media_task_runner)),
      media_log_(media::MediaLog::CloneSafely(params.media_log)),
      encrypted_media_init_data_cb_(
          std::move(params.encrypted_media_init_data_cb)),
      key_request_cb_(std::move(params.key_request_cb)),
      start_load_cb_(std::move(params.start_load_cb)),
      track_manager_(std::move(params.track_manager)),
      pending_player_(std::move(player)),
      pending_client_receiver_(std::move(client)) {
  DETACH_FROM_SEQUENCE(sequence_checker_);
}

NativeHlsDemuxer::~NativeHlsDemuxer() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
}

std::vector<raw_ptr<media::DemuxerStream>> NativeHlsDemuxer::GetAllStreams() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  std::vector<raw_ptr<media::DemuxerStream>> streams;
  for (const auto& stream : streams_) {
    streams.push_back(stream.get());
  }
  return streams;
}

NativeHlsSource* NativeHlsDemuxer::GetParcNativeHlsSource() {
  return this;
}

std::string NativeHlsDemuxer::GetDisplayName() const {
  return "NativeHlsDemuxer";
}

media::DemuxerType NativeHlsDemuxer::GetDemuxerType() const {
  // HLS from a manifest: DemuxerManager deletes it on the media thread, where
  // its pipes are bound, and metrics count it as HLS.
  return media::DemuxerType::kManifestDemuxer;
}

void NativeHlsDemuxer::Initialize(media::DemuxerHost* host,
                                  media::PipelineStatusCallback status_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  DCHECK(media_task_runner_->RunsTasksInCurrentSequence());
  DCHECK(!host_);
  host_ = host;
  init_cb_ = std::move(status_cb);

  if (!pending_player_ || !pending_client_receiver_) {
    std::move(init_cb_).Run(media::DEMUXER_ERROR_COULD_NOT_OPEN);
    return;
  }
  player_.Bind(std::move(pending_player_), media_task_runner_);
  client_receiver_.Bind(std::move(pending_client_receiver_),
                        media_task_runner_);
  player_.set_disconnect_handler(base::BindOnce(
      &NativeHlsDemuxer::OnPlayerDisconnected, base::Unretained(this)));
  // The client pipe carries Initialize's answer: losing it is losing the
  // player.
  client_receiver_.set_disconnect_handler(base::BindOnce(
      &NativeHlsDemuxer::OnPlayerDisconnected, base::Unretained(this)));

  // A CDM the pipeline held before this demuxer started: AVFoundation may
  // ask for keys before the item is ready to play.
  if (pending_cdm_context_) {
    SendCdm(std::exchange(pending_cdm_context_, nullptr), base::DoNothing());
  }

  // The answer is OnInitialized, on the client's pipe, after any OnError
  // about the item.
  player_->Initialize(url_, mime_type_);
}

void NativeHlsDemuxer::OnInitialized(
    media::mojom::FairPlayHlsMetadataPtr metadata) {
  const bool success = !metadata.is_null();
  OnPlayerInitialized(success, std::move(metadata));
}

void NativeHlsDemuxer::OnPlayerInitialized(
    bool success,
    media::mojom::FairPlayHlsMetadataPtr metadata) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!init_cb_) {
    return;
  }
  if (!success || !metadata) {
    std::move(init_cb_).Run(InitializeFailureStatus(init_error_));
    return;
  }

  // AVFoundation's codecs and size, so the element's metadata (videoWidth,
  // videoHeight, the media session's codecs) is Safari's. Nothing decodes
  // these configs, and they are clear: keys go to AVPlayer, never through a
  // decryptor here.
  if (metadata->has_audio) {
    streams_.push_back(std::make_unique<PlaceholderStream>(
        media::AudioDecoderConfig(
            metadata->audio_codec, media::kSampleFormatF32,
            media::ChannelLayoutConfig::Stereo(), 48000,
            std::vector<uint8_t>(), media::EncryptionScheme::kUnencrypted)));
  }
  if (metadata->has_video) {
    const gfx::Size size = metadata->natural_size;
    streams_.push_back(std::make_unique<PlaceholderStream>(
        media::VideoDecoderConfig(
            metadata->video_codec, media::VIDEO_CODEC_PROFILE_UNKNOWN,
            media::VideoDecoderConfig::AlphaMode::kIsOpaque,
            media::VideoColorSpace(), media::kNoTransformation, size,
            gfx::Rect(size), size, std::vector<uint8_t>(),
            media::EncryptionScheme::kUnencrypted)));
    if (natural_size_.IsEmpty()) {
      natural_size_ = size;
    }
  }
  {
    base::AutoLock lock(time_lock_);
    duration_ = metadata->duration;
    seekable_ = ToRanges(metadata->seekable);
    start_date_ = metadata->start_date;
  }
  host_->SetDuration(metadata->duration);
  host_->OnBufferedTimeRangesChanged(ToRanges(metadata->buffered));
  tracks_ready_ = true;
  ApplyTracks(pending_tracks_ ? *pending_tracks_ : metadata->tracks);
  pending_tracks_.reset();
  for (const auto& [track_key, cues] : pending_cues_) {
    ForwardTextCues(track_key, cues);
  }
  pending_cues_.clear();
  std::move(init_cb_).Run(media::PIPELINE_OK);
}

void NativeHlsDemuxer::AbortPendingReads() {}

void NativeHlsDemuxer::StartWaitingForSeek(base::TimeDelta seek_time) {}

void NativeHlsDemuxer::CancelPendingSeek(base::TimeDelta seek_time) {}

void NativeHlsDemuxer::Seek(base::TimeDelta time,
                            media::PipelineStatusCallback status_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (stopped_ || !player_.is_bound()) {
    std::move(status_cb).Run(media::PIPELINE_ERROR_INVALID_STATE);
    return;
  }
  base::TimeDelta tolerance_before;
  {
    base::AutoLock lock(time_lock_);
    seek_time_ = time;
    // A fast seek set for this target applies to this seek.
    if (requested_fast_seek_ && requested_fast_seek_->first == time) {
      tolerance_before = requested_fast_seek_->second;
      requested_fast_seek_.reset();
    }
  }
  const bool fast = tolerance_before.is_positive();
  player_->Seek(time, tolerance_before,
                base::BindOnce(&NativeHlsDemuxer::OnPlayerSeeked,
                               weak_factory_.GetWeakPtr(), time, fast,
                               std::move(status_cb)));
}

void NativeHlsDemuxer::ParcSetFastSeek(base::TimeDelta target,
                                       base::TimeDelta tolerance_before) {
  base::AutoLock lock(time_lock_);
  if (tolerance_before.is_positive()) {
    requested_fast_seek_ = std::make_pair(target, tolerance_before);
  } else {
    requested_fast_seek_.reset();
  }
}

std::optional<base::TimeDelta> NativeHlsDemuxer::ParcTakeFastSeekLanding() {
  base::AutoLock lock(time_lock_);
  return std::exchange(fast_seek_landing_, std::nullopt);
}

void NativeHlsDemuxer::OnPlayerSeeked(base::TimeDelta time,
                                      bool fast,
                                      media::PipelineStatusCallback status_cb,
                                      bool success,
                                      base::TimeDelta current_time) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  {
    base::AutoLock lock(time_lock_);
    // The player's clock restarts at the target, or where a fast seek
    // landed (the pipeline starts the renderer there); its next time update
    // follows. A fast seek that didn't finish says nothing of a landing.
    seek_time_.reset();
    const bool landed = fast && success;
    time_ = landed ? current_time : time;
    if (landed) {
      fast_seek_landing_ = current_time;
    }
    rate_ = 0;
    capture_time_ = base::TimeTicks::Now();
  }
  // AVFoundation answers false only when a later seek interrupted this one;
  // the pipeline serializes its seeks, so the later one completes it.
  if (!success) {
    DVLOG(1) << "Native HLS seek to " << time << " was interrupted";
  }
  std::move(status_cb).Run(media::PIPELINE_OK);
}

bool NativeHlsDemuxer::IsSeekable() const {
  // A live stream's duration is infinite; its DVR window comes from the
  // player's seekable ranges.
  base::AutoLock lock(time_lock_);
  return duration_ != media::kInfiniteDuration;
}

void NativeHlsDemuxer::Stop() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  stopped_ = true;
  // Closing the pipes ends the GPU player, which unregisters its layer.
  client_receiver_.reset();
  player_.reset();
  client_ = nullptr;
  host_ = nullptr;
  {
    base::AutoLock lock(time_lock_);
    seek_time_.reset();
  }
  if (init_cb_) {
    std::move(init_cb_).Run(media::PIPELINE_ERROR_ABORT);
  }
}

base::TimeDelta NativeHlsDemuxer::GetStartTime() const {
  return base::TimeDelta();
}

base::Time NativeHlsDemuxer::GetTimelineOffset() const {
  base::AutoLock lock(time_lock_);
  return start_date_.value_or(base::Time());
}

int64_t NativeHlsDemuxer::GetMemoryUsage() const {
  // The media lives in the GPU process.
  return 0;
}

std::optional<media::container_names::MediaContainerName>
NativeHlsDemuxer::GetContainerForMetrics() const {
  return std::nullopt;
}

void NativeHlsDemuxer::OnTracksChanged(
    media::DemuxerStream::Type track_type,
    std::optional<media::MediaTrack::Id> track_id,
    base::TimeDelta curr_time,
    TrackChangeCB change_completed_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // AVPlayer switches renditions itself (FairPlayHlsPlayer's track
  // selection); the placeholder stream stays.
  media::DemuxerStream* stream = nullptr;
  for (const auto& candidate : streams_) {
    if (candidate->type() == track_type) {
      stream = candidate.get();
      break;
    }
  }
  std::move(change_completed_cb).Run(stream);
}

void NativeHlsDemuxer::SetPlaybackRate(double rate) {}

void NativeHlsDemuxer::ParcProvideClearKey(const std::string& key_id,
                                           const std::vector<uint8_t>& key) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The page's legacy clear key session has the key a clearkey:// request
  // asked for; AVFoundation gets its requested bytes (WebKit's
  // fulfillRequestWithKeyData).
  if (player_.is_bound() && !key_id.empty() && !key.empty()) {
    player_->ProvideClearKey(key_id, key);
  }
}

std::optional<media::Demuxer::ParcNativeTimeline>
NativeHlsDemuxer::GetParcNativeTimeline() const {
  base::AutoLock lock(time_lock_);
  ParcNativeTimeline timeline;
  timeline.seekable = seekable_;
  timeline.start_date = start_date_;
  return timeline;
}

void NativeHlsDemuxer::SetCdmForNativePlayer(media::CdmContext* cdm_context) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!player_.is_bound()) {
    pending_cdm_context_ = cdm_context;
    return;
  }
  SendCdm(cdm_context, base::DoNothing());
}

void NativeHlsDemuxer::SetClient(NativeHlsSource::Client* client) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_ = client;
  if (!client_) {
    return;
  }
  if (layer_token_) {
    client_->OnSourceLayerRegistered(*layer_token_, natural_size_);
  }
  if (waiting_for_key_) {
    client_->OnSourceWaiting(media::WaitingReason::kNoDecryptionKey);
  }
}

void NativeHlsDemuxer::Play(double rate) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (player_.is_bound() && rate > 0) {
    player_->Play(rate);
  }
}

void NativeHlsDemuxer::Pause() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (player_.is_bound()) {
    player_->Pause();
  }
}

void NativeHlsDemuxer::SetVolume(float volume) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (player_.is_bound()) {
    player_->SetVolume(volume);
  }
}

void NativeHlsDemuxer::SetPreservesPitch(bool preserves_pitch) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (player_.is_bound()) {
    player_->SetPreservesPitch(preserves_pitch);
  }
}

void NativeHlsDemuxer::SetCdm(media::CdmContext* cdm_context,
                              NativeHlsSource::CdmAttachedCB cdm_attached_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!player_.is_bound()) {
    pending_cdm_context_ = cdm_context;
    std::move(cdm_attached_cb).Run(true);
    return;
  }
  SendCdm(cdm_context, std::move(cdm_attached_cb));
}

void NativeHlsDemuxer::SendCdm(media::CdmContext* cdm_context,
                               NativeHlsSource::CdmAttachedCB cdm_attached_cb) {
  DCHECK(player_.is_bound());
  const std::optional<base::UnguessableToken> cdm_id =
      cdm_context ? cdm_context->GetCdmId() : std::nullopt;
  if (!cdm_id) {
    // Only a CDM hosted in the GPU process (MojoCdm) has an ID the player
    // can find; FairPlay's always does.
    std::move(cdm_attached_cb).Run(false);
    return;
  }
  if (cdm_id_ == cdm_id) {
    std::move(cdm_attached_cb).Run(true);
    return;
  }
  cdm_id_ = cdm_id;
  player_->SetCdm(*cdm_id, std::move(cdm_attached_cb));
}

media::BufferingState NativeHlsDemuxer::GetBufferingState() const {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  return buffering_state_;
}

base::TimeDelta NativeHlsDemuxer::GetMediaTime() {
  base::AutoLock lock(time_lock_);
  if (seek_time_) {
    return *seek_time_;
  }
  return InterpolateNativeHlsTime(time_, rate_, capture_time_,
                                  base::TimeTicks::Now(), duration_);
}

base::WeakPtr<NativeHlsSource> NativeHlsDemuxer::GetWeakPtr() {
  return weak_factory_.GetWeakPtr();
}

void NativeHlsDemuxer::StartLoad(
    media::mojom::FairPlayHlsRequestPtr request,
    mojo::PendingReceiver<media::mojom::FairPlayHlsLoad> load,
    mojo::PendingRemote<media::mojom::FairPlayHlsLoadClient> client) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!start_load_cb_) {
    // Dropping the pipes fails the load (FairPlayHlsLoadClient's pipe
    // closes without OnComplete).
    return;
  }
  start_load_cb_.Run(std::move(request), std::move(load), std::move(client));
}

void NativeHlsDemuxer::OnTimeUpdate(base::TimeDelta time,
                                    double rate,
                                    base::TimeTicks capture_time) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  base::AutoLock lock(time_lock_);
  time_ = time;
  rate_ = rate;
  capture_time_ = capture_time;
}

void NativeHlsDemuxer::OnBufferingStateChange(media::BufferingState state) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  buffering_state_ = state;
  // Playback going on again means the key arrived.
  if (state == media::BUFFERING_HAVE_ENOUGH) {
    waiting_for_key_ = false;
  }
  if (client_) {
    client_->OnSourceBufferingStateChange(state);
  }
}

void NativeHlsDemuxer::OnBufferedRangesChanged(
    std::vector<media::mojom::FairPlayHlsTimeRangePtr> buffered) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (host_) {
    host_->OnBufferedTimeRangesChanged(ToRanges(buffered));
  }
}

void NativeHlsDemuxer::OnSeekableRangesChanged(
    std::vector<media::mojom::FairPlayHlsTimeRangePtr> seekable) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The player sends the element's window (WebKit's one range, an end of
  // kInfiniteDuration for live); WebMediaPlayerImpl::Seekable() reads it.
  base::AutoLock lock(time_lock_);
  seekable_ = ToRanges(seekable);
}

void NativeHlsDemuxer::OnDurationChange(base::TimeDelta duration) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  {
    base::AutoLock lock(time_lock_);
    duration_ = duration;
  }
  if (host_) {
    host_->SetDuration(duration);
  }
}

void NativeHlsDemuxer::OnStartDateChanged(
    std::optional<base::Time> start_date) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  base::AutoLock lock(time_lock_);
  start_date_ = start_date;
}

void NativeHlsDemuxer::OnTracksChanged(
    std::vector<media::mojom::FairPlayHlsTrackPtr> tracks) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!tracks_ready_) {
    pending_tracks_ = std::move(tracks);
    return;
  }
  ApplyTracks(tracks);
}

void NativeHlsDemuxer::ApplyTracks(
    const std::vector<media::mojom::FairPlayHlsTrackPtr>& tracks) {
  if (!track_manager_ || stopped_) {
    return;
  }
  std::vector<media::ParcInbandAudioTrack> audio_tracks;
  std::vector<media::ParcInbandTextTrack> text_tracks;
  for (const auto& track : tracks) {
    if (track->type == media::mojom::FairPlayHlsTrackType::kAudio) {
      media::ParcInbandAudioTrack audio;
      audio.key = track->key;
      audio.id = track->id;
      audio.kind = track->kind;
      audio.label = track->label;
      audio.language = track->language;
      audio.enabled = track->enabled;
      audio_tracks.push_back(std::move(audio));
      continue;
    }
    if (track->type != media::mojom::FairPlayHlsTrackType::kText) {
      continue;
    }
    media::ParcInbandTextTrack text;
    text.key = track->key;
    text.id = track->id;
    text.kind = track->kind;
    text.label = track->label;
    text.language = track->language;
    text.index = track->index;
    text.is_default = track->is_default;
    text.is_closed_captions = track->is_closed_captions;
    text.is_sdh = track->is_sdh;
    text.contains_only_forced_subtitles =
        track->contains_only_forced_subtitles;
    text.is_main_program_content = track->is_main_program_content;
    text.is_easy_to_read = track->is_easy_to_read;
    text.automatic = track->automatic;
    text_tracks.push_back(std::move(text));
  }
  track_manager_->ParcSetInbandAudioTracks(
      audio_tracks,
      base::BindPostTask(
          media_task_runner_,
          base::BindRepeating(&NativeHlsDemuxer::SetAudioTrackEnabled,
                              weak_factory_.GetWeakPtr())));
  track_manager_->ParcSetInbandTextTracks(
      text_tracks,
      base::BindPostTask(
          media_task_runner_,
          base::BindRepeating(&NativeHlsDemuxer::SetTextTrackMode,
                              weak_factory_.GetWeakPtr())));
}

void NativeHlsDemuxer::OnTextCues(
    const std::string& track_key,
    std::vector<media::mojom::FairPlayHlsCuePtr> cues) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!tracks_ready_) {
    pending_cues_.emplace_back(track_key, std::move(cues));
    return;
  }
  ForwardTextCues(track_key, cues);
}

void NativeHlsDemuxer::ForwardTextCues(
    const std::string& track_key,
    const std::vector<media::mojom::FairPlayHlsCuePtr>& cues) {
  if (!track_manager_ || stopped_) {
    return;
  }
  std::vector<media::ParcInbandTextCue> result;
  result.reserve(cues.size());
  for (const auto& cue : cues) {
    media::ParcInbandTextCue out;
    out.type = ToParcCueType(cue->type);
    out.cue_id = cue->cue_id;
    out.start = cue->start;
    out.end = cue->end;
    out.complete = cue->complete;
    out.text = cue->text;
    out.identifier = cue->identifier;
    out.settings = cue->settings;
    out.source_id = cue->source_id;
    out.original_start_time = cue->original_start_time;
    out.line = cue->line;
    out.position = cue->position;
    out.size = cue->size;
    out.base_font_size = cue->base_font_size;
    out.relative_font_size = cue->relative_font_size;
    out.font_name = cue->font_name;
    out.align = ToParcCueAlign(cue->align);
    out.position_align = ToParcCueAlign(cue->position_align);
    out.foreground_color = cue->foreground_color;
    out.background_color = cue->background_color;
    out.highlight_color = cue->highlight_color;
    out.prevent_line_wrapping = cue->prevent_line_wrapping;
    result.push_back(std::move(out));
  }
  track_manager_->ParcAddInbandTextCues(track_key, result);
}

void NativeHlsDemuxer::SetAudioTrackEnabled(const std::string& key,
                                            bool enabled) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!player_.is_bound() || stopped_) {
    return;
  }
  player_->SetAudioTrackEnabled(key, enabled);
}

void NativeHlsDemuxer::SetTextTrackMode(const std::string& key,
                                        media::ParcInbandTextTrackMode mode) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!player_.is_bound() || stopped_) {
    return;
  }
  media::mojom::FairPlayHlsTextTrackMode mojo_mode =
      media::mojom::FairPlayHlsTextTrackMode::kDisabled;
  switch (mode) {
    case media::ParcInbandTextTrackMode::kDisabled:
      mojo_mode = media::mojom::FairPlayHlsTextTrackMode::kDisabled;
      break;
    case media::ParcInbandTextTrackMode::kHidden:
      mojo_mode = media::mojom::FairPlayHlsTextTrackMode::kHidden;
      break;
    case media::ParcInbandTextTrackMode::kShowing:
      mojo_mode = media::mojom::FairPlayHlsTextTrackMode::kShowing;
      break;
  }
  player_->SetTextTrackMode(key, mojo_mode);
}

void NativeHlsDemuxer::OnNaturalSizeChange(const gfx::Size& size) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  natural_size_ = size;
  if (client_) {
    client_->OnSourceNaturalSizeChange(size);
  }
}

void NativeHlsDemuxer::OnLayerRegistered(
    const base::UnguessableToken& layer_token,
    const gfx::Size& natural_size) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The GPU process makes the token. An empty one would name no layer.
  if (layer_token.is_empty() || layer_token_) {
    DLOG(ERROR) << "Unexpected native HLS layer token";
    return;
  }
  layer_token_ = layer_token;
  if (natural_size_.IsEmpty()) {
    natural_size_ = natural_size;
  }
  if (client_) {
    client_->OnSourceLayerRegistered(*layer_token_, natural_size_);
  }
}

void NativeHlsDemuxer::OnStatisticsUpdate(
    const media::PipelineStatistics& delta) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (client_) {
    client_->OnSourceStatisticsUpdate(delta);
  }
}

void NativeHlsDemuxer::OnEncrypted(const std::string& init_data_type,
                                   const std::vector<uint8_t>& init_data) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  const media::EmeInitDataType type =
      media::StringToEmeInitDataType(init_data_type);
  if (type == media::EmeInitDataType::UNKNOWN || init_data.empty()) {
    DLOG(ERROR) << "Unexpected native HLS init data type " << init_data_type;
    return;
  }
  // `encrypted` (initDataType "skd", the key URI), raised on the main thread.
  encrypted_media_init_data_cb_.Run(type, init_data);
}

void NativeHlsDemuxer::OnKeyRequest(const std::string& key_uri) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // webkitneedkey (WebKit's keyNeeded) for every skd:// and clearkey://
  // request, repeats included. It reaches the main thread before the
  // `encrypted` the same request may raise: both post in the player's order.
  if (key_request_cb_) {
    key_request_cb_.Run(key_uri);
  }
}

void NativeHlsDemuxer::OnWaiting(media::WaitingReason reason) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (reason == media::WaitingReason::kNoDecryptionKey) {
    waiting_for_key_ = true;
  }
  // `waitingforkey` reaches the element through the renderer facade; one
  // made later hears it when it attaches.
  if (client_) {
    client_->OnSourceWaiting(reason);
  }
}

void NativeHlsDemuxer::OnEnded() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (client_) {
    client_->OnSourceEnded();
  }
}

void NativeHlsDemuxer::OnError(const media::PipelineStatus& status,
                               const std::string& message) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (media_log_) {
    MEDIA_LOG(ERROR, media_log_.get())
        << "Native HLS player: " << message;
  }
  if (status.is_ok()) {
    return;
  }
  if (init_cb_) {
    // OnInitialized(null) follows on the same pipe and reports it.
    if (!init_error_) {
      init_error_ = status;
    }
    return;
  }
  ReportError(status);
}

void NativeHlsDemuxer::OnPlayerDisconnected() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_receiver_.reset();
  player_.reset();
  {
    // A pending seek's reply went with the player; the clock stays put.
    base::AutoLock lock(time_lock_);
    seek_time_.reset();
  }
  // The GPU process went away (as a MojoRenderer reports it).
  const media::PipelineStatus status(media::PIPELINE_ERROR_DISCONNECTED);
  if (init_cb_) {
    std::move(init_cb_).Run(status);
    return;
  }
  ReportError(status);
}

void NativeHlsDemuxer::ReportError(media::PipelineStatus status) {
  if (stopped_) {
    return;
  }
  if (client_) {
    client_->OnSourceError(std::move(status));
    return;
  }
  if (host_) {
    host_->OnDemuxerError(std::move(status));
  }
}

// static
media::PipelineStatus NativeHlsDemuxer::InitializeFailureStatus(
    std::optional<media::PipelineStatus> reported_error) {
  if (reported_error && !reported_error->is_ok()) {
    return *reported_error;
  }
  return media::DEMUXER_ERROR_COULD_NOT_OPEN;
}

}  // namespace parc::fairplay
