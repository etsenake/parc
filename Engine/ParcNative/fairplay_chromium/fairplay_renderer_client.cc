#include "content/renderer/media/fairplay/fairplay_renderer_client.h"

#include <utility>

#include "base/check.h"
#include "base/logging.h"
#include "media/base/video_frame.h"
#include "media/base/video_renderer_sink.h"
#include "media/mojo/clients/mojo_renderer.h"

namespace media {

FairPlayRendererClient::FairPlayRendererClient(
    scoped_refptr<base::SequencedTaskRunner> media_task_runner,
    std::unique_ptr<MojoRenderer> mojo_renderer,
    mojo::PendingReceiver<mojom::FairPlayRendererClientExtension>
        client_extension_receiver,
    VideoRendererSink* sink)
    : media_task_runner_(std::move(media_task_runner)),
      mojo_renderer_(std::move(mojo_renderer)),
      pending_client_extension_receiver_(std::move(client_extension_receiver)),
      sink_(sink) {
  DETACH_FROM_SEQUENCE(sequence_checker_);
}

FairPlayRendererClient::~FairPlayRendererClient() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
}

void FairPlayRendererClient::Initialize(MediaResource* media_resource,
                                        RendererClient* client,
                                        PipelineStatusCallback init_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  DCHECK(media_task_runner_->RunsTasksInCurrentSequence());
  DCHECK(!client_);
  client_ = client;
  client_extension_receiver_.Bind(std::move(pending_client_extension_receiver_),
                                  media_task_runner_);
  // The MojoRenderer reports to this object, which passes everything on to
  // |client_| and paints the hole frame on natural size changes.
  mojo_renderer_->Initialize(media_resource, this, std::move(init_cb));
}

void FairPlayRendererClient::SetCdm(CdmContext* cdm_context,
                                    CdmAttachedCB cdm_attached_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  mojo_renderer_->SetCdm(cdm_context, std::move(cdm_attached_cb));
}

void FairPlayRendererClient::SetLatencyHint(
    std::optional<base::TimeDelta> latency_hint) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  mojo_renderer_->SetLatencyHint(latency_hint);
}

void FairPlayRendererClient::Flush(base::OnceClosure flush_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  mojo_renderer_->Flush(std::move(flush_cb));
}

void FairPlayRendererClient::StartPlayingFrom(base::TimeDelta time) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  mojo_renderer_->StartPlayingFrom(time);
}

void FairPlayRendererClient::SetPlaybackRate(double playback_rate) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  mojo_renderer_->SetPlaybackRate(playback_rate);
}

void FairPlayRendererClient::SetVolume(float volume) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  mojo_renderer_->SetVolume(volume);
}

base::TimeDelta FairPlayRendererClient::GetMediaTime() {
  // Renderer::GetMediaTime() may be called from any thread; MojoRenderer's
  // is.
  return mojo_renderer_->GetMediaTime();
}

RendererType FairPlayRendererClient::GetRendererType() {
  return RendererType::kFairPlay;
}

void FairPlayRendererClient::OnError(PipelineStatus status) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnError(std::move(status));
}

void FairPlayRendererClient::OnFallback(PipelineStatus status) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnFallback(std::move(status));
}

void FairPlayRendererClient::OnEnded() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnEnded();
}

void FairPlayRendererClient::OnStatisticsUpdate(
    const PipelineStatistics& stats) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnStatisticsUpdate(stats);
}

void FairPlayRendererClient::OnBufferingStateChange(
    BufferingState state,
    BufferingStateChangeReason reason) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnBufferingStateChange(state, reason);
}

void FairPlayRendererClient::OnWaiting(WaitingReason reason) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnWaiting(reason);
}

void FairPlayRendererClient::OnAudioConfigChange(
    const AudioDecoderConfig& config) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnAudioConfigChange(config);
}

void FairPlayRendererClient::OnVideoConfigChange(
    const VideoDecoderConfig& config) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnVideoConfigChange(config);
}

void FairPlayRendererClient::OnVideoNaturalSizeChange(const gfx::Size& size) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  natural_size_ = size;
  // The player's NaturalSize() first: the repaint changes the video surface,
  // and Picture in Picture reads the size when it sees that change.
  client_->OnVideoNaturalSizeChange(size);
  PaintHoleFrame();
}

void FairPlayRendererClient::OnVideoOpacityChange(bool opaque) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnVideoOpacityChange(opaque);
}

void FairPlayRendererClient::OnVideoFrameRateChange(std::optional<int> fps) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnVideoFrameRateChange(fps);
}

void FairPlayRendererClient::OnLayerRegistered(
    const base::UnguessableToken& layer_token,
    const gfx::Size& natural_size) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The GPU process makes the token. An empty one would name no layer.
  if (layer_token.is_empty() || layer_token_) {
    DLOG(ERROR) << "Unexpected FairPlay layer token";
    return;
  }
  layer_token_ = layer_token;
  if (natural_size_.IsEmpty()) {
    natural_size_ = natural_size;
  }
  PaintHoleFrame();
}

void FairPlayRendererClient::PaintHoleFrame() {
  if (!layer_token_ || natural_size_.IsEmpty()) {
    return;
  }
  // cc turns this into a VideoHoleDrawQuad naming the token, and the GPU
  // process's CARendererLayerTree puts the registered layer there.
  scoped_refptr<VideoFrame> frame = VideoFrame::CreateVideoHoleFrame(
      *layer_token_, natural_size_, base::TimeDelta());
  if (!frame) {
    return;
  }
  sink_->PaintSingleFrame(std::move(frame), /*repaint_duplicate_frame=*/true);
}

}  // namespace media
