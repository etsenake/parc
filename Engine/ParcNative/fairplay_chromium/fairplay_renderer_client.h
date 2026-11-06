// Installed by the reviewed overlay at //content/renderer/media/fairplay/.
// Render-process media::Renderer for FairPlay Streaming playback. It wraps the
// MojoRenderer connected to FairPlayRendererAdapter in the GPU process and
// paints the video as a hole frame naming the adapter's display layer: no
// VideoFrame ever carries the decrypted pixels, the compositor places the
// layer itself.
#ifndef CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_H_
#define CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_H_

#include <memory>
#include <optional>

#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/unguessable_token.h"
#include "media/base/renderer.h"
#include "media/base/renderer_client.h"
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "ui/gfx/geometry/size.h"

namespace media {

class MojoRenderer;
class VideoRendererSink;

class FairPlayRendererClient final
    : public Renderer,
      public RendererClient,
      public mojom::FairPlayRendererClientExtension {
 public:
  // Constructed on the main thread; every other call is on
  // |media_task_runner|.
  FairPlayRendererClient(
      scoped_refptr<base::SequencedTaskRunner> media_task_runner,
      std::unique_ptr<MojoRenderer> mojo_renderer,
      mojo::PendingReceiver<mojom::FairPlayRendererClientExtension>
          client_extension_receiver,
      VideoRendererSink* sink);
  FairPlayRendererClient(const FairPlayRendererClient&) = delete;
  FairPlayRendererClient& operator=(const FairPlayRendererClient&) = delete;
  ~FairPlayRendererClient() override;

  // Renderer implementation.
  void Initialize(MediaResource* media_resource,
                  RendererClient* client,
                  PipelineStatusCallback init_cb) override;
  void SetCdm(CdmContext* cdm_context, CdmAttachedCB cdm_attached_cb) override;
  void SetLatencyHint(std::optional<base::TimeDelta> latency_hint) override;
  void Flush(base::OnceClosure flush_cb) override;
  void StartPlayingFrom(base::TimeDelta time) override;
  void SetPlaybackRate(double playback_rate) override;
  void SetVolume(float volume) override;
  base::TimeDelta GetMediaTime() override;
  RendererType GetRendererType() override;

  // RendererClient implementation, forwarded to the pipeline's client.
  void OnError(PipelineStatus status) override;
  void OnFallback(PipelineStatus status) override;
  void OnEnded() override;
  void OnStatisticsUpdate(const PipelineStatistics& stats) override;
  void OnBufferingStateChange(BufferingState state,
                              BufferingStateChangeReason reason) override;
  void OnWaiting(WaitingReason reason) override;
  void OnAudioConfigChange(const AudioDecoderConfig& config) override;
  void OnVideoConfigChange(const VideoDecoderConfig& config) override;
  void OnVideoNaturalSizeChange(const gfx::Size& size) override;
  void OnVideoOpacityChange(bool opaque) override;
  void OnVideoFrameRateChange(std::optional<int> fps) override;

  // mojom::FairPlayRendererClientExtension implementation.
  void OnLayerRegistered(const base::UnguessableToken& layer_token,
                         const gfx::Size& natural_size) override;

 private:
  void PaintHoleFrame();

  const scoped_refptr<base::SequencedTaskRunner> media_task_runner_;
  std::unique_ptr<MojoRenderer> mojo_renderer_;
  // Bound on |media_task_runner_| in Initialize().
  mojo::PendingReceiver<mojom::FairPlayRendererClientExtension>
      pending_client_extension_receiver_;
  mojo::Receiver<mojom::FairPlayRendererClientExtension>
      client_extension_receiver_{this};
  const raw_ptr<VideoRendererSink> sink_;

  raw_ptr<RendererClient> client_ = nullptr;
  std::optional<base::UnguessableToken> layer_token_;
  gfx::Size natural_size_;

  SEQUENCE_CHECKER(sequence_checker_);
};

}  // namespace media

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_H_
