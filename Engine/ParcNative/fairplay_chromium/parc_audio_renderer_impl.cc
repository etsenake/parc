#include "media/renderers/audio_renderer_impl.h"

#include <algorithm>
#include <memory>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/memory/scoped_refptr.h"
#include "base/numerics/safe_conversions.h"
#include "base/synchronization/lock.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "media/base/audio_bus.h"
#include "media/base/audio_glitch_info.h"
#include "media/base/timestamp_constants.h"
#include "media/base/vector_math.h"
#include "media/filters/audio_clock.h"
#include "media/renderers/parc_audio_renderer_mixed_sink.h"

namespace media {

namespace {

constexpr base::TimeDelta kParcMixedDriftTolerance = base::Milliseconds(30);

}

ParcAudioRendererExtension* AudioRendererImpl::GetParcExtension() {
  return this;
}

std::unique_ptr<AudioRenderer> AudioRendererImpl::ParcCreateMixedRenderer() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  {
    base::AutoLock auto_lock(lock_);
    if (state_ == kUninitialized || state_ == kInitializing ||
        audio_parameters_.IsBitstreamFormat()) {
      return nullptr;
    }
  }
  auto sink = base::MakeRefCounted<ParcMixedSink>(audio_parameters_);
  auto renderer = std::make_unique<AudioRendererImpl>(
      task_runner_, sink, create_audio_decoders_cb_, media_log_, player_id_);
  renderer->parc_mixed_sink_ = sink;
  sink->SetRenderer(renderer.get());
  base::AutoLock auto_lock(lock_);
  std::erase_if(parc_mixed_sinks_,
                [](const scoped_refptr<ParcMixedSink>& mixed_sink) {
                  return mixed_sink->HasOneRef();
                });
  parc_mixed_sinks_.push_back(std::move(sink));
  const int channels = audio_parameters_.channels();
  if (!parc_mix_bus_ || parc_mix_bus_->channels() != channels) {
    parc_mix_bus_ =
        AudioBus::Create(channels, audio_parameters_.frames_per_buffer());
    parc_mix_wrapper_ = AudioBus::CreateWrapper(channels);
  }
  return renderer;
}

void AudioRendererImpl::ParcSetOwnAudioMuted(bool muted) {
  base::AutoLock auto_lock(lock_);
  parc_own_audio_muted_ = muted;
}

int AudioRendererImpl::ParcMix_Locked(base::TimeDelta start,
                                      int own_frames,
                                      int frames,
                                      base::TimeDelta delay,
                                      base::TimeTicks delay_timestamp,
                                      AudioBus* audio_bus) {
  lock_.AssertAcquired();
  if (!frames) {
    return 0;
  }
  const int channels = audio_bus->channels();
  if (!parc_mix_bus_ || parc_mix_bus_->channels() != channels ||
      parc_mix_bus_->frames() < frames) {
    parc_mix_bus_ = AudioBus::Create(channels, audio_bus->frames());
  }
  if (!parc_mix_wrapper_ || parc_mix_wrapper_->channels() != channels) {
    parc_mix_wrapper_ = AudioBus::CreateWrapper(channels);
  }
  parc_mix_wrapper_->set_frames(frames);
  for (int ch = 0; ch < channels; ++ch) {
    parc_mix_wrapper_->SetChannelData(
        ch, parc_mix_bus_->channel(ch).first(static_cast<size_t>(frames)));
  }
  audio_bus->ZeroFramesPartial(own_frames, frames - own_frames);
  int mixed_frames = 0;
  for (const scoped_refptr<ParcMixedSink>& sink : parc_mixed_sinks_) {
    if (sink->params().channels() != channels ||
        sink->params().sample_rate() != audio_parameters_.sample_rate()) {
      continue;
    }
    const int rendered =
        sink->Render(start, delay, delay_timestamp, parc_mix_wrapper_.get());
    for (int ch = 0; ch < channels; ++ch) {
      vector_math::FMAC(
          parc_mix_wrapper_->channel(ch).first(static_cast<size_t>(rendered)),
          1.0f, audio_bus->channel(ch).first(static_cast<size_t>(rendered)));
    }
    mixed_frames = std::max(mixed_frames, rendered);
  }
  return mixed_frames;
}

int AudioRendererImpl::ParcRenderMixed(base::TimeDelta start,
                                       base::TimeDelta delay,
                                       base::TimeTicks delay_timestamp,
                                       AudioBus* audio_bus) {
  {
    base::AutoLock auto_lock(lock_);
    if (state_ == kPlaying && algorithm_ && playback_rate_ > 0) {
      const base::TimeDelta back = audio_clock_->back_timestamp();
      if (back - start > kParcMixedDriftTolerance) {
        return 0;
      }
      base::TimeDelta behind;
      if (start - back > kParcMixedDriftTolerance) {
        behind = start - back;
      }
      auto to_frames = [this](base::TimeDelta time) {
        return base::ClampFloor(time.InSecondsF() *
                                audio_parameters_.sample_rate() /
                                playback_rate_);
      };
      if (first_packet_timestamp_ != kNoTimestamp &&
          first_packet_timestamp_ > back && behind.is_positive()) {
        const int silent =
            to_frames(std::min(behind, first_packet_timestamp_ - back));
        audio_clock_->WroteAudio(silent, silent, 0, playback_rate_);
        behind = start - audio_clock_->back_timestamp();
      }
      int behind_frames = behind.is_positive() ? to_frames(behind) : 0;
      while (behind_frames > 0) {
        const int dropped = algorithm_->FillBuffer(
            audio_bus, 0, std::min(behind_frames, audio_bus->frames()),
            playback_rate_);
        if (!dropped) {
          break;
        }
        audio_clock_->WroteAudio(dropped, dropped, 0,
                                 algorithm_->effective_playback_rate());
        behind_frames -= dropped;
      }
    }
  }
  return Render(delay, delay_timestamp, AudioGlitchInfo(), audio_bus);
}

}
