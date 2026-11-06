// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //ui/accelerated_widget_mac/protected_layer_registry.h and compiled into the
// accelerated_widget_mac component, so a component build has one registry.
//
// GPU-process registry of the layers FairPlay renderers present into. A
// FairPlay renderer's AVSampleBufferDisplayLayer shows video that Apple never
// hands back as pixels, so the compositor can't draw it; it can only place the
// layer itself. The renderer registers its layer here under an
// UnguessableToken and sends the token to the renderer process, whose client
// paints media::VideoFrame::CreateVideoHoleFrame(token, natural_size, ts).
// cc turns that frame into a viz::VideoHoleDrawQuad carrying the token, and
// CARendererLayerTree puts the registered layer where the quad is, in z-order
// among the page's other CALayers, with preventsCapture = YES. See
// COMPOSITING.md beside this file's source in the Parc repository.
//
// Contract with the registering side (the FairPlay renderer):
//  - Register before the token leaves the GPU process, so every quad that can
//    name the token finds the layer. Unregister when the renderer is
//    destroyed, after flushing the layer with removal of its displayed image.
//  - The compositor owns the layer's place in the tree: superlayer,
//    anchorPoint, position, bounds, transform, opacity, hidden,
//    geometryFlipped, videoGravity and preventsCapture. The renderer owns only
//    media: enqueue, flush, the content key recipient, the render synchronizer
//    and the time base.
//  - A token names one layer for its whole life. Never re-register a token for
//    another layer; make a new token.
//
// Thread-safe: every function may be called on any thread. The registry
// retains the layer from Register until Unregister. Lookup takes its strong
// reference under the lock and returns it autoreleased, so a concurrent
// Unregister can't free the layer under the compositor.
//
// Objective-C++ only (it forward-declares CALayer with @class): include it
// from .mm files.

#ifndef UI_ACCELERATED_WIDGET_MAC_PROTECTED_LAYER_REGISTRY_H_
#define UI_ACCELERATED_WIDGET_MAC_PROTECTED_LAYER_REGISTRY_H_

#include "base/unguessable_token.h"
#include "ui/accelerated_widget_mac/accelerated_widget_mac_export.h"

@class CALayer;

namespace ui {

class ACCELERATED_WIDGET_MAC_EXPORT ProtectedLayerRegistry {
 public:
  ProtectedLayerRegistry() = delete;

  // Retains `layer` under `token`. Returns false, changing nothing, when the
  // token is empty, the layer is nil, or the token already names a different
  // layer. Registering the same layer under the same token again returns true.
  static bool Register(const base::UnguessableToken& token, CALayer* layer);

  // Releases the layer registered under `token`. Unknown tokens are ignored.
  // The compositor drops the layer from its tree at its next commit.
  static void Unregister(const base::UnguessableToken& token);

  // The layer registered under `token`, or nil.
  static CALayer* Lookup(const base::UnguessableToken& token);
};

}  // namespace ui

#endif  // UI_ACCELERATED_WIDGET_MAC_PROTECTED_LAYER_REGISTRY_H_
