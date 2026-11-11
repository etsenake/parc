#include "content/renderer/media/fairplay/fairplay_renderer_factories.h"

#include <utility>

#include "content/renderer/media/fairplay/fairplay_renderer_client_factory.h"
#include "content/renderer/media/fairplay/native_hls_renderer_factory.h"
#include "media/base/renderer.h"
#include "media/base/renderer_factory_selector.h"
#include "media/mojo/clients/mojo_renderer_factory.h"
#include "media/mojo/mojom/interface_factory.mojom.h"

namespace parc::fairplay {

void AddRendererFactories(
    media::RendererFactorySelector& selector,
    std::unique_ptr<media::MojoRendererFactory> mojo_renderer_factory,
    media::mojom::InterfaceFactory* interface_factory) {
  selector.AddFactory(media::RendererType::kFairPlay,
                      std::make_unique<media::FairPlayRendererClientFactory>(
                          std::move(mojo_renderer_factory)));
  selector.AddFactory(
      media::RendererType::kFairPlayHls,
      std::make_unique<NativeHlsRendererFactory>(interface_factory));
}

void MoveRendererFactories(media::RendererFactorySelector& selector,
                           media::mojom::InterfaceFactory* interface_factory) {
  auto follow_mute_state = [interface_factory](auto* factory) {
    if (auto target = factory->ParcMuteStateHandoffTarget()) {
      interface_factory->CreateMuteStateHandoff(std::move(target));
    }
  };
  if (auto* factory = selector.GetFactory(media::RendererType::kFairPlay)) {
    auto* fairplay_factory =
        static_cast<media::FairPlayRendererClientFactory*>(factory);
    fairplay_factory->mojo_renderer_factory()->ParcSetInterfaceFactory(
        interface_factory);
    follow_mute_state(fairplay_factory);
  }
  if (auto* factory = selector.GetFactory(media::RendererType::kFairPlayHls)) {
    auto* native_hls_factory = static_cast<NativeHlsRendererFactory*>(factory);
    native_hls_factory->ParcSetInterfaceFactory(interface_factory);
    follow_mute_state(native_hls_factory);
  }
}

}  // namespace parc::fairplay
