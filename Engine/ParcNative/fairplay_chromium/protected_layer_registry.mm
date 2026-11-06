// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //ui/accelerated_widget_mac/protected_layer_registry.mm.

#include "ui/accelerated_widget_mac/protected_layer_registry.h"

#import <QuartzCore/QuartzCore.h>

#include <map>

#include "base/no_destructor.h"
#include "base/synchronization/lock.h"
#include "base/thread_annotations.h"

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

namespace ui {
namespace {

class Layers {
 public:
  bool Register(const base::UnguessableToken& token, CALayer* layer) {
    if (token.is_empty() || !layer) {
      return false;
    }
    base::AutoLock hold(lock_);
    auto [it, inserted] = layers_.try_emplace(token, layer);
    return inserted || it->second == layer;
  }

  void Unregister(const base::UnguessableToken& token) {
    // Release outside the lock: the last release of a CALayer can run
    // arbitrary teardown, which must not re-enter the registry under it.
    [[maybe_unused]] CALayer* released = Take(token);
  }

  CALayer* Lookup(const base::UnguessableToken& token) {
    CALayer* layer = nil;
    {
      base::AutoLock hold(lock_);
      auto it = layers_.find(token);
      if (it != layers_.end()) {
        layer = it->second;
      }
    }
    return layer;
  }

 private:
  CALayer* Take(const base::UnguessableToken& token) {
    base::AutoLock hold(lock_);
    auto it = layers_.find(token);
    if (it == layers_.end()) {
      return nil;
    }
    CALayer* layer = it->second;
    layers_.erase(it);
    return layer;
  }

  base::Lock lock_;
  std::map<base::UnguessableToken, CALayer*> layers_ GUARDED_BY(lock_);
};

Layers& GetLayers() {
  static base::NoDestructor<Layers> layers;
  return *layers;
}

}  // namespace

// static
bool ProtectedLayerRegistry::Register(const base::UnguessableToken& token,
                                      CALayer* layer) {
  return GetLayers().Register(token, layer);
}

// static
void ProtectedLayerRegistry::Unregister(const base::UnguessableToken& token) {
  GetLayers().Unregister(token);
}

// static
CALayer* ProtectedLayerRegistry::Lookup(const base::UnguessableToken& token) {
  return GetLayers().Lookup(token);
}

}  // namespace ui
