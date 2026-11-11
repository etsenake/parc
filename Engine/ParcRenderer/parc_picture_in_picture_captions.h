// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/core/html/media/parc_picture_in_picture_captions.h.
// Whether an element is one of the page's captions a picture in picture
// window shows (ParcPageCaptions), which style hides in the tab, keeping its
// layout, and whose layer paints only it. ParcPageCaptions keeps them in its
// own set rather than in Element's flags, so element.h stays as Chromium has
// it. Main thread.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PICTURE_IN_PICTURE_CAPTIONS_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PICTURE_IN_PICTURE_CAPTIONS_H_

#include "third_party/blink/renderer/core/core_export.h"

namespace blink {

class Element;

CORE_EXPORT bool IsParcPictureInPictureCaptions(const Element& element);

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PICTURE_IN_PICTURE_CAPTIONS_H_
