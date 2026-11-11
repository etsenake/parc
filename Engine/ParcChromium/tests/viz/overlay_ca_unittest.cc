// Copyright 2014 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <stddef.h>

#include <utility>
#include <variant>
#include <vector>

#include "base/containers/flat_map.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/functional/function_ref.h"
#include "base/memory/raw_ptr.h"
#include "base/unguessable_token.h"
#include "build/build_config.h"
#include "cc/test/fake_output_surface_client.h"
#include "cc/test/resource_provider_test_utils.h"
#include "components/viz/client/client_resource_provider.h"
#include "components/viz/common/frame_sinks/copy_output_request.h"
#include "components/viz/common/quads/aggregated_render_pass.h"
#include "components/viz/common/quads/aggregated_render_pass_draw_quad.h"
#include "components/viz/common/quads/compositor_render_pass.h"
#include "components/viz/common/quads/compositor_render_pass_draw_quad.h"
#include "components/viz/common/quads/solid_color_draw_quad.h"
#include "components/viz/common/quads/texture_draw_quad.h"
#include "components/viz/common/quads/video_hole_draw_quad.h"
#include "components/viz/common/resources/transferable_resource.h"
#include "components/viz/service/display/ca_layer_overlay.h"
#include "components/viz/service/display/display_resource_provider_skia.h"
#include "components/viz/service/display/output_surface.h"
#include "components/viz/service/display/output_surface_client.h"
#include "components/viz/service/display/output_surface_frame.h"
#include "components/viz/service/display/overlay_processor_mac.h"
#include "components/viz/test/fake_skia_output_surface.h"
#include "components/viz/test/overlay_candidate_matchers.h"
#include "components/viz/test/test_context_provider.h"
#include "components/viz/test/test_gles2_interface.h"
#include "gpu/command_buffer/client/client_shared_image.h"
#include "gpu/config/gpu_finch_features.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "ui/gfx/geometry/rect_conversions.h"
#include "ui/gfx/video_types.h"
#include "ui/latency/latency_info.h"

namespace viz {
namespace {

const gfx::Rect kOverlayRect(0, 0, 256, 256);
const gfx::PointF kUVTopLeft(0.1f, 0.2f);
const gfx::PointF kUVBottomRight(1.0f, 1.0f);
const gfx::Rect kRenderPassOutputRect(0, 0, 256, 256);
const gfx::Rect kOverlayDamageRect(0, 0, 100, 100);

class CATestOverlayProcessor : public OverlayProcessorMac {
 public:
  CATestOverlayProcessor() : OverlayProcessorMac() {}
};

std::unique_ptr<AggregatedRenderPass> CreateRenderPass() {
  AggregatedRenderPassId render_pass_id{1};

  auto pass = std::make_unique<AggregatedRenderPass>();
  pass->SetNew(render_pass_id, kRenderPassOutputRect, kRenderPassOutputRect,
               gfx::Transform());

  SharedQuadState* shared_state = pass->CreateAndAppendSharedQuadState();
  shared_state->opacity = 1.f;
  return pass;
}

static ResourceId CreateResourceInLayerTree(
    ClientResourceProvider* child_resource_provider,
    const gfx::Size& size,
    bool is_overlay_candidate) {
  gpu::SharedImageUsageSet usage = gpu::SHARED_IMAGE_USAGE_DISPLAY_READ;
  if (is_overlay_candidate) {
    usage |= gpu::SHARED_IMAGE_USAGE_SCANOUT;
  }
  auto resource = TransferableResource::Make(
      gpu::ClientSharedImage::CreateForTesting(
          {SinglePlaneFormat::kRGBA_8888, size, gfx::ColorSpace(),
           kTopLeft_GrSurfaceOrigin, kPremul_SkAlphaType, usage},
          GL_TEXTURE_2D),
      TransferableResource::ResourceSource::kTest, gpu::SyncToken());

  ResourceId resource_id =
      child_resource_provider->ImportResource(resource, base::DoNothing());

  return resource_id;
}

ResourceId CreateResource(DisplayResourceProvider* parent_resource_provider,
                          ClientResourceProvider* child_resource_provider,
                          RasterContextProvider* child_context_provider,
                          const gfx::Size& size,
                          bool is_overlay_candidate) {
  ResourceId resource_id = CreateResourceInLayerTree(
      child_resource_provider, size, is_overlay_candidate);

  int child_id =
      parent_resource_provider->CreateChild(base::DoNothing(), SurfaceId());

  // Transfer resource to the parent.
  std::vector<ResourceId> resource_ids_to_transfer;
  resource_ids_to_transfer.push_back(resource_id);
  std::vector<TransferableResource> list;

  CHECK(child_context_provider);
  child_resource_provider->PrepareSendToParent(
      resource_ids_to_transfer, &list,
      child_context_provider->SharedImageInterface());
  parent_resource_provider->ReceiveFromChild(child_id, list);

  // Delete it in the child so it won't be leaked, and will be released once
  // returned from the parent.
  child_resource_provider->RemoveImportedResource(resource_id);

  // In DisplayResourceProvider's namespace, use the mapped resource id.
  std::unordered_map<ResourceId, ResourceId, ResourceIdHasher> resource_map =
      parent_resource_provider->GetChildToParentMap(child_id);
  return resource_map[list[0].id];
}

TextureDrawQuad* CreateCandidateQuadAt(
    DisplayResourceProvider* parent_resource_provider,
    ClientResourceProvider* child_resource_provider,
    RasterContextProvider* child_context_provider,
    const SharedQuadState* shared_quad_state,
    AggregatedRenderPass* render_pass,
    const gfx::Rect& rect,
    gfx::ProtectedVideoType protected_video_type) {
  bool needs_blending = false;
  bool nearest_neighbor = false;
  gfx::Size resource_size_in_pixels = rect.size();
  bool is_overlay_candidate = true;
  ResourceId resource_id = CreateResource(
      parent_resource_provider, child_resource_provider, child_context_provider,
      resource_size_in_pixels, is_overlay_candidate);

  auto* overlay_quad = render_pass->CreateAndAppendDrawQuad<TextureDrawQuad>();
  overlay_quad->SetNew(
      shared_quad_state, rect, rect, needs_blending, resource_id,
      /*top_left=*/gfx::ScalePoint(kUVTopLeft, rect.width(), rect.height()),
      /*bottom_right=*/
      gfx::ScalePoint(kUVBottomRight, rect.width(), rect.height()),
      SkColors::kTransparent, nearest_neighbor,
      /*secure_output=*/false, protected_video_type,
      /*is_tex_coords_normalized=*/false);

  return overlay_quad;
}

TextureDrawQuad* CreateFullscreenCandidateQuad(
    DisplayResourceProvider* parent_resource_provider,
    ClientResourceProvider* child_resource_provider,
    RasterContextProvider* child_context_provider,
    const SharedQuadState* shared_quad_state,
    AggregatedRenderPass* render_pass) {
  return CreateCandidateQuadAt(
      parent_resource_provider, child_resource_provider, child_context_provider,
      shared_quad_state, render_pass, render_pass->output_rect,
      gfx::ProtectedVideoType::kClear);
}

SkM44 GetIdentityColorMatrix() {
  return SkM44();
}

class ParcCALayerOverlayTest : public testing::Test {
 protected:
  void SetUp() override {
    output_surface_ = FakeSkiaOutputSurface::Create3d();
    output_surface_->BindToClient(&output_surface_client_);

    resource_provider_ = std::make_unique<DisplayResourceProviderSkia>();
    lock_set_for_external_use_.emplace(resource_provider_.get(),
                                       output_surface_.get());

    child_provider_ = TestContextProvider::CreateGLES();
    child_provider_->BindToCurrentSequence();
    child_resource_provider_ = std::make_unique<ClientResourceProvider>();

    overlay_processor_ = std::make_unique<CATestOverlayProcessor>();
  }

  void TearDown() override {
    overlay_processor_ = nullptr;
    child_resource_provider_->ShutdownAndReleaseAllResources();
    child_resource_provider_ = nullptr;
    child_provider_ = nullptr;
    lock_set_for_external_use_.reset();
    resource_provider_ = nullptr;
    output_surface_ = nullptr;
  }

  OverlayProcessorInterface::PrimaryPlaneParams GetDefaultPrimaryPlane(
      const gfx::Size& primary_plane_size) {
    return OverlayProcessorInterface::PrimaryPlaneParams{
        .viewport_size = primary_plane_size,
        .resource_size_in_pixels = primary_plane_size,
        .supports_hdr = false,
        .is_opaque = true,
        .si_format = SinglePlaneFormat::kRGBA_8888,
        .color_space = gfx::ColorSpace::CreateSRGB(),
    };
  }

  std::unique_ptr<SkiaOutputSurface> output_surface_;
  cc::FakeOutputSurfaceClient output_surface_client_;
  std::unique_ptr<DisplayResourceProviderSkia> resource_provider_;
  std::optional<DisplayResourceProviderSkia::LockSetForExternalUse>
      lock_set_for_external_use_;
  scoped_refptr<TestContextProvider> child_provider_;
  std::unique_ptr<ClientResourceProvider> child_resource_provider_;
  std::unique_ptr<CATestOverlayProcessor> overlay_processor_;
  gfx::Rect damage_rect_ = kOverlayDamageRect;


 private:
  std::optional<OverlayCandidate> primary_plane_;
};


// Parc: a FairPlay video (a VideoHoleDrawQuad naming a registered layer) is
// placed with its token, except on a display that may not show protected
// layers (a parked pane compositor), which shows it black and never places it.
TEST_F(ParcCALayerOverlayTest, ProtectedLayerPlacedOrHeldBack) {
  const base::UnguessableToken token = base::UnguessableToken::Create();
  auto process = [&](bool copy_request, OverlayCandidateList* ca_layer_list,
                     AggregatedRenderPassList* pass_list) {
    auto pass = CreateRenderPass();
    auto* hole = pass->CreateAndAppendDrawQuad<VideoHoleDrawQuad>();
    hole->SetNew(pass->shared_quad_state_list.back(), kOverlayRect,
                 kOverlayRect, token);
    if (copy_request) {
      pass->copy_requests.push_back(CopyOutputRequest::CreateStubForTesting());
    }
    pass_list->push_back(std::move(pass));
    overlay_processor_->ProcessForOverlays(
        resource_provider_.get(), pass_list, GetIdentityColorMatrix(),
        SurfaceDamageRectList(),
        GetDefaultPrimaryPlane(pass_list->back()->output_rect.size()),
        ca_layer_list, &damage_rect_);
  };
  auto only_overlay = [](const OverlayCandidateList& list) {
    const OverlayCandidate* found = nullptr;
    for (const auto& candidate : list) {
      if (!candidate.is_root_render_pass) {
        EXPECT_FALSE(found);
        found = &candidate;
      }
    }
    return found;
  };

  // Allowed (the default): every quad is a CALayer, the hole with its token.
  {
    OverlayCandidateList ca_layer_list;
    AggregatedRenderPassList pass_list;
    process(/*copy_request=*/false, &ca_layer_list, &pass_list);
    const OverlayCandidate* overlay = only_overlay(ca_layer_list);
    ASSERT_TRUE(overlay);
    EXPECT_EQ(token, overlay->protected_layer_token);
    EXPECT_EQ(gfx::ProtectedVideoType::kHardwareProtected,
              overlay->protected_video_type);
    EXPECT_FALSE(overlay->is_solid_color);
    EXPECT_TRUE(overlay_processor_->HadProtectedLayer());
  }

  // Allowed, but the frame can't be all CALayers: the hole goes to an
  // underlay with its token and leaves a hole punch in the primary plane.
  {
    OverlayCandidateList ca_layer_list;
    AggregatedRenderPassList pass_list;
    process(/*copy_request=*/true, &ca_layer_list, &pass_list);
    const OverlayCandidate* overlay = only_overlay(ca_layer_list);
    ASSERT_TRUE(overlay);
    EXPECT_EQ(token, overlay->protected_layer_token);
    EXPECT_EQ(DrawQuad::Material::kSolidColor,
              pass_list.back()->quad_list.front()->material);
    EXPECT_TRUE(overlay_processor_->HadProtectedLayer());
  }

  overlay_processor_->SetProtectedLayersAllowed(false);

  // Parked: the hole is a black CALayer without a token.
  {
    OverlayCandidateList ca_layer_list;
    AggregatedRenderPassList pass_list;
    process(/*copy_request=*/false, &ca_layer_list, &pass_list);
    const OverlayCandidate* overlay = only_overlay(ca_layer_list);
    ASSERT_TRUE(overlay);
    EXPECT_FALSE(overlay->protected_layer_token);
    EXPECT_TRUE(overlay->is_solid_color);
    EXPECT_EQ(SkColors::kBlack, overlay->color);
    EXPECT_TRUE(overlay_processor_->HadProtectedLayer());
  }

  // Parked, without all CALayers: no underlay; the hole stays in the primary
  // plane, where SkiaRenderer draws a quad that requires an overlay black
  // (magenta with DCHECKs).
  {
    OverlayCandidateList ca_layer_list;
    AggregatedRenderPassList pass_list;
    process(/*copy_request=*/true, &ca_layer_list, &pass_list);
    EXPECT_FALSE(only_overlay(ca_layer_list));
    EXPECT_EQ(DrawQuad::Material::kVideoHole,
              pass_list.back()->quad_list.front()->material);
    EXPECT_TRUE(overlay_processor_->HadProtectedLayer());
  }

  // Allowed again: placed with its token.
  overlay_processor_->SetProtectedLayersAllowed(true);
  {
    OverlayCandidateList ca_layer_list;
    AggregatedRenderPassList pass_list;
    process(/*copy_request=*/false, &ca_layer_list, &pass_list);
    const OverlayCandidate* overlay = only_overlay(ca_layer_list);
    ASSERT_TRUE(overlay);
    EXPECT_EQ(token, overlay->protected_layer_token);
    EXPECT_TRUE(overlay_processor_->HadProtectedLayer());
  }
}

// Parc: the protected-layer flag changes nothing in a frame without a FairPlay
// video, so a parked pane compositor's frames are what they were.
TEST_F(ParcCALayerOverlayTest, ProtectedLayersFlagLeavesOrdinaryFramesAlone) {
  auto process = [&](OverlayCandidateList* ca_layer_list) {
    auto pass = CreateRenderPass();
    TextureDrawQuad* video = CreateFullscreenCandidateQuad(
        resource_provider_.get(), child_resource_provider_.get(),
        child_provider_.get(), pass->shared_quad_state_list.back(), pass.get());
    video->is_video_frame = true;
    auto* color = pass->CreateAndAppendDrawQuad<SolidColorDrawQuad>();
    color->SetNew(pass->shared_quad_state_list.back(), kOverlayRect,
                  kOverlayRect, SkColors::kRed, /*anti_aliasing_off=*/false);
    AggregatedRenderPassList pass_list;
    pass_list.push_back(std::move(pass));
    overlay_processor_->ProcessForOverlays(
        resource_provider_.get(), &pass_list, GetIdentityColorMatrix(),
        SurfaceDamageRectList(),
        GetDefaultPrimaryPlane(pass_list.back()->output_rect.size()),
        ca_layer_list, &damage_rect_);
  };

  OverlayCandidateList allowed;
  process(&allowed);
  overlay_processor_->SetProtectedLayersAllowed(false);
  OverlayCandidateList parked;
  process(&parked);

  ASSERT_EQ(2U, allowed.size());
  ASSERT_EQ(allowed.size(), parked.size());
  for (size_t i = 0; i < allowed.size(); ++i) {
    EXPECT_EQ(allowed[i].display_rect, parked[i].display_rect);
    EXPECT_EQ(allowed[i].is_solid_color, parked[i].is_solid_color);
    EXPECT_EQ(allowed[i].color, parked[i].color);
    EXPECT_EQ(allowed[i].protected_video_type, parked[i].protected_video_type);
    EXPECT_FALSE(parked[i].protected_layer_token);
  }
  EXPECT_FALSE(overlay_processor_->HadProtectedLayer());
}

// Parc: a FairPlay video drawn inside a render pass, as in a player dialog
// that keeps an opacity animation. The root draws a page background and a
// dialog pass; the dialog draws a black background, the video and a caption.
class ParcCALayerOverlayNestedTest : public ParcCALayerOverlayTest {
 protected:
  static constexpr AggregatedRenderPassId kDialogPassId{2};

  struct Frame {
    AggregatedRenderPassList passes;
    OverlayCandidateList candidates;
    raw_ptr<AggregatedRenderPass> dialog = nullptr;
  };

  // What a test can change before the frame is processed.
  struct Parts {
    raw_ptr<AggregatedRenderPass> root;
    raw_ptr<AggregatedRenderPassDrawQuad> dialog_quad;
    raw_ptr<SharedQuadState> dialog_sqs;
    raw_ptr<SharedQuadState> video_sqs;
    raw_ptr<DrawQuad> video;
  };

  // The dialog pass's 100x60 content is drawn at (20, 30), twice as large.
  // The video sits at (10, 10) in it, 80x40.
  std::unique_ptr<AggregatedRenderPass> CreateDialogPass(
      float video_opacity,
      SharedQuadState** video_sqs_out = nullptr) {
    auto pass = std::make_unique<AggregatedRenderPass>();
    pass->SetNew(kDialogPassId, gfx::Rect(0, 0, 100, 60), gfx::Rect(),
                 gfx::Transform());
    pass->has_damage_from_contributing_content = false;
    SharedQuadState* sqs = pass->CreateAndAppendSharedQuadState();
    sqs->opacity = 1.f;
    auto* caption = pass->CreateAndAppendDrawQuad<SolidColorDrawQuad>();
    caption->SetNew(sqs, gfx::Rect(10, 40, 80, 10), gfx::Rect(10, 40, 80, 10),
                    SkColors::kWhite, /*anti_aliasing_off=*/false);
    SharedQuadState* video_sqs = pass->CreateAndAppendSharedQuadState();
    video_sqs->opacity = video_opacity;
    video_sqs->quad_to_target_transform.Translate(10, 10);
    auto* video = pass->CreateAndAppendDrawQuad<VideoHoleDrawQuad>();
    video->SetNew(video_sqs, gfx::Rect(0, 0, 80, 40), gfx::Rect(0, 0, 80, 40),
                  token_);
    SharedQuadState* background_sqs = pass->CreateAndAppendSharedQuadState();
    background_sqs->opacity = 1.f;
    auto* background = pass->CreateAndAppendDrawQuad<SolidColorDrawQuad>();
    background->SetNew(background_sqs, pass->output_rect, pass->output_rect,
                       SkColors::kBlack, /*anti_aliasing_off=*/false);
    if (video_sqs_out) {
      *video_sqs_out = video_sqs;
    }
    return pass;
  }

  Frame Process(float dialog_opacity, float video_opacity) {
    return Process(dialog_opacity, video_opacity, [](const Parts&) {});
  }

  Frame Process(float dialog_opacity,
                float video_opacity,
                base::FunctionRef<void(const Parts&)> configure) {
    Frame frame;
    SharedQuadState* video_sqs = nullptr;
    auto dialog = CreateDialogPass(video_opacity, &video_sqs);
    frame.dialog = dialog.get();
    frame.passes.push_back(std::move(dialog));

    auto root = CreateRenderPass();
    SharedQuadState* dialog_sqs = root->CreateAndAppendSharedQuadState();
    dialog_sqs->opacity = dialog_opacity;
    dialog_sqs->quad_to_target_transform.Translate(20, 30);
    dialog_sqs->quad_to_target_transform.Scale(2, 2);
    auto* dialog_quad =
        root->CreateAndAppendDrawQuad<AggregatedRenderPassDrawQuad>();
    dialog_quad->SetNew(dialog_sqs, gfx::Rect(0, 0, 100, 60),
                        gfx::Rect(0, 0, 100, 60), kDialogPassId,
                        kInvalidResourceId, gfx::RectF(), gfx::Size(),
                        /*force_anti_aliasing_off=*/false);
    SharedQuadState* page_sqs = root->CreateAndAppendSharedQuadState();
    page_sqs->opacity = 1.f;
    auto* page = root->CreateAndAppendDrawQuad<SolidColorDrawQuad>();
    page->SetNew(page_sqs, root->output_rect, root->output_rect, SkColors::kRed,
                 /*anti_aliasing_off=*/false);
    configure(Parts{root.get(), dialog_quad, dialog_sqs, video_sqs,
                    *std::next(frame.passes.front()->quad_list.begin())});
    frame.passes.push_back(std::move(root));

    overlay_processor_->ProcessForOverlays(
        resource_provider_.get(), &frame.passes, GetIdentityColorMatrix(),
        SurfaceDamageRectList(),
        GetDefaultPrimaryPlane(frame.passes.back()->output_rect.size()),
        &frame.candidates, &damage_rect_);
    return frame;
  }

  static const OverlayCandidate* ProtectedLayer(const Frame& frame) {
    for (const auto& candidate : frame.candidates) {
      if (candidate.protected_layer_token) {
        return &candidate;
      }
    }
    return nullptr;
  }

  static const DrawQuad* DialogVideoQuad(const Frame& frame) {
    // Front to back: caption, video (or its punch), background.
    return *std::next(frame.dialog->quad_list.begin());
  }

  const base::UnguessableToken token_ = base::UnguessableToken::Create();
};

// The protected layer goes right below the dialog's CALayer, in root space,
// with the dialog's opacity, and the video is punched out of the dialog so
// its caption stays on top.
TEST_F(ParcCALayerOverlayNestedTest, PlacedBelowItsPass) {
  Frame frame = Process(/*dialog_opacity=*/0.5f, /*video_opacity=*/1.f);
  ASSERT_EQ(3u, frame.candidates.size());
  EXPECT_TRUE(frame.candidates[0].is_solid_color);
  EXPECT_EQ(SkColors::kRed, frame.candidates[0].color);
  const OverlayCandidate& layer = frame.candidates[1];
  EXPECT_EQ(token_, layer.protected_layer_token);
  EXPECT_EQ(gfx::ProtectedVideoType::kHardwareProtected,
            layer.protected_video_type);
  ASSERT_TRUE(frame.candidates[2].rpdq);
  EXPECT_EQ(kDialogPassId, frame.candidates[2].rpdq->render_pass_id);

  gfx::Transform expected_transform;
  expected_transform.Translate(20, 30);
  expected_transform.Scale(2, 2);
  expected_transform.Translate(10, 10);
  EXPECT_EQ(expected_transform, std::get<gfx::Transform>(layer.transform));
  EXPECT_EQ(gfx::RectF(0, 0, 80, 40), layer.display_rect);
  EXPECT_EQ(gfx::RectF(40, 50, 160, 80),
            OverlayCandidate::DisplayRectInTargetSpace(layer));
  EXPECT_FALSE(layer.clip_rect);
  EXPECT_TRUE(layer.rounded_corners.IsEmpty());
  EXPECT_EQ(0u, layer.sorting_context_id);
  EXPECT_FLOAT_EQ(0.5f, layer.opacity);

  // An opaque video leaves a transparent punch, drawn without blending.
  const DrawQuad* punch = DialogVideoQuad(frame);
  ASSERT_EQ(DrawQuad::Material::kSolidColor, punch->material);
  EXPECT_EQ(SkColors::kTransparent,
            SolidColorDrawQuad::MaterialCast(punch)->color);
  EXPECT_FALSE(punch->ShouldDrawWithBlending());
  EXPECT_TRUE(overlay_processor_->HadProtectedLayer());

  // The first punched frame redraws the whole dialog pass; later ones don't.
  EXPECT_TRUE(frame.dialog->has_damage_from_contributing_content);
  EXPECT_EQ(frame.dialog->output_rect, frame.dialog->damage_rect);
  Frame next = Process(/*dialog_opacity=*/0.5f, /*video_opacity=*/1.f);
  ASSERT_TRUE(ProtectedLayer(next));
  EXPECT_FALSE(next.dialog->has_damage_from_contributing_content);
  EXPECT_EQ(gfx::Rect(), next.dialog->damage_rect);
}

// Opacity is exact when only one of the video and its passes is translucent;
// a translucent video leaves a DstOut punch that keeps the rest of what it
// covers.
TEST_F(ParcCALayerOverlayNestedTest, TranslucentVideoAndPass) {
  {
    Frame frame = Process(/*dialog_opacity=*/1.f, /*video_opacity=*/0.5f);
    const OverlayCandidate* layer = ProtectedLayer(frame);
    ASSERT_TRUE(layer);
    EXPECT_FLOAT_EQ(1.f, layer->opacity);
    const DrawQuad* punch = DialogVideoQuad(frame);
    ASSERT_EQ(DrawQuad::Material::kSolidColor, punch->material);
    EXPECT_EQ(SkColors::kBlack,
              SolidColorDrawQuad::MaterialCast(punch)->color);
    EXPECT_EQ(SkBlendMode::kDstOut, punch->shared_quad_state->blend_mode);
    EXPECT_FLOAT_EQ(0.5f, punch->shared_quad_state->opacity);
  }
  {
    // Both translucent: c / (1 - a + c) with c = 0.25 and a = 0.5.
    Frame frame = Process(/*dialog_opacity=*/0.5f, /*video_opacity=*/0.5f);
    const OverlayCandidate* layer = ProtectedLayer(frame);
    ASSERT_TRUE(layer);
    EXPECT_FLOAT_EQ(1.f / 3.f, layer->opacity);
  }
}

// Clips and one uniform rounded clip carry onto the layer in root space.
TEST_F(ParcCALayerOverlayNestedTest, ClipAndRoundedCorners) {
  {
    Frame frame = Process(1.f, 1.f, [](const Parts& parts) {
      parts.dialog_sqs->clip_rect = gfx::Rect(50, 60, 100, 40);
      parts.dialog_sqs->mask_filter_info =
          gfx::MaskFilterInfo(gfx::RRectF(gfx::RectF(20, 30, 200, 120), 12));
    });
    const OverlayCandidate* layer = ProtectedLayer(frame);
    ASSERT_TRUE(layer);
    EXPECT_EQ(gfx::Rect(50, 60, 100, 40), layer->clip_rect);
    EXPECT_EQ(gfx::RRectF(gfx::RectF(20, 30, 200, 120), 12),
              layer->rounded_corners);
  }
  {
    // The video's own clip and rounded corners scale into root space.
    Frame frame = Process(1.f, 1.f, [](const Parts& parts) {
      parts.video_sqs->clip_rect = gfx::Rect(10, 10, 40, 40);
      parts.video_sqs->mask_filter_info =
          gfx::MaskFilterInfo(gfx::RRectF(gfx::RectF(10, 10, 80, 40), 4));
    });
    const OverlayCandidate* layer = ProtectedLayer(frame);
    ASSERT_TRUE(layer);
    EXPECT_EQ(gfx::Rect(40, 50, 80, 80), layer->clip_rect);
    EXPECT_EQ(gfx::RRectF(gfx::RectF(40, 50, 160, 80), 8),
              layer->rounded_corners);
  }
  {
    // Two different rounded clips can't both apply: black.
    Frame frame = Process(1.f, 1.f, [](const Parts& parts) {
      parts.video_sqs->mask_filter_info =
          gfx::MaskFilterInfo(gfx::RRectF(gfx::RectF(10, 10, 80, 40), 4));
      parts.dialog_sqs->mask_filter_info =
          gfx::MaskFilterInfo(gfx::RRectF(gfx::RectF(20, 30, 200, 120), 12));
    });
    EXPECT_FALSE(ProtectedLayer(frame));
    EXPECT_EQ(DrawQuad::Material::kVideoHole, DialogVideoQuad(frame)->material);
  }
}

// What a CALayer can't reproduce stays black, as SkiaRenderer draws a hole it
// can't place, and the dialog pass keeps the hole.
TEST_F(ParcCALayerOverlayNestedTest, EffectsKeepItBlack) {
  const auto expect_black = [&](base::FunctionRef<void(const Parts&)> effect) {
    Frame frame = Process(1.f, 1.f, effect);
    EXPECT_FALSE(ProtectedLayer(frame));
    EXPECT_EQ(DrawQuad::Material::kVideoHole, DialogVideoQuad(frame)->material);
    EXPECT_TRUE(overlay_processor_->HadProtectedLayer());
  };
  // A filter.
  expect_black([](const Parts& parts) {
    parts.dialog_quad->filters.Append(
        cc::FilterOperation::CreateBlurFilter(4.f));
  });
  // A mask image.
  expect_black([](const Parts& parts) {
    parts.dialog_quad->resource_id = ResourceId(7);
  });
  // A free rotation.
  expect_black([](const Parts& parts) {
    parts.dialog_sqs->quad_to_target_transform.RotateAboutZAxis(30);
  });
  // A 3D sorting context.
  expect_black(
      [](const Parts& parts) { parts.dialog_sqs->sorting_context_id = 3; });
  // Corners of different radii.
  expect_black([](const Parts& parts) {
    gfx::RRectF rrect(gfx::RectF(20, 30, 200, 120), 12);
    rrect.SetCornerRadii(gfx::RRectF::Corner::kUpperLeft, 4, 4);
    parts.dialog_sqs->mask_filter_info = gfx::MaskFilterInfo(rrect);
  });
  // The pass drawn a second time.
  expect_black([](const Parts& parts) {
    auto* again =
        parts.root->CreateAndAppendDrawQuad<AggregatedRenderPassDrawQuad>();
    again->SetNew(parts.dialog_sqs, gfx::Rect(0, 0, 100, 60),
                  gfx::Rect(0, 0, 100, 60), kDialogPassId, kInvalidResourceId,
                  gfx::RectF(), gfx::Size(),
                  /*force_anti_aliasing_off=*/false);
  });
}

// A pass nothing draws (one kept only for a copy request) keeps its hole, and
// a frame without a nested hole is left exactly as it was.
TEST_F(ParcCALayerOverlayNestedTest, UndrawnPassAndOrdinaryFrames) {
  {
    AggregatedRenderPassList passes;
    auto dialog = CreateDialogPass(/*video_opacity=*/1.f);
    AggregatedRenderPass* dialog_pass = dialog.get();
    passes.push_back(std::move(dialog));
    passes.push_back(CreateRenderPass());
    OverlayCandidateList candidates;
    overlay_processor_->ProcessForOverlays(
        resource_provider_.get(), &passes, GetIdentityColorMatrix(),
        SurfaceDamageRectList(),
        GetDefaultPrimaryPlane(passes.back()->output_rect.size()),
        &candidates, &damage_rect_);
    for (const auto& candidate : candidates) {
      EXPECT_FALSE(candidate.protected_layer_token);
    }
    EXPECT_EQ(DrawQuad::Material::kVideoHole,
              (*std::next(dialog_pass->quad_list.begin()))->material);
    EXPECT_FALSE(dialog_pass->has_damage_from_contributing_content);
  }
  {
    AggregatedRenderPassList passes;
    auto child = std::make_unique<AggregatedRenderPass>();
    child->SetNew(kDialogPassId, gfx::Rect(0, 0, 100, 60), gfx::Rect(),
                  gfx::Transform());
    child->has_damage_from_contributing_content = false;
    SharedQuadState* sqs = child->CreateAndAppendSharedQuadState();
    sqs->opacity = 1.f;
    auto* color = child->CreateAndAppendDrawQuad<SolidColorDrawQuad>();
    color->SetNew(sqs, child->output_rect, child->output_rect, SkColors::kBlue,
                  /*anti_aliasing_off=*/false);
    AggregatedRenderPass* child_pass = child.get();
    passes.push_back(std::move(child));
    auto root = CreateRenderPass();
    auto* quad = root->CreateAndAppendDrawQuad<AggregatedRenderPassDrawQuad>();
    quad->SetNew(root->shared_quad_state_list.back(), gfx::Rect(0, 0, 100, 60),
                 gfx::Rect(0, 0, 100, 60), kDialogPassId, kInvalidResourceId,
                 gfx::RectF(), gfx::Size(), /*force_anti_aliasing_off=*/false);
    passes.push_back(std::move(root));
    OverlayCandidateList candidates;
    overlay_processor_->ProcessForOverlays(
        resource_provider_.get(), &passes, GetIdentityColorMatrix(),
        SurfaceDamageRectList(),
        GetDefaultPrimaryPlane(passes.back()->output_rect.size()),
        &candidates, &damage_rect_);
    ASSERT_EQ(1u, candidates.size());
    EXPECT_EQ(quad, candidates[0].rpdq);
    EXPECT_EQ(1u, child_pass->quad_list.size());
    EXPECT_EQ(color, child_pass->quad_list.front());
    EXPECT_EQ(SkColors::kBlue, color->color);
    EXPECT_FALSE(child_pass->has_damage_from_contributing_content);
    EXPECT_EQ(gfx::Rect(), child_pass->damage_rect);
    EXPECT_FALSE(overlay_processor_->HadProtectedLayer());
  }
}

// When the frame can't be all CALayers (here a copy request on the root), the
// layer is an underlay at full strength, the video is punched out of the
// dialog, and the root gets a DstOut copy of the video's footprint just below
// the dialog, at the dialog's opacity, so the page below it gives way by the
// share the video covers.
TEST_F(ParcCALayerOverlayNestedTest, UnderlayRoute) {
  const auto copy_request = [](const Parts& parts) {
    parts.root->copy_requests.push_back(
        CopyOutputRequest::CreateStubForTesting());
  };
  damage_rect_ = gfx::Rect(1, 2, 3, 4);
  Frame frame = Process(/*dialog_opacity=*/0.5f, /*video_opacity=*/1.f,
                        copy_request);
  ASSERT_EQ(2u, frame.candidates.size());
  const OverlayCandidate& layer = frame.candidates[0];
  EXPECT_EQ(token_, layer.protected_layer_token);
  EXPECT_TRUE(frame.candidates[1].is_root_render_pass);
  gfx::Transform expected_transform;
  expected_transform.Translate(20, 30);
  expected_transform.Scale(2, 2);
  expected_transform.Translate(10, 10);
  EXPECT_EQ(expected_transform, std::get<gfx::Transform>(layer.transform));
  EXPECT_EQ(gfx::RectF(0, 0, 80, 40), layer.display_rect);
  EXPECT_FLOAT_EQ(1.f, layer.opacity);

  const DrawQuad* punch = DialogVideoQuad(frame);
  ASSERT_EQ(DrawQuad::Material::kSolidColor, punch->material);
  EXPECT_EQ(SkColors::kTransparent,
            SolidColorDrawQuad::MaterialCast(punch)->color);

  // Root, front to back: the dialog, its punch copy, the page.
  const QuadList& root_quads = frame.passes.back()->quad_list;
  ASSERT_EQ(3u, root_quads.size());
  ASSERT_EQ(DrawQuad::Material::kAggregatedRenderPass,
            root_quads.front()->material);
  EXPECT_EQ(kDialogPassId,
            AggregatedRenderPassDrawQuad::MaterialCast(root_quads.front())
                ->render_pass_id);
  const DrawQuad* copy = *std::next(root_quads.begin());
  ASSERT_EQ(DrawQuad::Material::kSolidColor, copy->material);
  EXPECT_EQ(SkColors::kBlack, SolidColorDrawQuad::MaterialCast(copy)->color);
  EXPECT_EQ(gfx::Rect(0, 0, 80, 40), copy->rect);
  EXPECT_EQ(expected_transform,
            copy->shared_quad_state->quad_to_target_transform);
  EXPECT_EQ(SkBlendMode::kDstOut, copy->shared_quad_state->blend_mode);
  EXPECT_FLOAT_EQ(0.5f, copy->shared_quad_state->opacity);
  EXPECT_FALSE(copy->shared_quad_state->clip_rect);
  EXPECT_TRUE(copy->shared_quad_state->mask_filter_info.IsEmpty());
  EXPECT_EQ(DrawQuad::Material::kSolidColor, root_quads.back()->material);

  // The first punched frame redraws the root and the dialog; later ones
  // leave the damage alone.
  EXPECT_EQ(frame.passes.back()->output_rect, damage_rect_);
  EXPECT_TRUE(frame.dialog->has_damage_from_contributing_content);
  damage_rect_ = gfx::Rect(1, 2, 3, 4);
  Frame next = Process(0.5f, 1.f, copy_request);
  ASSERT_TRUE(ProtectedLayer(next));
  EXPECT_EQ(gfx::Rect(1, 2, 3, 4), damage_rect_);
  EXPECT_FALSE(next.dialog->has_damage_from_contributing_content);

  // A translucent video in an opaque dialog: DstOut at the video's opacity
  // in the dialog, a full punch in the root, and the underlay at full
  // strength.
  Frame translucent = Process(1.f, 0.5f, [&](const Parts& parts) {
    copy_request(parts);
    parts.dialog_sqs->clip_rect = gfx::Rect(50, 60, 100, 40);
  });
  ASSERT_TRUE(ProtectedLayer(translucent));
  EXPECT_FLOAT_EQ(1.f, ProtectedLayer(translucent)->opacity);
  EXPECT_EQ(gfx::Rect(50, 60, 100, 40), ProtectedLayer(translucent)->clip_rect);
  EXPECT_EQ(SkBlendMode::kDstOut,
            DialogVideoQuad(translucent)->shared_quad_state->blend_mode);
  const DrawQuad* full_copy =
      *std::next(translucent.passes.back()->quad_list.begin());
  EXPECT_EQ(SkBlendMode::kDstOut, full_copy->shared_quad_state->blend_mode);
  EXPECT_FLOAT_EQ(1.f, full_copy->shared_quad_state->opacity);
  EXPECT_EQ(gfx::Rect(50, 60, 100, 40),
            full_copy->shared_quad_state->clip_rect);

  // Parked: no underlay, no punches, and the root is redrawn once more.
  overlay_processor_->SetProtectedLayersAllowed(false);
  damage_rect_ = gfx::Rect(1, 2, 3, 4);
  Frame parked = Process(1.f, 1.f, copy_request);
  EXPECT_FALSE(ProtectedLayer(parked));
  EXPECT_EQ(2u, parked.passes.back()->quad_list.size());
  EXPECT_EQ(DrawQuad::Material::kVideoHole, DialogVideoQuad(parked)->material);
  EXPECT_EQ(parked.passes.back()->output_rect, damage_rect_);
}

// A video two passes deep (the dialog inside a page-level opacity group): the
// pass in between gets a DstOut copy of the footprint below the dialog, at
// the dialog's opacity, in its own space; the root gets one too on the
// underlay route.
TEST_F(ParcCALayerOverlayNestedTest, TwoPassesDeep) {
  constexpr AggregatedRenderPassId kGroupPassId{3};
  const auto process = [&](float group_opacity, float dialog_opacity,
                           bool all_ca_layers, AggregatedRenderPass** group_out,
                           AggregatedRenderPassList* passes) {
    passes->push_back(CreateDialogPass(/*video_opacity=*/1.f));
    // The group's 200x150 content is drawn at (8, 4); the dialog is at
    // (20, 30) in it, twice as large.
    auto group = std::make_unique<AggregatedRenderPass>();
    group->SetNew(kGroupPassId, gfx::Rect(0, 0, 200, 150), gfx::Rect(),
                  gfx::Transform());
    group->has_damage_from_contributing_content = false;
    SharedQuadState* dialog_sqs = group->CreateAndAppendSharedQuadState();
    dialog_sqs->opacity = dialog_opacity;
    dialog_sqs->quad_to_target_transform.Translate(20, 30);
    dialog_sqs->quad_to_target_transform.Scale(2, 2);
    auto* dialog_quad =
        group->CreateAndAppendDrawQuad<AggregatedRenderPassDrawQuad>();
    dialog_quad->SetNew(dialog_sqs, gfx::Rect(0, 0, 100, 60),
                        gfx::Rect(0, 0, 100, 60), kDialogPassId,
                        kInvalidResourceId, gfx::RectF(), gfx::Size(),
                        /*force_anti_aliasing_off=*/false);
    SharedQuadState* group_bg_sqs = group->CreateAndAppendSharedQuadState();
    group_bg_sqs->opacity = 1.f;
    auto* group_bg = group->CreateAndAppendDrawQuad<SolidColorDrawQuad>();
    group_bg->SetNew(group_bg_sqs, group->output_rect, group->output_rect,
                     SkColors::kGreen, /*anti_aliasing_off=*/false);
    *group_out = group.get();
    passes->push_back(std::move(group));

    auto root = CreateRenderPass();
    SharedQuadState* group_sqs = root->CreateAndAppendSharedQuadState();
    group_sqs->opacity = group_opacity;
    group_sqs->quad_to_target_transform.Translate(8, 4);
    auto* group_quad =
        root->CreateAndAppendDrawQuad<AggregatedRenderPassDrawQuad>();
    group_quad->SetNew(group_sqs, gfx::Rect(0, 0, 200, 150),
                       gfx::Rect(0, 0, 200, 150), kGroupPassId,
                       kInvalidResourceId, gfx::RectF(), gfx::Size(),
                       /*force_anti_aliasing_off=*/false);
    if (!all_ca_layers) {
      root->copy_requests.push_back(CopyOutputRequest::CreateStubForTesting());
    }
    passes->push_back(std::move(root));
    OverlayCandidateList candidates;
    overlay_processor_->ProcessForOverlays(
        resource_provider_.get(), passes, GetIdentityColorMatrix(),
        SurfaceDamageRectList(),
        GetDefaultPrimaryPlane(passes->back()->output_rect.size()),
        &candidates, &damage_rect_);
    return candidates;
  };
  gfx::Transform in_group;
  in_group.Translate(20, 30);
  in_group.Scale(2, 2);
  in_group.Translate(10, 10);
  gfx::Transform in_root;
  in_root.Translate(8, 4);
  in_root.PreConcat(in_group);
  const auto expect_copy = [](const DrawQuad* copy,
                              const gfx::Transform& transform, float opacity) {
    ASSERT_EQ(DrawQuad::Material::kSolidColor, copy->material);
    EXPECT_EQ(SkColors::kBlack, SolidColorDrawQuad::MaterialCast(copy)->color);
    EXPECT_EQ(SkBlendMode::kDstOut, copy->shared_quad_state->blend_mode);
    EXPECT_EQ(transform, copy->shared_quad_state->quad_to_target_transform);
    EXPECT_FLOAT_EQ(opacity, copy->shared_quad_state->opacity);
  };

  {
    // All CALayers: the layer sits below the group's CALayer with the
    // group's opacity; only the group pass gets a copy.
    AggregatedRenderPassList passes;
    AggregatedRenderPass* group = nullptr;
    OverlayCandidateList candidates =
        process(/*group_opacity=*/0.5f, /*dialog_opacity=*/1.f,
                /*all_ca_layers=*/true, &group, &passes);
    ASSERT_EQ(2u, candidates.size());
    EXPECT_EQ(token_, candidates[0].protected_layer_token);
    EXPECT_EQ(in_root, std::get<gfx::Transform>(candidates[0].transform));
    EXPECT_FLOAT_EQ(0.5f, candidates[0].opacity);
    ASSERT_TRUE(candidates[1].rpdq);
    EXPECT_EQ(kGroupPassId, candidates[1].rpdq->render_pass_id);
    ASSERT_EQ(3u, group->quad_list.size());
    expect_copy(*std::next(group->quad_list.begin()), in_group, 1.f);
    EXPECT_EQ(1u, passes.back()->quad_list.size());
    EXPECT_EQ(DrawQuad::Material::kSolidColor,
              (*std::next(passes.front()->quad_list.begin()))->material);
    EXPECT_TRUE(group->has_damage_from_contributing_content);
    EXPECT_EQ(group->output_rect, group->damage_rect);
  }
  {
    // Underlays: copies in the group at the dialog's opacity and in the root
    // at the group's, and the underlay at full strength.
    AggregatedRenderPassList passes;
    AggregatedRenderPass* group = nullptr;
    OverlayCandidateList candidates =
        process(/*group_opacity=*/1.f, /*dialog_opacity=*/0.5f,
                /*all_ca_layers=*/false, &group, &passes);
    ASSERT_EQ(2u, candidates.size());
    EXPECT_EQ(token_, candidates[0].protected_layer_token);
    EXPECT_EQ(in_root, std::get<gfx::Transform>(candidates[0].transform));
    EXPECT_FLOAT_EQ(1.f, candidates[0].opacity);
    ASSERT_EQ(3u, group->quad_list.size());
    expect_copy(*std::next(group->quad_list.begin()), in_group, 0.5f);
    const QuadList& root_quads = passes.back()->quad_list;
    ASSERT_EQ(2u, root_quads.size());
    expect_copy(root_quads.back(), in_root, 1.f);
  }
}

// Where the dialog draws something opaque over the video, the occlusion
// culler trims the hole. The layer and the root's copy leave that part out, so
// a translucent dialog can't let the video show through it.
TEST_F(ParcCALayerOverlayNestedTest, OccludedPartLeftOut) {
  const auto occlude = [](const Parts& parts) {
    parts.video->visible_rect = gfx::Rect(0, 0, 80, 30);
  };
  Frame frame =
      Process(/*dialog_opacity=*/0.5f, /*video_opacity=*/1.f, occlude);
  ASSERT_TRUE(ProtectedLayer(frame));
  EXPECT_EQ(gfx::Rect(40, 50, 160, 60), ProtectedLayer(frame)->clip_rect);

  Frame underlay = Process(0.5f, 1.f, [&](const Parts& parts) {
    occlude(parts);
    parts.root->copy_requests.push_back(
        CopyOutputRequest::CreateStubForTesting());
  });
  const DrawQuad* copy = *std::next(underlay.passes.back()->quad_list.begin());
  ASSERT_EQ(DrawQuad::Material::kSolidColor, copy->material);
  EXPECT_EQ(gfx::Rect(0, 0, 80, 40), copy->rect);
  EXPECT_EQ(gfx::Rect(0, 0, 80, 30), copy->visible_rect);
}

// A parked display leaves the nested video black too, and the dialog pass is
// redrawn when its punch goes away and when it comes back.
TEST_F(ParcCALayerOverlayNestedTest, ParkedDisplay) {
  ASSERT_TRUE(ProtectedLayer(Process(1.f, 1.f)));
  overlay_processor_->SetProtectedLayersAllowed(false);
  Frame parked = Process(1.f, 1.f);
  EXPECT_FALSE(ProtectedLayer(parked));
  EXPECT_EQ(DrawQuad::Material::kVideoHole, DialogVideoQuad(parked)->material);
  EXPECT_TRUE(parked.dialog->has_damage_from_contributing_content);
  EXPECT_EQ(parked.dialog->output_rect, parked.dialog->damage_rect);
  EXPECT_TRUE(overlay_processor_->HadProtectedLayer());
  overlay_processor_->SetProtectedLayersAllowed(true);
  Frame resumed = Process(1.f, 1.f);
  EXPECT_TRUE(ProtectedLayer(resumed));
  EXPECT_TRUE(resumed.dialog->has_damage_from_contributing_content);
}


}  // namespace
}  // namespace viz
