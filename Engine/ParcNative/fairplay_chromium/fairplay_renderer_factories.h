// Installed by the reviewed overlay at
// //content/renderer/media/fairplay/fairplay_renderer_factories.h.
//
// The FairPlay and native HLS renderer factories of a frame's
// RendererFactorySelector, which MediaFactory makes and moves with a player.
#ifndef CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_FACTORIES_H_
#define CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_FACTORIES_H_

#include <memory>

namespace media {
class MojoRendererFactory;
class RendererFactorySelector;
namespace mojom {
class InterfaceFactory;
}  // namespace mojom
}  // namespace media

namespace parc::fairplay {

// The FairPlay Streaming Renderer runs next to the FairPlay CDM in the GPU
// process. PipelineImpl selects it only when the attached CDM
// RequiresFairPlayRenderer(); it is never the base renderer. DemuxerManager
// asks the native HLS factory for its demuxer (an AVPlayer next to the
// frame's FairPlay CDMs) on pages presenting Safari's identity; PipelineImpl
// then takes its renderer.
void AddRendererFactories(
    media::RendererFactorySelector& selector,
    std::unique_ptr<media::MojoRendererFactory> mojo_renderer_factory,
    media::mojom::InterfaceFactory* interface_factory);

// For a player moved to this frame: its FairPlay renderers find a CDM another
// frame of the process made (MojoCdmServiceContext::GetCdmContextRef) and get
// this frame's tab mute, which the one playing follows too
// (CreateMuteStateHandoff).
void MoveRendererFactories(media::RendererFactorySelector& selector,
                           media::mojom::InterfaceFactory* interface_factory);

}  // namespace parc::fairplay

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_FACTORIES_H_
