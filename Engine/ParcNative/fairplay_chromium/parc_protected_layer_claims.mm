// Copyright 2026 Parc contributors.
// Installed at //ui/accelerated_widget_mac/parc_protected_layer_claims.mm.

#include "ui/accelerated_widget_mac/parc_protected_layer_claims.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cstdint>
#include <unordered_map>
#include <vector>

#include "base/no_destructor.h"

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

namespace ui {
namespace {

// A content layer's host is live while its fifth ancestor is the
// coordinator's layer.
bool IsHostInLiveTree(CALayer* host) {
  CALayer* layer = host;
  for (int depth = 0; depth < 5 && layer; ++depth) {
    layer = layer.superlayer;
  }
  return layer != nil;
}

struct ProtectedLayerClaims {
  struct Claim {
    uint64_t sequence = 0;
    const void* claimant = nullptr;
    CALayer* __strong* claimant_host = nullptr;
    CALayer* __strong* claimant_protected_layer = nullptr;
    float scale_factor = 1.f;
  };

  uint64_t last_sequence = 0;
  // Keyed by the registered layer, which each claimant retains.
  std::unordered_map<const void*, std::vector<Claim>> by_layer;
};

ProtectedLayerClaims& GetProtectedLayerClaims() {
  static base::NoDestructor<ProtectedLayerClaims> claims;
  return *claims;
}

void FillProtectedLayer(CALayer* host,
                        CALayer* protected_layer,
                        float scale_factor) {
  // The host carries the quad's rect and opacity; its ancestors carry the
  // transform, clip and rounded corners.
  const CGRect bounds = host.bounds;
  // The native HLS player's AVPlayerLayer gets the display's scale, as WebKit
  // gives its AVPlayerLayer the page's (mediaPlayerContentsScale), before its
  // bounds: it takes its player at its first size, and AVFoundation then
  // keeps HLS variants to that size on screen (fairplay_hls_player_layer.h).
  if ([protected_layer isKindOfClass:[AVPlayerLayer class]] &&
      protected_layer.contentsScale != scale_factor) {
    protected_layer.contentsScale = scale_factor;
  }
  if (!CGPointEqualToPoint(protected_layer.anchorPoint, CGPointZero)) {
    protected_layer.anchorPoint = CGPointZero;
  }
  if (!CGPointEqualToPoint(protected_layer.position, CGPointZero)) {
    protected_layer.position = CGPointZero;
  }
  if (!CGRectEqualToRect(protected_layer.bounds, bounds)) {
    protected_layer.bounds = bounds;
  }
  if (!CATransform3DIsIdentity(protected_layer.transform)) {
    protected_layer.transform = CATransform3DIdentity;
  }
  if (protected_layer.opacity != 1) {
    protected_layer.opacity = 1;
  }
  if (protected_layer.hidden) {
    protected_layer.hidden = NO;
  }
  if ([protected_layer
          isKindOfClass:[AVSampleBufferDisplayLayer class]]) {
    AVSampleBufferDisplayLayer* av_layer =
        static_cast<AVSampleBufferDisplayLayer*>(protected_layer);
    // Protected video is never captured: screenshots and screen sharing show
    // black here, as in Safari.
    if (!av_layer.preventsCapture) {
      av_layer.preventsCapture = YES;
    }
    // cc laid the quad out at the video's display aspect ratio (object-fit is
    // already applied), so the frame fills it, as Chromium's own video
    // AVSampleBufferDisplayLayers do.
    if (![av_layer.videoGravity isEqualToString:AVLayerVideoGravityResize]) {
      av_layer.videoGravity = AVLayerVideoGravityResize;
    }
    // The workaround Chromium's video layers use for transformed HDR content,
    // which is otherwise flipped vertically (https://crbug.com/398425794).
    if (!av_layer.geometryFlipped) {
      av_layer.geometryFlipped = YES;
    }
  } else if ([protected_layer isKindOfClass:[AVPlayerLayer class]]) {
    // The native HLS player's layer (NATIVE_HLS.md) fills the quad the same
    // way. AVFoundation itself keeps FairPlay video from an AVPlayer out of
    // screenshots and screen sharing; clear HLS can be captured, as in
    // Safari. Its geometry is left alone: the flip above works around an
    // AVSampleBufferDisplayLayer bug, and WebKit doesn't flip its
    // AVPlayerLayer.
    AVPlayerLayer* player_layer =
        static_cast<AVPlayerLayer*>(protected_layer);
    if (![player_layer.videoGravity
            isEqualToString:AVLayerVideoGravityResize]) {
      player_layer.videoGravity = AVLayerVideoGravityResize;
    }
  }
}

void HandOnProtectedLayer(CALayer* layer) {
  if (IsHostInLiveTree(layer.superlayer)) {
    return;
  }
  // Its holder let it go or went away. A tree that showed it may not commit
  // again for a long time (video plays without compositor frames), so move it
  // now to the newest committed layer that shows it, if one is still live.
  auto& by_layer = GetProtectedLayerClaims().by_layer;
  auto it = by_layer.find((__bridge const void*)layer);
  if (it == by_layer.end()) {
    return;
  }
  CALayer* newest_host = nil;
  CALayer* newest_protected_layer = nil;
  float newest_scale_factor = 1.f;
  uint64_t newest_sequence = 0;
  for (const auto& claim : it->second) {
    CALayer* candidate_host = *claim.claimant_host;
    if (claim.sequence > newest_sequence && candidate_host &&
        IsHostInLiveTree(candidate_host)) {
      newest_host = candidate_host;
      newest_protected_layer = *claim.claimant_protected_layer;
      newest_scale_factor = claim.scale_factor;
      newest_sequence = claim.sequence;
    }
  }
  if (newest_host) {
    [newest_host addSublayer:layer];
    FillProtectedLayer(newest_host, newest_protected_layer,
                       newest_scale_factor);
  }
}

}  // namespace

void ParcUpdateProtectedLayerClaim(
    ParcProtectedLayerClaimAction action,
    const void* claimant,
    CALayer* __strong* claimant_host,
    CALayer* __strong* claimant_protected_layer,
    CALayer* __strong* hosted_layer,
    float scale_factor) {
  CALayer* protected_layer = *claimant_protected_layer;
  if (action == ParcProtectedLayerClaimAction::kRelease) {
    auto& by_layer = GetProtectedLayerClaims().by_layer;
    auto it = by_layer.find((__bridge const void*)protected_layer);
    if (it != by_layer.end()) {
      std::erase_if(it->second, [claimant](const auto& claim) {
        return claim.claimant == claimant;
      });
      if (it->second.empty()) {
        by_layer.erase(it);
      }
    }
    HandOnProtectedLayer(protected_layer);
    return;
  }

  // Let go of a layer this host took for another token, handing it on to
  // another tree that still shows it.
  CALayer* host = *claimant_host;
  CALayer* previously_hosted = *hosted_layer;
  if (previously_hosted && previously_hosted != protected_layer &&
      previously_hosted.superlayer == host) {
    CALayer* released = previously_hosted;
    [released removeFromSuperlayer];
    HandOnProtectedLayer(released);
  }
  *hosted_layer = protected_layer;
  if (!protected_layer) {
    return;
  }

  ProtectedLayerClaims& claims = GetProtectedLayerClaims();
  claims.by_layer[(__bridge const void*)protected_layer].push_back(
      {++claims.last_sequence, claimant, claimant_host,
       claimant_protected_layer, scale_factor});

  // A layer has one superlayer, and the tree committing now takes it. A tree
  // that stopped drawing (a hidden or parked compositor) keeps its last tree
  // but never commits, so it can't hold the layer away from the compositor
  // that shows the page now. Two trees that both keep drawing the same token
  // (one surface embedded twice) would trade it each frame; Picture in Picture
  // must stop the page from drawing it (COMPOSITING.md).
  if (protected_layer.superlayer != host) {
    [host addSublayer:protected_layer];
  }
  FillProtectedLayer(host, protected_layer, scale_factor);
}

}  // namespace ui
