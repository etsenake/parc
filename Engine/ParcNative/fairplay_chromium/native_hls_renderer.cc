#include "content/renderer/media/fairplay/native_hls_renderer.h"

#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/logging.h"
#include "media/base/media_resource.h"
#include "media/base/renderer_client.h"
#include "media/base/video_frame.h"
#include "media/base/video_renderer_sink.h"

namespace parc::fairplay {

NativeHlsRenderer::NativeHlsRenderer(
    scoped_refptr<base::SequencedTaskRunner> media_task_runner,
    media::VideoRendererSink* sink)
    : media_task_runner_(std::move(media_task_runner)), sink_(sink) {
  DETACH_FROM_SEQUENCE(sequence_checker_);
}

NativeHlsRenderer::~NativeHlsRenderer() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (pending_cdm_attached_cb_) {
    std::move(pending_cdm_attached_cb_).Run(false);
  }
  if (source_) {
    source_->SetClient(nullptr);
  }
}

void NativeHlsRenderer::Initialize(media::MediaResource* media_resource,
                                   media::RendererClient* client,
                                   media::PipelineStatusCallback init_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  DCHECK(media_task_runner_->RunsTasksInCurrentSequence());
  DCHECK(!client_);
  NativeHlsSource* source =
      media_resource ? media_resource->GetParcNativeHlsSource() : nullptr;
  if (!source) {
    // Only a NativeHlsDemuxer's pipeline asks for this renderer.
    std::move(init_cb).Run(media::PIPELINE_ERROR_INITIALIZATION_FAILED);
    return;
  }
  client_ = client;
  source_ = source->GetWeakPtr();
  time_source_.store(source, std::memory_order_release);
  if (pending_cdm_attached_cb_) {
    source->SetCdm(std::exchange(pending_cdm_context_, nullptr),
                   std::move(pending_cdm_attached_cb_));
  }
  if (volume_) {
    source->SetVolume(*volume_);
  }
  if (preserves_pitch_) {
    source->SetPreservesPitch(*preserves_pitch_);
  }
  // The source replays the display layer it already has, so a facade made
  // again after a suspension paints at once.
  source->SetClient(this);
  std::move(init_cb).Run(media::PIPELINE_OK);
}

void NativeHlsRenderer::SetCdm(media::CdmContext* cdm_context,
                               CdmAttachedCB cdm_attached_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!source_) {
    // Before Initialize() (PipelineImpl::InitializeRenderer's order): held
    // for the source, replacing an earlier one.
    if (pending_cdm_attached_cb_) {
      std::move(pending_cdm_attached_cb_).Run(false);
    }
    pending_cdm_context_ = cdm_context;
    pending_cdm_attached_cb_ = std::move(cdm_attached_cb);
    return;
  }
  // AVPlayer's keys come from the CDM's content key session in the GPU
  // process; the player finds the CDM by its ID.
  source_->SetCdm(cdm_context, std::move(cdm_attached_cb));
}

void NativeHlsRenderer::SetLatencyHint(
    std::optional<base::TimeDelta> latency_hint) {
  // AVPlayer buffers as it does in Safari, which has no latencyHint.
}

void NativeHlsRenderer::SetPreservesPitch(bool preserves_pitch) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  preserves_pitch_ = preserves_pitch;
  if (source_) {
    source_->SetPreservesPitch(preserves_pitch);
  }
}

void NativeHlsRenderer::Flush(base::OnceClosure flush_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // A seek follows (Demuxer::Seek moves AVPlayer), then StartPlayingFrom().
  playing_ = false;
  ended_ = false;
  reported_buffering_state_ = media::BUFFERING_HAVE_NOTHING;
  std::move(flush_cb).Run();
}

void NativeHlsRenderer::StartPlayingFrom(base::TimeDelta time) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  playing_ = true;
  ended_ = false;
  if (!source_) {
    return;
  }
  // AVPlayer already sits at `time` (Demuxer::Seek). Whatever it has
  // buffered there tells readyState, as playbackLikelyToKeepUp does in
  // Safari. The pipeline sets the rate next. Reported afresh, as RendererImpl
  // reports HAVE_ENOUGH after every StartPlayingFrom: the pipeline finishes a
  // seek only then, whatever was reported before it. And in a later task, as
  // RendererImpl's always comes: PipelineImpl posts the seek's completion
  // when this returns, and WebMediaPlayerImpl drops a buffering state that
  // reaches it before that completion, so a report made here would be lost
  // and the seek would never finish.
  reported_buffering_state_ = media::BUFFERING_HAVE_NOTHING;
  media_task_runner_->PostTask(
      FROM_HERE, base::BindOnce(&NativeHlsRenderer::ReportStartState,
                                weak_factory_.GetWeakPtr(), ++starts_));
}

void NativeHlsRenderer::ReportStartState(uint64_t start) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // Not after a flush or a later start, which reports for itself.
  if (!playing_ || start != starts_ || !source_) {
    return;
  }
  ReportBufferingState(source_->GetBufferingState());
}

void NativeHlsRenderer::SetPlaybackRate(double playback_rate) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!source_) {
    return;
  }
  if (playback_rate != 0) {
    source_->Play(playback_rate);
  } else {
    source_->Pause();
  }
}

void NativeHlsRenderer::SetVolume(float volume) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The element's effective volume: 0 while muted.
  volume_ = volume;
  if (source_) {
    source_->SetVolume(volume);
  }
}

base::TimeDelta NativeHlsRenderer::GetMediaTime() {
  NativeHlsSource* source = time_source_.load(std::memory_order_acquire);
  return source ? source->GetMediaTime() : base::TimeDelta();
}

media::RendererType NativeHlsRenderer::GetRendererType() {
  return media::RendererType::kFairPlayHls;
}

void NativeHlsRenderer::OnSourceBufferingStateChange(
    media::BufferingState state) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (playing_) {
    ReportBufferingState(state);
  }
}

void NativeHlsRenderer::ReportBufferingState(media::BufferingState state) {
  if (!client_ || state == reported_buffering_state_) {
    return;
  }
  reported_buffering_state_ = state;
  // AVPlayer runs out when the network can't keep up
  // (playbackBufferEmpty), never because a decoder starves here.
  client_->OnBufferingStateChange(
      state, state == media::BUFFERING_HAVE_NOTHING
                 ? media::DEMUXER_UNDERFLOW
                 : media::BUFFERING_CHANGE_REASON_UNKNOWN);
}

void NativeHlsRenderer::OnSourceEnded() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // AVPlayerItemDidPlayToEndTimeNotification, once per run to the end.
  if (!client_ || !playing_ || ended_) {
    return;
  }
  ended_ = true;
  client_->OnEnded();
}

void NativeHlsRenderer::OnSourceError(media::PipelineStatus status) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (client_) {
    client_->OnError(std::move(status));
  }
}

void NativeHlsRenderer::OnSourceStatisticsUpdate(
    const media::PipelineStatistics& delta) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (client_) {
    client_->OnStatisticsUpdate(delta);
  }
}

void NativeHlsRenderer::OnSourceWaiting(media::WaitingReason reason) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (client_) {
    client_->OnWaiting(reason);
  }
}

void NativeHlsRenderer::OnSourceNaturalSizeChange(const gfx::Size& size) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (size.IsEmpty() || size == natural_size_) {
    return;
  }
  natural_size_ = size;
  // The player's NaturalSize() first: the repaint changes the video surface,
  // and Picture in Picture reads the size when it sees that change.
  if (client_) {
    client_->OnVideoNaturalSizeChange(size);
  }
  PaintHoleFrame();
}

void NativeHlsRenderer::OnSourceLayerRegistered(
    const base::UnguessableToken& layer_token,
    const gfx::Size& natural_size) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  layer_token_ = layer_token;
  if (natural_size_.IsEmpty()) {
    natural_size_ = natural_size;
  }
  PaintHoleFrame();
}

void NativeHlsRenderer::PaintHoleFrame() {
  if (!sink_ || !layer_token_ || natural_size_.IsEmpty()) {
    return;
  }
  // cc turns this into a VideoHoleDrawQuad naming the token, and the GPU
  // process's CARendererLayerTree puts the player's AVPlayerLayer there.
  scoped_refptr<media::VideoFrame> frame = media::VideoFrame::CreateVideoHoleFrame(
      *layer_token_, natural_size_, base::TimeDelta());
  if (!frame) {
    return;
  }
  sink_->PaintSingleFrame(std::move(frame), /*repaint_duplicate_frame=*/true);
}

}  // namespace parc::fairplay
