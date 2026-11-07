#include "content/renderer/media/fairplay/native_hls_renderer_factory.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "content/renderer/media/fairplay/native_hls_demuxer.h"
#include "content/renderer/media/fairplay/native_hls_renderer.h"
#include "media/mojo/mojom/interface_factory.mojom.h"
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"

namespace parc::fairplay {

NativeHlsRendererFactory::NativeHlsRendererFactory(
    media::mojom::InterfaceFactory* interface_factory)
    : interface_factory_(interface_factory) {}

NativeHlsRendererFactory::~NativeHlsRendererFactory() = default;

void NativeHlsRendererFactory::ParcSetInterfaceFactory(
    media::mojom::InterfaceFactory* interface_factory) {
  DCHECK(interface_factory);
  interface_factory_ = interface_factory;
}

std::unique_ptr<media::Renderer> NativeHlsRendererFactory::CreateRenderer(
    const scoped_refptr<base::SequencedTaskRunner>& media_task_runner,
    const scoped_refptr<base::TaskRunner>& /*worker_task_runner*/,
    media::AudioRendererSink* /*audio_renderer_sink*/,
    media::VideoRendererSink* video_renderer_sink,
    media::RequestOverlayInfoCB /*request_overlay_info_cb*/,
    const gfx::ColorSpace& /*target_color_space*/) {
  // Audio and video play through AVPlayer in the GPU process; the sink only
  // shows the hole frame naming its layer.
  return std::make_unique<NativeHlsRenderer>(media_task_runner,
                                             video_renderer_sink);
}

std::unique_ptr<media::Demuxer>
NativeHlsRendererFactory::CreateParcNativeHlsDemuxer(
    media::ParcNativeHlsDemuxerParams params) {
  if (!interface_factory_ || !params.media_task_runner) {
    return nullptr;
  }
  // The player lives as long as these pipes: the demuxer binds them on the
  // media thread and closes them when it stops.
  mojo::PendingRemote<media::mojom::FairPlayHlsPlayer> player;
  mojo::PendingRemote<media::mojom::FairPlayHlsPlayerClient> client;
  mojo::PendingReceiver<media::mojom::FairPlayHlsPlayerClient> client_receiver =
      client.InitWithNewPipeAndPassReceiver();
  interface_factory_->CreateFairPlayHlsPlayer(
      player.InitWithNewPipeAndPassReceiver(), std::move(client),
      mojo::NullRemote());
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
