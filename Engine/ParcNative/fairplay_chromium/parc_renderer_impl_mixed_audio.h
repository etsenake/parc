#ifndef MEDIA_RENDERERS_PARC_RENDERER_IMPL_MIXED_AUDIO_H_
#define MEDIA_RENDERERS_PARC_RENDERER_IMPL_MIXED_AUDIO_H_

#include <memory>
#include <optional>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "media/base/audio_renderer.h"
#include "media/base/buffering_state.h"
#include "media/base/demuxer_stream.h"
#include "media/base/media_resource.h"
#include "media/base/pipeline_status.h"
#include "media/base/renderer_client.h"
#include "media/renderers/renderer_impl.h"

namespace media {

struct RendererImpl::ParcMixedAudio {
  int id = 0;
  raw_ptr<DemuxerStream> stream;
  std::unique_ptr<ParcMixedAudioClient> client;
  std::unique_ptr<AudioRenderer> renderer;
  bool initialized = false;
  bool playing = false;
  bool ticking = false;
  bool ended = false;
  BufferingState buffering_state = BUFFERING_HAVE_NOTHING;
  base::OnceClosure flush_done_cb;
};

class RendererImpl::ParcMixedAudioClient final : public RendererClient {
 public:
  ParcMixedAudioClient(RendererImpl* renderer, int id)
      : renderer_(renderer), id_(id) {}

  void OnError(PipelineStatus error) override { renderer_->OnError(error); }
  void OnFallback(PipelineStatus error) override {
    renderer_->OnFallback(std::move(error).AddHere());
  }
  void OnEnded() override { renderer_->OnParcMixedAudioEnded(id_); }
  void OnStatisticsUpdate(const PipelineStatistics& stats) override {
    renderer_->OnStatisticsUpdate(stats);
  }
  void OnBufferingStateChange(BufferingState state,
                              BufferingStateChangeReason reason) override {
    renderer_->OnParcMixedAudioBufferingStateChange(id_, state, reason);
  }
  void OnWaiting(WaitingReason reason) override {
    renderer_->OnWaiting(reason);
  }
  void OnAudioConfigChange(const AudioDecoderConfig& config) override {}
  void OnVideoConfigChange(const VideoDecoderConfig& config) override {}
  void OnVideoNaturalSizeChange(const gfx::Size& size) override {}
  void OnVideoOpacityChange(bool opaque) override {}
  void OnVideoFrameRateChange(std::optional<int> fps) override {}
  bool IsVideoStreamAvailable() override {
    return renderer_->media_resource_->GetFirstStream(DemuxerStream::VIDEO);
  }

 private:
  raw_ptr<RendererImpl> renderer_;
  const int id_;
};

}

#endif
