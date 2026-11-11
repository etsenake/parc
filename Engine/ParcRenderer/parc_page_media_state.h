// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PAGE_MEDIA_STATE_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PAGE_MEDIA_STATE_H_

#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/platform/heap/collection_support/heap_linked_hash_set.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/member.h"
#include "third_party/blink/renderer/platform/supplementable.h"

namespace blink {

class Page;

// The media state Parc's shell gives a page through its WebPreferences
// (WebViewImpl's ApplyWebPreferences): whether the page's view is in a
// window, independent of minimisation and occlusion, and whether the Mac's
// power state restricts autoplay.
class CORE_EXPORT ParcPageMediaState final
    : public GarbageCollected<ParcPageMediaState>,
      public Supplement<Page> {
 public:
  // An observer that stops observing `page` stays here until it is
  // collected, so it checks that `page` is still the page it observes.
  class InWindowObserver : public GarbageCollectedMixin {
   public:
    virtual void PageInWindowChanged(Page& page) = 0;
  };

  static const char kSupplementName[];

  static ParcPageMediaState& From(Page& page);

  explicit ParcPageMediaState(Page& page);

  bool InWindow() const { return in_window_; }
  void SetInWindow(bool in_window);

  bool MediaPowerRestricted() const { return media_power_restricted_; }
  void SetMediaPowerRestricted(bool restricted) {
    media_power_restricted_ = restricted;
  }

  // Observers are told in the order they started observing.
  void AddInWindowObserver(InWindowObserver* observer);
  void RemoveInWindowObserver(InWindowObserver* observer);

  void Trace(Visitor* visitor) const override;

 private:
  bool in_window_ = true;
  bool media_power_restricted_ = false;
  HeapLinkedHashSet<WeakMember<InWindowObserver>> in_window_observers_;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PAGE_MEDIA_STATE_H_
