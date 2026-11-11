// Copyright 2026 Parc contributors.
// Installed at //components/viz/service/display/parc_ca_layer_overlay.cc.

#include "components/viz/service/display/parc_ca_layer_overlay.h"

#include <algorithm>
#include <optional>
#include <utility>
#include <vector>

#include "base/containers/flat_map.h"
#include "base/memory/raw_ptr.h"
#include "components/viz/common/quads/aggregated_render_pass_draw_quad.h"
#include "components/viz/common/quads/draw_quad.h"
#include "components/viz/common/quads/solid_color_draw_quad.h"
#include "components/viz/common/quads/video_hole_draw_quad.h"
#include "components/viz/service/display/display_resource_provider.h"
#include "ui/gfx/geometry/mask_filter_info.h"
#include "ui/gfx/geometry/rect_conversions.h"

namespace viz {
namespace {

// The render pass draw quad that draws a non-root pass into its parent.
struct PassEmbedding {
  raw_ptr<AggregatedRenderPass> parent = nullptr;
  raw_ptr<const AggregatedRenderPassDrawQuad> quad = nullptr;
  int count = 0;
};

using PassEmbeddings = base::flat_map<AggregatedRenderPassId, PassEmbedding>;

PassEmbeddings FindPassEmbeddings(AggregatedRenderPassList& render_passes) {
  PassEmbeddings embeddings;
  for (auto& pass : render_passes) {
    for (const DrawQuad* quad : pass->quad_list) {
      if (const auto* rpdq =
              quad->DynamicCast<AggregatedRenderPassDrawQuad>()) {
        PassEmbedding& embedding = embeddings[rpdq->render_pass_id];
        embedding.parent = pass.get();
        embedding.quad = rpdq;
        ++embedding.count;
      }
    }
  }
  return embeddings;
}

// One render pass draw quad between a protected hole and the root, with the
// hole's footprint in the space of the pass that quad draws into.
struct NestedLevel {
  raw_ptr<const AggregatedRenderPassDrawQuad> quad = nullptr;
  // The pass `quad` draws, and the pass `quad` is in.
  AggregatedRenderPassId pass_id;
  raw_ptr<AggregatedRenderPass> parent = nullptr;
  float opacity = 1.f;
  // The hole quad's transform, clip and rounded clip in `parent`'s space.
  gfx::Transform transform;
  std::optional<gfx::Rect> clip_rect;
  gfx::RRectF rounded_corners;
};

// A protected video drawn inside a non-root render pass, and the protected
// layer that shows it in root space.
struct NestedHole {
  raw_ptr<AggregatedRenderPass> pass = nullptr;
  raw_ptr<const DrawQuad> quad = nullptr;
  // From `pass` up to the root, innermost first.
  std::vector<NestedLevel> levels;
  OverlayCandidate layer;
};

enum class NestedHolePlan {
  kShow,
  // Nothing of it can be seen, so it needs no layer.
  kInvisible,
  // A CALayer can't show it as the page draws it. SkiaRenderer draws it black.
  kKeepBlack,
};

// Adds a mask filter's clip, a plain rect to `clip` and rounded corners to
// `rounded`. False for what a CALayer can't show: a gradient mask, corners of
// different radii, or a second rounded clip that differs from the first.
bool AddMaskClip(const gfx::MaskFilterInfo& mask,
                 ParcMaskableRRectPredicate is_maskable_rrect,
                 gfx::RectF* clip,
                 gfx::RRectF* rounded) {
  if (mask.IsEmpty()) {
    return true;
  }
  if (mask.HasGradientMask()) {
    return false;
  }
  const gfx::RRectF& bounds = mask.rounded_corner_bounds();
  if (!mask.HasRoundedCorners()) {
    clip->Intersect(bounds.rect());
    return true;
  }
  if (!is_maskable_rrect(bounds) ||
      (!rounded->IsEmpty() && *rounded != bounds)) {
    return false;
  }
  *rounded = bounds;
  return true;
}

// Works out where a protected hole drawn in the non-root `hole->pass` shows,
// in each pass up to the root. A CALayer can carry opacity, scale and
// translation, clips and one uniform rounded clip. Anything else stays black.
NestedHolePlan PlanNestedHole(
    const DisplayResourceProvider* resource_provider,
    const AggregatedRenderPass* root,
    const PassEmbeddings& embeddings,
    ParcProtectedLayerCandidateBuilder build_candidate,
    ParcMaskableRRectPredicate is_maskable_rrect,
    NestedHole* hole) {
  bool skip = false;
  if (!build_candidate(resource_provider, gfx::RectF(root->output_rect),
                       hole->quad, &hole->layer, &skip)) {
    return NestedHolePlan::kKeepBlack;
  }
  if (skip) {
    return NestedHolePlan::kInvisible;
  }

  // The geometry is kept in the space of the pass being walked: first the
  // hole's pass, then each parent up to the root.
  const SharedQuadState* sqs = hole->quad->shared_quad_state;
  gfx::Transform transform = sqs->quad_to_target_transform;
  gfx::RectF clip(hole->pass->output_rect);
  if (sqs->clip_rect) {
    clip.Intersect(gfx::RectF(*sqs->clip_rect));
  }
  gfx::RRectF rounded;
  if (!AddMaskClip(sqs->mask_filter_info, is_maskable_rrect, &clip,
                   &rounded)) {
    return NestedHolePlan::kKeepBlack;
  }

  const AggregatedRenderPass* pass = hole->pass;
  while (pass != root) {
    auto found = embeddings.find(pass->id);
    if (found == embeddings.end() || found->second.count != 1 ||
        hole->levels.size() >= embeddings.size()) {
      return NestedHolePlan::kKeepBlack;
    }
    AggregatedRenderPass* parent = found->second.parent;
    const AggregatedRenderPassDrawQuad* rpdq = found->second.quad;
    const SharedQuadState* rpdq_sqs = rpdq->shared_quad_state;
    if (rpdq_sqs->opacity == 0.f || rpdq->visible_rect.IsEmpty()) {
      return NestedHolePlan::kInvisible;
    }
    if (rpdq_sqs->blend_mode != SkBlendMode::kSrcOver ||
        !rpdq->filters.IsEmpty() || !rpdq->backdrop_filters.IsEmpty() ||
        rpdq->mask_resource_id() != kInvalidResourceId ||
        rpdq_sqs->sorting_context_id != 0 ||
        !rpdq_sqs->quad_to_target_transform.IsScaleOrTranslation()) {
      return NestedHolePlan::kKeepBlack;
    }

    // A pass's backing starts at its output rect's origin and is drawn at the
    // render pass draw quad's rect.
    gfx::Transform parent_from_pass = rpdq_sqs->quad_to_target_transform;
    parent_from_pass.Translate(rpdq->rect.x() - pass->output_rect.x(),
                               rpdq->rect.y() - pass->output_rect.y());
    transform.PostConcat(parent_from_pass);
    clip = parent_from_pass.MapRect(clip);
    clip.Intersect(rpdq_sqs->quad_to_target_transform.MapRect(
        gfx::RectF(rpdq->rect)));
    if (rpdq_sqs->clip_rect) {
      clip.Intersect(gfx::RectF(*rpdq_sqs->clip_rect));
    }
    if (parent != root) {
      clip.Intersect(gfx::RectF(parent->output_rect));
    }
    if (!rounded.IsEmpty()) {
      gfx::MaskFilterInfo mapped(rounded);
      mapped.ApplyTransform(parent_from_pass);
      // A non-uniform scale makes corners elliptical.
      if (mapped.IsEmpty() ||
          !is_maskable_rrect(mapped.rounded_corner_bounds())) {
        return NestedHolePlan::kKeepBlack;
      }
      rounded = mapped.rounded_corner_bounds();
    }
    if (!AddMaskClip(rpdq_sqs->mask_filter_info, is_maskable_rrect, &clip,
                     &rounded)) {
      return NestedHolePlan::kKeepBlack;
    }

    // SkiaRenderer draws the hole flattened into its pass.
    NestedLevel& level = hole->levels.emplace_back();
    level.quad = rpdq;
    level.pass_id = pass->id;
    level.parent = parent;
    level.opacity = rpdq_sqs->opacity;
    level.transform = transform;
    level.transform.Flatten();
    const gfx::RectF footprint =
        level.transform.MapRect(gfx::RectF(hole->quad->rect));
    gfx::RectF visible = footprint;
    visible.Intersect(clip);
    if (!rounded.IsEmpty()) {
      visible.Intersect(rounded.rect());
    }
    if (visible.IsEmpty()) {
      return NestedHolePlan::kInvisible;
    }
    if (!clip.Contains(footprint)) {
      level.clip_rect = gfx::ToEnclosingRect(clip);
    }
    level.rounded_corners = rounded;
    pass = parent;
  }

  const NestedLevel& outermost = hole->levels.back();
  OverlayCandidate& layer = hole->layer;
  layer.transform = outermost.transform;
  layer.clip_rect = outermost.clip_rect;
  layer.rounded_corners = outermost.rounded_corners;
  layer.sorting_context_id = 0;
  // Where the occlusion culler trimmed the hole because its pass draws
  // something opaque over it, leave the layer out too.
  if (hole->quad->visible_rect != hole->quad->rect &&
      outermost.transform.Preserves2dAxisAlignment()) {
    const gfx::Rect visible = gfx::ToEnclosingRect(
        outermost.transform.MapRect(gfx::RectF(hole->quad->visible_rect)));
    layer.clip_rect = layer.clip_rect
                          ? gfx::IntersectRects(*layer.clip_rect, visible)
                          : visible;
  }
  return NestedHolePlan::kShow;
}

// The layer's opacity when the pass drawn in the root is a CALayer above it,
// with the hole punched out of the pass and the pass's opacity applying to
// what is left. With c the video's own opacity times every pass's (its share
// of the pixel) and a the outermost pass's opacity, it is c / (1 - a + c).
// That is exact whenever at most one of them is below 1, assuming what a
// translucent video covers in its own pass is opaque: a fading dialog
// (c = a) gets a; a translucent video in an opaque dialog gets 1, the dialog
// showing through the punch's remainder.
float CALayerRouteOpacity(const NestedHole& hole) {
  float c = hole.quad->shared_quad_state->opacity;
  for (const NestedLevel& level : hole.levels) {
    c *= level.opacity;
  }
  const float a = hole.levels.back().opacity;
  return c / (1.f - a + c);
}

// A black DstOut copy of a hole's footprint, drawn in `parent` just below the
// render pass draw quad that draws `pass_id`, at that quad's opacity.
struct BelowPassPunch {
  raw_ptr<AggregatedRenderPass> parent = nullptr;
  AggregatedRenderPassId pass_id;
  gfx::Rect rect;
  // Where the hole's pass draws something opaque over it, leave the parent's
  // content alone.
  gfx::Rect visible_rect;
  gfx::Transform transform;
  std::optional<gfx::Rect> clip_rect;
  gfx::RRectF rounded_corners;
  float opacity = 1.f;
};

BelowPassPunch MakeBelowPassPunch(const NestedHole& hole,
                                  const NestedLevel& level) {
  return BelowPassPunch{level.parent,          level.pass_id,
                        hole.quad->rect,       hole.quad->visible_rect,
                        level.transform,       level.clip_rect,
                        level.rounded_corners, level.opacity};
}

void DrawBelowPassPunch(const BelowPassPunch& punch) {
  QuadList& quads = punch.parent->quad_list;
  for (auto it = quads.begin(); it != quads.end(); ++it) {
    const auto* rpdq = it->DynamicCast<AggregatedRenderPassDrawQuad>();
    if (!rpdq || rpdq->render_pass_id != punch.pass_id) {
      continue;
    }
    SharedQuadState* sqs = punch.parent->CreateAndAppendSharedQuadState();
    sqs->SetAll(punch.transform, punch.rect, punch.rect,
                gfx::MaskFilterInfo(punch.rounded_corners), punch.clip_rect,
                /*contents_opaque=*/false, punch.opacity, SkBlendMode::kDstOut,
                /*sorting_context=*/0, /*layer_id=*/0u,
                /*fast_rounded_corner=*/false);
    // QuadList runs front to back, so the copy is drawn just before the pass.
    auto copy =
        quads.InsertAfterAndInvalidateAllPointers<SolidColorDrawQuad>(it, 1u);
    static_cast<SolidColorDrawQuad*>(*copy)->SetNew(
        sqs, punch.rect, punch.visible_rect, SkColors::kBlack,
        /*anti_aliasing_off=*/false);
    return;
  }
}

// Redraws `id`'s pass whole this frame, with every pass that draws it, because
// its hole punch started or stopped. The root isn't touched.
void RedrawPassAndEmbedders(
    AggregatedRenderPassId id,
    const AggregatedRenderPassList& render_passes,
    const PassEmbeddings& embeddings) {
  const AggregatedRenderPass* root = render_passes.back().get();
  for (size_t steps = 0; steps < render_passes.size(); ++steps) {
    auto pass = std::ranges::find(render_passes, id, &AggregatedRenderPass::id);
    if (pass == render_passes.end() || pass->get() == root) {
      return;
    }
    (*pass)->has_damage_from_contributing_content = true;
    (*pass)->damage_rect = (*pass)->output_rect;
    auto found = embeddings.find(id);
    if (found == embeddings.end()) {
      return;
    }
    id = found->second.parent->id;
  }
}

}  // namespace

gfx::CALayerResult ParcFromVideoHoleQuad(const DrawQuad* quad,
                                         OverlayCandidate* ca_layer_overlay) {
  const auto* hole = VideoHoleDrawQuad::MaterialCast(quad);
  if (hole->overlay_plane_id.is_empty()) {
    return gfx::kCALayerFailedUnknown;
  }
  ca_layer_overlay->protected_layer_token = hole->overlay_plane_id;
  ca_layer_overlay->protected_video_type =
      gfx::ProtectedVideoType::kHardwareProtected;
  return gfx::kCALayerSuccess;
}

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
    bool* had_protected_layer) {
  // Every frame costs one look at each non-root quad.
  AggregatedRenderPass* root = render_passes->back().get();
  bool has_hole = false;
  for (const auto& pass : *render_passes) {
    if (pass.get() == root || has_hole) {
      break;
    }
    has_hole = std::ranges::any_of(pass->quad_list, [](const DrawQuad* quad) {
      return quad->material == DrawQuad::Material::kVideoHole;
    });
  }
  if (!has_hole && punched_passes->empty()) {
    return;
  }
  if (has_hole) {
    *had_protected_layer = true;
  }

  base::flat_set<AggregatedRenderPassId> punched;
  std::vector<BelowPassPunch> below_pass_punches;
  {
    const PassEmbeddings embeddings = FindPassEmbeddings(*render_passes);
    std::vector<NestedHole> holes;
    // A parked display leaves every hole black, as in the root pass.
    if (has_hole && protected_layers_allowed) {
      for (const auto& pass : *render_passes) {
        if (pass.get() == root) {
          break;
        }
        for (const DrawQuad* quad : pass->quad_list) {
          if (quad->material != DrawQuad::Material::kVideoHole) {
            continue;
          }
          NestedHole hole;
          hole.pass = pass.get();
          hole.quad = quad;
          if (PlanNestedHole(resource_provider, root, embeddings,
                             build_candidate, is_maskable_rrect, &hole) ==
              NestedHolePlan::kShow) {
            holes.push_back(std::move(hole));
          }
        }
      }
    }

    for (NestedHole& hole : holes) {
      // One video is one layer; a second hole naming it stays black.
      if (std::ranges::any_of(*ca_layer_overlays,
                              [&](const OverlayCandidate& candidate) {
                                return candidate.protected_layer_token ==
                                       hole.layer.protected_layer_token;
                              })) {
        continue;
      }
      if (all_ca_layers) {
        // The layer goes right below the CALayer of the pass drawn in the
        // root, so that pass's content stays above the video and the root's
        // content below the pass stays below it.
        auto pass_layer = std::ranges::find_if(
            *ca_layer_overlays, [&](const OverlayCandidate& candidate) {
              return candidate.rpdq == hole.levels.back().quad;
            });
        if (pass_layer == ca_layer_overlays->end()) {
          continue;
        }
        // One layer more than the root's quads; the CALayer count limit is a
        // performance guard, and a video is one layer either way.
        hole.layer.opacity = CALayerRouteOpacity(hole);
        ca_layer_overlays->insert(pass_layer, hole.layer);
        // Each pass in between draws the inner pass over what it draws below
        // it, which the video covers too.
        for (size_t i = 0; i + 1 < hole.levels.size(); ++i) {
          below_pass_punches.push_back(
              MakeBelowPassPunch(hole, hole.levels[i]));
        }
      } else {
        // An underlay below the primary plane, as for a hole in the root
        // pass. Every pass up to the root draws the inner pass over what it
        // draws below it, so each of those is punched as well. The punches
        // carry the opacity, so the layer is drawn at full strength: exact
        // when at most one of the video and its passes is translucent, the
        // page being opaque.
        hole.layer.opacity = 1.f;
        ca_layer_overlays->push_back(hole.layer);
        for (const NestedLevel& level : hole.levels) {
          below_pass_punches.push_back(MakeBelowPassPunch(hole, level));
        }
      }

      // The video shows through a transparent punch in its own pass (DstOut
      // when it is translucent, keeping the rest of what it covers), under
      // whatever that pass draws over it.
      for (auto it = hole.pass->quad_list.begin();
           it != hole.pass->quad_list.end(); ++it) {
        if (*it == hole.quad) {
          hole.pass->ReplaceExistingQuadWithHolePunch(it);
          break;
        }
      }
      punched.insert(hole.pass->id);
    }

    // Redraw a pass whose punch starts or stops, even if nothing else changed.
    if (punched != *punched_passes) {
      for (AggregatedRenderPassId id : punched) {
        if (!punched_passes->contains(id)) {
          RedrawPassAndEmbedders(id, *render_passes, embeddings);
        }
      }
      for (AggregatedRenderPassId id : *punched_passes) {
        if (!punched.contains(id)) {
          RedrawPassAndEmbedders(id, *render_passes, embeddings);
        }
      }
      if (!all_ca_layers) {
        *root_damage_rect = root->output_rect;
      }
    }
  }

  for (const BelowPassPunch& punch : below_pass_punches) {
    DrawBelowPassPunch(punch);
  }
  *punched_passes = std::move(punched);
}

}  // namespace viz
