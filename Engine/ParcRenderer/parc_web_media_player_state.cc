// Copyright 2026 Parc contributors.
#include "third_party/blink/renderer/platform/media/parc_web_media_player_state.h"

#include <algorithm>
#include <limits>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "base/numerics/safe_conversions.h"
#include "base/task/bind_post_task.h"
#include "media/base/parc_demuxer_extension.h"
#include "media/base/parc_pipeline_extension.h"
#include "media/base/renderer_factory.h"
#include "media/base/renderer_factory_selector.h"
#include "media/filters/pipeline_controller.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/public/platform/web_audio_source_provider_impl.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/public/platform/web_media_player_encrypted_media_client.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/renderer/platform/media/parc_media_player_client.h"
#include "third_party/blink/renderer/platform/media/parc_web_media_player_rules.h"
#include "third_party/blink/renderer/platform/media/url_index.h"
#include "third_party/blink/renderer/platform/media/video_frame_compositor.h"
#if BUILDFLAG(IS_MAC)
#include "third_party/blink/renderer/platform/media/fairplay_hls_loader.h"
#endif
#include "third_party/blink/renderer/platform/media/web_media_player_impl.h"
#include "third_party/blink/renderer/platform/scheduler/public/frame_scheduler.h"
#include "third_party/blink/renderer/platform/scheduler/public/post_cross_thread_task.h"
#include "third_party/blink/renderer/platform/weborigin/kurl.h"
#include "third_party/blink/renderer/platform/wtf/cross_thread_functional.h"

namespace blink {

ParcWebMediaPlayerState::ParcWebMediaPlayerState(
    WebMediaPlayerImpl& player,
    scoped_refptr<ParcFrameTaskRunner> frame_task_runner)
    : player_(player), frame_task_runner_(std::move(frame_task_runner)) {}

ParcWebMediaPlayerState::~ParcWebMediaPlayerState() = default;

ParcWebMediaPlayerExtension::ParcFrameServices::ParcFrameServices() = default;
ParcWebMediaPlayerExtension::ParcFrameServices::ParcFrameServices(
    ParcFrameServices&&) = default;
ParcWebMediaPlayerExtension::ParcFrameServices::~ParcFrameServices() = default;

void ParcWebMediaPlayerState::ParcSetCastPrompted(bool prompted) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  cast_prompted_ = prompted;
  UpdateLoadsForCast();
}

void ParcWebMediaPlayerState::ParcOnFrozenInBackForwardCache() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  DCHECK(player_->paused_);

  if (player_->observer_) {
    player_->observer_->OnFrozen();
  }
  if (player_->demuxer_manager_->HasDataSource() && !player_->IsStreaming() &&
      !loads_for_cast_) {
    player_->demuxer_manager_->StopPreloading();
  }
}

void ParcWebMediaPlayerState::ParcSetPageHidden(
    std::optional<bool> is_page_hidden) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  const bool was_page_hidden = player_->IsPageHidden();
  page_hidden_ = is_page_hidden;
  if (player_->IsPageHidden() == was_page_hidden) {
    return;
  }
  if (player_->IsPageHidden()) {
    player_->ParcPageHidden();
  } else {
    player_->ParcPageShown();
  }
}

bool ParcWebMediaPlayerState::ParcMoveToFrame(ParcFrameServices services) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (!frame_task_runner_ || !MoveToFrame(*services.frame)) {
    return false;
  }

  player_->delegate_->PlayerGone(player_->delegate_id_);
  player_->delegate_->RemoveObserver(player_->delegate_id_);
  player_->delegate_ = services.delegate;
  player_->delegate_id_ = player_->delegate_->AddObserver(&*player_);
  player_->delegate_->SetIdle(player_->delegate_id_, true);
  player_->delegate_state_ = WebMediaPlayerImpl::DelegateState::GONE;

  player_->url_index_ = services.url_index;
  if (mb_data_source_) {
    mb_data_source_->ParcMoveToUrlIndex(*player_->url_index_);
  }
#if BUILDFLAG(IS_MAC)
  if (hls_loader_) {
    hls_loader_->SetFetchContext(player_->url_index_->fetch_context());
  }
#endif

  PostCrossThreadTask(
      *player_->media_task_runner_, FROM_HERE,
      CrossThreadBindOnce(&WebAudioSourceProviderImpl::ParcSwitchSink,
                          player_->audio_source_provider_,
                          std::move(services.audio_sink)));
  std::move(services.move_factories).Run(*player_->renderer_factory_selector_);
  std::move(services.move_media_log).Run(*player_->media_log_);
  player_->UpdatePlayState();
  return true;
}

bool ParcWebMediaPlayerState::MoveToFrame(WebLocalFrame& frame) {
  if (frame.Scheduler() == player_->frame_scheduler_) {
    return false;
  }
  player_->frame_scheduler_ = frame.Scheduler();
  player_->has_transient_user_activation_cb_ = blink::BindRepeating(
      &WebLocalFrame::HasTransientUserActivation, blink::Unretained(&frame));
  frame_task_runner_->SetTarget(player_->frame_scheduler_->GetTaskRunner(
      TaskType::kMediaElementEvent));
  return true;
}

void ParcWebMediaPlayerState::ParcReportStateToClient() {
  player_->ParcReportStateToClient();
}

double ParcWebMediaPlayerState::ParcStartDate() const {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());

  if (player_->ready_state_ == WebMediaPlayer::kReadyStateHaveNothing) {
    return 0;
  }
  std::optional<parc::fairplay::NativeHlsSource::Timeline> timeline =
      media::ParcNativeHlsTimeline(player_->demuxer_manager_->ParcDemuxer());
  if (!timeline || !timeline->start_date) {
    return std::numeric_limits<double>::quiet_NaN();
  }
  return timeline->start_date->InMillisecondsFSinceUnixEpoch();
}

void ParcWebMediaPlayerState::ParcFastSeek(double seconds,
                                           double tolerance_before) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  fast_seek_tolerance_ = base::Seconds(tolerance_before);
  player_->Seek(seconds);
}

void ParcWebMediaPlayerState::ParcEnabledAudioTracksChanged(
    const std::vector<WebMediaPlayer::TrackId>& enabled_track_ids) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
#if BUILDFLAG(IS_MAC)
  if (chunk_demuxer_ && player_->PresentsParcSafariIdentity()) {
    std::vector<media::MediaTrack::Id> ids;
    for (const WebMediaPlayer::TrackId& id : enabled_track_ids) {
      ids.push_back(media::MediaTrack::Id(id.Utf8().data()));
    }
    chunk_demuxer_->ParcSetEnabledAudioTracks(ids);
  }
  for (FileTrack& track : file_audio_tracks_) {
    track.on = std::ranges::any_of(
        enabled_track_ids, [&](const WebMediaPlayer::TrackId& id) {
          return media::MediaTrack::Id(id.Utf8().data()) == track.id;
        });
  }
  if (file_on_native_route_) {
    SendFileTrackChoices();
  }
#endif
  player_->EnabledAudioTracksChanged(
      enabled_track_ids.empty()
          ? std::nullopt
          : std::make_optional(enabled_track_ids.front()));
}

base::TimeDelta ParcWebMediaPlayerState::PipelineMediaTime() const {
  return std::max(
      player_->pipeline_controller_->GetMediaTime() + live_time_offset_,
      base::TimeDelta());
}

base::TimeDelta ParcWebMediaPlayerState::PipelineSeekTime(
    base::TimeDelta time) const {
  return std::max(time - live_time_offset_, base::TimeDelta());
}

bool ParcWebMediaPlayerState::TakeEncryptedMediaInitData(
    media::EmeInitDataType init_data_type,
    const std::vector<uint8_t>& init_data) {
#if BUILDFLAG(IS_MAC)
  if (init_data_type == media::EmeInitDataType::SKD) {
    last_skd_init_data_ = init_data;
  }
#endif

  const bool safari_media_source =
      player_->load_type_ == WebMediaPlayer::kLoadTypeMediaSource &&
      ClientPresentsParcSafariIdentity(*player_->client_);
  if (safari_media_source
          ? init_data_type != media::EmeInitDataType::SINF &&
                init_data_type != media::EmeInitDataType::MPTS
          : init_data_type == media::EmeInitDataType::SINF) {
    return true;
  }

  if (safari_media_source) {
    SourceKeyChanged("", init_data_type, init_data);
    return true;
  }
  return false;
}

void ParcWebMediaPlayerState::OnChunkDemuxerOpened(
    media::ChunkDemuxer& demuxer) {
#if BUILDFLAG(IS_MAC)
  const bool safari_identity = player_->PresentsParcSafariIdentity();
  demuxer.ParcSetClearDolbyVisionAllowed(ClearDolbyVisionAllowed());
  demuxer.ParcSetSafariMediaSource(safari_identity);
  demuxer.ParcSetSafariEviction(safari_identity);
  demuxer.ParcSetSafariInitSegmentRules(safari_identity);
  demuxer.ParcSetDolbyVisionAppendedCallback(
      base::BindPostTaskToCurrentDefault(base::BindRepeating(
          [](base::WeakPtr<WebMediaPlayerImpl> player) {
            if (player) {
              player->parc_->SwitchToFairPlayIfNeeded();
            }
          },
          player_->weak_this_)));
  if (safari_identity) {
    demuxer.ParcSetSourceKeyCallback(
        base::BindPostTaskToCurrentDefault(base::BindRepeating(
            [](base::WeakPtr<WebMediaPlayerImpl> player, const std::string& id,
               media::EmeInitDataType init_data_type,
               const std::vector<uint8_t>& init_data) {
              if (player) {
                player->parc_->SourceKeyChanged(id, init_data_type, init_data);
              }
            },
            player_->weak_this_)));
    demuxer.ParcAllowSourceBuffersAfterInit(
        base::BindPostTaskToCurrentDefault(base::BindRepeating(
            [](base::WeakPtr<WebMediaPlayerImpl> player,
               const media::PipelineMetadata& added,
               const std::vector<media::ChunkDemuxer::ParcAddedTrack>& tracks) {
              if (player) {
                player->parc_->OnSourceBufferStreamsAdded(added, tracks);
              }
            },
            player_->weak_this_)));
  }
#endif
  chunk_demuxer_ = &demuxer;
}

bool ParcWebMediaPlayerState::MonitorsSourceBuffers() const {
  return player_->load_type_ == WebMediaPlayer::kLoadTypeMediaSource &&
         chunk_demuxer_ && ClientPresentsParcSafariIdentity(*player_->client_);
}

void ParcWebMediaPlayerState::MonitorSourceBuffers(bool seek_start) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (!MonitorsSourceBuffers() ||
      player_->ready_state_ < WebMediaPlayer::kReadyStateHaveMetadata) {
    return;
  }
  const std::optional<media::ChunkDemuxer::ParcBufferedState> source =
      chunk_demuxer_->ParcGetBufferedState();
  if (!source) {
    return;
  }
  const bool time_progressing = !player_->paused_ &&
                                player_->playback_rate_ != 0 &&
                                !player_->seeking_ && renderer_has_enough_;
  WebMediaPlayer::ReadyState state = ParcSourceBufferReadyState(
      *source, player_->GetCurrentTimeInternal(), time_progressing);
  if (seek_start && state != WebMediaPlayer::kReadyStateHaveMetadata) {
    return;
  }
  if (player_->should_notify_time_changed_ && !player_->seeking_ &&
      renderer_ready_) {
    state = std::max(state, WebMediaPlayer::kReadyStateHaveCurrentData);
  }
  if (state != player_->ready_state_ &&
      (state < WebMediaPlayer::kReadyStateHaveCurrentData ||
       !player_->HasVideo() || renderer_ready_)) {
    player_->SetReadyState(state);
  }
  if (player_->should_notify_time_changed_ && !player_->seeking_ &&
      renderer_ready_ &&
      player_->ready_state_ >= WebMediaPlayer::kReadyStateHaveCurrentData) {
    player_->should_notify_time_changed_ = false;
    player_->client_->TimeChanged();
  }
}

bool ParcWebMediaPlayerState::UrlSeekKeepsReadyState(
    base::TimeDelta time) const {
  return player_->load_type_ == WebMediaPlayer::kLoadTypeURL &&
         ClientPresentsParcSafariIdentity(*player_->client_) &&
         player_->ready_state_ > WebMediaPlayer::kReadyStateHaveMetadata &&
         player_->Buffered().Contain(time.InSecondsF());
}

void ParcWebMediaPlayerState::FinishUrlSeekAtFrame() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (!player_->should_notify_time_changed_ ||
      player_->ready_state_ < WebMediaPlayer::kReadyStateHaveCurrentData) {
    return;
  }
  if (!player_->HasVideo()) {
    player_->should_notify_time_changed_ = false;
    player_->client_->TimeChanged();
    return;
  }
  if (!player_->has_first_frame_) {
    return;
  }
  PostCrossThreadTask(
      *player_->vfc_task_runner_, FROM_HERE,
      CrossThreadBindOnce(
          &VideoFrameCompositor::SetOnNewProcessedFrameCallback,
          CrossThreadUnretained(player_->compositor_.get()),
          CrossThreadBindOnce(base::BindPostTaskToCurrentDefault(
              ConvertToBaseOnceCallback(CrossThreadBindOnce(
                  [](base::WeakPtr<WebMediaPlayerImpl> player,
                     uint64_t seek_id, base::TimeTicks frame_time,
                     bool is_frame_readable) {
                    if (player) {
                      player->parc_->OnUrlSeekFrame(seek_id);
                    }
                  },
                  player_->weak_this_, url_seek_id_))))));
}

void ParcWebMediaPlayerState::OnUrlSeekFrame(uint64_t seek_id) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (seek_id != url_seek_id_ || player_->seeking_ ||
      !player_->should_notify_time_changed_ ||
      player_->ready_state_ < WebMediaPlayer::kReadyStateHaveCurrentData) {
    return;
  }
  player_->should_notify_time_changed_ = false;
  player_->client_->TimeChanged();
}

void ParcWebMediaPlayerState::DidFinishSeek() {
  if (std::exchange(url_seek_keeps_ready_state_, false)) {
    FinishUrlSeekAtFrame();
  }
  MonitorSourceBuffers();
}

void ParcWebMediaPlayerState::SetRemoteRendering(bool remote_rendering) {
  player_->is_remote_rendering_ = remote_rendering;
  pipeline_task_runner_->SetCasting(remote_rendering);
  UpdateLoadsForCast();
}

void ParcWebMediaPlayerState::UpdateLoadsForCast() {
  const bool loads_for_cast =
      player_->is_remote_rendering_ || cast_requested_ || cast_prompted_;
  if (loads_for_cast_ == loads_for_cast) {
    return;
  }
  loads_for_cast_ = loads_for_cast;
  if (mb_data_source_) {
    mb_data_source_->ParcSetCasting(loads_for_cast);
  }
  if (hls_source_factory_) {
    hls_source_factory_->ParcSetCasting(loads_for_cast);
  }
}

#if BUILDFLAG(IS_MAC)
void ParcWebMediaPlayerState::ParcProvideClearKey(
    std::string_view key_id,
    base::span<const uint8_t> key) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  media::ParcPostNativeHlsClearKey(
      player_->demuxer_manager_->ParcDemuxer(), *player_->media_task_runner_,
      std::string(key_id), std::vector<uint8_t>(key.begin(), key.end()));
}

void ParcWebMediaPlayerState::ParcSetPlaybackTarget(
    std::string_view output_context_id,
    bool should_play) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  playback_target_id_ = std::string(output_context_id);
  should_play_to_playback_target_ = should_play;
  media::ParcPostNativeHlsPlaybackTarget(
      player_->demuxer_manager_->ParcDemuxer(), *player_->media_task_runner_,
      playback_target_id_, should_play);
  UpdateRouteForPlaybackTarget();
}

void ParcWebMediaPlayerState::ParcSetWirelessVideoPlaybackDisabled(
    bool disabled) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  wireless_video_playback_disabled_ = disabled;
  media::ParcPostNativeHlsWirelessVideoPlaybackDisabled(
      player_->demuxer_manager_->ParcDemuxer(), *player_->media_task_runner_,
      disabled);
}

bool ParcWebMediaPlayerState::ParcSupportsPlaybackTarget() const {
  return PlaysNativeHls() || file_native_mime_type_.has_value();
}

std::unique_ptr<media::Demuxer> ParcWebMediaPlayerState::CreateNativeHlsDemuxer(
    media::ParcNativeHlsDemuxerParams params) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  media::RendererFactory* factory =
      player_->renderer_factory_selector_->GetFactory(
          media::RendererType::kFairPlayHls);
  if (!factory || !player_->url_index_) {
    return nullptr;
  }
  hls_loader_ = std::make_unique<FairPlayHlsLoader>(
      player_->url_index_->fetch_context(),
      static_cast<UrlData::CorsMode>(player_->cors_mode_),
      player_->client_->IsAudioElement());
  params.start_load_cb = hls_loader_->GetStartLoadCallback();
  native_hls_ready_state_ = media::ParcNativeHlsReadyState::kHaveMetadata;
  ParcMediaPlayerClient* parc = player_->client_->ParcClient();
  params.prepare_to_play = parc && parc->ParcPreparesToPlay();
  if (parc) {
    parc->ParcVideoLayerSize(&params.video_layer_size,
                             &params.video_layer_scale);
  }
  params.playback_target_id = playback_target_id_;
  params.should_play_to_playback_target = should_play_to_playback_target_;
  params.wireless_video_playback_disabled = wireless_video_playback_disabled_;
  return factory->CreateParcNativeHlsDemuxer(std::move(params));
}

void ParcWebMediaPlayerState::NativeHlsMediaTypesChanged(bool has_audio,
                                                         bool has_video) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  media::PipelineMetadata& metadata = player_->pipeline_metadata_;
  if (player_->ready_state_ < WebMediaPlayer::kReadyStateHaveMetadata ||
      (!has_audio && !has_video) ||
      (metadata.has_audio == has_audio && metadata.has_video == has_video)) {
    return;
  }
  metadata.has_audio = has_audio;
  metadata.has_video = has_video;
  if (has_video) {
    player_->ActivateSurfaceLayerForVideo();
  }
  if (player_->observer_) {
    player_->observer_->OnMetadataChanged(metadata);
  }
  player_->delegate_has_audio_ = player_->HasUnmutedAudio();
  player_->DidMediaMetadataChange();
  player_->UpdatePlayState();
}

void ParcWebMediaPlayerState::NativeHlsTimeJumped() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (player_->seeking_ || !player_->pipeline_controller_->IsStable()) {
    return;
  }
  player_->pipeline_controller_->GetParcExtension()->ParcResetMediaTimeClamp();
  if (player_->paused_) {
    player_->paused_time_ = PipelineMediaTime();
  }
  if (auto* parc = player_->client_->ParcClient()) {
    parc->ParcPlayerTimeChanged();
  }
}

void ParcWebMediaPlayerState::NativeHlsReadyStateChanged(
    media::ParcNativeHlsReadyState state) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  native_hls_ready_state_ = state;
  ApplyNativeHlsReadyState();
}

void ParcWebMediaPlayerState::ApplyNativeHlsReadyState() {
  WebMediaPlayer::ReadyState target;
  switch (native_hls_ready_state_) {
    case media::ParcNativeHlsReadyState::kHaveCurrentData:
      target = WebMediaPlayer::kReadyStateHaveCurrentData;
      break;
    case media::ParcNativeHlsReadyState::kHaveFutureData:
      target = WebMediaPlayer::kReadyStateHaveFutureData;
      break;
    case media::ParcNativeHlsReadyState::kHaveEnoughData:
      target = WebMediaPlayer::kReadyStateHaveEnoughData;
      break;
    case media::ParcNativeHlsReadyState::kHaveMetadata:
      return;
  }
  if (player_->seeking_ ||
      player_->ready_state_ < WebMediaPlayer::kReadyStateHaveMetadata ||
      player_->ready_state_ == target) {
    return;
  }
  player_->SetReadyState(target);
  if (player_->should_notify_time_changed_ && !player_->seeking_ &&
      player_->ready_state_ >= WebMediaPlayer::kReadyStateHaveCurrentData) {
    player_->should_notify_time_changed_ = false;
    player_->client_->TimeChanged();
  }
  player_->UpdatePlayState();
}

bool ParcWebMediaPlayerState::PlaysNativeHls() const {
  return player_->renderer_type_ == media::RendererType::kFairPlayHls ||
         player_->demuxer_manager_->HasParcNativeHlsDemuxer();
}

void ParcWebMediaPlayerState::UpdateRouteForPlaybackTarget() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  const bool native = file_native_mime_type_ &&
                      should_play_to_playback_target_ &&
                      !playback_target_id_.empty() &&
                      !player_->is_remote_rendering_ && !player_->is_flinging_;
  if (native == file_on_native_route_ || route_switch_ ||
      player_->ready_state_ < WebMediaPlayer::kReadyStateHaveMetadata) {
    return;
  }
  SwitchRoute(native);
}

void ParcWebMediaPlayerState::SwitchRoute(bool native) {
  if (!route_switch_) {
    route_switch_ = RouteSwitch{player_->Duration(), std::nullopt,
                                player_->GetCurrentTimeInternal()};
    player_->seek_time_ = route_switch_->time;
    player_->seeking_ = true;
  }
  if (!native && std::exchange(native_wireless_, false)) {
    if (auto* parc = player_->client_->ParcClient()) {
      parc->ParcPlaybackTargetIsWirelessChanged(false);
    }
  }
  file_on_native_route_ = native;
  player_->StopForDemuxerReset();
  mb_data_source_ = nullptr;
  player_->demuxer_manager_->ParcSetNativeRoute(
      native ? file_native_mime_type_ : std::nullopt,
      base::BindOnce(
          [](base::WeakPtr<WebMediaPlayerImpl> player) {
            if (player) {
              player->parc_->RestartOnRoute();
            }
          },
          player_->weak_this_));
}

void ParcWebMediaPlayerState::RestartOnRoute() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (file_on_native_route_) {
    player_->StartPipeline();
    return;
  }
  player_->StartMultiBufferDataSource(
      KURL(player_->demuxer_manager_->LoadedUrl()));
}

void ParcWebMediaPlayerState::CheckFileTargetSupport() {
  file_native_mime_type_.reset();
  const media::PipelineMetadata& metadata = player_->pipeline_metadata_;
  if (player_->GetDemuxerType() != media::DemuxerType::kFFmpegDemuxer ||
      player_->load_type_ != WebMediaPlayer::kLoadTypeURL ||
      !ClientPresentsParcSafariIdentity(*player_->client_) ||
      !player_->demuxer_manager_->LoadedUrl().SchemeIsHTTPOrHTTPS() ||
      metadata.audio_decoder_config.is_encrypted() ||
      metadata.video_decoder_config.is_encrypted() ||
      player_->cdm_context_ref_) {
    return;
  }
  file_streaming_ = player_->IsStreaming();
  if (file_streaming_ &&
      player_->GetPipelineMediaDuration() != media::kInfiniteDuration) {
    return;
  }
  file_native_mime_type_ = ParcNativeFileMimeType(
      player_->demuxer_manager_->GetContainerForMetrics(), metadata.has_video);
}

void ParcWebMediaPlayerState::EndRouteSwitchForError() {
  if (std::exchange(route_switch_, std::nullopt)) {
    player_->seeking_ = false;
    player_->seek_time_ = base::TimeDelta();
  }
}

parc::fairplay::NativeHlsSource::FileTracks
ParcWebMediaPlayerState::FileTrackChoices() const {
  parc::fairplay::NativeHlsSource::FileTracks tracks;
  tracks.audio_count = base::checked_cast<uint32_t>(file_audio_tracks_.size());
  for (uint32_t i = 0; i < tracks.audio_count; ++i) {
    if (file_audio_tracks_[i].on) {
      tracks.audio.push_back(i);
    }
  }
  tracks.video_count = base::checked_cast<uint32_t>(file_video_tracks_.size());
  for (uint32_t i = 0; i < tracks.video_count && !tracks.video; ++i) {
    if (file_video_tracks_[i].on) {
      tracks.video = i;
    }
  }
  return tracks;
}

std::optional<ParcWebMediaPlayerState::RouteSwitch>
ParcWebMediaPlayerState::TakeSeekedRouteSwitch() {
  if (std::exchange(handoff_after_seek_, false)) {
    player_->main_task_runner_->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<WebMediaPlayerImpl> player) {
                         if (player) {
                           player->parc_->HandOffAfterSeek();
                         }
                       },
                       player_->weak_this_));
  }
  std::optional<RouteSwitch> route_switch =
      std::exchange(route_switch_, std::nullopt);
  if (route_switch && file_streaming_) {
    live_time_offset_ =
        route_switch->time - player_->pipeline_controller_->GetMediaTime();
  }
  return route_switch;
}

void ParcWebMediaPlayerState::FinishSeekedRouteSwitch(
    const std::optional<RouteSwitch>& route_switch) {
  if (PlaysNativeHls()) {
    ApplyNativeHlsReadyState();
    if (player_->should_notify_time_changed_ &&
        player_->ready_state_ >= WebMediaPlayer::kReadyStateHaveCurrentData) {
      player_->should_notify_time_changed_ = false;
      player_->client_->TimeChanged();
    }
  }
  if (!route_switch) {
    return;
  }
  if (!PlaysNativeHls()) {
    if (route_switch->ready_state &&
        *route_switch->ready_state > WebMediaPlayer::kReadyStateHaveMetadata &&
        *route_switch->ready_state != player_->ready_state_) {
      player_->SetReadyState(*route_switch->ready_state);
    }
    if (audio_track_choice_) {
      player_->pipeline_controller_->OnEnabledAudioTracksChanged(
          *audio_track_choice_);
    }
    if (video_track_choice_) {
      player_->pipeline_controller_->OnSelectedVideoTrackChanged(
          *video_track_choice_);
    }
  }
  if (player_->Duration() != route_switch->duration) {
    player_->client_->DurationChanged();
  }
  player_->UpdatePlayState();
  player_->main_task_runner_->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<WebMediaPlayerImpl> player) {
                       if (player) {
                         player->parc_->UpdateRouteForPlaybackTarget();
                       }
                     },
                     player_->weak_this_));
}

bool ParcWebMediaPlayerState::DetachFairPlayCdm(
    WebContentDecryptionModuleResult& result) {
  if (!player_->cdm_context_ref_ ||
      !player_->cdm_context_ref_->GetCdmContext()->RequiresFairPlayRenderer() ||
      !ClientPresentsParcSafariIdentity(*player_->client_)) {
    return false;
  }
  cdm_detached_ = true;
  InvalidateSourceKeyChecks();
  cdm_event_registration_.reset();
  if (std::exchange(key_check_pending_, false)) {
    ++key_check_;
    SetWaitingForKey(true);
  }
  player_->pipeline_controller_->SetCdm(nullptr, base::DoNothing());
  result.Complete();
  return true;
}

void ParcWebMediaPlayerState::InvalidateSourceKeyChecks() {
  for (auto& [id, key] : source_keys_) {
    key.check = ++source_key_check_;
  }
}

void ParcWebMediaPlayerState::WillAttachCdm() {
  InvalidateSourceKeyChecks();
  cdm_detached_ = false;
  if (player_->cdm_context_ref_ && renderer_created_ &&
      player_->cdm_context_ref_->GetCdmContext() == renderer_cdm_context_) {
    replaced_cdm_context_ref_ = std::move(player_->cdm_context_ref_);
  }
  cdm_event_registration_.reset();
  if (key_check_pending_) {
    ++key_check_;
  }
}

void ParcWebMediaPlayerState::DidAttachCdm() {
  if (ClientPresentsParcSafariIdentity(*player_->client_)) {
    cdm_event_registration_ =
        player_->cdm_context_ref_->GetCdmContext()->RegisterEventCB(
            base::BindRepeating(
                [](base::WeakPtr<WebMediaPlayerImpl> player,
                   media::CdmContext::Event event) {
                  if (player) {
                    player->parc_->OnCdmEvent(event);
                  }
                },
                player_->weak_this_));
    RecheckSourceKeys();
    if (player_->load_type_ != WebMediaPlayer::kLoadTypeMediaSource &&
        !PlaysNativeHls()) {
      SetWaitingForKey(false);
    }
    if ((waiting_for_key_ || key_check_pending_) &&
        player_->load_type_ != WebMediaPlayer::kLoadTypeMediaSource) {
      CheckWaitedKey();
    }
  }
  SwitchToFairPlayIfNeeded();
}

void ParcWebMediaPlayerState::DidFailToAttachCdm() {
  RecheckSourceKeys();
  media::CdmContextRef* ref = player_->cdm_context_ref_.get();
  renderer_cdm_context_ =
      ref && ref->GetCdmContext()->RequiresFairPlayRenderer()
          ? ref->GetCdmContext()
          : nullptr;
  SetDemuxerClearDolbyVisionAllowed(ClearDolbyVisionAllowed());
}

bool ParcWebMediaPlayerState::ClearDolbyVisionAllowed() {
  if (player_->PresentsParcSafariIdentity()) {
    return true;
  }
  media::CdmContextRef* ref = player_->pending_cdm_context_ref_
                                  ? player_->pending_cdm_context_ref_.get()
                                  : player_->cdm_context_ref_.get();
  return ref && ref->GetCdmContext()->RequiresFairPlayRenderer();
}

void ParcWebMediaPlayerState::SwitchToFairPlayIfNeeded() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (!renderer_created_ ||
      player_->renderer_type_ == media::RendererType::kFairPlayHls) {
    return;
  }
  const bool fairplay_cdm =
      player_->cdm_context_ref_ &&
      player_->cdm_context_ref_->GetCdmContext()->RequiresFairPlayRenderer();
  if (player_->renderer_type_ == media::RendererType::kFairPlay) {
    if (fairplay_cdm) {
      renderer_cdm_context_ = player_->cdm_context_ref_->GetCdmContext();
    }
    return;
  }
  if ((!fairplay_cdm &&
       !DemuxerPrefersFairPlayRenderer()) ||
      !FairPlayPlaysCurrentStreams()) {
    return;
  }
  HandOffOrRestart();
}

void ParcWebMediaPlayerState::HandOffOrRestart() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (handing_off_) {
    return;
  }
  if (player_->pipeline_controller_->IsPipelineSuspended()) {
    player_->ScheduleRestart();
    return;
  }
  if (!player_->pipeline_controller_->IsStable()) {
    if (player_->seeking_) {
      handoff_after_seek_ = true;
    } else {
      player_->ScheduleRestart();
    }
    return;
  }
  handing_off_ = true;
  player_->pipeline_controller_->GetParcExtension()->ParcHandOffToFairPlay(
      base::BindOnce(
          [](base::WeakPtr<WebMediaPlayerImpl> player, bool handed_off) {
            if (player) {
              player->parc_->OnHandOff(handed_off);
            }
          },
          player_->weak_this_));
}

void ParcWebMediaPlayerState::HandOffAfterSeek() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (player_->renderer_type_ == media::RendererType::kRendererImpl) {
    HandOffOrRestart();
  }
}

void ParcWebMediaPlayerState::OnHandOff(bool handed_off) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  handing_off_ = false;
  if (!handed_off) {
    player_->ScheduleRestart();
  }
}

bool ParcWebMediaPlayerState::FairPlayPlaysCurrentStreams() const {
  return ParcFairPlayPlaysStreams(
      player_->pipeline_metadata_,
      chunk_demuxer_ && ClientPresentsParcSafariIdentity(*player_->client_));
}

void ParcWebMediaPlayerState::OnSourceBufferStreamsAdded(
    const media::PipelineMetadata& added,
    const std::vector<media::ChunkDemuxer::ParcAddedTrack>& tracks) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (player_->ready_state_ < WebMediaPlayer::kReadyStateHaveMetadata) {
    if (!streams_added_before_metadata_) {
      streams_added_before_metadata_.emplace();
    }
    ParcAddStreams(added, &*streams_added_before_metadata_);
    return;
  }
  media::PipelineMetadata& metadata = player_->pipeline_metadata_;
  const bool had_video = metadata.has_video;
  ParcAddStreams(added, &metadata);
  if (!had_video && metadata.has_video) {
    player_->ActivateSurfaceLayerForVideo();
  }
  if (player_->observer_) {
    player_->observer_->OnMetadataChanged(metadata);
  }
  player_->delegate_has_audio_ = player_->HasUnmutedAudio();
  player_->DidMediaMetadataChange();
  if (!renderer_created_) {
    player_->UpdatePlayState();
    return;
  }
  media::CdmContextRef* cdm = player_->pending_cdm_context_ref_
                                  ? player_->pending_cdm_context_ref_.get()
                                  : player_->cdm_context_ref_.get();
  const bool fairplay_cdm =
      cdm && cdm->GetCdmContext()->RequiresFairPlayRenderer();
  const bool encrypted =
      (added.has_audio && added.audio_decoder_config.is_encrypted()) ||
      (added.has_video && added.video_decoder_config.is_encrypted());
  const bool joins =
      player_->renderer_type_ == media::RendererType::kFairPlay ||
      (player_->renderer_type_ == media::RendererType::kRendererImpl &&
       !(encrypted && fairplay_cdm));
  awaits_added_streams_renderer_ = true;
  renderer_ready_ = false;
  renderer_has_enough_ = false;
  player_->delegate_->ClearStaleFlag(player_->delegate_id_);
  if (player_->ready_state_ > WebMediaPlayer::kReadyStateHaveCurrentData) {
    player_->SetReadyState(WebMediaPlayer::kReadyStateHaveMetadata);
  }
  if (joins) {
    std::optional<media::MediaTrack::Id> audio;
    std::optional<media::MediaTrack::Id> video;
    for (const media::ChunkDemuxer::ParcAddedTrack& track : tracks) {
      auto& first = track.type == media::DemuxerStream::AUDIO ? audio : video;
      if (!first) {
        first = track.id;
      }
    }
    if (audio) {
      player_->pipeline_controller_->OnEnabledAudioTracksChanged(audio);
    }
    if (video) {
      player_->pipeline_controller_->OnSelectedVideoTrackChanged(video);
    }
    player_->UpdatePlayState();
  } else if (player_->pipeline_controller_->IsPipelineSuspended()) {
    player_->UpdatePlayState();
  } else if (player_->renderer_type_ == media::RendererType::kRendererImpl &&
             FairPlayPlaysCurrentStreams()) {
    HandOffOrRestart();
  } else {
    player_->ScheduleRestart();
  }
}
#endif

void ParcWebMediaPlayerState::SourceKeyChanged(
    const std::string& id,
    media::EmeInitDataType init_data_type,
    const std::vector<uint8_t>& init_data) {
  if (init_data.empty()) {
    source_keys_.erase(id);
    SetWaitingForKey(std::ranges::any_of(source_keys_,
        [](const auto& entry) { return entry.second.waiting; }));
    return;
  }
  if (auto* parc = player_->client_->ParcClient()) {
    parc->ParcWebKitMediaSourceKeyNeeded(init_data);
  }
  source_keys_[id].init_data_type = init_data_type;
  source_keys_[id].init_data = init_data;
  source_keys_[id].deliver_encrypted = true;
  CheckSourceKey(id);
}

void ParcWebMediaPlayerState::RecheckSourceKeys() {
  for (const auto& [id, key] : source_keys_)
    CheckSourceKey(id);
}

void ParcWebMediaPlayerState::CheckSourceKey(const std::string& id) {
  auto& key = source_keys_.at(id);
  const uint64_t check = key.check = ++source_key_check_;
  auto done = base::BindOnce(
      [](base::WeakPtr<WebMediaPlayerImpl> player, std::string id,
         uint64_t check, bool has_session) {
        if (!player)
          return;
        auto it = player->parc_->source_keys_.find(id);
        if (it == player->parc_->source_keys_.end() ||
            it->second.check != check)
          return;
        auto& key = it->second;
        const bool deliver_encrypted = std::exchange(key.deliver_encrypted, false);
        if (deliver_encrypted || has_session)
          key.waiting = !has_session;
        if (!has_session && deliver_encrypted)
          player->ParcDeliverEncryptedMediaInitData(key.init_data_type,
                                                    key.init_data);
        player->parc_->SetWaitingForKey(std::ranges::any_of(
            player->parc_->source_keys_,
            [](const auto& entry) { return entry.second.waiting; }));
      }, player_->weak_this_, id, check);
  auto* ref = player_->pending_cdm_context_ref_
                  ? player_->pending_cdm_context_ref_.get()
              : cdm_detached_ ? nullptr
                              : player_->cdm_context_ref_.get();
  if (!ref) {
    std::move(done).Run(false);
    return;
  }
  ref->GetCdmContext()->ParcHasSessionForInitData(
      key.init_data_type, key.init_data, std::move(done));
}

void ParcWebMediaPlayerState::SetWaitingForKey(bool waiting) {
#if BUILDFLAG(IS_MAC)
  if (!waiting || waiting != waiting_for_key_) {
    ++key_check_;
    key_check_pending_ = false;
  }
#endif
  if (waiting == waiting_for_key_) {
    return;
  }
  waiting_for_key_ = waiting;
  if (waiting) {
    player_->has_waiting_for_key_ = true;
    player_->media_metrics_provider_->SetHasWaitingForKey();
    player_->encrypted_client_->DidBlockPlaybackWaitingForKey();
  } else {
    player_->encrypted_client_->DidResumePlaybackBlockedForKey();
  }
}

#if BUILDFLAG(IS_MAC)
void ParcWebMediaPlayerState::OnCdmEvent(media::CdmContext::Event event) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (event != media::CdmContext::Event::kHasAdditionalUsableKey &&
      event != media::CdmContext::Event::kParcKeyStatusesChanged) {
    return;
  }
  if (player_->load_type_ == WebMediaPlayer::kLoadTypeMediaSource) {
    RecheckSourceKeys();
    return;
  }
  if (waited_key_.empty()) {
    SetWaitingForKey(false);
    return;
  }
  if (waiting_for_key_ || key_check_pending_) {
    CheckWaitedKey();
  }
}

void ParcWebMediaPlayerState::WaitForStalledKey() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (!PlaysNativeHls()) {
    if (player_->cdm_context_ref_ && !cdm_detached_) {
      SetWaitingForKey(false);
      return;
    }
    waited_key_.clear();
  } else if (!last_skd_init_data_.empty()) {
    waited_key_ = last_skd_init_data_;
  }
  SetWaitingForKey(true);
  CheckWaitedKey();
}

void ParcWebMediaPlayerState::CheckWaitedKey() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (waited_key_.empty() || !player_->cdm_context_ref_ || cdm_detached_) {
    return;
  }
  const uint64_t check = ++key_check_;
  key_check_pending_ = true;
  player_->cdm_context_ref_->GetCdmContext()->ParcHasSessionForInitData(
      media::EmeInitDataType::SKD, waited_key_,
      base::BindOnce(
          [](base::WeakPtr<WebMediaPlayerImpl> player, uint64_t check,
             std::vector<uint8_t> key, bool has_session) {
            if (!player || check != player->parc_->key_check_ ||
                key != player->parc_->waited_key_) {
              return;
            }
            player->parc_->key_check_pending_ = false;
            player->parc_->SetWaitingForKey(!has_session);
          },
          player_->weak_this_, check, waited_key_));
}
#endif

void ParcWebMediaPlayerState::RestrictDemuxerCanChangeType(
    media::ChunkDemuxer::ChangeTypeFilter filter) {
  media::Demuxer* demuxer = player_->demuxer_manager_->ParcDemuxer();
  if (demuxer->GetDemuxerType() == media::DemuxerType::kChunkDemuxer) {
    static_cast<media::ChunkDemuxer*>(demuxer)->RestrictCanChangeType(
        std::move(filter));
  }
}

void ParcWebMediaPlayerState::SetDemuxerClearDolbyVisionAllowed(bool allowed) {
  media::Demuxer* demuxer = player_->demuxer_manager_->ParcDemuxer();
  if (demuxer &&
      demuxer->GetDemuxerType() == media::DemuxerType::kChunkDemuxer) {
    static_cast<media::ChunkDemuxer*>(demuxer)->ParcSetClearDolbyVisionAllowed(
        allowed);
  }
}

bool ParcWebMediaPlayerState::DemuxerPrefersFairPlayRenderer() {
  media::Demuxer* demuxer = player_->demuxer_manager_->ParcDemuxer();
  return demuxer && media::ParcDemuxerPrefersFairPlayRenderer(demuxer);
}

void ParcWebMediaPlayerState::SetDemuxerFastSeek(
    base::TimeDelta target,
    base::TimeDelta tolerance_before) {
  if (media::Demuxer* demuxer = player_->demuxer_manager_->ParcDemuxer()) {
    media::ParcSetDemuxerFastSeek(demuxer, target, tolerance_before);
  }
}

#if BUILDFLAG(IS_MAC)
void ParcWebMediaPlayerState::SendFileTrackChoices() {
  media::ParcPostNativeHlsFileTracks(player_->demuxer_manager_->ParcDemuxer(),
                                     *player_->media_task_runner_,
                                     FileTrackChoices());
}
#endif

}
