#include "media/renderers/renderer_impl.h"

#include <algorithm>
#include <memory>
#include <utility>
#include <vector>

#include "base/barrier_closure.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/task/sequenced_task_runner.h"
#include "media/base/audio_renderer.h"
#include "media/base/cdm_context.h"
#include "media/base/demuxer_stream.h"
#include "media/base/media_resource.h"
#include "media/base/parc_demuxer_stream_extension.h"
#include "media/base/parc_renderer_extensions.h"
#include "media/base/renderer_client.h"
#include "media/base/time_source.h"
#include "media/base/video_renderer.h"
#include "media/renderers/parc_renderer_impl_mixed_audio.h"

namespace media {

namespace {
bool ParcIsEncrypted(DemuxerStream* stream) {
  return stream->type() == DemuxerStream::AUDIO
             ? stream->audio_decoder_config().is_encrypted()
             : stream->video_decoder_config().is_encrypted();
}
}

void RendererImpl::OnParcJoinInitialized(DemuxerStream* stream,
                                         base::OnceClosure join_completed_cb,
                                         PipelineStatus status) {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  const bool was_waiting = WaitingForEnoughData();
  const bool audio = stream->type() == DemuxerStream::AUDIO;
  (audio ? parc_audio_join_awaiting_cdm_ : parc_video_join_awaiting_cdm_) =
      nullptr;
  (audio ? parc_audio_joining_ : parc_video_joining_) = false;
  if (status != PIPELINE_OK) {
    std::move(join_completed_cb).Run();
    OnError(status);
    return;
  }
  if (state_ != STATE_PLAYING && state_ != STATE_FLUSHED &&
      state_ != STATE_FLUSHING) {
    std::move(join_completed_cb).Run();
    return;
  }
  const bool ended = state_ == STATE_PLAYING && PlaybackHasEnded();
  const base::TimeDelta now = GetMediaTime();
  if (audio) {
    audio_renderer_ = std::move(parc_audio_renderer_);
    current_audio_stream_ = stream;
    audio_ended_ = ended;
  } else {
    video_renderer_ = std::move(parc_video_renderer_);
    current_video_stream_ = stream;
    video_ended_ = ended;
  }
  if (time_ticking_) {
    PausePlayback();
  }
  if (audio) {
    {
      base::AutoLock lock(restarting_audio_lock_);
      time_source_ = audio_renderer_->GetTimeSource();
    }
    time_source_->SetMediaTime(now);
    time_source_->SetPlaybackRate(playback_rate_);
  }
  if (state_ == STATE_PLAYING) {
    if (audio) {
      audio_playing_ = true;
      audio_renderer_->StartPlaying();
    } else {
      video_playing_ = true;
      video_renderer_->StartPlayingFrom(now);
    }
    if (!was_waiting) {
      client_->OnBufferingStateChange(BUFFERING_HAVE_NOTHING,
                                      BUFFERING_CHANGE_REASON_UNKNOWN);
    }
  }
  if (audio && media_resource_->ParcMayAddStreams()) {
    parc_own_audio_muted_ = !ParcStreamIsEnabled(stream);
    if (auto* parc = audio_renderer_->GetParcExtension()) {
      parc->ParcSetOwnAudioMuted(parc_own_audio_muted_);
    }
    ParcSyncMixedAudio();
  }
  std::move(join_completed_cb).Run();
}

bool RendererImpl::ParcAwaitsCdm(DemuxerStream* stream) {
  return !cdm_context_ && ParcIsEncrypted(stream);
}

bool RendererImpl::ParcCannotDecrypt(DemuxerStream* stream) {
  return cdm_context_ && cdm_context_->RequiresFairPlayRenderer() &&
         ParcIsEncrypted(stream);
}

void RendererImpl::ParcSyncMixedAudio() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  if (!audio_renderer_ || !media_resource_->ParcMayAddStreams() ||
      (state_ != STATE_INITIALIZING && state_ != STATE_FLUSHED &&
       state_ != STATE_FLUSHING && state_ != STATE_PLAYING)) {
    return;
  }
  std::vector<DemuxerStream*> enabled;
  for (DemuxerStream* stream : media_resource_->GetAllStreams()) {
    if (stream->type() == DemuxerStream::AUDIO &&
        stream != current_audio_stream_ && ParcStreamIsEnabled(stream) &&
        !ParcCannotDecrypt(stream)) {
      enabled.push_back(stream);
    }
  }
  const bool was_waiting = WaitingForEnoughData();
  const bool ended = state_ == STATE_PLAYING && PlaybackHasEnded();
  std::vector<base::OnceClosure> flush_done_cbs;
  std::erase_if(parc_mixed_audio_, [&](const std::unique_ptr<ParcMixedAudio>&
                                           mixed) {
    if (std::ranges::contains(enabled, mixed->stream.get())) {
      return false;
    }
    if (mixed->flush_done_cb) {
      flush_done_cbs.push_back(std::move(mixed->flush_done_cb));
    }
    return true;
  });
  std::vector<ParcMixedAudio*> initializing;
  for (DemuxerStream* stream : enabled) {
    auto it = std::ranges::find(parc_mixed_audio_, stream,
                                [](const std::unique_ptr<ParcMixedAudio>& m) {
                                  return m->stream.get();
                                });
    if (it != parc_mixed_audio_.end() &&
        ((*it)->renderer || ParcAwaitsCdm(stream))) {
      continue;
    }
    std::unique_ptr<AudioRenderer> renderer;
    if (ParcAwaitsCdm(stream)) {
      OnWaiting(WaitingReason::kNoCdm);
    } else {
      if (auto* parc = audio_renderer_->GetParcExtension()) {
        renderer = parc->ParcCreateMixedRenderer();
      }
      if (!renderer) {
        if (it != parc_mixed_audio_.end()) {
          parc_mixed_audio_.erase(it);
        }
        continue;
      }
    }
    ParcMixedAudio* mixed = it != parc_mixed_audio_.end() ? it->get() : nullptr;
    if (!mixed) {
      mixed = parc_mixed_audio_.emplace_back(std::make_unique<ParcMixedAudio>())
                  .get();
      mixed->id = ++parc_last_mixed_audio_id_;
      mixed->stream = stream;
      mixed->client = std::make_unique<ParcMixedAudioClient>(this, mixed->id);
      mixed->ended = ended;
    }
    if (renderer) {
      mixed->renderer = std::move(renderer);
      initializing.push_back(mixed);
    }
  }
  for (ParcMixedAudio* mixed : initializing) {
    mixed->renderer->SetLatencyHint(parc_latency_hint_);
    mixed->renderer->SetPreservesPitch(parc_preserves_pitch_);
    mixed->renderer->Initialize(
        mixed->stream, cdm_context_, mixed->client.get(),
        base::BindOnce(&RendererImpl::OnParcMixedAudioInitialized, weak_this_,
                       mixed->id));
  }
  ParcUpdateWaiting(was_waiting, BUFFERING_CHANGE_REASON_UNKNOWN);
  if (!ended && state_ == STATE_PLAYING && PlaybackHasEnded()) {
    RunEndedCallbackIfNeeded();
  }
  for (base::OnceClosure& flush_done_cb : flush_done_cbs) {
    std::move(flush_done_cb).Run();
  }
}

RendererImpl::ParcMixedAudio* RendererImpl::ParcFindMixedAudio(int id) {
  auto it = std::ranges::find(parc_mixed_audio_, id,
                              [](const std::unique_ptr<ParcMixedAudio>& m) {
                                return m->id;
                              });
  return it != parc_mixed_audio_.end() ? it->get() : nullptr;
}

void RendererImpl::OnParcMixedAudioInitialized(int id, PipelineStatus status) {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  ParcMixedAudio* mixed = ParcFindMixedAudio(id);
  if (!mixed || state_ == STATE_ERROR) {
    return;
  }
  if (status != PIPELINE_OK) {
    OnError(status);
    return;
  }
  mixed->initialized = true;
  if (state_ == STATE_INITIALIZING) {
    if (std::ranges::all_of(parc_mixed_audio_, [](const auto& other) {
          return !other->renderer || other->initialized;
        })) {
      state_ = STATE_FLUSHED;
      FinishInitialization(PIPELINE_OK);
    }
    return;
  }
  if (state_ == STATE_PLAYING && !parc_backward_) {
    if (time_ticking_) {
      PausePlayback();
    }
    ParcStartMixedAudio(*mixed, GetMediaTime());
  }
}

void RendererImpl::ParcStartMixedAudio(ParcMixedAudio& mixed,
                                       base::TimeDelta time) {
  DCHECK(mixed.initialized);
  TimeSource* time_source = mixed.renderer->GetTimeSource();
  time_source->SetMediaTime(time);
  time_source->SetPlaybackRate(std::max(playback_rate_, 0.0));
  mixed.playing = true;
  mixed.buffering_state = BUFFERING_HAVE_NOTHING;
  mixed.renderer->StartPlaying();
}

void RendererImpl::ParcFlushMixedAudio(base::OnceClosure flush_done_cb) {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  std::vector<ParcMixedAudio*> playing;
  for (const auto& mixed : parc_mixed_audio_) {
    if (mixed->playing) {
      playing.push_back(mixed.get());
    }
  }
  base::RepeatingClosure done =
      base::BarrierClosure(playing.size(), std::move(flush_done_cb));
  for (ParcMixedAudio* mixed : playing) {
    mixed->flush_done_cb = done;
    mixed->renderer->Flush(base::BindOnce(
        &RendererImpl::OnParcMixedAudioFlushed, weak_this_, mixed->id));
  }
}

void RendererImpl::OnParcMixedAudioFlushed(int id) {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  ParcMixedAudio* mixed = ParcFindMixedAudio(id);
  if (!mixed) {
    return;
  }
  mixed->playing = false;
  mixed->ended = false;
  mixed->buffering_state = BUFFERING_HAVE_NOTHING;
  if (mixed->flush_done_cb) {
    std::move(mixed->flush_done_cb).Run();
  }
}

void RendererImpl::OnParcMixedAudioBufferingStateChange(
    int id,
    BufferingState state,
    BufferingStateChangeReason reason) {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  ParcMixedAudio* mixed = ParcFindMixedAudio(id);
  if (!mixed || !mixed->playing) {
    return;
  }
  const bool was_waiting = WaitingForEnoughData();
  mixed->buffering_state = state;
  ParcUpdateWaiting(was_waiting, reason);
}

void RendererImpl::OnParcMixedAudioEnded(int id) {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  ParcMixedAudio* mixed = ParcFindMixedAudio(id);
  if (!mixed || !mixed->playing || state_ != STATE_PLAYING ||
      PlaybackHasEnded()) {
    return;
  }
  mixed->ended = true;
  RunEndedCallbackIfNeeded();
}

void RendererImpl::ParcUpdateWaiting(bool was_waiting,
                                     BufferingStateChangeReason reason) {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  if (state_ != STATE_PLAYING || parc_backward_) {
    return;
  }
  const bool waiting = WaitingForEnoughData();
  if (!was_waiting && waiting) {
    PausePlayback();
    client_->OnBufferingStateChange(BUFFERING_HAVE_NOTHING, reason);
  } else if (was_waiting && !waiting && !pending_audio_track_change_ &&
             !pending_video_track_change_) {
    StartPlayback();
    client_->OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, reason);
  }
}

ParcRendererExtension* RendererImpl::GetParcExtension() {
  return this;
}

void RendererImpl::ParcStartPlayingBackwardFrom(
    base::TimeDelta time,
    double playback_rate,
    ParcSeekDemuxerCB seek_demuxer_cb) {
  DVLOG(1) << __func__ << "(" << time.InMicroseconds() << ", "
           << playback_rate << ")";
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  DCHECK_LE(playback_rate, 0);

  if (state_ != STATE_FLUSHED) {
    DCHECK_EQ(state_, STATE_ERROR);
    return;
  }

  state_ = STATE_PLAYING;
  parc_backward_ = true;
  parc_backward_reported_ = false;
  parc_backward_ended_ = false;
  playback_rate_ = playback_rate;
  parc_backward_clock_.SetMediaTime(time);
  parc_backward_clock_.SetPlaybackRate(playback_rate);
  {
    base::AutoLock lock(restarting_audio_lock_);
    parc_backward_clock_used_ = true;
  }

  if (video_renderer_) {
    video_playing_ = true;
    if (auto* parc = video_renderer_->GetParcExtension()) {
      parc->ParcStartPlayingBackwardFrom(time, std::move(seek_demuxer_cb));
    }
    return;
  }

  parc_backward_reported_ = true;
  if (playback_rate < 0) {
    ParcStartBackwardClock();
  }
  task_runner_->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<RendererImpl> renderer) {
                       if (renderer && renderer->parc_backward_ &&
                           renderer->state_ == STATE_PLAYING) {
                         renderer->client_->OnBufferingStateChange(
                             BUFFERING_HAVE_ENOUGH,
                             BUFFERING_CHANGE_REASON_UNKNOWN);
                       }
                     },
                     weak_this_));
}

void RendererImpl::ParcStartBackwardClock() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  DCHECK(parc_backward_);
  if (parc_backward_ticking_ || parc_backward_ended_) {
    return;
  }
  parc_backward_ticking_ = true;
  parc_backward_clock_.StartTicking();
  if (video_renderer_) {
    video_renderer_->OnTimeProgressing();
  }
  ParcScheduleReachStart();
}

void RendererImpl::ParcStopBackwardClock() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  parc_reach_start_cb_.Cancel();
  if (!parc_backward_ticking_) {
    return;
  }
  parc_backward_ticking_ = false;
  parc_backward_clock_.StopTicking();
  if (video_renderer_) {
    video_renderer_->OnTimeStopped();
  }
}

void RendererImpl::ParcScheduleReachStart() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  parc_reach_start_cb_.Cancel();
  if (!parc_backward_ticking_ || playback_rate_ >= 0) {
    return;
  }
  const base::TimeDelta left = parc_backward_clock_.CurrentMediaTime();
  parc_reach_start_cb_.Reset(
      base::BindOnce(&RendererImpl::ParcReachStart, weak_this_));
  task_runner_->PostDelayedTask(
      FROM_HERE, parc_reach_start_cb_.callback(),
      std::max(base::TimeDelta(), left / -playback_rate_));
}

void RendererImpl::ParcReachStart() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  if (parc_backward_clock_.CurrentMediaTime().is_positive()) {
    ParcScheduleReachStart();
    return;
  }
  ParcStopBackwardClock();
  parc_backward_clock_.SetMediaTime(base::TimeDelta());
  parc_backward_ended_ = true;
  client_->OnEnded();
}

void RendererImpl::ParcEndBackward() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  ParcStopBackwardClock();
  parc_backward_ = false;
  time_source_->SetMediaTime(std::max(
      base::TimeDelta(), parc_backward_clock_.CurrentMediaTime()));
  base::AutoLock lock(restarting_audio_lock_);
  parc_backward_clock_used_ = false;
}

}
