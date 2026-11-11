// Copyright 2026 Parc contributors.
// Installed at //components/viz/service/display/parc_ca_layer_overlay.h.

#ifndef COMPONENTS_VIZ_SERVICE_DISPLAY_PARC_CA_LAYER_OVERLAY_H_
#define COMPONENTS_VIZ_SERVICE_DISPLAY_PARC_CA_LAYER_OVERLAY_H_

#include "base/containers/flat_set.h"
#include "components/viz/common/quads/aggregated_render_pass.h"
#include "components/viz/service/display/overlay_candidate.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/rrect_f.h"

namespace viz {

class DisplayResourceProvider;
class DrawQuad;

using ParcProtectedLayerCandidateBuilder = bool (*)(
    const DisplayResourceProvider* resource_provider,
    const gfx::RectF& display_rect,
    const DrawQuad* quad,
    OverlayCandidate* candidate,
    bool* skip);
using ParcMaskableRRectPredicate = bool (*)(const gfx::RRectF& rrect);

// Plans protected video layers nested in non-root render passes. Chromium
// supplies its existing candidate and CALayer-mask primitives, so their
// behavior and call sites remain unchanged.
void ParcProcessNestedProtectedLayers(
    const DisplayResourceProvider* resource_provider,
    AggregatedRenderPassList* render_passes,
    bool protected_layers_allowed,
    bool all_ca_layers,
    ParcProtectedLayerCandidateBuilder build_candidate,
    ParcMaskableRRectPredicate is_maskable_rrect,
    OverlayCandidateList* ca_layer_overlays,
    gfx::Rect* root_damage_rect,
    base::flat_set<AggregatedRenderPassId>* punched_passes,
    bool* had_protected_layer);

}  // namespace viz

#endif  // COMPONENTS_VIZ_SERVICE_DISPLAY_PARC_CA_LAYER_OVERLAY_H_
