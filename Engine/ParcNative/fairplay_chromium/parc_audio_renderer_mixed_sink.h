#ifndef MEDIA_RENDERERS_PARC_AUDIO_RENDERER_MIXED_SINK_H_
#define MEDIA_RENDERERS_PARC_AUDIO_RENDERER_MIXED_SINK_H_

#include <string>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/synchronization/lock.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "media/base/audio_bus.h"
#include "media/base/audio_parameters.h"
#include "media/base/audio_renderer_sink.h"
#include "media/base/output_device_info.h"
#include "media/renderers/audio_renderer_impl.h"

namespace media {

class AudioRendererImpl::ParcMixedSink final : public AudioRendererSink {
 public:
  explicit ParcMixedSink(const AudioParameters& params) : params_(params) {}

  const AudioParameters& params() const { return params_; }

  void SetRenderer(AudioRendererImpl* renderer) {
    base::AutoLock auto_lock(lock_);
    renderer_ = renderer;
  }

  int Render(base::TimeDelta start,
             base::TimeDelta delay,
             base::TimeTicks delay_timestamp,
             AudioBus* audio_bus) {
    base::AutoLock auto_lock(lock_);
    if (!renderer_ || !started_ || !playing_) {
      return 0;
    }
    return renderer_->ParcRenderMixed(start, delay, delay_timestamp,
                                      audio_bus);
  }

  void Initialize(const AudioParameters& params,
                  RenderCallback* callback) override {}
  void Start() override {
    base::AutoLock auto_lock(lock_);
    started_ = true;
  }
  void Stop() override {
    base::AutoLock auto_lock(lock_);
    started_ = false;
    playing_ = false;
  }
  void Pause(PauseReason reason) override {
    base::AutoLock auto_lock(lock_);
    playing_ = false;
  }
  void Play() override {
    base::AutoLock auto_lock(lock_);
    playing_ = true;
  }
  void Flush() override {}
  bool SetVolume(double volume) override { return true; }
  OutputDeviceInfo GetOutputDeviceInfo() override {
    return OutputDeviceInfo(std::string(), OUTPUT_DEVICE_STATUS_OK, params_);
  }
  void GetOutputDeviceInfoAsync(OutputDeviceInfoCB info_cb) override {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(info_cb), GetOutputDeviceInfo()));
  }
  bool IsOptimizedForHardwareParameters() override { return true; }
  bool CurrentThreadIsRenderingThread() override { return false; }

 private:
  ~ParcMixedSink() override = default;

  const AudioParameters params_;
  base::Lock lock_;
  raw_ptr<AudioRendererImpl> renderer_ = nullptr;
  bool started_ = false;
  bool playing_ = false;
};

}

#endif
