// Copyright 2026 Parc contributors.
// Installed at //ui/accelerated_widget_mac/parc_protected_layer_claims.h.

#ifndef UI_ACCELERATED_WIDGET_MAC_PARC_PROTECTED_LAYER_CLAIMS_H_
#define UI_ACCELERATED_WIDGET_MAC_PARC_PROTECTED_LAYER_CLAIMS_H_

@class CALayer;

namespace ui {

enum class ParcProtectedLayerClaimAction {
  kCommit,
  kRelease,
};

// Commits or releases one content layer's claim on a registered protected
// layer. All calls stay on the coordinator's existing main thread.
void ParcUpdateProtectedLayerClaim(
    ParcProtectedLayerClaimAction action,
    const void* claimant,
    CALayer* __strong* claimant_host,
    CALayer* __strong* claimant_protected_layer,
    CALayer* __strong* hosted_layer,
    float scale_factor);

}  // namespace ui

#endif  // UI_ACCELERATED_WIDGET_MAC_PARC_PROTECTED_LAYER_CLAIMS_H_
