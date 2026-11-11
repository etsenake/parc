#include "content/renderer/media/fairplay/fairplay_renderer_factories.h"

#include <memory>
#include <utility>

#include "content/renderer/media/fairplay/fairplay_media_host_connection.h"
#include "content/renderer/media/fairplay/fairplay_renderer_client_factory.h"
#include "content/renderer/media/fairplay/native_hls_renderer_factory.h"
#include "media/base/renderer.h"
#include "media/base/renderer_factory_selector.h"

namespace parc::fairplay {

void AddRendererFactories(media::RendererFactorySelector& selector,
                          content::RenderFrame* render_frame) {
  FairPlayMediaHostConnection* media_host =
      FairPlayMediaHostConnection::ForFrame(render_frame);
  selector.AddFactory(
      media::RendererType::kFairPlay,
      std::make_unique<media::FairPlayRendererClientFactory>(media_host));
  selector.AddFactory(media::RendererType::kFairPlayHls,
                      std::make_unique<NativeHlsRendererFactory>(media_host));
}

void MoveRendererFactories(media::RendererFactorySelector& selector,
                           content::RenderFrame* render_frame) {
  FairPlayMediaHostConnection* media_host =
      FairPlayMediaHostConnection::ForFrame(render_frame);
  auto follow_mute_state = [media_host](auto* factory) {
    if (auto target = factory->ParcMuteStateHandoffTarget()) {
      media_host->CreateMuteStateHandoff(std::move(target));
    }
  };
  if (auto* factory = selector.GetFactory(media::RendererType::kFairPlay)) {
    auto* fairplay_factory =
        static_cast<media::FairPlayRendererClientFactory*>(factory);
    fairplay_factory->SetMediaHost(media_host);
    follow_mute_state(fairplay_factory);
  }
  if (auto* factory = selector.GetFactory(media::RendererType::kFairPlayHls)) {
    auto* native_hls_factory = static_cast<NativeHlsRendererFactory*>(factory);
    native_hls_factory->SetMediaHost(media_host);
    follow_mute_state(native_hls_factory);
  }
}

}  // namespace parc::fairplay
