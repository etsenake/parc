// Copyright 2026 Parc contributors.

#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PAGE_CAPTIONS_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PAGE_CAPTIONS_H_

#include <stdint.h>

#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/platform/heap/collection_support/heap_vector.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/member.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "third_party/blink/renderer/platform/wtf/vector.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/gfx/geometry/rect_f.h"

namespace gfx {
class SizeF;
}

namespace blink {

class Element;
class HTMLMediaElement;
class LayoutBoxModelObject;
class LayoutVideo;
class TextTrackContainer;
class HTMLVideoElement;

CORE_EXPORT SkBitmap PaintParcTextTracksForPictureInPicture(
    TextTrackContainer& text_track_container,
    HTMLMediaElement& media_element,
    const gfx::SizeF& window_size,
    float device_scale_factor,
    gfx::RectF& bounds);
CORE_EXPORT bool ParcTextTrackContainerShowsCues(
    const TextTrackContainer& text_track_container);
CORE_EXPORT SkBitmap PaintParcLayersForPictureInPicture(
    const HeapVector<Member<const LayoutBoxModelObject>>& containers,
    const Vector<gfx::RectF>& areas,
    const LayoutVideo& video,
    const gfx::SizeF& window_size,
    float device_scale_factor,
    gfx::RectF& bounds);

class CORE_EXPORT ParcPageCaptions final
    : public GarbageCollected<ParcPageCaptions> {
 public:
  explicit ParcPageCaptions(HTMLVideoElement& video);

  bool Update();

  SkBitmap Paint(const gfx::SizeF& window_size,
                 float device_scale_factor,
                 gfx::RectF& bounds);

  const HeapVector<Member<Element>>& Shown() const { return shown_; }

  void Clear();

  void Trace(Visitor*) const;

 private:

  struct Place {
    String path;
    bool named = false;
    bool live = false;
    bool seen_empty = false;
    uint64_t last_seen = 0;
    String text;

    Vector<String, 2> lines;
  };

  void Show(const HeapVector<Member<Element>>&);

  bool VideoShowsCues() const;

  Member<HTMLVideoElement> video_;
  HeapVector<Member<Element>> shown_;
  String shown_text_;
  Vector<gfx::RectF> shown_areas_;
  Vector<Place> places_;
  uint64_t looks_ = 0;
  uint64_t dom_tree_version_ = 0;
  uint64_t style_version_ = 0;
};

}

#endif
