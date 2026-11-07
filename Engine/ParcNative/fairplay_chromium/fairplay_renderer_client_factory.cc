#include "content/renderer/media/fairplay/fairplay_renderer_client_factory.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "content/renderer/media/fairplay/fairplay_renderer_client.h"
#include "media/mojo/clients/mojo_renderer.h"
#include "media/mojo/clients/mojo_renderer_factory.h"
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"

namespace media {

FairPlayRendererClientFactory::FairPlayRendererClientFactory(
    std::unique_ptr<MojoRendererFactory> mojo_renderer_factory)
    : mojo_renderer_factory_(std::move(mojo_renderer_factory)) {}

FairPlayRendererClientFactory::~FairPlayRendererClientFactory() = default;

std::unique_ptr<Renderer> FairPlayRendererClientFactory::CreateRenderer(
    const scoped_refptr<base::SequencedTaskRunner>& media_task_runner,
    const scoped_refptr<base::TaskRunner>& /*worker_task_runner*/,
    AudioRendererSink* /*audio_renderer_sink*/,
    VideoRendererSink* video_renderer_sink,
    RequestOverlayInfoCB /*request_overlay_info_cb*/,
    const gfx::ColorSpace& /*target_color_space*/) {
  // Audio plays through AVSampleBufferAudioRenderer in the GPU process, not
  // through |audio_renderer_sink|.
  mojo::PendingRemote<mojom::FairPlayRendererClientExtension>
      client_extension_remote;
  auto client_extension_receiver =
      client_extension_remote.InitWithNewPipeAndPassReceiver();
  std::unique_ptr<MojoRenderer> mojo_renderer =
      mojo_renderer_factory_->CreateFairPlayRenderer(
          std::move(client_extension_remote), media_task_runner,
          video_renderer_sink);
  auto renderer = std::make_unique<FairPlayRendererClient>(
      media_task_runner, std::move(mojo_renderer),
      std::move(client_extension_receiver), video_renderer_sink);
  media_task_runner_ = media_task_runner;
  renderer_ = renderer->GetWeakPtr();
  return renderer;
}

FairPlayRendererClientFactory::MuteStateHandoffTarget
FairPlayRendererClientFactory::ParcMuteStateHandoffTarget() {
  if (!media_task_runner_) {
    return {};
  }
  return base::BindPostTask(
      media_task_runner_,
      base::BindOnce(
          [](base::WeakPtr<FairPlayRendererClient> renderer, uint64_t order,
             const std::optional<base::UnguessableToken>& handoff) {
            if (renderer) {
              renderer->FollowMuteStateHandoff(handoff, order);
            }
          },
          renderer_, ++mute_state_handoff_requests_));
}

}  // namespace media
