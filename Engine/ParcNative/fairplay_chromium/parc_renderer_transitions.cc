// Copyright 2026 Parc contributors.
// Installed at //media/base/parc_renderer_transitions.cc.

#include "media/base/parc_renderer_transitions.h"

#include <algorithm>
#include <optional>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/bind_post_task.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/demuxer.h"
#include "media/base/parc_renderer_extensions.h"
#include "media/base/renderer.h"
#include "media/base/renderer_client.h"
#include "media/base/serial_runner.h"
#include "media/base/video_decoder_config.h"
#include "media/base/waiting.h"
#include "ui/gfx/geometry/size.h"

namespace media {

// The incoming renderer's client during a hand-off. It keeps what the
// pipeline must hear once that renderer takes over, and passes everything on
// from then.
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
    // Always: the pipeline's last state is the other renderer's.
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
    // Kept, should it take over before the hand-off ends; not ended from
    // inside the renderer's own call, which ending destroys it.
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
    ended_ = true;  // A split at the end of the stream.
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
      !host_->ParcDemuxer()->ParcBeginHandOff()) {
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
      host_->ParcDemuxer()->ParcBeginHandOff(), incoming_client_.get(),
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
  // Enough ahead for the incoming renderer to have its first frame there.
  constexpr base::TimeDelta kLead = base::Milliseconds(500);
  host_->ParcDemuxer()->ParcSplitForHandOff(
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

// At the split the playing renderer's last frame and sound end where the
// incoming renderer's begin, as Safari's one renderer plays straight on.
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
  // First, so its video renderer stops driving the video sink both share,
  // which the hole frame then takes.
  playing.reset();
  Renderer* renderer = host_->ParcRenderer();
  if (auto* parc = renderer->GetParcExtension()) {
    parc->ParcSetHidden(false);
  }
  // Before what the new renderer reports, which the caller then takes as
  // that renderer's.
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
  host_->ParcDemuxer()->ParcEndHandOff();
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
    demuxer->ParcEndHandOff();
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
  // A pause while playing backward stays backward.
  const bool backward =
      renderer && renderer->GetRendererType() == RendererType::kRendererImpl &&
      (playback_rate < 0 || (playback_rate == 0 && backward_));
  if (!host_->ParcIsPlaying() || turn_ || track_changes_ ||
      backward == backward_) {
    return;
  }

  // RendererRate() stopped time where the other direction starts.
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
  // A seek, turn or suspend flushes the renderer before it needs the demuxer.
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
  // The next Demuxer::Seek() is Resume()'s.
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
    host_->ParcDemuxer()->ParcEndHandOff();
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

}  // namespace media
