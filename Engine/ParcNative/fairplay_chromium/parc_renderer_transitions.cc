#include "media/base/parc_renderer_transitions.h"

#include <algorithm>
#include <optional>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/task/bind_post_task.h"
#include "build/build_config.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/cdm_context.h"
#include "media/base/demuxer.h"
#include "media/base/parc_demuxer_extension.h"
#include "media/base/parc_native_hls_source.h"
#include "media/base/parc_renderer_extensions.h"
#include "media/base/renderer.h"
#include "media/base/renderer_client.h"
#include "media/base/serial_runner.h"
#include "media/base/video_decoder_config.h"
#include "media/base/waiting.h"
#include "ui/gfx/geometry/size.h"

namespace media {
class ParcRendererTransitions::IncomingClient final : public RendererClient {
 public:
  explicit IncomingClient(ParcRendererTransitions* transitions)
      : transitions_(transitions) {}

  bool have_enough() const { return have_enough_; }

  void TakeOver() {
    RendererClient* client = transitions_->client_;
    taken_over_ = true;
    if (error_) {
      client->OnError(std::move(*error_));
      return;
    }
    if (natural_size_) {
      client->OnVideoNaturalSizeChange(*natural_size_);
    }
    if (audio_config_) {
      client->OnAudioConfigChange(*audio_config_);
    }
    if (video_config_) {
      client->OnVideoConfigChange(*video_config_);
    }
    if (opaque_) {
      client->OnVideoOpacityChange(*opaque_);
    }
    if (fps_) {
      client->OnVideoFrameRateChange(*fps_);
    }
    client->OnBufferingStateChange(
        have_enough_ ? BUFFERING_HAVE_ENOUGH : BUFFERING_HAVE_NOTHING,
        BUFFERING_CHANGE_REASON_UNKNOWN);
    if (waiting_) {
      client->OnWaiting(*waiting_);
    }
    if (ended_) {
      client->OnEnded();
    }
  }

  void OnError(PipelineStatus status) final {
    if (taken_over_) {
      transitions_->client_->OnError(std::move(status));
      return;
    }
    error_ = std::move(status);
    transitions_->media_task_runner_->PostTask(
        FROM_HERE,
        base::BindOnce(&ParcRendererTransitions::Abort,
                       transitions_->handoff_weak_factory_.GetWeakPtr(),
                       /*restart=*/true));
  }
  void OnFallback(PipelineStatus status) final {
    if (taken_over_) {
      transitions_->client_->OnFallback(std::move(status));
    }
  }
  void OnEnded() final {
    if (taken_over_) {
      transitions_->client_->OnEnded();
      return;
    }
    ended_ = true;
  }
  void OnStatisticsUpdate(const PipelineStatistics& stats) final {
    if (taken_over_) {
      transitions_->client_->OnStatisticsUpdate(stats);
    }
  }
  void OnBufferingStateChange(BufferingState state,
                              BufferingStateChangeReason reason) final {
    if (taken_over_) {
      transitions_->client_->OnBufferingStateChange(state, reason);
      return;
    }
    have_enough_ = state == BUFFERING_HAVE_ENOUGH;
    if (have_enough_) {
      waiting_.reset();
      transitions_->FollowPlayingClock();
    }
  }
  void OnWaiting(WaitingReason reason) final {
    if (taken_over_) {
      transitions_->client_->OnWaiting(reason);
      return;
    }
    waiting_ = reason;
  }
  void OnAudioConfigChange(const AudioDecoderConfig& config) final {
    if (taken_over_) {
      transitions_->client_->OnAudioConfigChange(config);
      return;
    }
    audio_config_ = config;
  }
  void OnVideoConfigChange(const VideoDecoderConfig& config) final {
    if (taken_over_) {
      transitions_->client_->OnVideoConfigChange(config);
      return;
    }
    video_config_ = config;
  }
  void OnVideoNaturalSizeChange(const gfx::Size& size) final {
    if (taken_over_) {
      transitions_->client_->OnVideoNaturalSizeChange(size);
      return;
    }
    natural_size_ = size;
  }
  void OnVideoOpacityChange(bool opaque) final {
    if (taken_over_) {
      transitions_->client_->OnVideoOpacityChange(opaque);
      return;
    }
    opaque_ = opaque;
  }
  void OnVideoFrameRateChange(std::optional<int> fps) final {
    if (taken_over_) {
      transitions_->client_->OnVideoFrameRateChange(fps);
      return;
    }
    fps_ = fps;
  }

 private:
  const raw_ptr<ParcRendererTransitions> transitions_;
  bool taken_over_ = false;
  bool have_enough_ = false;
  bool ended_ = false;
  std::optional<PipelineStatus> error_;
  std::optional<WaitingReason> waiting_;
  std::optional<bool> opaque_;
  std::optional<std::optional<int>> fps_;
  std::optional<gfx::Size> natural_size_;
  std::optional<AudioDecoderConfig> audio_config_;
  std::optional<VideoDecoderConfig> video_config_;
};

ParcRendererTransitions::ParcRendererTransitions(
    Host* host,
    RendererClient* client,
    scoped_refptr<base::SequencedTaskRunner> media_task_runner)
    : host_(host),
      client_(client),
      media_task_runner_(std::move(media_task_runner)) {
  DETACH_FROM_SEQUENCE(sequence_checker_);
}

ParcRendererTransitions::~ParcRendererTransitions() = default;

void ParcRendererTransitions::HandOff(base::OnceCallback<void(bool)> done) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  Renderer* renderer = host_->ParcRenderer();
  if (!host_->ParcIsPlaying() || handoff_done_ || handed_off_ || backward_ ||
      turn_ || host_->ParcPlaybackRate() < 0 || !renderer ||
      renderer->GetRendererType() == RendererType::kFairPlay ||
      renderer->GetRendererType() == RendererType::kFairPlayHls ||
      !ParcBeginDemuxerHandOff(host_->ParcDemuxer())) {
    std::move(done).Run(false);
    return;
  }
  handoff_done_ = std::move(done);
  host_->ParcCreateFairPlayRenderer(base::BindPostTaskToCurrentDefault(
      base::BindOnce(&ParcRendererTransitions::OnIncomingCreated,
                     handoff_weak_factory_.GetWeakPtr())));
}

void ParcRendererTransitions::OnIncomingCreated(
    std::unique_ptr<Renderer> renderer) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!handoff_done_) {
    return;
  }
  if (!renderer) {
    Abort(/*restart=*/true);
    return;
  }
  incoming_ = std::move(renderer);
  incoming_client_ = std::make_unique<IncomingClient>(this);
  if (auto* parc = incoming_->GetParcExtension()) {
    parc->ParcSetHidden(true);
  }
  host_->ParcConfigureRenderer(*incoming_);
  incoming_->Initialize(
      ParcBeginDemuxerHandOff(host_->ParcDemuxer()), incoming_client_.get(),
      base::BindOnce(&ParcRendererTransitions::OnIncomingInitialized,
                     handoff_weak_factory_.GetWeakPtr()));
}

void ParcRendererTransitions::OnIncomingInitialized(PipelineStatus status) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!handoff_done_) {
    return;
  }
  if (status != PIPELINE_OK) {
    Abort(/*restart=*/true);
    return;
  }
  constexpr base::TimeDelta kLead = base::Milliseconds(500);
  ParcSplitDemuxerForHandOff(
      host_->ParcDemuxer(),
      host_->ParcCurrentTimestamp() + kLead,
      base::BindOnce(&ParcRendererTransitions::OnSplit,
                     handoff_weak_factory_.GetWeakPtr()));
}

void ParcRendererTransitions::OnSplit(base::TimeDelta time) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!handoff_done_) {
    return;
  }
  split_ = true;
  incoming_->StartPlayingFrom(time);
}

void ParcRendererTransitions::FollowPlayingClock() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!split_ || !incoming_client_->have_enough()) {
    return;
  }
  Renderer* playing = host_->ParcRenderer();
  const double rate = host_->ParcIsPlaying() && !turn_ &&
                              buffering_state_ == BUFFERING_HAVE_ENOUGH
                          ? RendererRate()
                          : 0;
  if (auto* parc = incoming_->GetParcExtension()) {
    parc->ParcSetPlaybackRateAt(rate, playing->GetMediaTime(),
                                base::TimeTicks::Now());
  }
}

bool ParcRendererTransitions::TakeOverAtSplit() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!split_) {
    return false;
  }
  Swap();
  return true;
}

void ParcRendererTransitions::Swap() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  std::unique_ptr<Renderer> playing =
      host_->ParcReplaceRenderer(std::move(incoming_));
  handoff_weak_factory_.InvalidateWeakPtrs();
  split_ = false;
  handed_off_ = true;
  playing.reset();
  Renderer* renderer = host_->ParcRenderer();
  if (auto* parc = renderer->GetParcExtension()) {
    parc->ParcSetHidden(false);
  }
  std::move(handoff_done_).Run(true);
  incoming_client_->TakeOver();
  if (host_->ParcIsPlaying()) {
    renderer->SetPlaybackRate(RendererRate());
  }
  RunDeferredTrackChanges();
}

void ParcRendererTransitions::Settle() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!handoff_done_) {
    return;
  }
  if (split_) {
    Swap();
  } else {
    Abort(/*restart=*/true);
  }
}

void ParcRendererTransitions::Abort(bool restart) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!handoff_done_) {
    return;
  }
  handoff_weak_factory_.InvalidateWeakPtrs();
  incoming_.reset();
  incoming_client_.reset();
  split_ = false;
  ParcEndDemuxerHandOff(host_->ParcDemuxer());
  std::move(handoff_done_).Run(!restart);
  RunDeferredTrackChanges();
}

void ParcRendererTransitions::DestroyRenderer(
    std::unique_ptr<Renderer> renderer) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!handed_off_) {
    return;
  }
  renderer.reset();
  incoming_client_.reset();
  handed_off_ = false;
  if (Demuxer* demuxer = host_->ParcDemuxer()) {
    ParcEndDemuxerHandOff(demuxer);
  }
}

double ParcRendererTransitions::RendererRate() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  Renderer* renderer = host_->ParcRenderer();
  const double playback_rate = host_->ParcPlaybackRate();
  if (playback_rate >= 0 || !renderer) {
    return playback_rate;
  }
  const RendererType type = renderer->GetRendererType();
  if (type == RendererType::kFairPlayHls ||
      (type == RendererType::kRendererImpl && backward_)) {
    return playback_rate;
  }
  return 0;
}

void ParcRendererTransitions::TurnIfNeeded() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  Renderer* renderer = host_->ParcRenderer();
  const double playback_rate = host_->ParcPlaybackRate();
  const bool backward =
      renderer && renderer->GetRendererType() == RendererType::kRendererImpl &&
      (playback_rate < 0 || (playback_rate == 0 && backward_));
  if (!host_->ParcIsPlaying() || turn_ || track_changes_ ||
      backward == backward_) {
    return;
  }

  Demuxer* demuxer = host_->ParcDemuxer();
  const base::TimeDelta time =
      std::max(renderer->GetMediaTime(), demuxer->GetStartTime());
  demuxer->AbortPendingReads();
  SerialRunner::Queue fns;
  fns.Push(base::BindOnce(&Renderer::Flush, base::Unretained(renderer)));
  if (backward_) {
    fns.Push(base::BindOnce(&Demuxer::Seek, base::Unretained(demuxer), time));
  }
  turn_ = SerialRunner::Run(
      std::move(fns), base::BindOnce(&ParcRendererTransitions::CompleteTurn,
                                     weak_factory_.GetWeakPtr(), time));
}

void ParcRendererTransitions::CompleteTurn(base::TimeDelta time,
                                           PipelineStatus status) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  DCHECK(turn_);
  turn_.reset();
  if (status != PIPELINE_OK) {
    host_->ParcOnPipelineError(status);
    return;
  }

  Renderer* renderer = host_->ParcRenderer();
  backward_ = !backward_;
  turned_ = true;
  if (backward_) {
    if (auto* parc = renderer->GetParcExtension()) {
      parc->ParcStartPlayingBackwardFrom(
          time, std::min(host_->ParcPlaybackRate(), 0.0),
          base::BindRepeating(&ParcRendererTransitions::SeekDemuxer,
                              weak_factory_.GetWeakPtr()));
    }
  } else {
    renderer->StartPlayingFrom(time);
    renderer->SetPlaybackRate(RendererRate());
  }

  if (deferred_op_) {
    std::move(deferred_op_).Run();
    return;
  }
  TurnIfNeeded();
  RunDeferredTrackChanges();
}

void ParcRendererTransitions::SeekDemuxer(base::TimeDelta time,
                                          base::OnceClosure done) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!host_->ParcIsPlaying() || turn_ || !backward_) {
    return;
  }
  DCHECK(!demuxer_seek_pending_);
  demuxer_seek_pending_ = true;
  Demuxer* demuxer = host_->ParcDemuxer();
  demuxer->AbortPendingReads();
  demuxer->Seek(std::max(time, demuxer->GetStartTime()),
                base::BindOnce(&ParcRendererTransitions::OnDemuxerSeeked,
                               weak_factory_.GetWeakPtr(), std::move(done)));
}

void ParcRendererTransitions::OnDemuxerSeeked(base::OnceClosure done,
                                              PipelineStatus status) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  demuxer_seek_pending_ = false;
  if (status != PIPELINE_OK) {
    host_->ParcOnPipelineError(status);
    return;
  }
  std::move(done).Run();
}

void ParcRendererTransitions::DeferUntilTurned(base::OnceClosure op) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  deferred_op_ = std::move(op);
}

bool ParcRendererTransitions::DefersTrackChanges() const {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  return backward_ || turn_ || handoff_done_;
}

void ParcRendererTransitions::DeferTrackChange(base::OnceClosure change) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  deferred_track_changes_.push_back(std::move(change));
}

base::OnceClosure ParcRendererTransitions::CountTrackChange(
    base::OnceClosure change_completed_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  ++track_changes_;
  return base::BindOnce(&ParcRendererTransitions::OnTrackChangeDone,
                        weak_factory_.GetWeakPtr(),
                        std::move(change_completed_cb));
}

void ParcRendererTransitions::OnTrackChangeDone(
    base::OnceClosure change_completed_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  --track_changes_;
  std::move(change_completed_cb).Run();
  TurnIfNeeded();
}

void ParcRendererTransitions::RunDeferredTrackChanges() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (DefersTrackChanges()) {
    return;
  }
  std::vector<base::OnceClosure> changes;
  changes.swap(deferred_track_changes_);
  for (auto& change : changes) {
    std::move(change).Run();
  }
}

bool ParcRendererTransitions::OnBufferingStateChange(BufferingState state) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  const bool repeated = turned_ && state == buffering_state_;
  turned_ = false;
  buffering_state_ = state;
  FollowPlayingClock();
  return repeated;
}

void ParcRendererTransitions::OnSeeking() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  backward_ = false;
  buffering_state_ = BUFFERING_HAVE_NOTHING;
  turned_ = false;
}

void ParcRendererTransitions::OnSuspending() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (demuxer_seek_pending_) {
    host_->ParcDemuxer()->AbortPendingReads();
  }
  backward_ = false;
}

void ParcRendererTransitions::OnResuming() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  buffering_state_ = BUFFERING_HAVE_NOTHING;
  turned_ = false;
}

void ParcRendererTransitions::Stop() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  turn_.reset();
  handoff_weak_factory_.InvalidateWeakPtrs();
  incoming_.reset();
  if (handoff_done_ && host_->ParcDemuxer()) {
    ParcEndDemuxerHandOff(host_->ParcDemuxer());
  }
  handoff_done_.Reset();
  split_ = false;
  deferred_op_.Reset();
  deferred_track_changes_.clear();
  backward_ = false;
  track_changes_ = 0;
  demuxer_seek_pending_ = false;
  buffering_state_ = BUFFERING_HAVE_NOTHING;
  turned_ = false;
  weak_factory_.InvalidateWeakPtrs();
}

void ParcRendererTransitions::OnStart() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
#if BUILDFLAG(IS_MAC)
  CdmContext* cdm_context = host_->ParcCdmContext();
  Demuxer* demuxer = host_->ParcDemuxer();
  if (cdm_context && !cdm_detached_ && demuxer->GetParcNativeHlsSource()) {
    demuxer->GetParcNativeHlsSource()->SetCdm(cdm_context, base::DoNothing());
  }
#endif
}

bool ParcRendererTransitions::SetCdm(
    CdmContext* cdm_context,
    base::OnceCallback<void(bool)>& cdm_attached_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  Abort(/*restart=*/true);
#if BUILDFLAG(IS_MAC)
  Renderer* renderer = host_->ParcRenderer();
  Demuxer* demuxer = host_->ParcDemuxer();
  parc::fairplay::NativeHlsSource* native =
      demuxer ? demuxer->GetParcNativeHlsSource() : nullptr;
  if (!cdm_context) {
    cdm_detached_ = true;
    if (renderer &&
        (renderer->GetRendererType() == RendererType::kFairPlay ||
         renderer->GetRendererType() == RendererType::kFairPlayHls)) {
      renderer->SetCdm(nullptr, std::move(cdm_attached_cb));
      return true;
    }
    if (!renderer && native) {
      native->SetCdm(nullptr, std::move(cdm_attached_cb));
      return true;
    }
    std::move(cdm_attached_cb).Run(true);
    return true;
  }
  CdmContext* current = host_->ParcCdmContext();
  if (renderer && renderer->GetRendererType() != RendererType::kFairPlay &&
      current && current != cdm_context &&
      current->RequiresFairPlayRenderer() &&
      cdm_context->RequiresFairPlayRenderer() && !native) {
    host_->ParcSetCdmContext(cdm_context);
    cdm_detached_ = false;
    std::move(cdm_attached_cb).Run(true);
    return true;
  }
  if (!renderer && native) {
    native->SetCdm(
        cdm_context,
        base::BindOnce(
            [](base::WeakPtr<ParcRendererTransitions> transitions,
               base::OnceCallback<void(bool)> callback, CdmContext* context,
               bool success) {
              if (transitions) {
                transitions->host_->ParcOnCdmAttached(std::move(callback),
                                                      context, success);
              } else {
                std::move(callback).Run(success);
              }
            },
            cdm_weak_factory_.GetWeakPtr(), std::move(cdm_attached_cb),
            cdm_context));
    return true;
  }
#endif
  return false;
}

void ParcRendererTransitions::SetVolume(float volume) {
  if (incoming_) {
    incoming_->SetVolume(volume);
  }
}

void ParcRendererTransitions::SetLatencyHint(
    std::optional<base::TimeDelta> latency_hint) {
  if (incoming_) {
    incoming_->SetLatencyHint(latency_hint);
  }
}

void ParcRendererTransitions::SetPreservesPitch(bool preserves_pitch) {
  if (incoming_) {
    incoming_->SetPreservesPitch(preserves_pitch);
  }
}

void ParcRendererTransitions::SetRenderMutedAudio(bool render_muted_audio) {
  if (incoming_) {
    incoming_->SetRenderMutedAudio(render_muted_audio);
  }
}

void ParcRendererTransitions::OnAudioOutputDeviceChanged() {
  if (Renderer* renderer = host_->ParcRenderer()) {
    if (ParcRendererExtension* parc = renderer->GetParcExtension()) {
      parc->ParcOnAudioOutputDeviceChanged();
    }
  }
  if (incoming_) {
    if (ParcRendererExtension* parc = incoming_->GetParcExtension()) {
      parc->ParcOnAudioOutputDeviceChanged();
    }
  }
}

base::TimeDelta ParcRendererTransitions::FastSeekLanding(
    base::TimeDelta seek_time) {
  return ParcTakeDemuxerFastSeekLanding(host_->ParcDemuxer())
      .value_or(seek_time);
}

std::optional<RendererType> ParcRendererTypeFor(CdmContext* cdm_context,
                                                Demuxer* demuxer) {
  std::optional<RendererType> renderer_type;
#if BUILDFLAG(IS_MAC)
  if (cdm_context && cdm_context->RequiresFairPlayRenderer()) {
    renderer_type = RendererType::kFairPlay;
  }
  if (ParcDemuxerPrefersFairPlayRenderer(demuxer)) {
    renderer_type = RendererType::kFairPlay;
  }
  if (demuxer->GetParcNativeHlsSource()) {
    renderer_type = RendererType::kFairPlayHls;
  }
#endif
  return renderer_type;
}

}
