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
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/unguessable_token.h"
#include "media/base/renderer_factory.h"

namespace base {
class SequencedTaskRunner;
}  // namespace base

namespace media {

class FairPlayRendererClient;

namespace mojom {
class FairPlayMediaHost;
}  // namespace mojom

class FairPlayRendererClientFactory final : public RendererFactory {
 public:
  // `media_host` is the frame's (FairPlayMediaHostConnection), which goes
  // with the frame and hops to its own thread. A player a Safari-identity
  // element moves to another frame takes that frame's (SetMediaHost).
  explicit FairPlayRendererClientFactory(mojom::FairPlayMediaHost* media_host);
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

  void SetMediaHost(mojom::FairPlayMediaHost* media_host);
  // The player the renderers are for (WebMediaPlayer::GetPlayerId), whose
  // audibility grant each holds. Set on the main thread before the player
  // loads.
  void SetPlayerId(int32_t player_id);

  // Parc: gives the last renderer made, if it lives, a mute state handoff
  // (FairPlayMediaHost.CreateMuteStateHandoff) of the frame a Safari-identity
  // page moved its element to. Null before any renderer.
  using MuteStateHandoffTarget = base::OnceCallback<void(
      const std::optional<base::UnguessableToken>& handoff)>;
  MuteStateHandoffTarget ParcMuteStateHandoffTarget();

 private:
  raw_ptr<mojom::FairPlayMediaHost> media_host_;
  int32_t player_id_ = 0;
  scoped_refptr<base::SequencedTaskRunner> media_task_runner_;
  base::WeakPtr<FairPlayRendererClient> renderer_;
  uint64_t mute_state_handoff_requests_ = 0;
};

}  // namespace media

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_FACTORY_H_
