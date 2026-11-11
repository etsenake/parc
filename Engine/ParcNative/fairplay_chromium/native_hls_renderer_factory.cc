#include "content/renderer/media/fairplay/native_hls_renderer_factory.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "content/renderer/media/fairplay/native_hls_demuxer.h"
#include "content/renderer/media/fairplay/native_hls_renderer.h"
#include "media/base/parc_native_hls_demuxer_params.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "third_party/parc_fairplay/chromium/fairplay_media.mojom.h"

namespace parc::fairplay {

NativeHlsRendererFactory::NativeHlsRendererFactory(
    media::mojom::FairPlayMediaHost* media_host)
    : media_host_(media_host) {}

NativeHlsRendererFactory::~NativeHlsRendererFactory() = default;

void NativeHlsRendererFactory::SetMediaHost(
    media::mojom::FairPlayMediaHost* media_host) {
  DCHECK(media_host);
  media_host_ = media_host;
}

void NativeHlsRendererFactory::SetPlayerId(int32_t player_id) {
  player_id_ = player_id;
}

std::unique_ptr<media::Renderer> NativeHlsRendererFactory::CreateRenderer(
    const scoped_refptr<base::SequencedTaskRunner>& media_task_runner,
    const scoped_refptr<base::TaskRunner>& /*worker_task_runner*/,
    media::AudioRendererSink* audio_renderer_sink,
    media::VideoRendererSink* video_renderer_sink,
    media::RequestOverlayInfoCB /*request_overlay_info_cb*/,
    const gfx::ColorSpace& /*target_color_space*/) {
  // Audio and video play through AVPlayer in the GPU process; the video sink
  // only shows the hole frame naming its layer, and the audio sink only names
  // the output device.
  return std::make_unique<NativeHlsRenderer>(
      media_task_runner, video_renderer_sink, audio_renderer_sink);
}

std::unique_ptr<media::Demuxer>
NativeHlsRendererFactory::CreateParcNativeHlsDemuxer(
    media::ParcNativeHlsDemuxerParams params) {
  if (!media_host_ || !params.media_task_runner) {
    return nullptr;
  }
  // The player lives as long as these pipes: the demuxer binds them on the
  // media thread and closes them when it stops.
  mojo::PendingRemote<media::mojom::FairPlayHlsPlayer> player;
  mojo::PendingRemote<media::mojom::FairPlayHlsPlayerClient> client;
  mojo::PendingReceiver<media::mojom::FairPlayHlsPlayerClient> client_receiver =
      client.InitWithNewPipeAndPassReceiver();
  media_host_->CreateHlsPlayer(player_id_,
                               player.InitWithNewPipeAndPassReceiver(),
                               std::move(client));
  media_task_runner_ = params.media_task_runner;
  auto demuxer = std::make_unique<NativeHlsDemuxer>(
      std::move(params), std::move(player), std::move(client_receiver));
  demuxer_ = demuxer->GetDemuxerWeakPtr();
  return demuxer;
}

NativeHlsRendererFactory::MuteStateHandoffTarget
NativeHlsRendererFactory::ParcMuteStateHandoffTarget() {
  if (!media_task_runner_) {
    return {};
  }
  return base::BindPostTask(
      media_task_runner_,
      base::BindOnce(
          [](base::WeakPtr<NativeHlsDemuxer> demuxer, uint64_t order,
             const std::optional<base::UnguessableToken>& handoff) {
            if (demuxer) {
              demuxer->FollowMuteStateHandoff(handoff, order);
            }
          },
          demuxer_, ++mute_state_handoff_requests_));
}

}  // namespace parc::fairplay
