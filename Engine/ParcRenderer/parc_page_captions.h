// Copyright 2026 Parc contributors.
// Captions a page draws itself over a video in picture in picture. Netflix,
// YouTube, Disney+ and TELUS TV+ draw subtitles as page text over the video
// rather than as text track cues, which Safari's and Chrome's windows never
// show; Parc's window shows them, and hides them in the tab meanwhile. The
// captions are boxes of text over the video outside any control (link, form
// control, editable or widget role), holding no control, focusable element
// or the video: a box its player names for captions (caption, subtitles,
// timed text, text track) over the video at once, any other, a live region
// too, once it has shown two lines with a gap between, centred above or below
// the middle of the video. Each is painted alone, at its place, as the cue
// container is (TextTrackContainer::PaintForPictureInPicture). The video's
// own text tracks take their place when they show.
// Installed at third_party/blink/renderer/core/html/media/parc_page_captions.h.
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
}  // namespace gfx

namespace blink {

class Element;
class HTMLVideoElement;

class CORE_EXPORT ParcPageCaptions final
    : public GarbageCollected<ParcPageCaptions> {
 public:
  explicit ParcPageCaptions(HTMLVideoElement& video);

  // Looks at the page's text over the video, if its document changed since
  // the last look. Returns whether the captions to show changed.
  bool Update();
  // The shown captions painted for the window, as
  // TextTrackContainer::PaintForPictureInPicture paints cues. Empty when none
  // show.
  SkBitmap Paint(const gfx::SizeF& window_size,
                 float device_scale_factor,
                 gfx::RectF& bounds);
  // The boxes shown as captions, hidden in the tab.
  const HeapVector<Member<Element>>& Shown() const { return shown_; }
  // Shows the captions in the tab again and forgets them.
  void Clear();

  void Trace(Visitor*) const;

 private:
  // Text over the video in one place of the page, followed over time. Players
  // replace caption boxes, so a place is the path of tag names and first
  // classes from the player down.
  struct Place {
    String path;
    bool named = false;
    bool live = false;
    bool seen_empty = false;
    uint64_t last_seen = 0;
    String text;
    // Up to two different lines seen there.
    Vector<String, 2> lines;
  };

  void Show(const HeapVector<Member<Element>>&);

  Member<HTMLVideoElement> video_;
  HeapVector<Member<Element>> shown_;
  String shown_text_;
  Vector<gfx::RectF> shown_areas_;
  Vector<Place> places_;
  uint64_t looks_ = 0;
  uint64_t dom_tree_version_ = 0;
  uint64_t style_version_ = 0;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PAGE_CAPTIONS_H_
