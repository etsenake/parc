#include "third_party/parc_fairplay/chromium/fairplay_renderer_service.h"

#include <utility>

#include "base/functional/bind.h"
#include "media/base/cdm_context.h"
#include "media/base/renderer.h"
#include "media/mojo/services/mojo_cdm_service_context.h"
#include "media/mojo/services/mojo_renderer_service.h"

namespace media {

FairPlayRendererService::FairPlayRendererService(
    MojoCdmServiceContext* mojo_cdm_service_context,
    std::unique_ptr<media::Renderer> renderer)
    : mojo_cdm_service_context_(mojo_cdm_service_context),
      renderer_(renderer.get()) {
  service_ = std::make_unique<MojoRendererService>(mojo_cdm_service_context,
                                                   std::move(renderer));
}

FairPlayRendererService::~FairPlayRendererService() = default;

void FairPlayRendererService::Initialize(
    mojo::PendingAssociatedRemote<mojom::RendererClient> client,
    std::optional<std::vector<mojo::PendingRemote<mojom::DemuxerStream>>>
        streams,
    InitializeCallback callback) {
  service_->Initialize(std::move(client), std::move(streams),
                       std::move(callback));
}

void FairPlayRendererService::Flush(FlushCallback callback) {
  service_->Flush(std::move(callback));
}

void FairPlayRendererService::StartPlayingFrom(base::TimeDelta time_delta) {
  service_->StartPlayingFrom(time_delta);
}

void FairPlayRendererService::SetPlaybackRate(double playback_rate) {
  service_->SetPlaybackRate(playback_rate);
}

void FairPlayRendererService::SetVolume(float volume) {
  service_->SetVolume(volume);
}

void FairPlayRendererService::SetCdm(
    const std::optional<base::UnguessableToken>& cdm_id,
    SetCdmCallback callback) {
  if (cdm_context_ref_ &&
      renderer_->GetRendererType() == RendererType::kFairPlay) {
    if (!cdm_id) {
      renderer_->SetCdm(nullptr, std::move(callback));
      return;
    }
    std::unique_ptr<CdmContextRef> cdm_context_ref =
        mojo_cdm_service_context_
            ? mojo_cdm_service_context_->GetCdmContextRef(cdm_id.value())
            : nullptr;
    if (cdm_context_ref && cdm_context_ref->GetCdmContext() ==
                               cdm_context_ref_->GetCdmContext()) {
      renderer_->SetCdm(cdm_context_ref_->GetCdmContext(), std::move(callback));
      return;
    }
    if (cdm_context_ref) {
      replaced_cdm_context_refs_.push_back(std::move(cdm_context_ref_));
      cdm_context_ref_ = std::move(cdm_context_ref);
      renderer_->SetCdm(
          cdm_context_ref_->GetCdmContext(),
          base::BindOnce(&FairPlayRendererService::OnReplacementCdmAttached,
                         weak_factory_.GetWeakPtr(), std::move(callback)));
      return;
    }
  }

  if (cdm_context_ref_ || !mojo_cdm_service_context_ || !cdm_id) {
    std::move(callback).Run(false);
    return;
  }

  std::unique_ptr<CdmContextRef> cdm_context_ref =
      mojo_cdm_service_context_->GetCdmContextRef(cdm_id.value());
  if (!cdm_context_ref) {
    std::move(callback).Run(false);
    return;
  }

  cdm_context_ref_ = std::move(cdm_context_ref);
  renderer_->SetCdm(
      cdm_context_ref_->GetCdmContext(),
      base::BindOnce(&FairPlayRendererService::OnCdmAttached,
                     weak_factory_.GetWeakPtr(), std::move(callback)));
}

void FairPlayRendererService::SetLatencyHint(
    std::optional<base::TimeDelta> latency_hint) {
  service_->SetLatencyHint(latency_hint);
}

void FairPlayRendererService::OnCdmAttached(
    base::OnceCallback<void(bool)> callback,
    bool success) {
  if (!success) {
    cdm_context_ref_.reset();
  }
  std::move(callback).Run(success);
}

void FairPlayRendererService::OnReplacementCdmAttached(
    base::OnceCallback<void(bool)> callback,
    bool success) {
  if (!success) {
    cdm_context_ref_ = std::move(replaced_cdm_context_refs_.back());
    replaced_cdm_context_refs_.pop_back();
  }
  std::move(callback).Run(success);
}

}
