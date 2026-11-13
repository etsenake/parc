#include "media/renderers/audio_renderer_impl.h"

#include <memory>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/memory/scoped_refptr.h"
#include "base/synchronization/lock.h"
#include "base/task/sequenced_task_runner.h"
#include "media/base/audio_bus.h"
#include "media/renderers/parc_audio_renderer_mixed_sink.h"

namespace media {

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

}
