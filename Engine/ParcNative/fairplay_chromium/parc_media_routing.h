// Copyright 2026 Parc contributors.
#ifndef CONTENT_BROWSER_MEDIA_PARC_MEDIA_ROUTING_H_
#define CONTENT_BROWSER_MEDIA_PARC_MEDIA_ROUTING_H_

#include <vector>

#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "content/common/content_export.h"
#include "media/mojo/mojom/interface_factory.mojom.h"

namespace media {
struct CdmConfig;
}

namespace content {

class MediaInterfaceProxy;
class RenderFrameHost;
struct MediaPlayerId;

CONTENT_EXPORT base::ScopedClosureRunner ParcAddPlayerGrant(
    RenderFrameHost* rfh,
    int player_id);

bool ParcClaimPlayerGrant(const MediaPlayerId& id);

void ParcReleasePlayerGrant(const MediaPlayerId& id);

bool ParcHandleCdmRequest(
    RenderFrameHost& frame,
    const media::CdmConfig& cdm_config,
    media::mojom::InterfaceFactory::CreateCdmCallback& create_cdm_cb,
    std::vector<media::mojom::InterfaceFactory::CreateCdmCallback>& held,
    base::WeakPtr<MediaInterfaceProxy> proxy);

}

#endif
