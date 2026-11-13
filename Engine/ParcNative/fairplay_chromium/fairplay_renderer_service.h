#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_RENDERER_SERVICE_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_RENDERER_SERVICE_H_

#include <memory>
#include <optional>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "base/unguessable_token.h"
#include "media/mojo/mojom/renderer.mojom.h"
#include "mojo/public/cpp/bindings/pending_associated_remote.h"
#include "mojo/public/cpp/bindings/pending_remote.h"

namespace media {

class CdmContextRef;
class MojoCdmServiceContext;
class MojoRendererService;
class Renderer;

class FairPlayRendererService final : public mojom::Renderer {
 public:
  FairPlayRendererService(MojoCdmServiceContext* mojo_cdm_service_context,
                          std::unique_ptr<media::Renderer> renderer);
  FairPlayRendererService(const FairPlayRendererService&) = delete;
  FairPlayRendererService& operator=(const FairPlayRendererService&) = delete;
  ~FairPlayRendererService() final;

  void Initialize(
      mojo::PendingAssociatedRemote<mojom::RendererClient> client,
      std::optional<std::vector<mojo::PendingRemote<mojom::DemuxerStream>>>
          streams,
      InitializeCallback callback) final;
  void Flush(FlushCallback callback) final;
  void StartPlayingFrom(base::TimeDelta time_delta) final;
  void SetPlaybackRate(double playback_rate) final;
  void SetVolume(float volume) final;
  void SetCdm(const std::optional<base::UnguessableToken>& cdm_id,
              SetCdmCallback callback) final;
  void SetLatencyHint(std::optional<base::TimeDelta> latency_hint) final;

 private:
  void OnCdmAttached(base::OnceCallback<void(bool)> callback, bool success);
  void OnReplacementCdmAttached(base::OnceCallback<void(bool)> callback,
                                bool success);

  const raw_ptr<MojoCdmServiceContext> mojo_cdm_service_context_;
  std::unique_ptr<CdmContextRef> cdm_context_ref_;
  std::vector<std::unique_ptr<CdmContextRef>> replaced_cdm_context_refs_;
  std::unique_ptr<MojoRendererService> service_;
  raw_ptr<media::Renderer> renderer_;
  base::WeakPtrFactory<FairPlayRendererService> weak_factory_{this};
};

}

#endif
