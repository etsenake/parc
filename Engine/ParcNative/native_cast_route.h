// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_CAST_ROUTE_H_
#define PARC_NATIVE_NATIVE_CAST_ROUTE_H_

#include <optional>
#include <vector>

#include "components/media_router/common/media_route.h"

namespace content {
class WebContents;
}

namespace parc {

std::optional<media_router::MediaRoute> CastRouteForWebContents(
    content::WebContents* web_contents,
    const std::vector<media_router::MediaRoute>& routes);

}

#endif
