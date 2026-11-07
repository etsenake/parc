// Installed by the reviewed overlay at //content/renderer/media/fairplay/.
// Creates FairPlayRendererClient for the render process's media pipeline.
// Registered as RendererType::kFairPlay in content's MediaFactory; PipelineImpl
// picks it when the attached CDM RequiresFairPlayRenderer().
#ifndef CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_FACTORY_H_
#define CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_FACTORY_H_

#include <stdint.h>

#include <memory>

#include <optional>

#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/unguessable_token.h"
#include "media/base/renderer_factory.h"

namespace base {
class SequencedTaskRunner;
}  // namespace base

namespace media {

class FairPlayRendererClient;
class MojoRendererFactory;

class FairPlayRendererClientFactory final : public RendererFactory {
 public:
  explicit FairPlayRendererClientFactory(
      std::unique_ptr<MojoRendererFactory> mojo_renderer_factory);
  FairPlayRendererClientFactory(const FairPlayRendererClientFactory&) = delete;
  FairPlayRendererClientFactory& operator=(
      const FairPlayRendererClientFactory&) = delete;
  ~FairPlayRendererClientFactory() override;

  // RendererFactory implementation.
  std::unique_ptr<Renderer> CreateRenderer(
      const scoped_refptr<base::SequencedTaskRunner>& media_task_runner,
      const scoped_refptr<base::TaskRunner>& worker_task_runner,
      AudioRendererSink* audio_renderer_sink,
      VideoRendererSink* video_renderer_sink,
      RequestOverlayInfoCB request_overlay_info_cb,
      const gfx::ColorSpace& target_color_space) override;

  MojoRendererFactory* mojo_renderer_factory() {
    return mojo_renderer_factory_.get();
  }

  // Parc: gives the last renderer made, if it lives, a mute state handoff
  // (InterfaceFactory.CreateMuteStateHandoff) of the frame a Safari-identity
  // page moved its element to. Null before any renderer.
  using MuteStateHandoffTarget = base::OnceCallback<void(
      const std::optional<base::UnguessableToken>& handoff)>;
  MuteStateHandoffTarget ParcMuteStateHandoffTarget();

 private:
  std::unique_ptr<MojoRendererFactory> mojo_renderer_factory_;
  scoped_refptr<base::SequencedTaskRunner> media_task_runner_;
  base::WeakPtr<FairPlayRendererClient> renderer_;
  uint64_t mute_state_handoff_requests_ = 0;
};

}  // namespace media

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_FACTORY_H_
