// Installed by the reviewed overlay at
// //content/renderer/media/fairplay/fairplay_renderer_factories.h.
//
// The FairPlay and native HLS renderer factories of a frame's
// RendererFactorySelector, which MediaFactory makes and moves with a player.
#ifndef CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_FACTORIES_H_
#define CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_FACTORIES_H_

namespace content {
class RenderFrame;
}  // namespace content

namespace media {
class RendererFactorySelector;
}  // namespace media

namespace parc::fairplay {

// The FairPlay Streaming Renderer runs next to the FairPlay CDM in Parc's
// FairPlay media service, reached through the frame's FairPlayMediaHost.
// PipelineImpl selects it only when the attached CDM
// RequiresFairPlayRenderer(); it is never the base renderer. DemuxerManager
// asks the native HLS factory for its demuxer (an AVPlayer next to the
// frame's FairPlay CDMs) on pages presenting Safari's identity; PipelineImpl
// then takes its renderer.
void AddRendererFactories(media::RendererFactorySelector& selector,
                          content::RenderFrame* render_frame);

// Once the player exists: its FairPlay renderers and native HLS players hold
// its own audibility grant (WebMediaPlayer::GetPlayerId).
void SetRendererFactoriesPlayer(media::RendererFactorySelector& selector,
                                int player_id);

// For a player moved to this frame: its FairPlay renderers find a CDM another
// frame of the process made and get this frame's tab mute, which the one
// playing follows too (FairPlayMediaHost.CreateMuteStateHandoff).
void MoveRendererFactories(media::RendererFactorySelector& selector,
                           content::RenderFrame* render_frame);

}  // namespace parc::fairplay

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_FACTORIES_H_
