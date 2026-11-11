// Copyright 2016 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <AVFoundation/AVFoundation.h>

#include <memory>

#include "components/viz/common/resources/shared_image_format.h"
#include "gpu/GLES2/gl2extchromium.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "testing/gtest_mac.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/accelerated_widget_mac/ca_renderer_layer_tree.h"
#include "ui/accelerated_widget_mac/protected_layer_registry.h"
#include "ui/gfx/geometry/rect_conversions.h"
#include "ui/gfx/mac/io_surface.h"
#include "ui/gl/ca_renderer_layer_params.h"

@interface CALayer (Private)
@property BOOL wantsExtendedDynamicRangeContent;
@end

namespace gpu {

namespace {

struct CALayerProperties {
  CALayerProperties() = default;
  ~CALayerProperties() = default;

  bool is_clipped = true;
  gfx::Rect clip_rect;
  gfx::RRectF rounded_corner_bounds;
  int sorting_context_id = 0;
  gfx::Transform transform;
  gfx::RectF contents_rect = gfx::RectF(0.0f, 0.0f, 1.0f, 1.0f);
  gfx::Rect rect = gfx::Rect(0, 0, 256, 256);
  SkColor4f background_color = SkColors::kWhite;
  unsigned edge_aa_mask = 0;
  float opacity = 1.0f;
  float scale_factor = 1.0f;
  unsigned filter = GL_LINEAR;
  gfx::ScopedIOSurface io_surface;
  gfx::ColorSpace color_space;
  gfx::ProtectedVideoType protected_video_type =
      gfx::ProtectedVideoType::kClear;
  std::optional<base::UnguessableToken> protected_layer_token;

  bool allow_av_layers = true;
  bool allow_solid_color_layers = true;
};

bool ScheduleCALayer(ui::CARendererLayerTree* tree,
                     CALayerProperties* properties) {
  gfx::ScopedIOSurface io_surface;
  gfx::ColorSpace io_surface_color_space;
  if (properties->io_surface) {
    io_surface = properties->io_surface;
    io_surface_color_space = properties->color_space;
  }
  ui::CARendererLayerParams params(
      properties->is_clipped, properties->clip_rect,
      properties->rounded_corner_bounds, properties->sorting_context_id,
      properties->transform, io_surface, io_surface_color_space,
      properties->contents_rect, properties->rect, properties->background_color,
      properties->edge_aa_mask, properties->opacity, properties->filter,
      gfx::HDRMetadata(), properties->protected_video_type, false);
  params.protected_layer_token = properties->protected_layer_token;
  return tree->ScheduleCALayer(params);
}

// The single content layer under `superlayer` in a committed tree.
CALayer* OnlyContentLayerIn(CALayer* superlayer) {
  CALayer* layer = superlayer;
  for (int depth = 0; depth < 5; ++depth) {
    if (layer.sublayers.count != 1) {
      return nil;
    }
    layer = layer.sublayers[0];
  }
  return layer;
}

void UpdateCALayerTree(std::unique_ptr<ui::CARendererLayerTree>& ca_layer_tree,
                       CALayerProperties* properties,
                       CALayer* superlayer) {
  std::unique_ptr<ui::CARendererLayerTree> new_ca_layer_tree(
      new ui::CARendererLayerTree(properties->allow_av_layers,
                                  properties->allow_solid_color_layers));
  bool result = ScheduleCALayer(new_ca_layer_tree.get(), properties);
  EXPECT_TRUE(result);
  new_ca_layer_tree->CommitScheduledCALayers(
      superlayer, std::move(ca_layer_tree), properties->rect.size(),
      properties->scale_factor);
  std::swap(new_ca_layer_tree, ca_layer_tree);
}

}  // namespace

class ParcCALayerTreeTest : public testing::Test {
 protected:
  void SetUp() override { superlayer_ = [[CALayer alloc] init]; }
  // Traverse the tree. Validate that there exists only one content layer, and
  // return that layer.
  CALayer* GetOnlyContentLayer() {
    EXPECT_EQ(1u, [[superlayer_ sublayers] count]);
    CALayer* root_layer = [superlayer_ sublayers][0];
    EXPECT_EQ(1u, [[root_layer sublayers] count]);
    CALayer* clip_and_sorting_layer = [root_layer sublayers][0];
    EXPECT_EQ(1u, [[clip_and_sorting_layer sublayers] count]);
    CALayer* rounded_rect_layer = [clip_and_sorting_layer sublayers][0];
    EXPECT_EQ(1u, [[rounded_rect_layer sublayers] count]);
    CALayer* transform_layer = [rounded_rect_layer sublayers][0];
    EXPECT_EQ(1u, [[transform_layer sublayers] count]);
    return [transform_layer sublayers][0];
  }
  CALayer* __strong superlayer_;
};
// Parc: a quad carrying a registered FairPlay layer's token puts that layer in
// the tree where the quad is, follows the quad, moves to whichever tree
// committed it last and leaves black when the layer is gone.
TEST_F(ParcCALayerTreeTest, ProtectedLayer) {
  AVSampleBufferDisplayLayer* av_layer =
      [[AVSampleBufferDisplayLayer alloc] init];
  const base::UnguessableToken token = base::UnguessableToken::Create();
  ASSERT_TRUE(ui::ProtectedLayerRegistry::Register(token, av_layer));

  CALayerProperties properties;
  properties.protected_layer_token = token;
  properties.protected_video_type = gfx::ProtectedVideoType::kHardwareProtected;
  properties.background_color = SkColors::kTransparent;
  properties.is_clipped = false;
  properties.rect = gfx::Rect(16, 32, 64, 128);
  std::unique_ptr<ui::CARendererLayerTree> ca_layer_tree;

  // The registered layer fills a host at the quad's rect and can't be
  // captured.
  UpdateCALayerTree(ca_layer_tree, &properties, superlayer_);
  CALayer* host = GetOnlyContentLayer();
  EXPECT_FALSE([host isKindOfClass:[AVSampleBufferDisplayLayer class]]);
  EXPECT_EQ(host, av_layer.superlayer);
  EXPECT_EQ(1u, host.sublayers.count);
  EXPECT_EQ(gfx::Rect(16, 32, 64, 128),
            gfx::ToEnclosingRect(gfx::RectF(host.frame)));
  EXPECT_EQ(gfx::Rect(0, 0, 64, 128),
            gfx::ToEnclosingRect(gfx::RectF(av_layer.frame)));
  EXPECT_TRUE(av_layer.preventsCapture);
  EXPECT_NSEQ(AVLayerVideoGravityResize, av_layer.videoGravity);

  // The next frame keeps the host, and the layer follows the quad.
  properties.rect = gfx::Rect(8, 8, 32, 64);
  UpdateCALayerTree(ca_layer_tree, &properties, superlayer_);
  EXPECT_EQ(host, GetOnlyContentLayer());
  EXPECT_EQ(host, av_layer.superlayer);
  EXPECT_EQ(gfx::Rect(0, 0, 32, 64),
            gfx::ToEnclosingRect(gfx::RectF(av_layer.frame)));

  // Another compositor's tree showing the same quad takes the layer. When the
  // first tree commits again while the other is alive but idle (a parked
  // compositor keeps its last tree), the first tree takes it back.
  CALayer* other_superlayer = [[CALayer alloc] init];
  std::unique_ptr<ui::CARendererLayerTree> other_tree;
  UpdateCALayerTree(other_tree, &properties, other_superlayer);
  CALayer* other_host = OnlyContentLayerIn(other_superlayer);
  ASSERT_TRUE(other_host);
  EXPECT_EQ(other_host, av_layer.superlayer);
  UpdateCALayerTree(ca_layer_tree, &properties, superlayer_);
  host = GetOnlyContentLayer();
  EXPECT_EQ(host, av_layer.superlayer);
  EXPECT_EQ(0u, other_host.sublayers.count);

  // If the other tree takes it again (a held frame committed late) and then
  // drops the token, the layer goes straight back to the first tree, which
  // doesn't commit.
  UpdateCALayerTree(other_tree, &properties, other_superlayer);
  EXPECT_EQ(OnlyContentLayerIn(other_superlayer), av_layer.superlayer);
  CALayerProperties plain;
  plain.background_color = SkColors::kRed;
  UpdateCALayerTree(other_tree, &plain, other_superlayer);
  EXPECT_EQ(host, av_layer.superlayer);
  EXPECT_EQ(gfx::Rect(0, 0, 32, 64),
            gfx::ToEnclosingRect(gfx::RectF(av_layer.frame)));

  // Destroying the idle tree leaves the layer where it is.
  other_tree.reset();
  EXPECT_EQ(host, av_layer.superlayer);
  UpdateCALayerTree(ca_layer_tree, &properties, superlayer_);
  EXPECT_EQ(host, GetOnlyContentLayer());
  EXPECT_EQ(host, av_layer.superlayer);

  // Without a registered layer the host is black and empty, and the layer is
  // out of the visible tree.
  ui::ProtectedLayerRegistry::Unregister(token);
  UpdateCALayerTree(ca_layer_tree, &properties, superlayer_);
  host = GetOnlyContentLayer();
  EXPECT_EQ(0u, host.sublayers.count);
  EXPECT_TRUE(!av_layer.superlayer || !av_layer.superlayer.superlayer);
  ASSERT_TRUE(host.backgroundColor);
  EXPECT_EQ(1, CGColorGetAlpha(host.backgroundColor));
  const CGFloat* rgba = CGColorGetComponents(host.backgroundColor);
  EXPECT_EQ(0, rgba[0] + rgba[1] + rgba[2]);
}

// Parc: the native HLS player's AVPlayerLayer is placed like the MSE
// renderer's layer, filling the quad at the video's aspect ratio, with the
// display's scale (as WebKit gives its AVPlayerLayer the page's), and moves
// to the tree that committed it last.
TEST_F(ParcCALayerTreeTest, ProtectedPlayerLayer) {
  AVPlayerLayer* player_layer = [AVPlayerLayer playerLayerWithPlayer:nil];
  const base::UnguessableToken token = base::UnguessableToken::Create();
  ASSERT_TRUE(ui::ProtectedLayerRegistry::Register(token, player_layer));

  CALayerProperties properties;
  properties.protected_layer_token = token;
  properties.protected_video_type = gfx::ProtectedVideoType::kHardwareProtected;
  properties.background_color = SkColors::kTransparent;
  properties.is_clipped = false;
  properties.rect = gfx::Rect(16, 32, 64, 128);
  properties.scale_factor = 2.0f;
  std::unique_ptr<ui::CARendererLayerTree> ca_layer_tree;

  UpdateCALayerTree(ca_layer_tree, &properties, superlayer_);
  CALayer* host = GetOnlyContentLayer();
  EXPECT_FALSE([host isKindOfClass:[AVPlayerLayer class]]);
  EXPECT_EQ(host, player_layer.superlayer);
  EXPECT_EQ(gfx::Rect(0, 0, 32, 64),
            gfx::ToEnclosingRect(gfx::RectF(player_layer.frame)));
  EXPECT_EQ(2, player_layer.contentsScale);
  EXPECT_NSEQ(AVLayerVideoGravityResize, player_layer.videoGravity);
  EXPECT_FALSE(player_layer.geometryFlipped);

  CALayer* other_superlayer = [[CALayer alloc] init];
  std::unique_ptr<ui::CARendererLayerTree> other_tree;
  properties.rect = gfx::Rect(0, 0, 32, 18);
  UpdateCALayerTree(other_tree, &properties, other_superlayer);
  EXPECT_EQ(OnlyContentLayerIn(other_superlayer), player_layer.superlayer);
  EXPECT_EQ(gfx::Rect(0, 0, 16, 9),
            gfx::ToEnclosingRect(gfx::RectF(player_layer.frame)));
  UpdateCALayerTree(ca_layer_tree, &properties, superlayer_);
  EXPECT_EQ(GetOnlyContentLayer(), player_layer.superlayer);

  ui::ProtectedLayerRegistry::Unregister(token);
  UpdateCALayerTree(ca_layer_tree, &properties, superlayer_);
  EXPECT_EQ(0u, GetOnlyContentLayer().sublayers.count);
}

// Parc: Picture in Picture moves a FairPlay layer between the page's tree and
// the PiP window's tree. WebMediaPlayerImpl stops drawing the video in the page
// while in PiP, and a hidden PiP window keeps its last tree without committing.
TEST_F(ParcCALayerTreeTest, ProtectedLayerPictureInPicture) {
  AVSampleBufferDisplayLayer* av_layer =
      [[AVSampleBufferDisplayLayer alloc] init];
  const base::UnguessableToken token = base::UnguessableToken::Create();
  ASSERT_TRUE(ui::ProtectedLayerRegistry::Register(token, av_layer));

  CALayerProperties page_video;
  page_video.protected_layer_token = token;
  page_video.protected_video_type = gfx::ProtectedVideoType::kHardwareProtected;
  page_video.background_color = SkColors::kTransparent;
  page_video.is_clipped = false;
  page_video.rect = gfx::Rect(0, 0, 640, 360);
  CALayerProperties pip_video = page_video;
  pip_video.rect = gfx::Rect(0, 0, 320, 180);
  CALayerProperties page_placeholder;
  page_placeholder.background_color = SkColors::kRed;

  std::unique_ptr<ui::CARendererLayerTree> page_tree;
  std::unique_ptr<ui::CARendererLayerTree> pip_tree;
  CALayer* pip_superlayer = [[CALayer alloc] init];
  UpdateCALayerTree(page_tree, &page_video, superlayer_);
  EXPECT_EQ(GetOnlyContentLayer(), av_layer.superlayer);

  // Entering PiP: the PiP window's first frame takes the layer, and the
  // page's next frame, without the video, leaves it there.
  UpdateCALayerTree(pip_tree, &pip_video, pip_superlayer);
  CALayer* pip_host = OnlyContentLayerIn(pip_superlayer);
  ASSERT_TRUE(pip_host);
  EXPECT_EQ(pip_host, av_layer.superlayer);
  UpdateCALayerTree(page_tree, &page_placeholder, superlayer_);
  EXPECT_EQ(pip_host, av_layer.superlayer);
  EXPECT_EQ(gfx::Rect(0, 0, 320, 180),
            gfx::ToEnclosingRect(gfx::RectF(av_layer.frame)));

  // Leaving PiP: the page draws the video again and takes it back from the
  // hidden PiP window, which doesn't commit.
  UpdateCALayerTree(page_tree, &page_video, superlayer_);
  CALayer* page_host = GetOnlyContentLayer();
  EXPECT_EQ(page_host, av_layer.superlayer);
  EXPECT_EQ(0u, pip_host.sublayers.count);
  EXPECT_EQ(gfx::Rect(0, 0, 640, 360),
            gfx::ToEnclosingRect(gfx::RectF(av_layer.frame)));

  // A second session reuses the PiP window, which draws again.
  UpdateCALayerTree(pip_tree, &pip_video, pip_superlayer);
  EXPECT_EQ(OnlyContentLayerIn(pip_superlayer), av_layer.superlayer);
  UpdateCALayerTree(page_tree, &page_placeholder, superlayer_);

  // Closing the window before the page draws the video leaves the layer in
  // no tree until the page's frame takes it.
  pip_tree.reset();
  EXPECT_TRUE(!av_layer.superlayer || !av_layer.superlayer.superlayer);
  UpdateCALayerTree(page_tree, &page_video, superlayer_);
  EXPECT_EQ(GetOnlyContentLayer(), av_layer.superlayer);

  ui::ProtectedLayerRegistry::Unregister(token);
}

// Parc: a FairPlay video drawn inside a render pass (a player dialog with an
// opacity animation) is scheduled in root space right before the pass's own
// layer, with the composed clip, rounded clip and the opacity viz worked out.
// The protected host sits below the pass's layer and keeps that opacity; the
// registered layer fills it at full opacity.
TEST_F(ParcCALayerTreeTest, ProtectedLayerBelowPass) {
  AVSampleBufferDisplayLayer* av_layer =
      [[AVSampleBufferDisplayLayer alloc] init];
  const base::UnguessableToken token = base::UnguessableToken::Create();
  ASSERT_TRUE(ui::ProtectedLayerRegistry::Register(token, av_layer));

  CALayerProperties video;
  video.protected_layer_token = token;
  video.protected_video_type = gfx::ProtectedVideoType::kHardwareProtected;
  video.background_color = SkColors::kTransparent;
  video.is_clipped = true;
  video.clip_rect = gfx::Rect(50, 60, 100, 40);
  video.rounded_corner_bounds = gfx::RRectF(gfx::RectF(20, 30, 200, 120), 12);
  video.transform.Translate(20, 30);
  video.transform.Scale(2, 2);
  video.transform.Translate(10, 10);
  video.rect = gfx::Rect(0, 0, 80, 40);
  video.opacity = 0.5f;

  CALayerProperties pass;
  pass.io_surface = gfx::CreateIOSurface(gfx::Size(100, 60),
                                         viz::SinglePlaneFormat::kBGRA_8888);
  pass.is_clipped = false;
  pass.transform.Translate(20, 30);
  pass.transform.Scale(2, 2);
  pass.rect = gfx::Rect(0, 0, 100, 60);

  std::unique_ptr<ui::CARendererLayerTree> ca_layer_tree(
      new ui::CARendererLayerTree(true, true));
  EXPECT_TRUE(ScheduleCALayer(ca_layer_tree.get(), &video));
  EXPECT_TRUE(ScheduleCALayer(ca_layer_tree.get(), &pass));
  ca_layer_tree->CommitScheduledCALayers(superlayer_, nullptr,
                                         gfx::Size(256, 256), 1.0f);

  ASSERT_EQ(1u, superlayer_.sublayers.count);
  CALayer* root_layer = superlayer_.sublayers[0];
  ASSERT_EQ(2u, root_layer.sublayers.count);
  CALayer* video_clip = root_layer.sublayers[0];
  CALayer* video_rounded = video_clip.sublayers[0];
  CALayer* host = video_rounded.sublayers[0].sublayers[0];
  CALayer* pass_layer =
      root_layer.sublayers[1].sublayers[0].sublayers[0].sublayers[0];

  // Back to front: the protected host, then the pass's layer over it.
  EXPECT_EQ(host, av_layer.superlayer);
  EXPECT_EQ((__bridge id)pass.io_surface.get(), pass_layer.contents);
  EXPECT_FLOAT_EQ(0.5f, host.opacity);
  EXPECT_FLOAT_EQ(1.f, av_layer.opacity);
  EXPECT_TRUE(video_clip.masksToBounds);
  EXPECT_EQ(gfx::Rect(50, 60, 100, 40),
            gfx::ToEnclosingRect(gfx::RectF(video_clip.frame)));
  EXPECT_FLOAT_EQ(12.f, video_rounded.cornerRadius);
  EXPECT_EQ(gfx::Rect(20, 30, 200, 120),
            gfx::ToEnclosingRect(gfx::RectF(video_rounded.frame)));

  ui::ProtectedLayerRegistry::Unregister(token);
}


}  // namespace gpu
