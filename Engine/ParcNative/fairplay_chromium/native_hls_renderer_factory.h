// Installed by the reviewed overlay at //content/renderer/media/fairplay/.
// The RendererFactory MediaFactory registers for RendererType::kFairPlayHls:
// Safari's native HLS route (NATIVE_HLS.md beside this file's source in the
// Parc repository). It makes the route's demuxer, connected through the
// frame's InterfaceFactory to an AVPlayer in the GPU process next to the
// frame's FairPlay CDMs, and the renderer facade that drives it.
#ifndef CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_RENDERER_FACTORY_H_
#define CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_RENDERER_FACTORY_H_

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

namespace media::mojom {
class InterfaceFactory;
}  // namespace media::mojom

namespace parc::fairplay {

class NativeHlsDemuxer;

class NativeHlsRendererFactory final : public media::RendererFactory {
 public:
  // `interface_factory` is the frame's (MediaFactory's), which outlives every
  // player of the frame and hops to its own thread. A player a
  // Safari-identity element moves to another frame takes that frame's
  // (ParcSetInterfaceFactory).
  explicit NativeHlsRendererFactory(
      media::mojom::InterfaceFactory* interface_factory);
  NativeHlsRendererFactory(const NativeHlsRendererFactory&) = delete;
  NativeHlsRendererFactory& operator=(const NativeHlsRendererFactory&) = delete;
  ~NativeHlsRendererFactory() override;

  // media::RendererFactory.
  std::unique_ptr<media::Renderer> CreateRenderer(
      const scoped_refptr<base::SequencedTaskRunner>& media_task_runner,
      const scoped_refptr<base::TaskRunner>& worker_task_runner,
      media::AudioRendererSink* audio_renderer_sink,
      media::VideoRendererSink* video_renderer_sink,
      media::RequestOverlayInfoCB request_overlay_info_cb,
      const gfx::ColorSpace& target_color_space) override;
  std::unique_ptr<media::Demuxer> CreateParcNativeHlsDemuxer(
      media::ParcNativeHlsDemuxerParams params) override;

  void ParcSetInterfaceFactory(
      media::mojom::InterfaceFactory* interface_factory);
  // Parc: as FairPlayRendererClientFactory::ParcMuteStateHandoffTarget, for
  // the last player made.
  using MuteStateHandoffTarget = base::OnceCallback<void(
      const std::optional<base::UnguessableToken>& handoff)>;
  MuteStateHandoffTarget ParcMuteStateHandoffTarget();

 private:
  raw_ptr<media::mojom::InterfaceFactory> interface_factory_;
  scoped_refptr<base::SequencedTaskRunner> media_task_runner_;
  base::WeakPtr<NativeHlsDemuxer> demuxer_;
  uint64_t mute_state_handoff_requests_ = 0;
};

}  // namespace parc::fairplay

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_RENDERER_FACTORY_H_
