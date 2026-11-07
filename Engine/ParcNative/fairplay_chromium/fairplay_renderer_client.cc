#include "content/renderer/media/fairplay/fairplay_renderer_client.h"

#include <algorithm>
#include <utility>

#include "base/barrier_closure.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "media/base/media_resource.h"
#include "media/base/video_frame.h"
#include "media/base/video_renderer_sink.h"
#include "media/mojo/clients/mojo_demuxer_stream_impl.h"
#include "media/mojo/clients/mojo_renderer.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"

namespace media {

// The streams MojoRenderer hands the GPU process at Initialize.
class FairPlayRendererClient::PlayedStreams final : public MediaResource {
 public:
  explicit PlayedStreams(std::vector<raw_ptr<DemuxerStream>> streams)
      : streams_(std::move(streams)) {}
  std::vector<raw_ptr<DemuxerStream>> GetAllStreams() override {
    return streams_;
  }

 private:
  const std::vector<raw_ptr<DemuxerStream>> streams_;
};

FairPlayRendererClient::Played::Played() = default;
FairPlayRendererClient::Played::Played(Played&&) = default;
FairPlayRendererClient::Played& FairPlayRendererClient::Played::operator=(
    Played&&) = default;
FairPlayRendererClient::Played::~Played() = default;

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
  media_resource_ = media_resource;
  client_extension_receiver_.Bind(std::move(pending_client_extension_receiver_),
                                  media_task_runner_);
  // Safari's Media Source: the enabled streams, the first video and every
  // audio stream (WebKit's AudioVideoRendererAVFObjC keeps an audio renderer
  // per enabled track). Otherwise, or with nothing enabled, the first of each
  // type, as RendererImpl takes them.
  std::vector<raw_ptr<DemuxerStream>> streams;
  bool video = false;
  for (DemuxerStream* stream : media_resource->GetAllStreams()) {
    if (media_resource->ParcMayAddStreams() && stream->ParcIsEnabled() &&
        (stream->type() == DemuxerStream::AUDIO ||
         (stream->type() == DemuxerStream::VIDEO && !std::exchange(video, true)))) {
      streams.push_back(stream);
    }
  }
  if (streams.empty()) {
    for (DemuxerStream::Type type : {DemuxerStream::AUDIO, DemuxerStream::VIDEO}) {
      if (DemuxerStream* stream = media_resource->GetFirstStream(type)) {
        streams.push_back(stream);
      }
    }
  }
  for (DemuxerStream* stream : streams) {
    played_[next_stream_id_++].stream = stream;
  }
  initial_streams_ = std::make_unique<PlayedStreams>(std::move(streams));
  // The MojoRenderer reports to this object, which passes everything on to
  // |client_| and paints the hole frame on natural size changes.
  mojo_renderer_->Initialize(initial_streams_.get(), this, std::move(init_cb));
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

void FairPlayRendererClient::OnTracksChanged(
    DemuxerStream::Type track_type,
    DemuxerStream* stream,
    base::OnceClosure change_completed_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!media_resource_->ParcMayAddStreams()) {
    std::move(change_completed_cb).Run();
    return;
  }
  if (!renderer_extension_) {
    pending_track_change_ = base::BindOnce(
        &FairPlayRendererClient::OnTracksChanged, base::Unretained(this),
        track_type, base::Unretained(stream),
        std::move(change_completed_cb));
    return;
  }
  // AudioVideoRendererAVFObjC::removeTrack for an audio track turned off.
  for (auto it = played_.begin(); it != played_.end();) {
    if (track_type == DemuxerStream::AUDIO &&
        it->second.stream->type() == DemuxerStream::AUDIO &&
        !it->second.stream->ParcIsEnabled()) {
      renderer_extension_->RemoveStream(it->first);
      it = played_.erase(it);
    } else {
      ++it;
    }
  }
  // ...::addTrack for each one turned on: the change names one, but the
  // demuxer may join several audio streams in it.
  auto plays = [this](DemuxerStream* candidate) {
    return std::ranges::any_of(played_, [candidate](const auto& entry) {
      return entry.second.stream == candidate;
    });
  };
  std::vector<DemuxerStream*> added;
  if (track_type == DemuxerStream::AUDIO) {
    for (DemuxerStream* candidate : media_resource_->GetAllStreams()) {
      if (candidate->type() == DemuxerStream::AUDIO &&
          candidate->ParcIsEnabled() && !plays(candidate)) {
        added.push_back(candidate);
      }
    }
  } else if (stream && !plays(stream)) {
    added.push_back(stream);
  }
  base::RepeatingClosure done =
      base::BarrierClosure(added.size(), std::move(change_completed_cb));
  for (DemuxerStream* joining : added) {
    const uint32_t id = next_stream_id_++;
    mojo::PendingRemote<mojom::DemuxerStream> remote;
    Played& played = played_[id];
    played.stream = joining;
    played.proxy = std::make_unique<MojoDemuxerStreamImpl>(
        joining, remote.InitWithNewPipeAndPassReceiver());
    renderer_extension_->AddStream(
        id, std::move(remote),
        mojo::WrapCallbackWithDefaultInvokeIfNotRun(base::OnceClosure(done)));
  }
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

void FairPlayRendererClient::OnRendererExtension(
    mojo::PendingRemote<mojom::FairPlayRendererExtension> extension) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (renderer_extension_) {
    DLOG(ERROR) << "Unexpected second FairPlay renderer extension";
    return;
  }
  renderer_extension_.Bind(std::move(extension), media_task_runner_);
  if (pending_track_change_) {
    std::move(pending_track_change_).Run();
  }
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
